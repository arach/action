# action

Working-name rewrite for agentic macOS demo automation.

`action` is intended to be a native-first runtime for:

- observing apps, windows, and browser surfaces
- resolving stable targets before acting
- recording raw capture plus structured execution traces
- compiling scene intent into deterministic timelines
- composing polished promo/demo videos with pluggable render backends

## Principles

- Runtime first, scene DSL second
- macOS native fidelity over premature cross-platform support
- Explicit sessions and lifecycle
- Deterministic target resolution with confidence, not hidden guesswork
- Composition as a backend boundary, not the core architecture

## Monorepo Layout

- `packages/protocol`: shared runtime and manifest types
- `packages/runtime`: session state machine and execution primitives
- `packages/compiler`: scene-to-timeline compilation
- `packages/composer-core`: render manifest and composition contracts
- `packages/composer-remotion`: Remotion backend adapter
- `packages/cli`: CLI frontend
- `packages/mcp`: MCP frontend
- `native/engine`: Swift engine for macOS-native capture and automation
- `docs`: architecture and v0 notes

## Near-Term Goal

Build a solid v0 around:

- sessions
- observe / resolve / act
- raw capture + metadata trace
- chapters, labels, subtitles
- auto-zoom and click emphasis
- Remotion-backed finishing export

## Working Method

This repo is a rewrite informed by earlier projects, not a clean-room exercise.

Before implementing a substantial feature, do a short precedent review against
the relevant prior work and capture:

- what to keep
- what to avoid
- what to adapt
- what decision `action` is taking now

See [docs/PRECEDENT_REVIEW.md](/Users/arach/dev/action/docs/PRECEDENT_REVIEW.md).
