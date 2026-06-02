# Chia Poker Platform

Global-scale poker platform scaffold with **off-chain authoritative gameplay** and **Chia blockchain settlement** via [chia-gaming](https://github.com/Chia-Network/chia-gaming) state channels.

## Quick start

```bash
cd chia-poker
corepack enable
pnpm install
pnpm build
pnpm test

# Terminal 1 — REST API
pnpm dev:api

# Terminal 2 — WebSocket gateway
pnpm dev:gateway
```

Copy `.env.example` to `.env` and adjust Chia Gaming URLs when running the official lobby/game Docker stack.

## Monorepo layout

| Path | Purpose |
|------|---------|
| `packages/game-engine` | Deterministic NLHE engine, commit-reveal shuffle, hand evaluation |
| `packages/chia-bridge` | chia-gaming lobby adapter, settlement proofs |
| `packages/shared` | Types, variant catalog, event schemas |
| `services/api` | REST API (tables, variants, health) |
| `services/gateway` | WebSocket realtime scaffold |
| `docs/` | Architecture, roadmap, scaling, security |

## Chia Gaming integration

Head-to-head games (e.g. **California Poker / Calpoker**) map directly to Chia state channels. Multi-player ring games and tournaments use this repo’s off-chain engine with periodic on-chain settlement anchors.

See [docs/CHIA_INTEGRATION.md](./docs/CHIA_INTEGRATION.md).

## API (dev)

- `GET /health` — API health
- `GET /health/chia-gaming` — Lobby reachability
- `GET /v1/variants` — Supported poker variants
- `POST /v1/tables` — Create NLHE table
- `GET /v1/tables/:id` — Table state
- `POST /v1/tables/:id/seat` — Seat player

Gateway: `ws://localhost:4100/ws` — subscribe/ping protocol (MVP).

## Roadmap

See [docs/ROADMAP.md](./docs/ROADMAP.md) for phased delivery toward 100k+ concurrent players.

## License

MIT
