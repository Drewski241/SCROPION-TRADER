---
date: 2026-05-26T21:53:00-0500
author: AbandonedLand
commit: f60f50a
branch: main
repository: TibetTrader
topic: "TibetTrader AMM Bot Research"
tags: [research, codebase, SilentBot, SQLite, PowerShell, AMM, Dexie, TibetSwap]
status: complete
last_updated: 2026-05-26T21:55:00-0500
last_updated_by: AbandonedLand
last_updated_note: "Added follow-up research for TibetTrader AMM bot — scanner loop, config, trade lock, P&L, retry"
---

# Research: TibetTrader AMM Bot

## Research Question

Research the TibetTrader codebase to understand the current state of the AMM bot implementation and identify all gaps between the FRD (`.rpiv/artifacts/discover/2026-05-26_21-25-26_tibet-trader-amm-bot.md`) and the current code. The FRD defines 10 functional requirements including a JSON config file, scanner loop, trade lock, P&L logging, retry logic, and a bug fix. The codebase consists of two files: `trader.ps1` (~650 lines, SilentBot class) and `migrations.ps1` (~64 lines, SQLite schema).

## Summary

The codebase is a **library of class and function definitions with zero orchestration**. No scanner loop, no JSON config loader, no entry point, and no production error handling exist. All API URLs and the database path are hardcoded string literals. The `SilentBot` class implements correct concentrated-liquidity AMM math (`Adjust_X_Amount`/`Adjust_Y_Amount`) and a profitability evaluation pipeline (`checkDexieOfferAgainstBot`), but its trade execution method (`TakeDexieOffer`) contains a **critical branch inversion** (X-side trades enter the Y-side branch and vice versa) and a **null-reference typo** (`$this.yx` instead of `$this.yr`). The `states` table defines `offer_pending=2` as a lock state but it is never written. The `events` table is provisioned but never written to. The `trades` table is written to (trade logging) but never queried (no P&L summaries). The FRD's required features (JSON config, scanner loop, retry logic, P&L queries, TibetSwap integration) have zero implementation.

## Detailed Findings

### Core Architecture — Zero Orchestration
- `trader.ps1:1-650` contains only function/class definitions — **zero script-scope executable code**
- No `while`, `for`, `do`, or `Start-Sleep` constructs exist outside input validation (lines 101, 110, 129, 143 — all inside the interactive `SilentBot()` constructor)
- No `Run()`, `Start()`, `Main()`, or `Run-Loop()` method on `SilentBot`
- `migrations.ps1:65` — `Invoke-MigrateSql()` is defined but **never called anywhere** in the repo
- `SilentBot.Load()` at `trader.ps1:194` queries the `bots` table, but if `Invoke-MigrateSql()` hasn't run first, the table doesn't exist and the query throws

### JSON Config — All Values Hardcoded
| Hardcoded Value | Location | Line |
|---|---|---|
| `https://api.v2.tibetswap.io/pairs` | `Get-TTPairs()` | `trader.ps1:8` |
| `https://dexie.space/v1/assets?page_size=25&filter=` | `Get-TTPairs()` | `trader.ps1:15` |
| `~/.trader/tt.sqlite` | `Get-TTDatabase()` | `trader.ps1:36` |
| `'xch'` default token | `SilentBot()` constructor | `trader.ps1:66` |
- Zero `ConvertFrom-Json` references in the entire codebase
- `Get-TTDatabase()` is called at 6 call sites, all returning the hardcoded path
- Recommended pattern: `$script:Config = Get-Content "$PSScriptRoot\config.json" | ConvertFrom-Json` at top of `trader.ps1`

