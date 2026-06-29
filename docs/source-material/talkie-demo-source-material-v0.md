# Talkie Demo Source Material V0

Purpose: define the first Talkie source-material at-bats before capture execution.
This is intentionally words-first. It names the story, the minimum screens, the
raw assets to gather, and the Preframe intake shape we want Action to preserve.

## Selection

These are the first three stories to develop:

1. The Thought Lands
2. Voice To Agent
3. What Was I Working On?

They cover the core product argument:

- Talkie is fast enough to use inside active work.
- Talkie turns speech into an agent-readable work signal.
- Talkie makes local work context recoverable later.

## Action Drafts

First clickable source-pass drafts now live at:

- [talkie-thought-lands.json](../../scenarios/talkie-thought-lands.json)
- [talkie-voice-to-agent.json](../../scenarios/talkie-voice-to-agent.json)
- [talkie-work-reconstruction.json](../../scenarios/talkie-work-reconstruction.json)

The draft notes and run shape live in
[talkie-action-scenario-drafts-v0.md](talkie-action-scenario-drafts-v0.md).

Preframe's latest guidance: shoot continuous screen takes first, annotate named
timecode anchors and a one-line `hold` field per beat, then let composition
choose freezes and reframes after capture.

Follow-up review: Preframe signed off on keeping `hold` inside action `input`
for v0. Add `holdDurationHint` where the pause matters, use `preRoll` and
`postRoll` for cold plates and payoff breath beats, and mark companion captures
as pending until they exist.

## 1. The Thought Lands

### Story

A person is already working somewhere else. They speak one rough thought, release
the hotkey, and the text lands back where the cursor was. Talkie should feel like
an invisible capture layer, not a destination app.

### Screen Inventory

- Destination app with an active text field and cursor
- Talkie listening state over the destination app
- Destination app after text insertion
- Talkie library or dictation detail with the saved capture and context

### Raw Materials

- A clean destination app take, preferably Mail, Messages, Slack, Notes, or an
  editor
- One short spoken line that sounds natural, not scripted
- The resulting inserted text in the destination app
- A saved dictation/detail view showing transcript, app name, window title, and
  timestamp
- Optional close-up of the minimal HUD or menu bar state
- Optional trace or metadata export proving return-to-origin behavior

### Capture Notes

- Keep the first screen quiet. The viewer should understand the user was already
  in flow.
- Avoid opening Talkie first. The story is strongest when Talkie appears only as
  a brief recording surface.
- The inserted text should be short enough to read in one glance.

### Preframe Hooks

- Before/after text reveal in the destination app
- Cursor-return emphasis or subtle highlight around the target field
- Context card showing "said in Mail/Slack/Editor at time X" after the fact
- Origin/return rect framing: frame the destination before press, push in after
  release, and return to the exact origin rect
- Hold gesture as visual metronome: waveform or ring tied to press and release
- Breadcrumb overlay anchored to the focused window title

### Suggested Tags

`talkie`, `dictation`, `return-to-origin`, `hud`, `mac`, `local-first`

## 2. Voice To Agent

### Story

A spoken instruction becomes an agent-ready handoff. The user says the work in
plain language; Talkie captures it with context and sends it into an agent loop
without forcing the user to retype or translate the intent.

### Screen Inventory

- Developer workspace with the current task visible
- Talkie listening state while the instruction is spoken
- Agent destination receiving the cleaned instruction
- Agent running or acknowledging the work
- Optional Talkie workflow or console record showing the handoff path

### Raw Materials

- A realistic developer workspace, such as Claude Code, Codex, terminal, Cursor,
  or Talkie's embedded console
- One spoken instruction with enough specificity to be useful
- A cleaned handoff prompt or task body
- Agent acknowledgement, branch/task creation, issue draft, or initial response
- Workflow/run metadata showing the route from capture to agent
- Optional CLI or JSON artifact showing the handoff payload

### Capture Notes

- The agent should not magically finish a large task. The demo only needs to show
  the handoff becoming actionable.
- Prefer a small concrete instruction: fix a named bug, open a branch, write a
  review note, create an issue, summarize a diff.
- Show that Talkie carries context, not just transcript text.

### Preframe Hooks

- Split treatment: spoken transcript on one side, agent-ready prompt on the other
- Handoff pulse from Talkie capture into terminal/agent surface
- Tiny audit trail: input, route, destination, status
- Word-timed transcript materializing beside resolved `intent_payload` fields
- Long hold on the handoff moment where the agent target receives the work
- Subtle color or weight shift at first agent token

