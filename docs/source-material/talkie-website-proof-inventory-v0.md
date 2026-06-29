# Talkie Website Proof Inventory v0

Source repo: `/Users/art/dev/usetalkie.com`

Purpose: turn the website promises into captureable demo source material, while expanding the agentic story beyond what the current site undersells.

## Priority Narrative Lanes

### 1. Intro: A Thought Becomes Work

- Start with a messy voice memo.
- Show it landing in Talkie as transcript/source material.
- Shape it in Compose with rewrite/summarize/bullet actions.
- Route it into a workflow.
- End with a real output: file, issue, draft, clipboard, or agent handoff.

Primary proof assets:

- `TalkieHero.mp4`
- `TalkiePromo.mp4`
- `TalkieDictation.mp4`
- `TalkieWorkflowEditor.mp4`
- `TalkieWorkflowAgent.mp4`
- new source plate: `TalkieComposeShapeDraft.mp4`

### 2. Agentic: Voice Fires Claude Code

- Speak a development intent while the project is open.
- Talkie captures the transcript with app/project context.
- Terminal pulls recent voice context through `talkie search` or `talkie memos --json`.
- Claude Code turns the spoken instruction into a branch/diff/plan.
- Talkie records the result and stores the loop as auditable work.

Primary proof assets:

- `TalkieWorkflowAgent.mp4`
- `TalkieWorkflowShell.mp4`
- new source plate: `TalkieClaudeCodeHandoff.mp4`
- new source plate: `TalkieCliVoiceContext.mp4`
- new source plate: `TalkieAgentFeedbackLoop.mp4`

### 3. Recovery: Search, Echoes, CLI, Export

- Show Talkie as memory, not just input.
- Search past captures by phrase.
- Open a recent echo/memo.
- Export or query via CLI.
- Use the recovered thread as agent context.

Primary proof assets:

- `TalkieEchoes.mp4`
- `TalkieSearch.mp4`
- `TalkieExport.mp4`
- new source plate: `TalkieCliSearchToAgent.mp4`

### 4. Later: iOS And Watch Continuity

- Capture on iPhone.
- Show sync to Mac.
- Use the mobile capture as workflow input.
- Add Watch as the smallest capture surface after the Mac story is strong.

Primary proof assets:

- `TalkieiPhoneCapture.mp4`
- `TalkieiPhoneWidgets.mp4`
- `TalkieiPhoneSync.mp4`
- `TalkieWatchCapture.mp4`

## Website Coverage Matrix

| Site Surface | Promise | Proof Shot | Current Status |
|---|---|---|---|
| Home hero | Capture a thought, shape a draft, search what you said, kick off a workflow | `TalkieHero.mp4`, `TalkiePromo.mp4` | Needs full narrative edit |
| Home capture mode: Capture | iPhone, Watch, Mac all feed the same transcript system | `TalkieiPhoneCapture.mp4`, `TalkieWatchCapture.mp4`, Mac memo plate | iOS/Watch later |
| Home capture mode: Dictation | Speak into the app already in front | `TalkieHoldToTalk.mp4`, `TalkieReturnToOrigin.mp4` | Needs staged hotkey/pass-back capture |
| Home capture mode: Compose | Rewrite, expand, summarize, compare edits | `TalkieComposeShapeDraft.mp4` | Can capture now with seeded memo |
| Home capture mode: Recovery | Search across memos/dictations with app context | `TalkieSearch.mp4`, `TalkieCliVoiceContext.mp4` | App search likely captureable now; CLI may need mock data |
| Home capture mode: Workflows | Route captures into summaries, task lists, files, follow-up actions | `TalkieWorkflowEditor.mp4`, `TalkieWorkflowFile.mp4`, `TalkieWorkflowAgent.mp4` | Editor/run modal captured partially |
| Home capture mode: CLI | Query voice data from scripts/tools | `TalkieCliSearchToAgent.mp4` | Needs terminal plate |
| `/mac` | Hold-to-talk, return to origin, HUD, smart routing, menu bar | six Dictate shots from `VIDEO_SHOTS.md` | Needs native/macOS staging |
| `/workflows` | LLM, shell, save file, webhooks, mail/calendar/clipboard/notifications | workflow editor plus terminal/output plates | Editor/run captured partially; shell/file/agent need new plates |
| `/agents` | Voice -> GitHub issue, Claude Code, standup, PR review | agentic scenario set | Site undersells this; expand with sophisticated demos |
| `/docs/cli` | JSON CLI for agents, `jq`, search, workflow failures, engine/inference | CLI terminal plates | Needs staged terminal capture |
| `/docs/workflows` | 21 step types, variables, provider routing, shell allowlist, execution lifecycle | docs/site screenshot plus workflow app plates | Use website screenshot and app workflow visualizer |
| `/mobile` | iPhone capture, widgets, sync | iOS screen recordings | Later batch |