### Trade Lock — State Machine Defects
- `migrations.ps1:29-36` defines `states` table: `ready=1`, `offer_pending=2`, `disabled=3`
- `trader.ps1:61` — `[int]$state = 3` (default: disabled)
- `trader.ps1:277` — `activate()` sets `state = 1`
- `trader.ps1:270` — `deactivate()` sets `state = 3`
- `trader.ps1:570/584` — `TakeDexieOffer()` sets `state = 3` after trade (should be `state = 1` per FRD decision — lock is state 2)
- **State 2 (`offer_pending`) is never written** — the intended trade lock state is absent
- The `states` table is never JOINed or queried — `bots.state` uses raw integers exclusively
- FRD decision: State 2 should be used as the actual trade lock. State 3 = disabled (permanent stop).

### Branch Inversion Bug (Critical)
- `trader.ps1:563` — `if($check.bot.dx -lt 0)` — **should be `dx -gt 0`** (X-side trades have positive dx)
- `trader.ps1:573` — `if($check.bot.dy -lt 0)` — **should be `dy -gt 0`** (Y-side trades have positive dy)
- Root cause: `checkDexieOfferAgainstBot` computes `dx`/`dy` with sign conventions that invert the branch logic
- X-side trades (caller offers X, bot gives Y): `dx > 0`, `dy < 0` → enters Y-side branch (line 573)
- Y-side trades (caller offers Y, bot gives X): `dx < 0`, `dy > 0` → enters X-side branch (line 563)

### `$this.yx` Null Reference Bug
- `trader.ps1:577` — `if(($this.yr + $check.bot.yx) -lt 0)` — `$this.yx` is undefined on `SilentBot`
- `trader.ps1:581` — `$check.bot.yx` — should be `$check.bot.dy` (matching pattern of `check.bot.dx` at line 566)
- `$this.yx` → `$null` → `($this.yr + $null)` → `$this.yr` → balance check is effectively a no-op
- `$check.bot.yx` → hashtable key lookup for missing key → `$null` → same no-op effect
- Zero additional references to `.yx` in the codebase — isolated typo

### Profitability Evaluation — All Profit in Y Terms
- `trader.ps1:442-465` — `Adjust_X_Amount()` implements concentrated-liquidity formula correctly
  - `newxr = xr + amount`, `new_y = liquidity_squared / (newxr + xv)`, `dy = newyr - yr`
  - `dy` is the change in the bot's Y reserves — this is the single profit metric
- `trader.ps1:471-493` — `Adjust_Y_Amount()` is **dead code** — never called anywhere
- `trader.ps1:515-545` — `checkDexieOfferAgainstBot()` correctly compares offer terms against AMM formula:
  - Branch A (`token_x`, line 518-529): `profit = requested_Y - dy` (dy is negative, so = `requested + |dy|`)
  - Branch B (`token_y_id`, line 530-542): `profit = offered_Y - dy` (dy is positive, so = `offered - |dy|`)
- **All profit flows through `profit_y`** — `Adjust_X_Amount` computes `dy` (Y-change) in every case. There is no separate X-profit dimension. `profit_x` stays 0 (correct by design).

### TibetSwap Integration — Zero Implementation
- `trader.ps1:506-512` — `tibetQuoteFromX()` defined but **never called** (dead method)
- `trader.ps1:494-503` — `dexieOffersFromX()` defined but **never called** (dead method)
- No `TakeTibetSwapOffer()` method exists
- No offer-file building, no TibetSwap submission flow
- `ConvertTo-XchMojo` is called at `trader.ps1:509` but not defined in the repo (external module function)
- FRD: Integration point should be a new `TakeTibetSwapOffer()` method parallel to `TakeDexieOffer()`

### P&L Summary — Write-Only Logging
- `trader.ps1:595-633` — `Invoke-SQLDataUpdate()` inserts into `trades` table with `status = "pending"`
- `trader.ps1:569/583` — `profit_x` always hardcoded to `0`, all profit in `profit_y` (correct — `Adjust_X_Amount` prices all trades relative to Y-reserves)
- **Zero SQL aggregation queries exist** — no `SUM`, `GROUP BY`, `AVG`, or `SELECT` against the `trades` table
- `status` column is **dead** — always `"pending"`, never updated to `"completed"` or any other value
- No on-chain confirmation flow to update trade status

