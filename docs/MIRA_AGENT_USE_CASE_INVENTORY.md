# Mira Agent Use Case Inventory

This is a working inventory of what Mira can be for agents when we stop thinking
only in terms of demos.

The common thread is simple:

Mira gives an agent a reliable way to observe, resolve, act, inspect, and leave
proof in real macOS/browser/native surfaces.

## 1. Native App Development QA

Agents are already good at editing code. They are much weaker at checking the
actual native app the code produced.

Useful jobs:

- launch a fresh local build
- grant or verify macOS permissions
- exercise menus, windows, sheets, popovers, and permission flows
- inspect screenshots and accessibility trees
- catch visual regressions that unit tests miss
- record a failing run with logs, video, trace, and final screenshots

Examples:

- test an AppKit launcher after changing lifecycle code
- verify ScreenCaptureKit permission UX and recording markers
- smoke-test a signed `.app` bundle before release
- reproduce a native UI bug from a screenshot and produce a trace

Why agents care:

This turns "I changed the code" into "I verified the actual app."

## 2. Authenticated Browser Work

Many useful agent tasks live behind real browser sessions and cannot be solved
well by fetch, scraping, or stateless browser automation.

Useful jobs:

- use a persistent browser profile with human-provided credentials
- operate websites where DOM structure is unstable
- combine CDP, DOM, AX, and visual observation
- keep a video/trace audit trail of what the agent actually did
- avoid stealing the user's everyday browser context

Examples:

- configure GitHub releases or inspect CI artifacts
- operate Stripe, Vercel, Linear, Notion, Slack admin, or analytics consoles
- fill forms in authenticated SaaS tools
- compare a UI state before and after an operation

Why agents care:

This is the missing bridge between API-first automation and the real logged-in
web tools humans actually use.

## 3. Creative Tool Operation

Midjourney is a strong example because it is visual, authenticated, stateful,
and awkward for agents. It is not the only one.

Useful jobs:

- drive creative web apps where the output is visual
- submit prompts or edits
- wait for results
- inspect candidate outputs
- collect final assets plus prompt/provenance metadata
- make a video artifact of the creative run

Examples:

- Midjourney image exploration
- Figma design inspection and screenshot capture
- Canva or Webflow edits where an API is insufficient
- image/video generation workflows that need human account context

Why agents care:

The agent can become a creative operator, not just a prompt writer.

## 4. Regression And Acceptance Testing

Mira can become an acceptance harness for surfaces where traditional tests are
too narrow.

Useful jobs:

- run repeatable scenarios against a real app or browser
- assert key visual elements are present and near the action
- compare screenshots against prior takes
- detect text overlap, blank states, scroll drift, and wrong focus
- store a trace for every run

Examples:

- "Can the user complete onboarding?"
- "Does the dashboard still render correctly on mobile?"
- "Did the permission dialog appear in the expected moment?"
- "Was Mira/cursor within 200px of the intended target?"

Why agents care:

This gives agent-authored changes a product-level verification loop.

## 5. Human Demonstration To Scenario

Some workflows are easier for a human to show once than for an agent to author
from scratch.

Useful jobs:

- record a manual run
- capture clicks, keys, active windows, AX/DOM targets, and timing
- convert the trace into a scenario draft
- replace weak coordinates with stronger semantic targets
- rerun or polish the scenario later

Examples:

- user demonstrates a tricky admin workflow
- agent converts it into a repeatable run
- composer turns the rerun into training, release notes, or support material

Why agents care:

This turns human know-how into reusable agent procedure.

## 6. Support And Bug Reproduction

Mira can collect the kind of evidence that usually gets lost in "it didn't work"
reports.

Useful jobs:

- reproduce a bug in a controlled profile
- capture video, final screenshot, trace, logs, environment, and app state
- annotate where the agent expected one thing and saw another
- produce a concise artifact bundle for engineering

Examples:

- reproduce a checkout failure
- capture a permission bug in a native app
- verify a customer-reported layout issue
- record before/after evidence for a fix

Why agents care:

The agent can move from guessing about a user report to producing concrete
evidence.

## 7. Operational Backoffice Tasks

There are many repetitive tasks where APIs are unavailable, incomplete, or too
expensive to integrate.

Useful jobs:

- operate internal admin tools
- reconcile records across systems
- fill forms with visual confirmation
- capture proof of completion
- stop and ask when ambiguity is detected

Examples:

- update a customer record
- check a dashboard
- export a report
- reconcile a CMS field against a spreadsheet

Why agents care:

This expands automation into the messy long tail of tools that teams actually
use.

## 8. Agent Evaluation And Training

Mira can be a measurement framework for agents that act in GUIs.

Useful jobs:

- run tasks in controlled profiles
- record video plus structured traces
- score whether the agent resolved the right target
- measure intervention points, retries, latency, and drift
- build datasets from successful and failed runs

Examples:

- compare an AX-first agent against a vision-first agent
- evaluate browser-use reliability on authenticated workflows
- collect examples of good target resolution and bad coordinate guessing

Why agents care:

It creates an honest feedback loop for computer-use agents.

## 9. Release And Shipping Workflows

Mira can sit around CI/CD rather than inside it.

Useful jobs:

- verify local build artifacts
- inspect release pages
- test GitHub Actions manual dispatch or tag-push workflows
- capture proof that an upload or release succeeded
- smoke-test the shipped app after install

Examples:

- build signed app
- upload release assets
- open GitHub release page
- install and launch the app
- record a release smoke test

Why agents care:

This closes the gap between "the build passed" and "the product shipped."

## 10. Presentation And Communication

The capture is not only for debugging. It can become communication material.

Useful jobs:

- produce release clips
- create support walkthroughs
- generate product proof videos
- render narrated demos from the trace
- publish readme/site assets

Examples:

- the current Mira control-lanes video
- onboarding clips for a native workflow
- short before/after clips for a changelog

Why agents care:

An agent can not only do work; it can explain what happened.

## Useful Axes For Prioritization

When choosing which use cases to build first, score them on:

- Agent value: does this unlock work agents cannot currently do well?
- Native need: does it require real macOS/browser control rather than an API?
- Repeatability: can it become a scenario or regression test?
- Evidence value: does video plus trace materially help?
- Human handoff: can the system pause, ask, and resume safely?
- Credential reality: does it benefit from persistent profiles?
- Risk: what happens if the agent clicks or types the wrong thing?

## Near-Term Strong Bets

The strongest early lanes are:

- native app QA for this repo's own `Action.app`
- authenticated browser workflows with persistent profiles
- creative tool operation as a vivid proof point
- trace-backed regression checks
- human-run-to-scenario capture

Those lanes share the same primitives and make Mira useful before it becomes
broad.