## Agentic Expansion Scenarios

### A. Voice To Claude Code: Bug Fix Loop

- Screen 1: code editor or terminal in a real repo.
- Screen 2: Talkie memo/transcript: "Bug: queue jobs render in queue but not the Videos tab. Trace the state and patch it."
- Screen 3: terminal runs `talkie search "Videos tab queue"` and returns recent context as JSON.
- Screen 4: Claude Code receives the transcript/context, inspects files, creates a patch.
- Screen 5: terminal test passes.
- Screen 6: Talkie/queue shows the completed agent loop artifact.

Proof files:

- `TalkieClaudeCodeHandoff.mp4`
- `TalkieCliVoiceContext.mp4`
- `TalkieAgentFeedbackLoop.mp4`

### B. Voice To Research Brief

- Screen 1: messy memo in Talkie: "Research how teams are using voice notes as product backlog input..."
- Screen 2: Compose creates concise/bulleted/professional versions.
- Screen 3: workflow routes transcript through LLM summary and Save File.
- Screen 4: terminal or editor opens the markdown brief.
- Screen 5: CLI searches the original raw memo to prove provenance.

Proof files:

- `TalkieComposeShapeDraft.mp4`
- `TalkieWorkflowFile.mp4`
- `TalkieCliSearchToAgent.mp4`

### C. Voice To GitHub Issue

- Screen 1: user sees a bug in an app or browser.
- Screen 2: Talkie captures: "File an issue: third tab click does not update URL; tag router; due Friday."
- Screen 3: workflow editor shows `Dictate -> Shell -> GitHub`.
- Screen 4: terminal shows `gh issue create` with `{{TITLE}}` and `{{TRANSCRIPT}}`.
- Screen 5: GitHub issue URL is returned as workflow output.

Proof files:

- `TalkieWorkflowShell.mp4`
- `TalkieWorkflowAgent.mp4`
- `TalkieCliVoiceContext.mp4`

### D. Voice To PR Review

- Screen 1: PR diff in terminal or browser.
- Screen 2: Talkie captures review notes.
- Screen 3: Claude Code or `gh pr review` turns notes into inline comments.
- Screen 4: Talkie stores the review memo and the posted result.

Proof files:

- `TalkieClaudeCodeHandoff.mp4`
- `TalkieWorkflowShell.mp4`

### E. Voice To Standup Digest

- Screen 1: user dictates yesterday/today/blockers.
- Screen 2: workflow extracts sections.
- Screen 3: output is appended to a markdown/team digest.
- Screen 4: notification confirms completion.

Proof files:

- `TalkieWorkflowFile.mp4`
- `TalkieWorkflowAgent.mp4`

## Top Capture Batch

These are the next practical source plates to capture before iOS:

1. `TalkieComposeShapeDraft.mp4`
   - Talkie Compose.
   - Seed a messy memo.
   - Show quick actions: concise, professional, bullet points.
   - This covers Home Compose and the first half of the "thought becomes work" narrative.

2. `TalkieWorkflowEditor.mp4`
   - Workflow list.
   - Run workflow modal.
   - Search/select a source memo.
   - Visualizer open/zoom/inspect.
   - Existing `.mov` source clips partially cover this.

