# Agent Overview

Use this folder when you want dense context instead of narrative docs.

## Repo Summary

- Project: `action`
- Focus: native-first macOS demo automation
- Strongest current capability: native screenshot and recording
- Key architectural rule: AppKit lifecycle belongs to `Action.app`

## Core Files

- [ActionHostMain.swift](/Users/arach/dev/action/native/engine/Sources/ActionHostMain.swift)
- [ActionAgentRuntime.swift](/Users/arach/dev/action/native/engine/CoreSources/ActionAgentRuntime.swift)
- [ActionRecordingProbeLauncher.swift](/Users/arach/dev/action/native/engine/CoreSources/ActionRecordingProbeLauncher.swift)
- [RecordingProbeAppRunner.swift](/Users/arach/dev/action/native/engine/Sources/RecordingProbeAppRunner.swift)
- [ActionAgentProtocol.swift](/Users/arach/dev/action/native/engine/CoreSources/ActionAgentProtocol.swift)

## Key Rules

- Use bun for JS package management.
- Build the native app through the wrapper scripts, not by guessing bundle state.
- Keep WebKit and recording on real AppKit lifecycle paths.
- Treat recording completion as marker-file based, not reply-message based.
