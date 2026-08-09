# API

This page documents the current local agent protocol for `action`.

The protocol covers native health checks, permissions, window control,
screenshots, recording, and agent-owned drive leases for operator-visible
automation sessions.

Primary source:

- [ActionAgentProtocol.swift](native/engine/CoreSources/ActionAgentProtocol.swift)

Related runtime sources:

- [ActionDriveLeaseStore.swift](native/engine/CoreSources/ActionDriveLeaseStore.swift)
- [drive-client.ts](packages/runtime/src/drive-client.ts)
- MCP surface in [packages/mcp/src/index.ts](packages/mcp/src/index.ts)

## Transport

- Protocol: WebSocket
- Default host: `127.0.0.1`
- Default port: `4319`

## Request Shape

```json
{
  "id": "uuid-string",
  "method": "capture.recordRegion",
  "params": {
    "output": "/tmp/example.mov"
  }
}
```

Fields:

- `id`: request id, defaults to a UUID in native clients
- `method`: string name from `ActionAgentMethod`
- `params`: flat string map

## Response Shape

```json
{
  "id": "uuid-string",
  "ok": true,
  "result": {
    "status": "finished"
  },
  "error": null
}
```

Fields:

- `id`: mirrors request id
- `ok`: success flag
- `result`: optional flat string map
- `error`: optional error string

Nested objects such as drive leases are returned as JSON strings inside the
flat result map (for example `result.lease` or `result.snapshot`).

## Methods

| Method | Purpose | Key Params |
|---|---|---|
| `ping` | basic liveness check | none |
| `status` | server metadata and supported methods | none |
| `permissions.snapshot` | current permission state | none |
| `permissions.request` | request or prompt for permissions | none |
| `settings.openAccessibility` | open Accessibility settings pane | none |
| `settings.openScreenRecording` | open Screen Recording settings pane | none |
| `app.activate` | bring an app forward | `bundleId` |
| `window.setFrame` | move/resize an app window | `bundleId`, `x`, `y`, `width`, `height` |
| `window.getFrame` | inspect current app window frame | `bundleId` |
| `drive.begin` | open an agent-owned drive lease | `agent`, `task`, optional `mode`, `sessionId`, `implicit` |
| `drive.touch` | heartbeat a lease and record the latest AX tier | optional `leaseId`, `axTier` |
| `drive.release` | end a lease with a terminal outcome | `leaseId`, optional `outcome`, `summary` |
| `drive.status` | aggregate plus per-lease drive state | none |
| `capture.recordAppWindow` | record a target app window | `bundleId`, `output`, optional `stopFile`, `finishedFile`, `debugLog` |
| `capture.recordRegion` | record a bounded region | `x`, `y`, `width`, `height`, `output`, optional `fps`, `scale`, `stopFile`, `finishedFile`, `debugLog` |
| `capture.screenshotAppWindow` | screenshot a target app window | `bundleId`, `output` |
| `capture.screenshotRegion` | screenshot a bounded region | `x`, `y`, `width`, `height`, `output` |
| `capture.screenshotScreen` | screenshot the main display | `output` |

## Drive Lease Contract

Drive leases are the operator-visible control plane for automation clients.
They answer: who is driving the Mac, what task they claim, and whether control
has been returned.

### Ownership

- Lease state lives in the local **Action agent runtime**, not in a harness
  process or MCP client.
- Each active WebSocket connection is an owner. If that connection drops, the
  agent cancels the owner's active leases.
- `Action.app` owns the supervision HUD / AppKit presentation. The agent
  publishes short-lived presence registrations; the app renders them.

### Modes And Authorization

| Mode | Current behavior |
|---|---|
| `background` (default) | Granted immediately for observe / semantic / app-api / target-focus work |
| `attention` | Denied in v0; foreground keyboard or pointer control requires an approved attention lease, which is not available yet |

Background leases still record the AX action tier on every `drive.touch`. If a
client tries to touch a background lease with `axTier=attention`, the agent
rejects the call. That keeps the AX ladder from
[AX_BACKGROUND_AUTOMATION.md](AX_BACKGROUND_AUTOMATION.md) enforceable at the
lease boundary.

### Lifecycle Methods

#### `drive.begin`

