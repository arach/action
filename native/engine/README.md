# Native Engine

The native macOS layer is now split into three direct-native pieces:

- `ActionHost`: the real AppKit app bundle
- `ActionAgent`: the headless local automation service
- `ActionAgentCLI`: a thin native client that talks to the agent over WebSocket

This split is deliberate. AppKit and WebKit need a clean UI lifecycle, while
agentic automation and external integrations need a separate long-lived service.

## Commands

### App UI

```bash
swift run --package-path native/engine ActionHost status
```

### Start the agent

```bash
swift run --package-path native/engine ActionAgent --port 4319
```

Or via script:

```bash
native/engine/scripts/run-agent.sh --port 4319
```

### Call the agent from the native CLI

```bash
swift run --package-path native/engine ActionAgentCLI status
swift run --package-path native/engine ActionAgentCLI ping
swift run --package-path native/engine ActionAgentCLI permissions.snapshot
swift run --package-path native/engine ActionAgentCLI app.activate --bundle-id com.apple.Calculator
```

Or via script:

```bash
native/engine/scripts/run-agent-cli.sh status
```

### Current agent methods

- `ping`
- `status`
- `permissions.snapshot`
- `permissions.request`
- `settings.openAccessibility`
- `settings.openScreenRecording`
- `app.activate`
- `window.setFrame`
- `window.getFrame`

### Bundled outputs

`native/engine/scripts/build-app.sh` now builds the app bundle and embeds the
headless agent binary into `Action.app/Contents/Resources/ActionAgent`.

## Why This Exists

The long-term native architecture is:

- AppKit app for windows, WebKit, menus, permissions UX
- local agent service for WebSocket, automation orchestration, and durable state
- thin CLI client for native operational control

The native layer will own:

- ScreenCaptureKit capture
- Accessibility inspection
- input synthesis
- window management
- overlays and HUD windows
- local agent transport

The important part is the process boundary: UI and agent transport no longer
need to live in the same runtime model.
