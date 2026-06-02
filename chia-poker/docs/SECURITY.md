# Security

## Threat model (summary)

| Threat | Mitigation |
|--------|------------|
| Server deck bias | Commit-reveal; publish `commitHash` before seeds |
| Client action spoofing | Server-authoritative validation; signed intents (planned) |
| Collusion / bots | Table isolation, behavior scoring, CAPTCHA/device attestation |
| Wallet / key theft | HSM, no hot keys in app servers, withdrawal limits |
| DDoS | WAF, rate limits, regional absorption |
| Insider abuse | Audit logs, dual control on treasury |

## Funds handling

1. **Development** — Use chia-gaming simulator only.
2. **Staging** — Testnet + low stakes; monitor known alpha fund-leak issues.
3. **Production** — Segregated treasury, multi-sig for large movements, reconciliation jobs.

## Compliance (planned)

- Age / geo verification before real-money play
- AML transaction monitoring
- Responsible gaming (limits, self-exclusion)
- Jurisdiction-specific feature flags

## Audit artifacts

Each completed hand should retain:

- Event log (JSON)
- `SettlementProof` with `stateRootHash`
- Optional `chiaTxId`
- Commit hash + revealed seeds (post-hand)

Retention policies depend on licensing jurisdiction.