### Retry Logic — Zero Protection
- `trader.ps1:25` — only API error handling: `try/catch` in `Get-TTPairs()` that `throw`s (crashes)
- All other API calls have **zero** `try/catch`:
  - `trader.ps1:15` — `Invoke-RestMethod` for Dexie (bare)
  - `trader.ps1:497/500` — `Get-DexieOffers` (bare)
  - `trader.ps1:508/510` — `Get-TibetQuote` (bare)
  - `trader.ps1:567/581` — `Read-SageOffer` (bare)
  - `trader.ps1:568/582` — `Complete-SageOffer` (bare)
  - `trader.ps1:152/240` — `Invoke-SageRPC` (bare)
- `migrations.ps1:53-61` — `events` table provisioned but **never written to** (zero INSERT statements)
- FRD: Retry with 3 attempts, exponential backoff (5s base), log failures to `events` table

### Post-Trade AMM State — Stale Reserves
- `Adjust_X_Amount()` is a **pure function** — returns a trade object without mutating `$this.xr` or `$this.yr`
- Neither `checkDexieOfferAgainstBot()` nor `TakeDexieOffer()` writes back `newxr`/`newyr` from the trade object
- `trader.ps1:289-403` — `save()` serializes the original (pre-trade) `xr`/`yr` values to the database
- On subsequent cycles (if reactivated), `Adjust_X_Amount` uses **stale on-chain position data**
- FRD: Liquidity rebalancing excluded as non-goal. Bot remains locked until manual `activate()`.

### Dead Code & Schema Issues
- `trader.ps1:636-648` — `Invoke-SQLDataUpate()` (misspelled alias) — **dead code**, zero callers
- `trader.ps1:45` — `invert_price` — set, saved, loaded, but `Get_Price()` (line 426) is **never called**
- `trader.ps1:44` — `x_is_spread_token` — set, saved, loaded, but **never read** after assignment
- `migrations.ps1:53-61` — `events` table has incomplete schema (`event` and `event_status` columns have no type)
- `migrations.ps1:29-36` — `states` table never JOINed or queried

## Code References
- `trader.ps1:1-24` — Get-TTPairs function (hardcoded API URLs)
- `trader.ps1:31-36` — Get-TTDatabase function (hardcoded DB path)
- `trader.ps1:49-62` — SilentBot class definition (25 properties, state default=3)
- `trader.ps1:194-239` — SilentBot.Load() (SQLite query for bot state)
- `trader.ps1:289-403` — SilentBot.save() (INSERT/UPDATE for bot state)
- `trader.ps1:442-465` — Adjust_X_Amount() (core AMM math)
- `trader.ps1:471-493` — Adjust_Y_Amount() (dead code)
- `trader.ps1:515-545` — checkDexieOfferAgainstBot() (profitability evaluation)
- `trader.ps1:550-591` — TakeDexieOffer() (trade execution — branch inversion + typo bugs)
- `trader.ps1:595-633` — Invoke-SQLDataUpdate() (trade logging — write-only, profit_x always 0, all profit in profit_y)
- `trader.ps1:636-648` — Invoke-SQLDataUpate() (dead typo alias)
- `migrations.ps1:1-25` — bots table schema
- `migrations.ps1:29-36` — states table schema (dead lookup table)
- `migrations.ps1:37-47` — trades table schema
- `migrations.ps1:53-61` — events table schema (incomplete types)
- `migrations.ps1:65-74` — Invoke-MigrateSql / Invoke-MigrateFresh (never called)

## Integration Points

### Inbound References
- `trader.ps1:74` — `Get-TTPairs()` called from `SilentBot()` constructor (interactive setup)
- `trader.ps1:226` — `Get-TTDatabase()` called from `SilentBot.Load()`
- `trader.ps1:375/377/389` — `Get-TTDatabase()` called from `SilentBot.save()`
- `trader.ps1:633` — `Get-TTDatabase()` called from `Invoke-SQLDataUpdate()`
- `migrations.ps1:66-69` — `Get-TTDatabase()` called from `Invoke-MigrateSql()`
- `trader.ps1:518/531` — `Adjust_X_Amount()` called from `checkDexieOfferAgainstBot()`
- `trader.ps1:556` — `checkDexieOfferAgainstBot()` called from `TakeDexieOffer()`

