# Talkie Action Scenario Drafts V0

These are the first Action-clickable source passes for the three Talkie demo
stories. They are not final hero scripts. The first pass should create
continuous raw material with named beat anchors, then Preframe can freeze,
push in, or reframe after capture.

Local native target: the Talkie dev build currently resolves as
`to.talkie.app.mac.dev`.

## Preframe Follow-Up

Preframe's latest direction:

- Prioritize continuous screen continuity on the first pass.
- Do not shoot stills as the main material; mark frame beats in the manifest.
- Add a one-line `hold` field for each important beat.
- Keep `hold` inside action `input` for v0; extract later from real run traces.
- Add `holdDurationHint` when a hold needs editorial weight.
- Mark cold plates and payoff breath beats with `preRoll` or `postRoll`.
- Start each scenario from a cold, deterministic state.
- Use real, plausible content.
- Hold 2+ seconds after the payoff moment.
- Keep cursor movement deliberate.
- Keep window chrome, theme, scale, and sidebar state consistent.
- Capture clean separated audio.
- Capture at least two takes per beat.

## 1. The Thought Lands

- Action draft: `scenarios/talkie-thought-lands.json`
- Main screens:
  - Destination app manual take: cursor idle, hotkey press, text lands.
  - Talkie home as clean context plate.
  - Talkie Library as saved local record proof.
  - Talkie Notes as readable saved-text/context proof.
- Hold points:
  - `talkie-home-clean`
  - `saved-capture-row-readable`
  - `text-landed-in-field`
  - `saved-context-visible`
- Companion status:
  - `destination-hotkey-take`: pending
- Next self follow-ups:
  - Seed or select one safe dictation that matches the spoken line.
  - Capture the destination-app hotkey pass manually before the Talkie UI pass.
  - Verify Library/Notes labels resolve through Action AX.

## 2. Voice To Agent

- Action draft: `scenarios/talkie-voice-to-agent.json`
- Main screens:
  - Talkie Workflows.
  - Hey Talkie route selected.
  - Workflow visualizer via `VIEW`.
  - Talkie Console as the agent destination.
- Hold points:
  - `workflow-list-visible`
  - `payload-fully-resolved`
  - `agent-console-ready`
- Next self follow-ups:
  - Confirm advanced features and Pro Tools console are unlocked.
  - Seed one short spoken instruction plus resolved `intent_payload`.
  - Decide whether the destination is Talkie Console, Codex, or a terminal.

## 3. What Was I Working On?

- Action draft: `scenarios/talkie-work-reconstruction.json`
- Main screens:
  - Talkie Library with local records.
  - Stats or activity context.
  - Home as the final resume point.
- Companion plate:
  - `terminal-cli-plate`: pending, owns the `Preframe timecodes` query and generated summary.
- Hold points:
  - `local-records-visible`
  - `local-activity-context-visible`
  - `resume-line-highlighted`
- Next self follow-ups:
  - Seed the local records from `talkie-demo-seed-materials-v0.md`.
  - Create the terminal/CLI companion pass once the exact Talkie CLI command is verified.
  - Add source-run/handoff export support for scenario-level `preframe` metadata.

## Run Shape

Compile checks:

```bash
bun packages/cli/src/main.ts scenario talkie-thought-lands
bun packages/cli/src/main.ts scenario talkie-voice-to-agent
bun packages/cli/src/main.ts scenario talkie-work-reconstruction
```

First dry runs:

```bash
bun packages/cli/src/main.ts source run talkie-thought-lands mock
bun packages/cli/src/main.ts source run talkie-voice-to-agent mock
bun packages/cli/src/main.ts source run talkie-work-reconstruction mock
```

Native capture, once Talkie is seeded and permissions are checked:

```bash
bun packages/cli/src/main.ts source run talkie-thought-lands macos --export --profile final
bun packages/cli/src/main.ts source run talkie-voice-to-agent macos --export --profile final
bun packages/cli/src/main.ts source run talkie-work-reconstruction macos --export --profile final
```

## Native Proof

`talkie-thought-lands` completed a native draft pass against
`to.talkie.app.mac.dev`.

- Capture: `artifacts/sessions/talkie-thought-lands/capture.mov`
- Duration: 12.205s
- Frame size: 1320x1180
- Frames: 681
- Finished marker: present
