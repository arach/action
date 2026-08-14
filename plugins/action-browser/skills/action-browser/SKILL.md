---
name: action-browser
description: Use Action Browser when the user wants an agent to open a URL in a real Chrome session, inspect a page, click or fill a DOM element, or capture a browser screenshot without setting up a headless browser.
---

# Action Browser

Action Browser is the short path from a URL to visible proof in a **named
Action-owned Chrome profile** (not the user's daily Chrome).

## Default workflow

1. If the user names an identity (`coding`, `mira`, …), call `browser_use_profile`
   or pass `profile` to `browser_open`.
2. Call `browser_open` with the requested URL. It reuses this agent session's
   current tab by default. Leave `background` set to `true` unless the user asks
   to see the Chrome window, and set `newTab: true` only when parallel page state
   is intentional.
3. Call `browser_screenshot` and show the returned image to the user.
4. Call `browser_snapshot` before interacting with unfamiliar pages.
5. Use selectors returned by the snapshot for `browser_click` and
   `browser_fill`.
6. Take another screenshot after an action when visual confirmation matters.

When the user explicitly asks to open the URL in their normal daily Chrome,
call `browser_open` with `mode: "regular"`. This is a visible, open-only handoff:
do not follow it with `browser_snapshot`, `browser_click`, `browser_fill`, or
`browser_screenshot`, because those tools remain attached to Action Chrome.

## Identities and cookies

- Profiles live under `~/Library/Application Support/Action/ChromeProfiles/<name>`.
- Default blank profile is `agent-browser` unless `ACTION_BROWSER_PROFILE` is set.
- `browser_profiles` lists Action identities; `browser_profile_info` shows the active one.
- To reuse logins, seed with `browser_import_cookies` using **domain allowlists**:
  1. dry-run (`confirm` omitted/false)
  2. write (`confirm: true`) after the user approves
- Never claim a page is authenticated without observing it after seed/login.
- Do not attach automation to the user's personal Chrome user-data-dir. Regular
  mode opens a URL there without exposing CDP control.

## Companion extension

- `browser_companion_status` reports extension dist + localhost bridge health.
- Richer DOM tooling lives in `packages/chrome-companion` (observe/resolve/act).
- Load `packages/chrome-companion/dist` unpacked once per Action profile when
  the user wants the companion path.

## Important behavior

- Real Chrome with CDP — not headless.
- `browser_open` defaults to controlled `mode: "action"`; `mode: "regular"`
  opens the URL in normal Chrome and truthfully returns `controlAvailable: false`.
- `browser_open` creates one working tab per agent session, then navigates that
  tab on later calls. Use `newTab: true` for an intentional additional tab.
- `browser_screenshot` saves a PNG artifact and returns the image in the tool response.
- Prefer a stable CSS selector from `browser_snapshot` over text matching.
- Use `browser_close` when a temporary tab is no longer useful.
- Chrome belongs to the agent session that started it. It quits when that
  session ends, after fifteen idle minutes, or on `browser_close` with
  `scope: "browser"` — whichever comes first.
- Call `browser_close` with `scope: "browser"` when a browsing task is finished
  and nothing further is expected.

## Safety

Opening, inspecting, and capturing pages are ordinary read actions. Treat clicks
and form fills according to their actual consequence. Do not submit purchases,
publish content, delete data, or confirm other consequential actions without
the user's authority. Cookie import requires an explicit `confirm: true`.
