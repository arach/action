# action

This repo has agent-oriented documentation generated with Dewey.

Read first:

- [AGENTS.md](AGENTS.md)
- [docs/overview.agent.md](docs/overview.agent.md)
- [docs/native-runtime.agent.md](docs/native-runtime.agent.md)
- [docs/recording.agent.md](docs/recording.agent.md)

Critical rules:

- Use bun for JS package management.
- Treat `Action.app` as the owner of AppKit lifecycle.
- Treat the local agent as orchestration and transport, not the owner of fragile UI lifecycle behavior.
- Treat recording completion as artifact-marker based, not initial-response based.
