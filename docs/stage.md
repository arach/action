# Stage

Action owns the look of a take. The wallpaper is never written.

`action.stage.set` is the primitive: declare the world, Action makes it so.

```json
{
  "mode": "drape",
  "color": "0e0d0a",
  "subjects": [
    { "bundleId": "to.talkie.agent.dev", "title": "Settings" },
    { "bundleId": "com.googlecode.iterm2" }
  ]
}
```

## What it does

- Puts up a flat color sheet at ordinary window level (`NSWindow.Level.normal`).
- `AXRaise`s only the listed windows. Same level is what lets them sit on the sheet.
- Leaves every other app alone. No hiding. No desktop-picture writes.
- Dies with the process that asked for it. `action.stage.clear` takes it down on purpose.

`mode: "space"` keeps the sheet on the current Space only. Instantiate subjects on that Space; windows on other Spaces will not compose into the frame.

`level: "desktop"` is the other sheet in the repertoire. It sits under all app windows and is the wrong default for a take.

## Surfaces

- MCP: `action.stage.set`, `action.stage.clear`, `action.stage.status`
- CLI: `bun packages/cli/src/main.ts stage set|clear|status`
