# Recording Debug Prompt

Use this prompt when investigating native recording failures.

## Prompt

Review the current `action` recording path and diagnose why recording is failing.

You must:

1. read [docs/recording.md](/Users/arach/dev/action/docs/recording.md)
2. inspect [ActionHostMain.swift](/Users/arach/dev/action/native/engine/Sources/ActionHostMain.swift)
3. inspect [ActionAgentRuntime.swift](/Users/arach/dev/action/native/engine/CoreSources/ActionAgentRuntime.swift)
4. inspect [ActionRecordingProbeLauncher.swift](/Users/arach/dev/action/native/engine/CoreSources/ActionRecordingProbeLauncher.swift)
5. inspect [RecordingProbeAppRunner.swift](/Users/arach/dev/action/native/engine/Sources/RecordingProbeAppRunner.swift)

Then answer:

- where the failure occurs
- whether it is app lifecycle, agent transport, or capture configuration
- what artifact files prove that conclusion
- what smallest safe fix should be tried next
