# Source Material MCP Notes

Use the MCP tools as thin affordances over the existing Action runtime. Do not
create a separate source-material pipeline for agents.

## Current Tools

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

## Source Run Next Step

`action.source.run` should be added only after the scenario execution path is
available from runtime packages without importing CLI internals. Its job should
be orchestration over the same primitives:

1. create or select a session
2. stage/observe the target surface
3. start native recording
4. execute the compiled scenario actions
5. stop and wait for the finished marker
6. verify media
7. optionally export the handoff

Until then, agents should compose the loop from the existing observe, resolve,
act, record, verify, and export tools.