### Outbound Dependencies
- `trader.ps1:8/15` — External API calls: `api.v2.tibetswap.io`, `dexie.space`
- `trader.ps1:152/240` — `Invoke-SageRPC` (SageWallet RPC module)
- `trader.ps1:497/500` — `Get-DexieOffers` (Dexie module)
- `trader.ps1:508/510` — `Get-TibetQuote` (TibetSwap module)
- `trader.ps1:567/581` — `Read-SageOffer` (SageWallet module)
- `trader.ps1:568/582` — `Complete-SageOffer` (SageWallet module)
- `trader.ps1:509` — `ConvertTo-XchMojo` (Chia module)

### Infrastructure Wiring
- `~/.trader/tt.sqlite` — SQLite database (path hardcoded, created by `Get-TTDatabase()`)
- `migrations.ps1:65` — `Invoke-MigrateSql()` creates 4 tables (bots, trades, events, states)
- No config file, no DI framework, no module imports — all dependencies are external PowerShell modules

## Architecture Insights
- **Single-file class pattern**: Everything lives in `trader.ps1` — no separation between class definitions, utility functions, and orchestration
- **State as integer enum**: `bots.state` stores opaque integers (1, 3) with no foreign key to the `states` lookup table
- **Pure AMM math**: `Adjust_X_Amount()` is designed as a stateless calculation — it returns a trade object without mutating the bot instance
- **Write-only trade logging**: Trades are inserted into the `trades` table but never queried, and `status` is never updated from `"pending"`
- **All profit in Y terms**: `Adjust_X_Amount` computes `dy` (Y-reserve change) in every branch — there is no separate X-profit dimension. `profit_x` stays 0, all profit flows through `profit_y`.
- **Interactive-first design**: The `SilentBot()` constructor is interactive (uses Spectre.Console prompts), while `Init()` is non-interactive (for DB loading) — these are two parallel entry paths
- **No error handling for production paths**: All API calls are unprotected — a single network error crashes the bot

## Precedents & Lessons
3 similar past changes analyzed.

### Precedent: Initial AMM Bot scaffold
**Commit(s)**: `98db7cb` — "initial commit" (2026-05-25)
**Blast radius**: 4 files across 3 layers
- `trader.ps1` (+538 lines) — SilentBot class skeleton with interactive setup flow, AMM math, basic SQLite helpers
- `migrations.ps1` (+38 lines) — bots/trades table schema
- `build/system.data.sqlite.core.1.0.112/` — SQLite .NET NuGet package

**Lessons from docs**:
- `.rpiv/artifacts/discover/2026-05-26_21-25-26_tibet-trader-amm-bot.md` — The FRD explicitly states: *"Assumption: The existing AMM math in SilentBot (concentrated liquidity, pa/pb bounds, Adjust_X_Amount/Adjust_Y_Amount) is correct and should not be modified."* This assumption was upheld.

**Takeaway**: The initial scaffold was conservative — it put the AMM class, SQLite schema, and interactive setup into the first commit without any test scaffolding.

### Precedent: SQLite functional migration & schema expansion
**Commit(s)**: `63d0429` — "sql functional" (2026-05-25)
**Blast radius**: 4 files across 3 layers
- `trader.ps1` (+339/-300) — Massive rewrite: Get-TTPairs gained Dexie.space fallback; SilentBot gained state, pair_id, token_y_id, created_at/updated_at
- `migrations.ps1` (+59/-0) — Schema expanded: 7 new bot columns, 7 new trade columns, new states and events tables