### Suggested Tags

`talkie`, `agent`, `developer`, `workflow`, `handoff`, `cli`, `mac`

## 3. What Was I Working On?

### Story

Talkie reconstructs work from the user's local voice trail. Dictations, app
names, window titles, browser URLs, and git state become a timeline or standup
summary. The magic is retrospective: the user did not have to log their day.

### Screen Inventory

- Talkie library or dictations list with recent captures
- CLI or local data query showing structured voice records
- Work reconstruction output, such as timeline, standup, or ready-to-ship list
- Optional git or project state beside the Talkie-derived summary

### Raw Materials

- Seeded dictation records across several apps or projects
- Metadata-rich rows: app name, window title, URL or terminal/project context
- CLI outputs such as `talkie dictations --since 24h`, `talkie search`, and
  `talkie stats`
- A generated summary that groups the day into shipped, in-progress, blocked,
  and follow-up items
- Optional git log or branch state used as corroborating context

### Capture Notes

- Do not overplay surveillance. The story is user-controlled memory, not passive
  monitoring.
- Keep the data local and visible. The CLI or file output is part of the trust
  story.
- Use plausible but non-sensitive project names and transcripts.

### Preframe Hooks

- Timeline build-up from individual captures into grouped work arcs
- "Local signals" stack: transcript, app, window, URL, git
- Final standup card or ready-to-ship checklist
- Cold terminal reveal where CLI output carries the story
- Context card pile assembled from files, branch, shell command, and diff hints
- End frame parked on the file or task where the session left off

### Suggested Tags

`talkie`, `memory`, `cli`, `context`, `local-first`, `agents`, `timeline`

## Shared Source Material Requirements

Every capture should try to produce:

- Primary raw video
- Separate mic audio track
- First and last frame screenshots
- A few key stills for Preframe frame selection
- Runtime trace, if Action drives the take
- Stable `scenario_id`, `beat_id`, and `take_id`
- FPS, resolution, device scale, and capture profile
- Timecode anchors for press, release, first token, handoff, and return
- Intended hold point per beat, such as `text-landed-in-field`
- Hold duration hints for editorially important pauses
- Companion capture status for related plates that are not in the Action run
- Cursor path samples when available
- Focus app and focus window title per beat
- Transcript with word-level timings when available
- Intent payload for agent handoff demos
- Context snapshot for work reconstruction demos
- Redaction map for sensitive rects or strings
- Audio levels and keypress log
- Scenario family and editorial intent
- Surface metadata: app, window, viewport, device, and route
- Verification report: duration, dimensions, frame count, codec, warnings
- Preframe tags, style candidates, and composition notes
- Short `notes.md` per take covering what worked and what to retake

## Handoff Metadata To Preserve

The current Action handoff already writes `mira-handoff.json`. For these Talkie
demos, the useful additions are:

- `preframe.projectName`: `Talkie`
- `preframe.scenarioFamily`: one of `thought-lands`, `voice-to-agent`,
  `work-reconstruction`
- `preframe.editorialIntent`: one sentence
- `preframe.storyBeats`: ordered words-only beats
- `preframe.captureMode`: usually `continuous-screen-take`
- `preframe.anchorTimecodes`: named timing hooks for composition
- `preframe.intendedHoldPoints`: one-line hold labels per important beat
- `preframe.companions`: pending or completed related capture plates
- `preframe.styleCandidates`: suggested treatments
- `preframe.tags`: story, surface, product capability, and trust tags
- `preframe.keyScreens`: words-only screen inventory
- `preframe.captureWarnings`: known risks for the take

## Capture Pitfalls

Preframe flagged these as especially important:

- Lock display, scale factor, theme, zoom, and window chrome before recording.
- Keep screen and mic audio as separate tracks.
- Disable accidental tooltips where possible.
- Leave 1-2 seconds of clean idle headroom before press and after return.
- Capture real screen and voice timing together; avoid re-enacted timing when
  possible.
- Prioritize continuous source takes over stills; stills can be extracted later.
- Hold at least two seconds after the payoff moment.
- Mark tokens, private names, paths, and branch names for redaction during
  capture, not only in post.
- Record at least two usable takes per beat.

## Next Execution Shape

Do not start with one giant hero recording. Start with small verified takes:

1. Short take for each story, 10-20 seconds
2. Medium take for the strongest story, 25-40 seconds
3. Handoff export for each verified take
4. Preframe intake review
5. Only then compose a more polished hero sequence
