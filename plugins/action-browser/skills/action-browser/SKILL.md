---
name: action-browser
description: Use Action Browser when the user wants an agent to open a URL in a real Chrome session, inspect a page, click or fill a DOM element, or capture a browser screenshot without setting up a headless browser.
---

# Action Browser

Action Browser is the short path from a URL to visible proof in a real Chrome
runtime.

## Default workflow

1. Call `browser_open` with the requested URL. Leave `background` set to `true`
   unless the user asks to see the Chrome window.
2. Call `browser_screenshot` and show the returned image to the user.
3. Call `browser_snapshot` before interacting with unfamiliar pages.
4. Use selectors returned by the snapshot for `browser_click` and
   `browser_fill`.
5. Take another screenshot after an action when visual confirmation matters.

## Important behavior

- The MCP starts a dedicated Chrome profile on demand. It does not use headless
  Chrome and it does not take over the user's personal Chrome profile.
- The isolated profile does not inherit personal logins, cookies, history, or
  extensions. Never claim a page is authenticated without observing it.
- `browser_screenshot` saves a PNG artifact and returns the image directly in
  the tool response.
- Prefer a stable CSS selector from `browser_snapshot` over text matching.
- Use `browser_close` when a temporary tab is no longer useful.
- Chrome belongs to the agent session that started it. It quits when that
  session ends, after fifteen idle minutes, or on `browser_close` with
  `scope: "browser"` — whichever comes first. A later `browser_open` starts a
  fresh Chrome, so never assume an earlier tab survived.
- Call `browser_close` with `scope: "browser"` when a browsing task is finished
  and nothing further is expected. Chrome stays up if another live agent
  session still claims it.

## Safety

Opening, inspecting, and capturing pages are ordinary read actions. Treat clicks
and form fills according to their actual consequence. Do not submit purchases,
publish content, delete data, or confirm other consequential actions without
the user's authority.