3. `TalkieCliVoiceContext.mp4`
   - Terminal.
   - `talkie search "..." --json | jq ...`
   - Feed result into Claude Code or a staged `claude` command.
   - This is the proof that voice data is useful to agents.

4. `TalkieClaudeCodeHandoff.mp4`
   - Terminal/Claude Code.
   - Transcript becomes a concrete implementation task.
   - Agent inspects files and proposes/applies a change.
   - Ends with tests or a diff summary.

5. `TalkieSearch.mp4`
   - Talkie library/search.
   - Search by remembered phrase.
   - Open a result and show transcript/context.

6. `TalkieWorkflowFile.mp4`
   - Workflow with `LLM -> Save File`.
   - Show `@Notes/{{DATE}}-{{TITLE}}.md`.
   - Open resulting markdown.

## Existing Source Clips

Already captured in `/Users/art/dev/action/artifacts/action-demos`:

- `talkie-app-agent-console-launch.mov`
  - Candidate source for `TalkieWorkflowAgent.mp4` and the expanded `/agents` story.
  - Shows Talkie-native Console launching the Claude surface inside the app.

- `talkie-app-compose-model-routing.mov`
  - Candidate source for `TalkieComposeShapeDraft.mp4`.
  - Shows a seeded memo and model routing surface inside Compose.

- `talkie-app-search-recovery.mov`
  - Candidate source for `TalkieSearch.mp4`.
  - Shows search/recovery from the Talkie Home surface.

- `talkie-app-workflow-run-inspect.mov`
  - Candidate source for `TalkieWorkflowEditor.mp4`.
  - Shows workflow selection, run modal, and graph/visualizer inspection.

- `talkie-doing-run-to-visualizer.mov`
  - Candidate source for `TalkieWorkflowEditor.mp4` and `TalkieWorkflowAgent.mp4`.
  - Shows workflow modal, typing into source search, visualizer open/zoom/close.

- `talkie-doing-switch-and-inspect.mov`
  - Candidate source for `TalkieWorkflowEditor.mp4`.
  - Shows switching workflow, visualizer inspection, run modal.

Review contact sheets:

- `/Users/art/dev/action/artifacts/review/talkie-doing/run-to-visualizer-contact.jpg`
- `/Users/art/dev/action/artifacts/review/talkie-doing/switch-and-inspect-contact.jpg`

## Product Finding: Multiple Talkie Instances

During capture prep, two Talkie apps were briefly present:

- dev build: `to.talkie.app.mac.dev`
- removed/stale installed app bundle id that has now been deleted

The current behavior makes this feel too tense because windows/instances can appear to compete for the same agent and bridge ownership. The product should be calmer:

- a second Talkie window should be allowed to exist without trying to steal bridge/agent ownership
- a second Talkie app instance should either attach as an observer/client or show an explicit "owned by another instance" state
- the bridge and agent should expose a clear owner/lease, not mystery contention
- demo automation must activate an existing dev Talkie instead of launching another instance
- the removed installed bundle id should not be targeted by new tooling
- avoid app-name based local UI automation for "Talkie"; it can resolve the stale installed app. Use explicit bundle id `to.talkie.app.mac.dev`.

Capture scripts now default to the dev bundle, use `TALKIE_BUNDLE_ID` only for explicit overrides, do not launch Talkie, and refuse the removed installed bundle id. Example:

```bash
TALKIE_BUNDLE_ID=to.talkie.app.mac.dev bun scripts/capture-talkie-app-story-plates.mjs
```

## Notes For Preframe / Motion Treatment

- Treat raw Action captures as source footage, not final demos.
- For agentic clips, use chapter labels sparingly: `VOICE`, `CONTEXT`, `AGENT`, `OUTPUT`.
- Prefer visible cause/effect over decorative UI zooms.
- The strongest motion is the actual chain: transcript appears, command runs, agent works, output lands.
- The intro clips can be tighter and calmer; the agentic clips can feel like a live operations room.
