# Scaling to 100k+ Concurrent Players

## Capacity model (rough)

Assume average **80 hands/hour/table**, **9-handed** tables, **6s/action** budget:

| Metric | Target |
|--------|--------|
| Concurrent players | 100,000 |
| Avg players per table | 7 |
| Active tables | ~14,300 |
| Actions/sec (global) | ~3,000–8,000 peak |

Off-chain authoritative servers handle this; Chia handles **session boundaries** and **settlements**, not per-action writes.

## Topology

1. **Edge gateways** — Stateless WebSocket terminators (10–50 regions).
2. **Session router** — Consistent hash on `tableId` → game shard.
3. **Game shards** — 500–2,000 tables each; in-memory state + Redis checkpoint.
4. **Event bus** — All hand events to Kafka for analytics, fraud, settlement.
5. **Settlement workers** — Batch Chia transactions per table/tournament window.

## Data tiers

| Tier | Store | Use |
|------|-------|-----|
| Hot | Redis | Active hand state, presence, pub/sub |
| Warm | Postgres shard | Hand history, player stats |
| Cold | S3 + Parquet | ML training, regulatory export |

## Failure domains

- Shard loss → restore hand from Redis snapshot + event replay
- Gateway loss → clients reconnect; router reassigns
- Chia congestion → queue settlements with retry + fee bump policy

## Load testing gates

Before production scale:

- 5k synthetic tables on one shard (soak 1h)
- 50k WS connections across 5 gateway pods
- p99 action latency < 150ms within region
- Zero data loss on chaos kill of game pod mid-hand
