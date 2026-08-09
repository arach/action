# Native Runtime

This page describes the runtime split that currently makes `action` behave like
a real macOS app instead of a command wrapper pretending to be one.

## The Split

There are two native roles:

## `Action.app`

Owns:

- AppKit lifecycle
- menus and app-switcher behavior
- WebKit windows
- launcher UI
- permission UX
- recording probe execution
- supervision HUD presentation for drive presence

Main file:

- [ActionHostMain.swift](native/engine/Sources/ActionHostMain.swift)

## Local Agent Runtime

Owns:

- WebSocket transport
- automation-facing request handling
- local runtime methods
- bridge-friendly command orchestration
- agent-owned drive lease registry and heartbeat / expiry logic

Main files:

- [ActionAgentRuntime.swift](native/engine/CoreSources/ActionAgentRuntime.swift)
- [ActionAgentClient.swift](native/engine/CoreSources/ActionAgentClient.swift)
- [ActionAgentCommandBridge.swift](native/engine/Sources/ActionAgentCommandBridge.swift)
- [ActionDriveLeaseStore.swift](native/engine/CoreSources/ActionDriveLeaseStore.swift)

## Why This Exists

Two important failures pushed the design here:

### 1. WebKit

WebKit behaved unreliably when UI modes were entered through the wrong runtime
path. The fix was to let AppKit own the UI lifecycle cleanly.

### 2. ScreenCaptureKit Recording

Recording was not reliable when attempted inside the wrong lifecycle context.
The stable path now launches a fresh `Action.app` instance in `recording-probe`
mode for the actual capture work.

The lesson is simple:

**AppKit-dependent work should run inside a real app lifecycle.**

## Current Execution Flow

For normal operator usage:

1. `Action.app` launches
2. launcher UI comes up
3. local agent is started if needed
4. UI talks to the agent for runtime state and automation methods

For recording:

1. command or UI requests recording
2. host talks to the local agent
3. agent launches `Action.app` again in `recording-probe` mode
4. probe performs the actual `ScreenCaptureKit` recording
5. artifacts and finished markers are written

For drive leases:

1. an automation client opens a persistent WebSocket to the local agent
2. the client calls `drive.begin` with agent identity and task text
3. the agent stores the lease, keyed to that connection owner
4. the agent publishes a self-expiring supervision registration with agent + task
5. `Action.app` renders the supervision HUD; it does not own lease truth
6. observe / act paths call `drive.touch` so idle expiry cannot outlive real work
7. release, disconnect, idle timeout, max duration, stop-file, or agent restart ends the lease

See [api.md](api.md#drive-lease-contract) for method shapes, timers, and MCP mapping.

## Important Boundaries

Keep these rules intact:

- do not move WebKit lifecycle back into a fake headless command path
- do not move recording implementation back into the plain headless agent path
- keep the agent useful for orchestration and transport
- keep AppKit-owned concerns in the app process
- keep drive lease authority in the agent runtime; the HUD only presents presence
- do not let harness-local state be the only place a "driving" claim lives

## Scripts And Helpers

Useful native scripts live in:

- [native/engine/scripts](native/engine/scripts)

The most important ones right now are:

- `build-app.sh`
- `doctor.sh`
- `run-app-host.sh`
- `test-screenshot.sh`
- `test-record.sh`
