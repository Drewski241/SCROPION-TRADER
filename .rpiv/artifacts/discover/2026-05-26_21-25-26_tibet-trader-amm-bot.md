---
date: 2026-05-26T21:25:26-0500
author: AbandonedLand
commit: f60f50a
branch: main
repository: TibetTrader
topic: TibetTrader AMM Bot
tags: [intent, frd, SilentBot, trader, SQLite, Dexie, TibetSwap, SageWallet]
status: complete
last_updated: 2026-05-26T21:25:26-0500
last_updated_by: AbandonedLand
---

# FRD: TibetTrader AMM Bot

## Summary

A PowerShell-based Automated Market Maker (AMM) bot that maintains concentrated liquidity positions tracked in a local SQLite database and periodically scans TibetSwap and Dexie.space for profitable trade opportunities. When an offer meets the bot's profit criteria (evaluated using the existing `Adjust_X_Amount` AMM math), it auto-executes through the SageWallet on the Chia blockchain. All trades are logged with full P&L detail, enabling cumulative profit analysis per token, per bot, and over arbitrary time periods. The bot runs as a single persistent process with configurable scan intervals, profit thresholds, and API endpoints.

## Problem & Intent

"I'm working on a powershell script that interacts with the Chia Blockchain through SageWallet, TibetSwap and Dexie.space. I have a good start already. The idea behind this is to make a Uniswap v3 type of AMM, but instead of puting money into a liquidity pool, I want to track the liquidity pool internally though sqlite. and look at dexie and tibetswap periodically to see if any of the offers are acceptable to my AMM bot. I also want to log all the trades so I can do a Profit and Loss analysis on my bots."

## Goals

- **Auto-scan both DEXes**: Periodically poll Dexie.space (for sell offers) and TibetSwap (for price quotes) at a configurable interval to find trade opportunities.
- **Auto-execute profitable trades**: Evaluate offers against the bot's AMM state using `Adjust_X_Amount` — a trade is profitable when the offer gives more Y than the formula demands, or costs less Y than the formula demands.
- **Full P&L logging**: Record every executed trade with dx, dy, profit_x, profit_y, fee details, and support summary queries for cumulative P&L per token, per bot, and over arbitrary time periods.
- **JSON configuration**: Externalize API URLs, SQLite DB path, scan intervals, and profit thresholds into a JSON config file — separate config from code.
- **Trade lock (single trade at a time)**: The bot stops processing after initiating a trade and waits for blockchain confirmation or offer expiration before resuming the scan loop.
- **Fix existing bug**: Correct `$this.yx` → `$this.yr` on `trader.ps1:425` to fix Y-side trade execution.

## Non-Goals

- Liquidity rebalancing (restoring position after a trade)
- Multi-bot management from a single config (run multiple instances separately)
- Live dashboards, web UI, or real-time monitoring
- Telegram/Discord notifications
- On-chain pool deployment (all liquidity is tracked locally)
- Config reload without restart
- Test script / mocking layer

## Functional Requirements

1. **FR-1**: The system SHALL periodically poll Dexie.space for sell offers and TibetSwap for price quotes at an interval configured in the JSON config file.
2. **FR-2**: The system SHALL evaluate each offer against the bot's AMM state using `Adjust_X_Amount` — determining profitability by comparing offer dx/dy terms against the formula's computed dx/dy.
3. **FR-3**: For Dexie trades, the system SHALL execute via `Read-SageOffer` + `Complete-SageOffer` (existing flow, preserved).
4. **FR-4**: For TibetSwap trades, the system SHALL build an offer file via SageWallet and submit it to TibetSwap (user will provide the implementation function; this FR defines the integration point).
5. **FR-5**: The system SHALL lock during trade execution — stopping the scan loop until the trade is confirmed on-chain or the offer expires (whichever comes first).
6. **FR-6**: The system SHALL log every executed trade to the `trades` table with bot_id, offer_id, dx, dy, profit_x, profit_y, and timestamp.
7. **FR-7**: The system SHALL support P&L summary queries returning cumulative profit per token, per bot, and over user-specified time periods.
8. **FR-8**: The system SHALL read configuration from a JSON config file containing API URLs, SQLite DB path, scan interval, and profit threshold settings.
9. **FR-9**: The system SHALL implement configurable retry logic — on API error, retry up to 3 times with exponential backoff (5s base), then log the failure to the `events` table and continue the next scan cycle.
10. **FR-10**: The system SHALL fix the `$this.yx` → `$this.yr` bug on `trader.ps1:425` to enable correct Y-side trade execution.

