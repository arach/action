# Install Action

`action` is a native-first macOS app, so the shortest path is to build the signed `Action.app` bundle locally and verify the native host is healthy before debugging anything else.

## Requirements

- macOS on Apple Silicon
- Bun 1.3+
- Xcode command line tools / Swift build tooling

## 1. Clone

```bash
git clone git@github.com:arach/action.git
cd action
```

## 2. Install JS Dependencies

```bash
bun install
```

## 3. Build The App

```bash
bun run native:app:build
```

This produces:

`/Users/arach/dev/action/native/dist/Action.app`

## 4. Verify Native Health

```bash
bun run native:doctor
```

This is the recommended first check because it confirms:

- the app builds
- the app signs correctly
- the signature is valid
- current Accessibility and Screen Recording state

## 5. Launch

```bash
./scripts/action-dev launch
```

## 6. Optional Smoke Tests

Screenshot:

```bash
bun run native:test:screenshot
```

Recording:

```bash
bun run native:test:record
```

## Notes

- Accessibility and Screen Recording permissions may be required for capture flows.
- Recording completion is represented by the output artifact plus a finished marker file, not just the initial start acknowledgement.
