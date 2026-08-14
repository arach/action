# Browser Profiles, Cookies, and Companion

How Action gives agents a **browser identity** without taking over your daily
Chrome.

## Policy

| Mode | Use |
|------|-----|
| **Named Action profile** (default) | `~/Library/Application Support/Action/ChromeProfiles/<name>` |
| **Selective cookie seed** | Copy only allowlisted domains/names from personal Chrome |
| **Chrome Companion extension** | Optional richer DOM observe/act via localhost bridge |
| **Daily personal Chrome** | Explicit opt-in only — not the default automation target |

Do **not** point automation at your everyday Chrome user-data-dir while you are
browsing. Chrome locks that directory, and agents should not inherit your full
history, extensions, and sessions by accident.

## Named identities

Examples:

- `agent-browser` — default blank agent profile
- `coding` — seeded for GitHub / Linear / etc.
- `mira` — Midjourney / creative tooling example

Create and prepare:

```bash
# from repo root
bun run chrome:companion:profile -- setup coding
```

This builds the companion extension, creates the profile directory, opens
`chrome://extensions` in that profile, and reveals `packages/chrome-companion/dist`
so you can **Load unpacked** once.

Launch later:

```bash
bun run chrome:companion:profile -- launch coding
bun run chrome:companion:profile -- check coding
bun run chrome:companion:profile -- path coding
```

Environment aliases (shared between companion tooling and Action Browser MCP):

| Variable | Meaning |
|----------|---------|
| `ACTION_BROWSER_PROFILE` / `ACTION_CHROME_COMPANION_PROFILE` | Active profile name |
| `ACTION_BROWSER_PROFILE_DIR` / `ACTION_CHROME_COMPANION_PROFILE_DIR` | Absolute user-data-dir override |
| `ACTION_BROWSER_PROFILE_ROOT` / `ACTION_CHROME_COMPANION_PROFILE_ROOT` | Root for named profiles |
| `ACTION_BROWSER_DEBUG_PORT` | CDP port (MCP default `9334`) |
| `ACTION_ROOT` | Monorepo root (needed for cookie tools when MCP is not cwd-rooted) |

## Cookie seeding

Copy **selected** cookies from personal Chrome into an Action profile:

```bash
# list personal Chrome profiles
bun run chrome:companion:import:cookies -- --list-profiles

# list Action profiles
bun run chrome:companion:import:cookies -- --list-action-profiles

# dry-run
bun run chrome:companion:import:cookies -- list --into coding --domains github.com

# write
bun run chrome:companion:import:cookies -- import --into coding --domains github.com --confirm

# narrow cookies
bun run chrome:companion:import:cookies -- import --into mira \
  --domains midjourney.com \
  --only cf_clearance \
  --confirm
```

Or via profile CLI:

```bash
bun run chrome:companion:profile -- import-cookies import --into coding --domains github.com --confirm
```

Notes:

- Requires a Keychain allow for Chrome Safe Storage only when decrypting values;
  the import path copies encrypted blobs as-is for same-machine use.
- Prefer domain allowlists over full-jar dumps.
- Cookies are not a complete identity (localStorage / passkeys may still need a
  one-time interactive login in the Action profile).

## Chrome Companion (generic extension)

Package: `packages/chrome-companion`

- Manifest V3 extension with DOM observe / resolve / act helpers
- Localhost bridge on `http://127.0.0.1:4321` (WebSocket for the extension)
- One-time **Load unpacked** per Action profile (`dist/` after build)

```bash
bun run chrome:companion:build
bun run chrome:companion:bridge
bun run chrome:companion:health
bun run chrome:companion:profile -- setup coding
```

Chrome Stable often ignores `--load-extension`; the reliable path is manual
unpacked install inside the Action-owned profile.

## Action Browser MCP

Server: `plugins/action-browser/server/index.ts`

### Tools

| Tool | Purpose |
|------|---------|
| `browser_profiles` | List Action profiles + policy summary |
| `browser_use_profile` | Switch active identity (`coding`, `mira`, …) |
| `browser_profile_info` | Active path, cookies readiness, companion hints |
| `browser_import_cookies` | Dry-run or confirm seed from personal Chrome |
| `browser_companion_status` | Extension dist + bridge health |
| `browser_open` | Open URL in the session's working tab; optional `profile` or `newTab: true` |
| `browser_tabs` / `browser_snapshot` / `browser_click` / `browser_fill` / `browser_screenshot` / `browser_close` | Page automation via CDP |

### Claude Code (native Action MCP vs browser)

- **Native runtime MCP** (`action`): observe/act/record on macOS via Action.app
- **Browser MCP** (`action-browser` plugin or local stdio): Chrome identities + CDP

Install browser plugin (marketplace):

```bash
claude plugin marketplace add arach/action
claude plugin install action-browser@action --scope user
```

Or point Claude at the local server with a default identity:

```bash
claude mcp add action-browser -s user \
  -e ACTION_ROOT=/Users/arach/dev/action \
  -e ACTION_BROWSER_PROFILE=coding \
  -- /Users/arach/.bun/bin/bun /Users/arach/dev/action/plugins/action-browser/server/index.ts
```

### Agent workflow

```text
browser_profiles
browser_use_profile { profile: "coding" }
# first time only: seed logins
browser_import_cookies { into: "coding", domains: ["github.com"], confirm: false }
browser_import_cookies { into: "coding", domains: ["github.com"], confirm: true }
browser_open { url: "https://github.com", profile: "coding" }
browser_screenshot
browser_companion_status   # optional richer DOM path
```

## What is intentionally not done

- Automatic attach to the currently open personal Chrome window
- Silent full cookie jar import
- Claiming a page is authenticated without observing it after seed/login

## Related

- [packages/chrome-companion/README.md](../packages/chrome-companion/README.md)
- [ACT-001 surface adapter architecture](decisions/ACT-001-surface-adapter-architecture.md)
- [plugins/action-browser/skills/action-browser/SKILL.md](../plugins/action-browser/skills/action-browser/SKILL.md)