## Non-Functional Requirements

- **Performance**: Scanner interval is configurable (default ~30s); each API call should complete within 10 seconds before triggering the retry logic. No high-frequency trading requirements.
- **Security**: Wallet fingerprint stored in plaintext in SQLite. SageWallet RPC handles blockchain authentication externally (not in scope to change). Config file should not contain secrets.
- **Reliability**: Retry with exponential backoff on API errors. Failed trades logged to `events` table. Bot state persists to SQLite on every save — survives restart without loss of bot definitions.
- **Consistency**: Single-trade-at-a-time execution ensures no concurrent trades on the same bot. Bot state (`state` column) transitions to a locking state during trade execution and resumes afterward.

## Constraints & Assumptions

- **Technical**: The `bots` table defines per-bot constraints (X/Y values, max amounts, price range `pa`/`pb`). Only one trade executes per bot at a time.
- **Technical**: TibetSwap execution uses a different flow than Dexie — offer file must be built via SageWallet and submitted to TibetSwap (not a simple accept-offer). User will provide the TibetSwap offer-building function.
- **Technical**: Chia blockchain confirmation time is 10-30 seconds; trade lock must account for this.
- **Environmental**: Depends on external PowerShell modules (Spectre.Console, SageWallet RPC, Dexie module, TibetSwap module) not in the repository.
- **Assumption**: The existing AMM math in `SilentBot` (concentrated liquidity, `pa`/`pb` bounds, `Adjust_X_Amount`/`Adjust_Y_Amount`) is correct and should not be modified.
- **Assumption**: Dexie offers are pre-existing sell orders that can be accepted via `Complete-SageOffer`.

## Acceptance Criteria

