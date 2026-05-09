# API

This page documents the current local agent protocol for `action`.

The protocol is intentionally small right now. It is enough to support native
health checks, permissions, window control, screenshots, and recording.

Primary source:

- [ActionAgentProtocol.swift](native/engine/CoreSources/ActionAgentProtocol.swift)

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
| `capture.recordAppWindow` | record a target app window | `bundleId`, `output`, optional `stopFile`, `finishedFile`, `debugLog` |
| `capture.recordRegion` | record a bounded region | `x`, `y`, `width`, `height`, `output`, optional `fps`, `scale`, `stopFile`, `finishedFile`, `debugLog` |
| `capture.screenshotAppWindow` | screenshot a target app window | `bundleId`, `output` |
| `capture.screenshotRegion` | screenshot a bounded region | `x`, `y`, `width`, `height`, `output` |
| `capture.screenshotScreen` | screenshot the main display | `output` |

## Recording Contract

Recording methods have a special lifecycle:

- startup success means the recording path was accepted
- actual completion is represented by the finished marker file
- for debugging, pass `debugLog`

This matters because recording is currently performed by launching a real
`Action.app` probe instance rather than keeping the full recording lifecycle
inside the headless agent process.
