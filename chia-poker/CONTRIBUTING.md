# Contributing

## Setup

```bash
cd chia-poker
corepack enable
pnpm install
pnpm build
pnpm test
```

## Branch naming

Use feature branches off `main`. Cloud agent branches use `cursor/<description>-2897`.

## Pull requests

- Keep changes focused on one concern
- Run `pnpm test` and `pnpm typecheck` before opening
- Update docs when changing architecture or public APIs
