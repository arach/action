# action

Native-first macOS capture and demo workstation.

`action` is an AppKit-based macOS app for staging flows, recording them, reviewing the output, and handing the result to an agent or post-production toolchain.

Today the project is centered on a signed `Action.app`, a local agent runtime, an embedded web console, and a guided review loop for captured sessions.

## What Exists Today

- Signed `Action.app` bundle with a real AppKit lifecycle
- Local agent process for orchestration and automation-facing methods
- Guided capture flow that records playable session artifacts
- Session library and inline replay / review UI
- Embedded local console inside the app shell
- Native developer CLI for build / launch / relaunch / host commands

## Why This Project Exists

The goal is not just “screen recording.”

The goal is a native runtime where a human or an agent can:

- stage a scene
- run deterministic actions
- capture raw media plus structured trace data
- review the result immediately
- feed that output into editing, composition, or another agent

That is why the project is split between:

- `Action.app` for AppKit, WebKit, permissions UX, launcher UI, and recording-probe lifecycle
- the local agent for transport, orchestration, and automation-facing methods

## Current Product Loop

The strongest loop in the repo right now is:

1. Launch `Action.app`
2. Ensure the local console is running
3. Run a guided capture
4. Save a playable session with trace + screenshots
5. Review the result in-app
6. Leave machine-readable feedback for the next iteration

## Quick Start

Requirements:

- macOS on Apple Silicon
- Bun
- Xcode command line tools / Swift toolchain

Install dependencies:

```bash
bun install
```

Build the app:

```bash
bun run native:app:build
```

Verify native health:

```bash
bun run native:doctor
```

Launch the app:

```bash
bun run action-dev -- launch
```

## Developer CLI

For the tightest local loop, use the repo-local dev CLI:

```bash
alias action-dev='bun /Users/arach/dev/action/packages/cli/src/action-dev.ts'
action-dev relaunch
action-dev host guided-calculator-demo
action-dev logs
```

Or link the repo bins once:

```bash
bun link
action-dev relaunch
action scenario calculator-demo
```

Useful commands:

- `action-dev build`
- `action-dev rebuild`
- `action-dev launch`
- `action-dev relaunch`
- `action-dev quit`
- `action-dev doctor`
- `action-dev hud`
- `action-dev host <args...>`
- `action-dev agent <args...>`
- `action-dev agent-cli <args...>`

## Repository Layout

- `native/engine` — Swift app host, agent runtime, embedded console, native scripts
- `packages/hud` — local web console / HUD surface
- `packages/cli` — JS CLI entrypoints
- `packages/runtime` — runtime primitives and session logic
- `packages/protocol` — shared runtime protocol types
- `packages/compiler` — scenario / compilation layer
- `packages/composer-*` — composition backends and contracts
- `docs` — architecture, milestones, runtime notes, and capture docs
- `scripts/action-dev` — developer-facing native CLI wrapper

## Important Runtime Notes

- Recording is asynchronous.
- A start response means recording was accepted, not completed.
- Completion is represented by the artifact plus a finished marker file.
- The recording path is currently stabilized by launching a fresh `Action.app` instance in `recording-probe` mode.

## Read Next

- [Getting Started](/Users/arach/dev/action/docs/getting-started.md)
- [Native Runtime](/Users/arach/dev/action/docs/native-runtime.md)
- [Recording](/Users/arach/dev/action/docs/recording.md)
- [Architecture](/Users/arach/dev/action/docs/ARCHITECTURE.md)

## Status

This repo is still early, but it is no longer just architecture notes. The native app, guided capture loop, embedded console, session review flow, and local developer tooling are all real and in active use.
