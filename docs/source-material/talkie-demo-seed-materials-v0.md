# Talkie Demo Seed Materials V0

These are practical starter materials for the first three Talkie demo stories.
They are not final scripts. They are safe, non-sensitive placeholders that make
the first capture session easier to stage.

## 1. The Thought Lands

### Preferred Destination

Use one of:

- Mail reply draft
- Messages conversation
- Notes document
- Editor comment or markdown file

The cleanest first take is probably Notes or Mail because the text field is
stable, readable, and emotionally obvious.

### Spoken Line Options

- "Can you send me the outline after lunch? I want the demo story to start with
  the cursor, not the app."
- "Let's keep the opening simple. One thought, one hotkey, and then the text
  lands right back here."
- "Note to self, the magic is return to origin. Talkie should feel like it
  vanished after helping."

### Inserted Text Target

Use the transcript almost verbatim. Avoid over-polish; the point is fast
capture inside flow.

Example final text:

```text
Let's keep the opening simple: one thought, one hotkey, and then the text lands right back here.
```

### Beat IDs

- `origin-idle`: destination app open, cursor visible, 1-2 seconds clean plate
- `capture-press`: Talkie capture starts
- `voice-in-flight`: short line spoken
- `capture-release`: capture stops
- `return-landed`: text appears in the origin field
- `context-proof`: saved dictation/detail view shows source app and window

### Retake Checklist

- Text field visible before and after
- No accidental menus or tooltips
- Cursor or focus state unchanged after return
- 1-2 seconds idle headroom before press and after paste
- At least two usable takes

## 2. Voice To Agent

### Preferred Destination

Use one of:

- Claude Code terminal
- Talkie embedded console
- Codex terminal session
- GitHub issue draft flow

The cleanest first take is a terminal or Talkie console surface receiving an
agent-ready prompt.

### Spoken Line Options

- "Create an issue for the tab router bug. The third tab updates the panel but
  not the URL, and it should be tagged for Friday."
- "Ask the agent to review the return-to-origin capture path and list the exact
  metadata we need for Preframe."
- "Open a branch for the Talkie demo seed materials and make the source-material
  plan easier to execute."

### Intent Payload Example

```json
{
  "kind": "agent_task",
  "source": "talkie_dictation",
  "title": "Fix tab router URL state",
  "body": "The third tab updates the visible panel but does not update the URL. Investigate the router state and tag the issue for Friday.",
  "context": {
    "app": "Claude Code",
    "windowTitle": "talkie - demo source material",
    "workspace": "/Users/art/dev/talkie"
  },
  "destination": {
    "type": "github_issue_or_agent_prompt",
    "labels": ["bug", "demo-followup"]
  }
}
```

### Agent Prompt Target

```text
Create an issue for the tab router bug: the third tab updates the visible panel but does not update the URL. Tag it for Friday and include a short reproduction note.
```

### Beat IDs

- `workspace-idle`: agent/developer workspace visible
- `capture-press`: Talkie capture starts
- `voice-instruction`: spoken task
- `payload-resolved`: transcript becomes structured intent
- `handoff`: agent target receives prompt or task
- `agent-ack`: agent acknowledges, queues, or starts

### Retake Checklist

- Agent target is legible
- Handoff moment is visible and not too fast
- Payload does not contain private paths unless redacted
- Agent response is modest: acknowledged, queued, or first step started
- At least two usable takes

## 3. What Was I Working On?

### Seed Dictation Rows

Use plausible local records like these:

| Time | App | Window | Transcript |
| --- | --- | --- | --- |
| 09:14 | Claude Code | Talkie source material | "The return-to-origin demo should start in the destination app, not in Talkie." |
| 09:42 | Chrome | usetalkie.com hero notes | "The site needs to show that a mic becomes output, not just transcription." |
| 10:18 | Terminal | action source factory | "Preframe will need timecodes, cursor path, and clean idle headroom." |
| 11:03 | Notes | Demo planning | "For the agent story, keep the payoff to handoff, not completed work." |
| 14:27 | Claude Code | Talkie CLI docs | "The local-first proof should be a CLI query over voice data." |

### CLI Output Sketch

Use short outputs that fit on screen. The actual execution can replace these
with live `talkie` CLI output later.

```text
$ talkie dictations --since 24h --pretty

09:14  Claude Code   Talkie source material       return-to-origin demo...
09:42  Chrome        usetalkie.com hero notes     mic becomes output...
10:18  Terminal      action source factory        timecodes, cursor path...
11:03  Notes         Demo planning                payoff is handoff...
14:27  Claude Code   Talkie CLI docs              local-first proof...
```

```text
$ talkie search "Preframe timecodes"

10:18  Terminal / action source factory
Preframe will need timecodes, cursor path, and clean idle headroom.
```

### Reconstruction Output Sketch

```text
Work session summary

Shipped:
- First Talkie source-material plan drafted.

In progress:
- Return-to-origin capture story.
- Voice-to-agent handoff story.
- Work reconstruction CLI story.

Needs follow-up:
- Add timecode anchors to Action handoff metadata.
- Capture two clean takes per beat.
- Mark redaction strings before Preframe intake.
```

### Beat IDs

- `local-records`: Talkie library or dictation list
- `cli-query`: terminal query over voice data
- `context-stack`: app/window/git/context signals appear
- `summary-build`: reconstruction groups the session
- `you-are-here`: final cursor/file/task state

### Retake Checklist

- No private names, tokens, branches, or real client context
- CLI output is short enough to read
- Terminal font size and window scale are consistent
- The summary is useful, not cute
- At least two usable takes
