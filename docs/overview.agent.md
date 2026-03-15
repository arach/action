# Overview (Agent)

## Project

- Name: `action`
- Type: monorepo with native macOS runtime focus
- Primary native surface: `Action.app`
- Primary automation surface: local WebSocket agent runtime

## Current Truth

- Native app lifecycle matters more than CLI convenience for WebKit and recording.
- `Action.app` is the owner of AppKit lifecycle, menus, WebKit, and permission UX.
- Recording stability currently depends on running capture in a fresh app instance via `recording-probe`.
- The agent is for transport and orchestration, not for pretending to be a full UI lifecycle host.

## Entry Points

- Root framing: [README.md](/Users/arach/dev/action/README.md)
- Native host main: [ActionHostMain.swift](/Users/arach/dev/action/native/engine/Sources/ActionHostMain.swift)
- Agent runtime: [ActionAgentRuntime.swift](/Users/arach/dev/action/native/engine/CoreSources/ActionAgentRuntime.swift)
- Recording probe launcher: [ActionRecordingProbeLauncher.swift](/Users/arach/dev/action/native/engine/CoreSources/ActionRecordingProbeLauncher.swift)
- Recording probe app runner: [RecordingProbeAppRunner.swift](/Users/arach/dev/action/native/engine/Sources/RecordingProbeAppRunner.swift)

## Use This Page For

- quick repo orientation
- understanding app-vs-agent ownership
- finding the files that currently define runtime truth

## Do Not Assume

- that command-mode execution owns the correct macOS UI lifecycle
- that the agent should directly host all AppKit-dependent behavior
- that older architecture docs always describe the latest capture implementation details
