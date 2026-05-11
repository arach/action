# Source Material Factory 10/10 Plan

## Purpose

This is the working game plan for getting Action/Mira from "useful raw
captures" to a 10/10 source-material factory for Preframe and agent-authored
demo work.

The goal is not a prettier one-off recording. The goal is a repeatable loop
that lets a human or agent choose a product surface, describe a demo goal, and
receive verified raw assets plus structured traces that are easy to compose
later.

## The 10/10 Bar

A 10/10 run has these properties:

- Actionable by another agent through CLI or MCP without relying on hidden
  Codex computer vision.
- Driven through stable targets first: DOM, accessibility, semantic ids, text,
  roles, and only then coordinates.
- Recorded through the native ScreenCaptureKit path at full app-window fidelity.
- Produces a handoff directory that Preframe can ingest without interpretation.
- Carries enough trace detail to understand what happened and why each action
  was chosen.
- Verifies media quality automatically before calling the run done.
- Leaves no stale overlay, probe, browser, or recording processes behind.
- Makes failure diagnosable from the artifact folder alone.
- Supports many scenario at-bats across Talkie, Preframe, browser apps, and
  native apps.
- Feels boringly easy to use.

## User Experience Target

The north-star CLI should feel like this:

```bash
bun run action source run scenarios/talkie-workflows-tour.json --driver macos --export
```

The north-star MCP flow should expose the same primitives:

- create or select a session
- observe the current surface
- resolve a target
- act on the target
- record the surface
- verify the media
- export the handoff

The agent should not need to know whether a final click came from DOM, AX, or a
coordinate fallback unless the resolution was ambiguous.

## Scorecard

Use this scorecard after every source-material run.

| Area | 10/10 Standard | Current Gap |
| --- | --- | --- |
| Action loop | Agent can observe, resolve, act, and repeat through CLI/MCP | Scripted scenarios exist, autonomous loops are partial |
| Target resolution | DOM/AX/semantic targets are default; coordinates are explicit fallback | Some scenarios still rely on brittle labels or manual refs |
| Recording quality | Full-size app-window capture, verified media, predictable bitrate behavior | Valid captures exist; bitrate can look low on static screens |
| Handoff | One obvious manifest with media, trace, screenshots, verification, tags | Handoff exists; schema needs richer scenario metadata |
| Cleanup | No stale overlay/probe/browser leftovers | Improved, but supervision cleanup needs more hardening |
| Scenario library | Many vivid, purposeful demo flows | Early Talkie and Preframe examples only |
| Agent ergonomics | One command/tool for run + verify + export | Still split across commands and occasional manual native calls |
| Diagnostics | Artifact folder explains failures without tribal knowledge | Logs exist, but not yet summarized into a run report |

## Workstreams

### 1. Source Run Command

Build a single command that executes the whole loop:

```bash
action source run <scenario-or-url> --driver macos --export
```

It should:

- normalize all artifact paths
- stage the window or browser surface
- start native recording
- drive actions through configured tools
- stop and await the finished marker
- verify the movie with media metadata
- export `mira-handoff.json`

Definition of done:

- one command can reproduce the existing Talkie exports
- one command can reproduce the Preframe browser tour
- failures return a useful JSON object with artifact paths

### 2. Agent-Facing MCP Loop

Expose the source-material loop as MCP-friendly primitives and a higher-level
tool.

Required tools:

- `action.source.run`
- `action.source.verify`
- `action.source.export`
- `action.observe.markup`
- `action.resolve.target`
- `action.act.execute`

Definition of done:

- Claude Code can drive a browser or app demo through Action tools alone
- a caller can choose draft or final recording profile
- target ambiguity is reported, not guessed away

### 3. Markup Observation Layer

Create a consolidated observation payload for agents that do not have their own
computer use.

The payload should combine:

