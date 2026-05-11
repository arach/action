# Source Material MCP Notes

Use the MCP tools as thin affordances over the existing Action runtime. Do not
create a separate source-material pipeline for agents.

## Current Tools

- `action.source.run`
  - Input: `scenarioIdOrPath` or inline `scenario`, plus optional `driver`,
    `profile`, `export`, and `outputDir`.
  - `driver` defaults to `mock`; use `macos` for real native capture.
  - `export: true` requires `driver: "macos"` because handoff export verifies
    real media and rejects placeholder captures.
  - Output includes `ok` and a `sourceRun` object with the run snapshot, trace
    events, scenario, session output directory, and optional export result.

- `action.source.verify`
  - Input: `path`, plus optional `minDurationSeconds`, `minFrameCount`,
    `minWidth`, and `minHeight`.
  - Paths may be absolute or relative to the Action repo root.
  - Output includes `ok` and a `verification` report with status, media
    metadata, and warning/error issues.

- `action.source.export`
  - Input: `sessionIdOrPath`, plus optional `outputDir`.
  - `sessionIdOrPath` may be a session id under `artifacts/sessions`, an
    absolute session directory, or an Action-root-relative session directory.
  - Output includes `ok` and an `export` object with the handoff manifest,
    copied artifacts, primary video path, and source session path.

## Source Run Shape

`action.source.run` is orchestration over the same runtime primitives:

1. create or select a session
2. stage/observe the target surface
3. start native recording
4. execute the compiled scenario actions
5. stop and wait for the finished marker
6. verify media
7. optionally export the handoff

Agents can still compose the loop manually from observe, resolve, act, record,
verify, and export tools when they need more control than a scenario run gives
them.
