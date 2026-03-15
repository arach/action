# action

> Native-first macOS demo automation with an AppKit UI and a local agent runtime

## Critical Context

**IMPORTANT:** Read these rules before making any changes:

- Use bun as the JavaScript package manager for this repo.
- The native product lives in native/engine and builds a signed Action.app bundle.
- Action.app owns AppKit lifecycle, menus, WebKit, permissions UX, and the recording probe path.
- The local Action agent exposes WebSocket methods and should not own fragile AppKit lifecycle responsibilities directly.
- ScreenCaptureKit recording is currently stabilized by launching a fresh Action.app instance in recording-probe mode.
- Recording commands should be treated as asynchronous: the initial CLI reply acknowledges startup, while completion is represented by a finished marker file.
- The repo still contains older design docs in docs/*.md that describe architecture and product direction beyond the Dewey quickstart set.

## Project Structure

| Component | Path | Purpose |
|-----------|------|---------|
| Root | `README.md` | |
| Dewey | `dewey.config.ts` | |
| Native | `native/engine/` | |
| AppHost | `native/engine/Sources/ActionHostMain.swift` | |
| AgentRuntime | `native/engine/CoreSources/ActionAgentRuntime.swift` | |
| RecordingProbe | `native/engine/Sources/RecordingProbeAppRunner.swift` | |
| Launcher | `native/engine/Sources/ActionLauncherViewModel.swift` | |
| Docs | `docs/` | |

## Quick Navigation

- Working with **webkit**? → Read docs/native-runtime.md and native/engine/Sources/ActionHostMain.swift for the AppKit-owned UI lifecycle.
- Working with **record**? → Read docs/recording.md and native/engine/CoreSources/ActionRecordingProbeLauncher.swift before changing recording behavior.
- Working with **agent**? → Read docs/native-runtime.md and native/engine/CoreSources/ActionAgentRuntime.swift for the current app/agent split.
- Working with **permission**? → Check native/engine/Sources/ActionLauncherViewModel.swift and the native wrapper scripts in native/engine/scripts/.
- Working with **build**? → Use bun run native:doctor or native/engine/scripts/build-app.sh to produce a signed app bundle.

## Overview

# Overview

`action` is a native-first macOS demo automation project.

It is aimed at a workflow where a human operator or an AI agent can:

- inspect an app, browser surface, or bounded region
- execute deterministic actions
- record raw capture plus structured runtime traces
- turn those traces into polished demo or promo outputs later

## What Exists Today

The current repo is early, but it already has a meaningful native core:

- a signed `Action.app` bundle
- a real AppKit launcher with menus and WebKit support
- a local `Action` agent runtime reachable over WebSocket
- native screenshot and recording commands
- permission and diagnostics wrappers for local development

The strongest proof point right now is native capture:

- screenshot flows work
- `ScreenCaptureKit` recording now works through a real app lifecycle path

## Current Architecture Direction

The project is deliberately split into two responsibilities:

- `Action.app` owns AppKit lifecycle, menus, WebKit, settings, and permission UX
- the local agent owns transport, automation-facing methods, and runtime orchestration

This split exists because UI lifecycle and automation lifecycle are not the same
problem on macOS. Earlier experiments showed that trying to make a command-style
runtime also own WebKit and recording behavior leads to brittle failures.

## Repository Shape

- [README.md](/Users/arach/dev/action/README.md): top-level project framing
- [docs/ARCHITECTURE.md](/Users/arach/dev/action/docs/ARCHITECTURE.md): deeper product and systems architecture
- [docs/VISION.md](/Users/arach/dev/action/docs/VISION.md): product intent and precedent learnings
- [native/engine](/Users/arach/dev/action/native/engine): Swift native engine, app host, local agent, and scripts
- [packages](/Users/arach/dev/action/packages): JS-side tooling and operator surfaces

## What Matters Most Right Now

At this stage, the most important technical goal is reliable native capture.

That means:

- real AppKit lifecycle correctness
- stable `ScreenCaptureKit` recording behavior
- clear artifacts and finished markers
- preserving a clean boundary between UI-owned behavior and agent-owned behavior

## Getting-started

# Getting Started

This is the shortest path to a useful local dev loop for `action`.

## Prerequisites

- macOS on Apple Silicon
- Bun
- Swift/Xcode native build tooling
- willingness to grant Accessibility and Screen Recording permissions for native automation tests

## Install

```bash
bun install
```

## Build The Native App

```bash
bun run native:app:build
```

This produces a signed app bundle at:

`/Users/arach/dev/action/native/dist/Action.app`

## Check Native Health

Use the doctor wrapper before debugging anything capture-related:

```bash
bun run native:doctor
```

This is the safest high-signal command because it:

- builds the app if needed
- signs it
- verifies signature state
- reports current Accessibility and Screen Recording status

## Useful Smoke Commands

Check permissions:

```bash
bun run native:permissions:status
```

Request permissions:

```bash
bun run native:permissions:request
```

Run a screenshot smoke test:

```bash
bun run native:test:screenshot
```

Run a recording smoke test:

```bash
bun run native:test:record
```

## Important Runtime Note

Recording is asynchronous.

The initial CLI response means recording startup was accepted. Completion is
represented by the artifact plus a finished marker file written later by the
recording path.

If you are debugging recording, inspect:

- the `.mov` output
- the `.finished` marker
- the debug log passed through `--debug-log`

## Where To Read Next

- [docs/native-runtime.md](/Users/arach/dev/action/docs/native-runtime.md)
- [docs/recording.md](/Users/arach/dev/action/docs/recording.md)
- [docs/ARCHITECTURE.md](/Users/arach/dev/action/docs/ARCHITECTURE.md)

## Native-runtime

# Native Runtime

This page describes the runtime split that currently makes `action` behave like
a real macOS app instead of a command wrapper pretending to be one.

## The Split

There are two native roles:

## `Action.app`

Owns:

- AppKit lifecycle
- menus and app-switcher behavior
- WebKit windows
- launcher UI
- permission UX
- recording probe execution

Main file:

- [ActionHostMain.swift](/Users/arach/dev/action/native/engine/Sources/ActionHostMain.swift)

## Local Agent Runtime

Owns:

- WebSocket transport
- automation-facing request handling
- local runtime methods
- bridge-friendly command orchestration

Main files:

- [ActionAgentRuntime.swift](/Users/arach/dev/action/native/engine/CoreSources/ActionAgentRuntime.swift)
- [ActionAgentClient.swift](/Users/arach/dev/action/native/engine/CoreSources/ActionAgentClient.swift)
- [ActionAgentCommandBridge.swift](/Users/arach/dev/action/native/engine/Sources/ActionAgentCommandBridge.swift)

## Why This Exists

Two important failures pushed the design here:

### 1. WebKit

WebKit behaved unreliably when UI modes were entered through the wrong runtime
path. The fix was to let AppKit own the UI lifecycle cleanly.

### 2. ScreenCaptureKit Recording

Recording was not reliable when attempted inside the wrong lifecycle context.
The stable path now launches a fresh `Action.app` instance in `recording-probe`
mode for the actual capture work.

The lesson is simple:

**AppKit-dependent work should run inside a real app lifecycle.**

## Current Execution Flow

For normal operator usage:

1. `Action.app` launches
2. launcher UI comes up
3. local agent is started if needed
4. UI talks to the agent for runtime state and automation methods

For recording:

1. command or UI requests recording
2. host talks to the local agent
3. agent launches `Action.app` again in `recording-probe` mode
4. probe performs the actual `ScreenCaptureKit` recording
5. artifacts and finished markers are written

## Important Boundaries

Keep these rules intact:

- do not move WebKit lifecycle back into a fake headless command path
- do not move recording implementation back into the plain headless agent path
- keep the agent useful for orchestration and transport
- keep AppKit-owned concerns in the app process

## Scripts And Helpers

Useful native scripts live in:

- [native/engine/scripts](/Users/arach/dev/action/native/engine/scripts)

The most important ones right now are:

- `build-app.sh`
- `doctor.sh`
- `run-app-host.sh`
- `test-screenshot.sh`
- `test-record.sh`

## Recording

# Recording

Recording is the most important runtime path in this project.

This page documents how it currently works and what assumptions should remain
true while the product is still being hardened.

## What Is Stable Right Now

The native recording path now succeeds for:

- bounded region recording
- app-window recording

The successful path produces:

- a `.mov` file
- a `.finished` marker file
- an optional debug log if `--debug-log` is supplied

## The Key Discovery

The main recording bug was not just a bad capture configuration.

The deeper issue was lifecycle ownership:

- `ScreenCaptureKit` recording was unreliable or crash-prone when hosted from the
  wrong runtime path
- a minimal real AppKit app lifecycle succeeded with the same capture logic

That is why the current solution uses a dedicated `recording-probe` mode inside
`Action.app`.

## Current Recording Path

For a region recording request:

1. host command accepts the request
2. host sends a recording method to the local agent
3. agent launches `Action.app` with `recording-probe`
4. probe runner creates a tiny AppKit window and starts recording
5. recording continues until the stop file appears
6. probe writes the finished marker and exits

Core files:

- [ActionRecordingProbeLauncher.swift](/Users/arach/dev/action/native/engine/CoreSources/ActionRecordingProbeLauncher.swift)
- [RecordingProbeAppRunner.swift](/Users/arach/dev/action/native/engine/Sources/RecordingProbeAppRunner.swift)
- [ActionHostMain.swift](/Users/arach/dev/action/native/engine/Sources/ActionHostMain.swift)

## Testing Recording

The wrapper script is:

```bash
bun run native:test:record
```

For lower-level testing, `run-app-host.sh` can call recording commands
directly.

## Important Caveat

The initial CLI reply usually means:

`recording started successfully`

It does **not** mean:

`recording completed successfully`

Completion is represented by the finished marker file.

## What To Preserve

- real AppKit lifecycle for actual recording work
- stop-file and finished-file based orchestration
- debug-log passthrough for probe runs
- clean app/agent separation even if the app is doing the final recording work

## What To Avoid

- pushing real recording back into a plain headless lifecycle
- assuming a WebSocket ack is equivalent to a completed recording
- removing the probe path before a better lifecycle-safe replacement exists

---
Generated by [Dewey 0.3.1](https://github.com/arach/dewey) | Last updated: 2026-03-15