# Talkie Primitive Demo Source Material V0

Purpose: set up the first simple Talkie captures before returning to agentic
workflow stories. These demos should prove the atoms: capture, configure, and
personalize.

## Scenario Drafts

- [talkie-record-memo-primitive.json](../../scenarios/talkie-record-memo-primitive.json)
- [talkie-tune-settings-primitive.json](../../scenarios/talkie-tune-settings-primitive.json)
- [talkie-teach-words-primitive.json](../../scenarios/talkie-teach-words-primitive.json)

Local native target: `to.talkie.app.mac.dev`.

## 1. Record A Memo

- Start in Library, not in a workflow.
- Open the Record surface.
- Speak one short memo.
- Show recording state, timer, waveform, then processing.
- Open the saved memo.
- Hold on readable transcript/details.

Suggested spoken memo:

```text
I want to remember three things for the Talkie launch page: record fast, clean up names, and keep every thought searchable.
```

Capture requirements:

- Microphone permission already granted.
- At least one transcription model downloaded and available.
- Library list does not need to be empty, but the new memo should be easy to
  identify.
- Leave 1 second before pressing record and 2 seconds after the memo detail
  opens.

Preframe holds:

- `library-ready`
- `record-surface-ready`
- `recording-state-visible`
- `processing-pipeline-visible`
- `saved-memo-readable`

## 2. Tune Dictation Settings

- Open Settings.
- Go to Dictation.
- Hold on shortcuts, microphone, sounds, and display controls.
- Go to Models.
- Hold on Parakeet/Whisper model cards.
- Return Home.

Capture requirements:

- Settings sidebar expanded so labels are readable.
- Avoid changing destructive settings during the demo.
- If a model is currently downloading, either let it finish or choose another
  take; we want control, not an accidental progress-demo.
- Optional companion take: after returning Home, dictate into a text field to
  show the setup paying off.

Preframe holds:

- `settings-sidebar-readable`
- `dictation-shortcuts-visible`
- `model-cards-visible`
- `home-ready-after-setup`

## 3. Teach Talkie Your Words

- Open Settings.
- Go to Context.
- Open Dictionary.
- Show `YOUR WORDS`.
- Add one source/replacement pair.
- Open Test Playground.
- Run a sentence that proves the replacement.

Suggested seed entries:

| Source | Replacement |
| --- | --- |
| `pre frame` | `Preframe` |
| `latices` | `Lattices` |
| `mira` | `Mira` |
| `clawed code` | `Claude Code` |

Suggested playground input:

```text
send the pre frame treatment to mira and keep lattices as the action layer
```

Expected output:

```text
send the Preframe treatment to Mira and keep Lattices as the action layer
```

Capture requirements:

- Dictionary processing enabled.
- Settings audience should allow the Context playground tab if we want the
  in-settings Playground path; otherwise use the `Test` sheet.
- The first capture can manually type entries; later Action can automate the
  Add Entry sheet once the AX target order is verified.

Preframe holds:

- `context-tabs-visible`
- `your-words-visible`
- `add-entry-sheet-visible`
- `playground-input-output-visible`
- `corrected-terms-readable`

## Run Checks

Compile checks:

```bash
bun packages/cli/src/main.ts scenario talkie-record-memo-primitive
bun packages/cli/src/main.ts scenario talkie-tune-settings-primitive
bun packages/cli/src/main.ts scenario talkie-teach-words-primitive
```

Mock source-run checks:

```bash
bun packages/cli/src/main.ts source run talkie-record-memo-primitive mock
bun packages/cli/src/main.ts source run talkie-tune-settings-primitive mock
bun packages/cli/src/main.ts source run talkie-teach-words-primitive mock
```

Native source-run, once Talkie is launched and seeded:

```bash
bun packages/cli/src/main.ts source run talkie-record-memo-primitive macos --export --profile final
bun packages/cli/src/main.ts source run talkie-tune-settings-primitive macos --export --profile final
bun packages/cli/src/main.ts source run talkie-teach-words-primitive macos --export --profile final
```

## Capture Notes

- These are not hero videos. They are primitive source takes.
- Prefer continuous screen recordings over isolated stills.
- Keep the same Talkie theme, window size, and display scale across all three.
- Avoid terminal-heavy shots in this pass.
- Mark manual beats in the handoff rather than pretending Action performed them.
- Record at least two takes per scenario before handing to Preframe.
