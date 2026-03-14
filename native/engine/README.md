# Native Engine

The native macOS host now begins with a small Swift executable:

- `ActionHost`

Its immediate purpose is to own permission flow that a terminal-only runtime
cannot handle well enough.

## Commands

### Permission status

```bash
swift run --package-path native/engine ActionHost status
```

Returns JSON like:

```json
{
  "accessibility": "denied",
  "screenRecording": "granted"
}
```

### Request permissions

```bash
swift run --package-path native/engine ActionHost request
```

This attempts to trigger the Accessibility and Screen Recording permission flows.

### Open settings panes

```bash
swift run --package-path native/engine ActionHost open-accessibility-settings
swift run --package-path native/engine ActionHost open-screen-recording-settings
```

## Why This Exists

The long-term native engine will own:

- ScreenCaptureKit capture
- Accessibility inspection
- input synthesis
- window management
- overlays and HUD windows

The first concrete step is permission ownership, because the rest of the native
feature set depends on it.