**Lessons from docs**:
- Schema grew by 25+ columns but left several fields (state enum mapping, events types, invert_price logic) half-wired — technical debt to track

**Takeaway**: Schema migrations should include a checklist of which fields are exercised by which methods.

### Precedent: AMM fee removal + scanner loop + trade execution methods
**Commit(s)**: `f60f50a` — "updated sql stuff" (2026-05-26)
**Blast radius**: 2 files across 2 layers
- `trader.ps1` (+160/-58) — Removed fee calculation from Adjust_X_Amount/Adjust_Y_Amount; added Dexie/TibetSwap methods, profitability evaluation, trade execution, SQL logging
- `migrations.ps1` (-12/+0) — Simplified trades table: removed token columns, required_profit columns, xr/xv/yr/yv columns — replaced with dx, dy

**Follow-up fixes**: None — this is the latest commit. No subsequent bugfix commits.

**Lessons from docs**:
- The `$this.yx` typo in `TakeDexieOffer` at line 577 is a fresh bug introduced in this commit that has NOT been fixed
- Fee logic removal means the trades table no longer records fee amounts — P&L analysis will be incomplete

**Takeaway**: The $this.yx → $this.yr typo recurs on every X/Y variable edit — consider adding a naming convention or lint rule.

### Composite Lessons
- **`$this.yx` → `$this.yr` typo persists**: The FRD explicitly called this fix as a requirement, but the latest commit introduced a *new instance* of the same typo in `TakeDexieOffer` at line 577. Every time X/Y variables are typed, this typo recurs.
- **Schema bloat with half-wired fields**: The `bots` table grew to 25+ columns but `invert_price`, `x_is_spread_token`, `state` enum, and `events` table types are not fully wired in code.
- **No follow-up fixes in git history**: All 3 commits have zero follow-up bugfix commits — bugs are not tracked in version control.
- **No test scaffolding**: From commit 1 to 3, no test files exist. All changes are untested in a critical-path trading system.

## Historical Context (from `.rpiv/artifacts/`)
- `.rpiv/artifacts/discover/2026-05-26_21-25-26_tibet-trader-amm-bot.md` — FRD defining 10 functional requirements for the AMM bot

## Follow-up Research 2026-05-26T21:55:00-0500

The developer corrected the profit calculation insight: since `Adjust_X_Amount` is the only AMM math function used (both in Branch A and Branch B of `checkDexieOfferAgainstBot`), all profit is computed in Y terms (`dy`). There is no separate X-profit dimension — `profit_x` is correctly hardcoded to 0, and all profit flows through `profit_y`. The developer checkpoint question about splitting profit by direction was incorrect and the original `profit_x = 0` design was right.

## Developer Context
**Q (`trader.ps1:563/573`): Found a critical branch inversion — X-side trades enter the Y-side branch and vice versa due to inverted `dx -lt 0` and `dy -lt 0` conditions. Should I fix both the branch conditions and the `$this.yx → $this.yr` typo together?**
A: Fix both now (Recommended).

**Q (`trader.ps1:569/583`): profit_x is hardcoded to 0 for all trades. Should profit be split by direction (X-side → profit_x, Y-side → profit_y) or keep everything in profit_y?**
A: Keep profit_x at 0. `Adjust_X_Amount` computes all profit in Y terms (`dy`) regardless of trade direction — the AMM formula prices trades relative to Y-reserves. All profit flows through `profit_y`.

**Q (`migrations.ps1:29-36`): The states table defines offer_pending=2 but it's never used. Should it be an actual trade lock state?**
A: Use state 2 as lock (Recommended).

**Q (`trader.ps1:570/584`): After a trade, the bot locks at state=3 and never updates xr/yr reserves. How should recovery work?**
A: I made a mistake when setting state to 3 after a trade. It should be set to 2 (offer_pending/locked during execution), then revert to 1 (ready) after the trade is successful. State 3 should be a flag to stop running any checks on this bot (disabled).

## Related Research
- None

## Open Questions
- None explicitly deferred by the developer.