- [ ] Running the PowerShell script starts a scanner loop that polls Dexie.space and TibetSwap at the configured interval (read from JSON config).
- [ ] A profitable Dexie offer is auto-accepted via `Read-SageOffer` + `Complete-SageOffer` and logged to the `trades` table with correct dx, dy, and profit values.
- [ ] The TibetSwap trade path is wired up as an integration point (calls user's offer-building function) — execution follows the build-offer-then-submit flow.
- [ ] P&L summary query returns correct cumulative profit per token, per bot, and for a user-specified date range.
- [ ] JSON config file is read on startup and controls API URLs, DB path, scan interval, and profit threshold.
- [ ] Bot locks during trade execution — scan loop pauses until the trade is confirmed or the offer expires.
- [ ] The `$this.yx` bug on `trader.ps1:425` is fixed to `$this.yr` — Y-side trades compute correctly.
- [ ] API errors trigger up to 3 retries with exponential backoff (5s base); failures beyond retry count are logged to the `events` table.

## Recommended Approach

A single PowerShell process (`trader.ps1`) that reads a JSON config on startup, loads bot definitions from SQLite, and runs a periodic scanner loop. On each cycle, it queries Dexie.space for offers and TibetSwap for quotes, evaluates profitability via `Adjust_X_Amount` against each bot's AMM state, and auto-executes profitable trades through SageWallet (Dexie: accept existing offer; TibetSwap: build and submit offer file). Trade lock prevents concurrent execution per bot. All trades are logged with full P&L detail to SQLite, with summary queries for analysis.

## Decisions

### AMM Math Model
**Question**: Keep the existing concentrated liquidity AMM math (pa/pb bounds, Adjust_X_Amount), or change the model?
**Recommended**: Keep existing — the concentrated liquidity model is already correct and implemented in SilentBot.
**Chosen**: Keep existing concentrated liquidity model with pa/pb bounded price range.
**Rationale**: Developer confirmed — the existing math (`liquidity = amount / (1/√pa - 1/√pb)`) is the desired model. No changes needed.

### DEX Execution Targets
**Question**: Which DEXes should the bot auto-execute trades on?
**Recommended**: Both Dexie.space and TibetSwap for best price discovery.
**Chosen**: Both Dexie.space and TibetSwap.
**Rationale**: Developer confirmed both DEXes as execution targets.

### P&L Granularity
**Question**: How granular should P&L logging be?
**Recommended**: Full P&L — per-trade detail plus summary queries for cumulative profit per token and per bot.
**Chosen**: Full P&L — per-trade dx, dy, profit_x, profit_y, fees; plus summary queries.
**Rationale**: Developer confirmed full P&L with summaries.

### Configuration Approach
**Question**: Should API endpoints, DB path, and intervals be in a config file or hardcoded?
**Recommended**: JSON config file to separate config from code.
**Chosen**: JSON config file with API URLs, DB path, scan interval, profit threshold, and retry settings.
**Rationale**: Developer confirmed. Hardcoded values in trader.ps1 will be parameterized.

### Bug Fix
**Question**: Fix the `$this.yx` → `$this.yr` bug on trader.ps1:425 now or later?
**Recommended**: Fix now — the bug breaks Y-side trade execution.
**Chosen**: Fix now.
**Rationale**: Developer confirmed. The typo prevents correct balance checking on Y-side trades.

### Profit Determination
**Question**: How should profitability of an offer be determined?
**Recommended**: Use the existing `Adjust_X_Amount` function comparing offer terms against AMM formula output.
**Chosen**: `Adjust_X_Amount` — a profitable trade is when getting more Y than the formula demands, or spending less Y than the formula demands.
**Rationale**: Developer's own words — the profit determination logic is already encoded in `checkDexieOfferAgainstBot()` and `Adjust_X_Amount()`. No new formula needed.

### Trade Lock (Single Trade at a Time)
**Question**: How should concurrent trade execution be prevented?
**Recommended**: Trade lock — bot stops scanning while a trade is in flight, resumes after confirmation or offer expiry.
**Chosen**: Single trade at a time with trade lock; bot stops processing until trade is verified or offer expires.
**Rationale**: Developer confirmed. Bot constraints (X/Y amounts, price range) are already confined in the `bots` table.

### Scanner Retry Strategy
**Question**: How should API errors (Dexie/TibetSwap downtime) be handled?
**Recommended**: Configurable interval + retry with exponential backoff (3x, 5s base).
**Chosen**: Retry up to 3 times with exponential backoff (5s base); log failures to `events` table.
**Rationale**: Developer confirmed. Graceful degradation — bot continues scanning after errors rather than crashing.

### TibetSwap Execution Flow
**Question**: How does TibetSwap trade execution work?
**Recommended**: Build offer file via SageWallet → submit to TibetSwap (different from Dexie's accept-offer flow).
**Chosen**: TibetSwap: build offer file via SageWallet, then submit to TibetSwap. User will provide the offer-building function; this FR defines the integration point.
**Rationale**: Developer clarified the TibetSwap flow is different from Dexie. The integration point is defined; implementation of the offer-building function is provided by the developer.

### Bot Lifecycle
**Question**: Single persistent process or multiple named bots with lifecycle commands?
**Recommended**: Single persistent process that runs until killed.
**Chosen**: Single process — one PowerShell script with a scanner loop, start once and run until Ctrl-C.
**Rationale**: Developer confirmed. No need for complex lifecycle management.

### Acceptance Criteria Scope
**Question**: What should be the scope of acceptance criteria?
**Recommended**: Scanner + trade flow + P&L + config + trade lock + bug fix. No live config reload or test scripts.
**Chosen**: 8 concrete acceptance criteria covering scanner, Dexie execution, TibetSwap integration, P&L queries, JSON config, trade lock, bug fix, and retry logic.
**Rationale**: Developer confirmed the full scope. Explicitly excluded: live config reload and test scripts.

## Open Questions
- None explicitly deferred by the developer.

## Suggested Follow-ups
- **Liquidity rebalancing**: After a trade, the bot goes to a locked/inactive state and does not restore its position. Rebalancing would compute the optimal X/Y allocation at the new price and refill the pool. (`trader.ps1:242` — state set to 3 after trade, no auto-rebalancing)
- **Bot state enum mapping**: `states` table has string values (`ready`, `offer_pending`, `disabled`) but `bots.state` uses raw integers (1, 3). These are not wired together. (`migrations.ps1:29-36`)
- **Unused `events` table**: The `events` table (`migrations.ps1:53-61`) has an incomplete schema (no types for `event`/`event_status`). Could be expanded for richer audit logging.
- **Typo dead alias**: `Invoke-SQLDataUpate()` on `trader.ps1:636` is a misspelled wrapper of `Invoke-SQLDataUpdate()` — dead code that should be removed. (`trader.ps1:636-648`)
- **Invert price logic**: The `invert_price` and `x_is_spread_token` fields are defined but not fully exercised in the trade execution path. (`trader.ps1:42-46`)
- **No .gitignore or README**: Project has no documentation or gitignore. Could benefit from a README explaining setup and dependencies.

## References
- Input: Developer feature description (free-text prompt)
- `trader.ps1` — Core AMM bot implementation (SilentBot class, ~650 lines)
- `migrations.ps1` — SQLite schema definitions (bots, trades, events, states tables)
