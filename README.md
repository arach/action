# mira

**[arach.github.io/action](https://arach.github.io/action/)** · Agentic macOS demo workstation.

Mira is a native-first macOS agent for staging flows, driving real apps and browser surfaces, recording what happened, and handing the result to an agent or post-production toolchain.

The current binary is still `Action.app`: the working-name runtime that owns AppKit lifecycle, permissions UX, WebKit, native capture, and the recording probe. Mira is the product face layered on top of that runtime.

Demo capture: [Mira shows her control lanes](https://arach.github.io/action/#demo) · [MP4](https://arach.github.io/action/assets/mira-control-lanes-demo.mp4)

## What Exists Today

- Signed `Action.app` bundle with a real AppKit lifecycle
- Local agent process for orchestration and automation-facing methods
- Guided capture flow that records playable session artifacts
- Session library and inline replay / review UI
- Embedded local console inside the app shell
- Native developer CLI for build / launch / relaunch / host commands

## Why Mira Exists

The goal is not just “screen recording.”

The goal is a native agent workspace where Mira can:

- observe a scene through vision, browser context, and accessibility state
- resolve targets through AX, DOM, CDP, or calibrated native context
- run deterministic native actions
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

## Distribution

Action uses the same installer shape as Talkie: an `Installer/` directory with a
single DMG builder that creates a drag-to-Applications disk image.

Build a signed and notarized DMG:

```bash
bun run native:dmg:build
```

For local packaging without Apple notarization:

```bash
SKIP_NOTARIZE=1 bun run native:dmg:build
```

The output is:

```text
Installer/Action-for-Mac.dmg
```

Ship a public GitHub release from `main`:

```bash
bun run release:ship -- 0.1.0 --watch
```

The release workflow builds, signs, notarizes, verifies, and uploads the DMG. On
the publishing path it creates the `vX.Y.Z` tag only after verification passes,
then creates or updates the GitHub Release with generic and versioned DMG assets.
For an artifact-only run, add `--no-publish`.

Users install it by opening the DMG, dragging `Action.app` to Applications, then
granting Accessibility and Screen Recording permissions on first launch.

## Developer CLI

For the tightest local loop, use the repo-local dev CLI:

```bash
alias action-dev='bun packages/cli/src/action-dev.ts'
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

## Mira Companion

Mira also has a lattice-native desktop presence. The native launcher renders her
from the bundled pet pack, and the desktop actor path reuses Lattices'
`overlay.actor.*` daemon API.

```bash
bun run mira:install
bun run mira:show -- "Mira online"
bun run mira:move -- 900 720 900
bun run mira:hide
```

`mira:show` expects the Lattices app daemon to be reachable at
`ws://127.0.0.1:9399`.

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

- [Getting Started](docs/getting-started.md)
- [Native Runtime](docs/native-runtime.md)
- [Recording](docs/recording.md)
- [Architecture](docs/ARCHITECTURE.md)

## Status

This repo is still early, but it is no longer just architecture notes. The native app, guided capture loop, embedded console, session review flow, and local developer tooling are all real and in active use.