- accessibility tree
- DOM snapshot when available
- screenshot metadata
- cursor and active-window state
- optional MiniMax VLM interpretation
- target candidates with confidence and bounding boxes

Definition of done:

- the observation is compact enough to fit in normal agent loops
- each candidate has a stable reference or an explicit coordinate fallback
- VLM output is additive, not the source of truth when AX/DOM exists

### 4. Scenario Library

Build many small, purposeful at-bats instead of one giant showcase.

Initial families:

- Talkie workflow switching, review, search, collapse, and detail drill-in
- Preframe catalog, queue, frames, FX, prompt, and player flows
- Browser SaaS app onboarding and search flows
- Native app permission/setup flows
- "Agent without eyes" flows where the driver only sees Action markup

Definition of done:

- at least 20 verified raw captures
- each capture has a one-line editorial reason to exist
- each family has short, medium, and long variants

### 5. Media Verification

Promote verification from ad hoc `ffprobe` checks to a first-class runtime step.

Verification should record:

- duration
- dimensions
- codec
- frame count
- average frame rate
- bitrate
- file size
- finished-marker status
- first/last frame screenshots

Definition of done:

- bad `.mov` containers are rejected automatically
- suspiciously short or tiny recordings are marked as warnings
- `mira-handoff.json` includes the media report

### 6. Capture Quality Profiles

Make quality explicit and boring.

Profiles:

- `draft`: fast, smaller, suitable for iteration
- `final`: full app-window size, high-quality H.264
- `archive`: larger intermediate-quality capture when composition needs more
  latitude

Definition of done:

- profiles are available in CLI and MCP
- the chosen profile is written into trace and handoff
- quality settings are visible in logs and verification

### 7. Overlay And Supervision Reliability

The HUD should always help and never trap the operator.

Required behavior:

- live recording indicator stays above masks
- clear/stop is always reachable
- stale overlay registrations expire or self-heal
- cleanup happens on success and failure

Definition of done:

- repeated failing takes do not leave persistent overlay processes
- the supervision HUD reports what it stopped
- run reports include cleanup actions

### 8. Preframe Intake Contract

Make handoff manifests feel native to Preframe.

Add:

- project name
- scenario family
- editorial intent
- style candidates
- media metadata
- trace path
- screenshots
- tags
- verification warnings

Definition of done:

- Preframe can list handoff folders as raw source assets
- a composition can choose takes by tags, duration, and surface
- no manual explanation is needed outside the folder

## Milestones

### Milestone 1: Boring Repeatability

- relative paths work everywhere
- recording finalization is robust
- source run report exists
- media verification is automatic
- Talkie and Preframe runs can be reproduced from one command

### Milestone 2: Agent-Usable Loop

- MCP source run tools exist
- observation payload includes AX plus optional VLM summaries
- actions can be driven from target refs
- ambiguity is explicit

### Milestone 3: Scenario Volume

- 20 verified raw captures
- at least 5 product/demo families
- every take has handoff, trace, media report, and final screenshot

### Milestone 4: Preframe-Ready Library

- Preframe can ingest or browse handoff folders
- raw assets have consistent tags and editorial intent
- demos can be composed from the library without more capture work

## Immediate Queue

1. Done: normalize path handling for native host commands.
2. Done: add a media verification helper and CLI command.
3. Done: add a first `action source run` CLI path for scenario runs.
4. Done: add MCP source run/verify/export affordances.
5. Done: add the first compact markup observation contract.
6. Done: add the first six Talkie/Preframe scenario at-bats.
7. Done: harden supervision overlay termination after recordings.
8. Add a richer source-run report.
9. Generate the next 10 verified Talkie and Preframe captures.
10. Add MiniMax VLM as an optional observation enrichment provider.

## Decision Log

- Preframe receives raw source assets and does polish later.
- Action owns live observation, action, trace, recording, and handoff.
- VLM should complement AX/DOM, not replace them.
- Many short verified takes beat one overproduced showcase at this stage.
