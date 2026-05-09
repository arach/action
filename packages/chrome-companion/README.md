# Action Chrome Companion

Minimal Manifest V3 companion extension for Action browser-surface experiments.

It contains:

- a service worker that relays `action.*` messages to the active tab
- a content script with a small DOM observer/actor stub
- self-contained Bun scripts for typechecking and building the unpacked extension

## Commands

```bash
bun run typecheck
bun run build
```

The build output is written to `dist/` and can be loaded in Chrome as an unpacked
extension.

## Message API

Send messages to the extension service worker with one of these methods:

- `action.observe`
- `action.resolve`
- `action.setValue`
- `action.click`
- `action.rect`

Example:

```js
chrome.runtime.sendMessage({
  method: "action.observe",
  params: { selector: "button, input, textarea, a" }
});
```