Required params:

- `agent`: automation client identity shown to the operator
- `task`: short description of the work

Optional params:

- `mode`: `background` (default) or `attention`
- `sessionId`: Action session id used for drive artifacts; when omitted the
  agent creates `drive_<leaseId>`
- `implicit`: `"true"` when the runtime auto-opened the lease for an unattributed act

Success result fields:

- `status`: `granted` or `denied`
- `lease`: JSON string of the lease record
- `reason`: present when denied

#### `drive.touch`

Heartbeats an active lease owned by the calling connection.

- With no `leaseId`, the agent uses the caller's single active lease
- With multiple active leases for the same connection, callers must pass
  `leaseId` or the agent returns an ambiguous-lease error
- Optional `axTier` updates `lastAxTier` on the lease

Result:

- `status: "driving"` plus `lease` when a lease is active
- `status: "idle"` when the connection has no active lease

#### `drive.release`

Required: `leaseId`.

Optional:

- `outcome`: `done`, `failed`, or `cancelled` (default when omitted: `cancelled`)
- `summary`: short completion text shown in terminal presence and stored on the lease

#### `drive.status`

Result field:

- `snapshot`: JSON string of the aggregate status object

Parsed snapshot shape:

```json
{
  "state": "idle",
  "activeCount": 0,
  "leases": []
}
```

`state` is `driving` when any lease is active, otherwise `idle`. The `leases`
array includes active leases and recently completed ones still within the
terminal retention window.

### Timing Defaults

These values are defined by `ActionDriveLeaseStore`:

| Timer | Value | Effect |
|---|---|---|
| Idle expiry | 90 seconds | No `touch` / act activity → lease becomes `expired` |
| Maximum duration | 30 minutes | Lease cannot outlive this wall-clock span |
| Terminal HUD lifetime | 8 seconds | Done / failed / cancelled / expired chip remains visible, then presence is removed |
| Active presence refresh | about 2.5 seconds | Active HUD registrations expire quickly unless renewed by activity |

### Cleanup Paths

Active leases are terminalized when any of the following happens:

- explicit `drive.release`
- idle silence past 90 seconds
- maximum duration exceeded
- supervision stop-file appears for that lease
- driving WebSocket client disconnects
- Action agent process restarts (persisted `driving` records are marked `expired`
  on load because their owner is gone)

### MCP Surface

The MCP package exposes the same product contract with prefixed names:

| MCP tool | Agent method |
|---|---|
| `action.drive.begin` | `drive.begin` |
| `action.drive.release` | `drive.release` |
| `action.drive.status` | `drive.status` |

`drive.touch` is not a separate MCP tool. Observe and act tools accept an
optional `leaseId` and heartbeat through the persistent MCP agent socket.
If an act arrives with no active lease, MCP opens an implicit background lease
so presence still lights up.

Recommended harness flow:

1. `action.drive.begin` with `agent` and `task`
2. pass the returned `leaseId` on observe / act calls
3. `action.drive.release` with an honest outcome when the work ends

### Session Artifacts

Drive work should leave inspectable session artifacts under the session output
directory, typically:

- `drive-lease.json` — latest lease record
- `drive-trace.json` — lease begin / tier / release events
- `session.json` — session metadata including `driveLeaseId` and the lease

Native lease records themselves are also persisted under:

`~/Library/Application Support/Action/runtime/drive/leases/`

### On-Demand Local Agent Lifecycle

Automation clients such as MCP keep a long-lived WebSocket to the agent so
leases stay tied to a real connection:

1. connect to `ws://127.0.0.1:4319`
2. if the agent is down, launch it through the native host (`agent --port 4319`)
3. use a short idle-exit window on the agent process so an unused agent can exit
4. keep the client socket open for the harness lifetime
5. on client close or crash, the agent cancels that owner's active leases

Do not open a fresh one-shot socket per act for drive work. Connection identity
is part of the safety model.

## Recording Contract

Recording methods have a special lifecycle:

- startup success means the recording path was accepted
- actual completion is represented by the finished marker file
- for debugging, pass `debugLog`

This matters because recording is currently performed by launching a real
`Action.app` probe instance rather than keeping the full recording lifecycle
inside the headless agent process.
