# Roadmap

## Phase 0 — Foundation (current)

- [x] Monorepo scaffold
- [x] NLHE engine with commit-reveal shuffle
- [x] Hand evaluator (showdown)
- [x] REST API + WebSocket gateway skeleton
- [x] chia-gaming client adapter
- [x] Architecture + security docs

## Phase 1 — Playable MVP

- [ ] Web client (table UI, action buttons)
- [ ] Full hand lifecycle API (start, seed, action, showdown)
- [ ] Postgres persistence for tables/hands/events
- [ ] Redis pub/sub for gateway fanout
- [ ] Docker Compose dev stack
- [ ] chia-gaming simulator E2E

## Phase 2 — Multi-variant

- [ ] PLO4 / PLO5 engines
- [ ] SNG + MTT schedulers
- [ ] Calpoker route through chia-gaming native flow
- [ ] Rake accounting + ledger

## Phase 3 — Scale (10k–100k concurrent)

- [ ] Regional game shards + session router
- [ ] Kafka (or NATS) event backbone
- [ ] Autoscaling (K8s) + HPA on CPU/action rate
- [ ] Global Redis cluster for hot state
- [ ] CockroachDB or Aurora for durable ledger
- [ ] CDN + Anycast edge gateways
- [ ] Load tests (k6) with SLO targets

## Phase 4 — Enterprise (GGPoker-class ops)

- [ ] KYC / AML integrations
- [ ] Anti-bot + collusion ML pipeline
- [ ] 24/7 SRE runbooks, incident response
- [ ] Responsible gaming tooling
- [ ] Multi-jurisdiction licensing support
- [ ] External security audits

## Non-goals (for now)

- Putting every fold/call on-chain (too slow/expensive)
- Single monolithic server for global traffic
