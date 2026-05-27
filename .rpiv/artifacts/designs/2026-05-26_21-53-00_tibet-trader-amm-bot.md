---
date: 2026-05-26T21:53:00-0500
author: AbandonedLand
commit: f60f50a
branch: main
repository: TibetTrader
topic: "TibetTrader AMM Bot Design"
tags: [design, scanner, config, retry, PS, SilentBot, SQLite, AMM]
status: in-progress
parent: .rpiv/artifacts/research/2026-05-26_21-53-00_tibet-trader-amm-bot.md
last_updated: 2026-05-26T21:53:00-0500
last_updated_by: AbandonedLand
---

# Design: TibetTrader AMM Bot Scanner Loop

## Summary

Append orchestration code to the existing single-file `trader.ps1`: a JSON config loader, per-API-call retry wrapper with exponential backoff, a main scanner loop with Ctrl-C handling, P&L summary queries, and bug fixes in `TakeDexieOffer()` (branch inversion, `$this.yx` typo, state machine recovery). The `SilentBot` class and SQLite helpers remain unchanged except for targeted bug fixes.

## Requirements

1. **FR-1**: Periodically poll Dexie.space for sell offers at a configurable interval
2. **FR-2**: Evaluate each offer against the bot's AMM state using `Adjust_X_Amount`
3. **FR-3**: Execute Dexie trades via `Read-SageOffer` + `Complete-SageOffer` (existing flow)
4. **FR-4**: TibetSwap integration point defined as stub — user provides offer-building function later
5. **FR-5**: Lock during trade execution — scan loop pauses until trade completes or fails
6. **FR-6**: Log every executed trade with dx, dy, profit_y, and timestamp
7. **FR-7**: Support P&L summary queries (cumulative profit per token, per bot, date range)
8. **FR-8**: Read configuration from JSON config file (API URLs, DB path, scan interval, retry settings)
9. **FR-9**: Per-API-call retry logic — 3 attempts, 5s base exponential backoff, log failures to events table
10. **FR-10**: Fix `$this.yx` → `$this.yr` bug in `TakeDexieOffer`

## Current State Analysis

### Key Discoveries

- `trader.ps1:1-650` — **Zero orchestration**: only function/class definitions. No `while`, `for`, `Start-Sleep`, or entry point outside the interactive constructor.
- `trader.ps1:563/573` — **Branch inversion**: `dx -lt 0` should be `dx -gt 0`, `dy -lt 0` should be `dy -gt 0`. X-side trades enter Y-side branch.
- `trader.ps1:577` — **Null reference typo**: `$this.yx` is undefined → `$null` → balance check is a no-op.
- `trader.ps1:570/584` — **Wrong state after trade**: sets `state = 3` (disabled/permanent stop) instead of state 1 (ready).
- `migrations.ps1:53-58` — **Dead events table**: incomplete schema (no column types for `event`, `event_status`, `created_at`), never written to.
- `migrations.ps1:11` — **Typo**: `NUMBERIC` instead of `NUMERIC` for `spread_percentage`.
- All API URLs and DB path are **hardcoded string literals** — 6+ call sites share the same values.
- `TakeDexieOffer()` at `trader.ps1:550-591` is the **only** trade executor — called 0 times internally (no scanner calls it).
- **Module surface**: PowerSage (`Invoke-SageRPC`, `Read-SageOffer`, `Complete-SageOffer`, `Get-SageKeys`), PowerDexie (`Get-DexieOffers`), PowerTibetSwap (`Get-TibetQuote`, `ConvertTo-XchMojo` from PowerSage), PSSQLite (`Invoke-SqliteQuery`).

### Patterns to Follow

- Single-file architecture — append new code to `trader.ps1` (existing pattern)
- Spectre.Console for output: `Write-SpectreHost`, `Invoke-SpectreCommandWithStatus` with color tags `[green]`, `[red]`, `[blue]`, `[yellow]`
- Heredoc SQL strings with parameterized queries via `Invoke-SqliteQuery -SqlParameters`
- Array-or-single-result handling: `$result -is [System.Array] ? $result[0] : $result`
- Try/catch with `throw` for fatal errors at `trader.ps1:11-23`

### Constraints

- The AMM math (`Adjust_X_Amount`, `Adjust_Y_Amount`) must NOT be modified — per FRD assumption
- The `SilentBot` class properties must NOT be renamed
- PowerShell 7.4+ required (per PowerSage minimum version)
- External modules are not in the repo — assumed pre-installed

## Scope

### Building

- JSON config loader with validation and required-field checking
- Per-API-call retry wrapper with exponential backoff (3 attempts, 5s base, 30s cap)
- Main scanner loop that loads active bots, polls Dexie offers, evaluates profitability, executes trades
- Ctrl-C graceful shutdown handler
- Bug fixes in `TakeDexieOffer()`: branch inversion, `$this.yx` → `$this.yr`, state values after trade
- Trade lock: state 2 during execution, recover to state 1 on success or failure
- P&L summary query function (cumulative per token, per bot, date range)
- Events table schema fix (add `details TEXT` column)
- Events table write for retry exhaustion logging
- TibetSwap integration stub (`TakeTibetSwapOffer` method with comment placeholder)

### Not Building

- TibetSwap full integration (stub only — user provides offer-building function)
- Liquidity rebalancing (restoring position after trade)
- Multi-bot management from a single config (separate instances only)
- Live dashboards, web UI, or real-time monitoring
- Telegram/Discord notifications
- Config reload without restart
- Test scripts / mocking layer
- On-chain confirmation flow (trade status stays "pending")

## Decisions

### Per-API-Call Retry (with Exponential Backoff)

**Ambiguity**: Should retry wrap each individual API call, or the entire scan cycle?

**Explored**:
- **Option A — Per-API-call retry**: Each API call (`Get-DexieOffers`, `Read-SageOffer`, etc.) gets its own retry wrapper. If Dexie times out, TibetSwap still runs. More resilient, follows FRD intent.
- **Option B — Per-scan-cycle retry**: The entire scan loop retries if any call fails. Simpler but one failing API blocks the entire cycle.

**Decision**: Per-API-call retry. Every function that calls an external API (`Get-DexieOffers`, `Read-SageOffer`, `Complete-SageOffer`, `Get-TTPairs`) is wrapped by `Invoke-WithRetry`. Configurable per-call (max retries, delay base). Retry exhaustion logs to the events table.

### TibetSwap Integration — Stub Only

**Ambiguity**: How deep should TibetSwap integration go — full with external function hook, or stub only?

**Explored**:
- **Option A — Full integration point**: `TakeTibetSwapOffer()` reads a config path to the user's offer-building function, calls it with AMM state, builds and submits the offer. Also wires `Get-TibetQuote` into scanner.
- **Option B — Stub only**: `TakeTibetSwapOffer()` defined but empty with parameter signature and comment. No TibetSwap API calls in scanner.

**Decision**: Stub only. Define `TakeTibetSwapOffer()` with the same signature pattern as `TakeDexieOffer`, include a comment indicating the user should fill in the offer-building call, and do NOT wire TibetSwap quote fetching into the scanner loop.

### Trade Lock — State 2 with Recovery

**Ambiguity**: When a trade fails mid-execution, should the bot resume scanning or stay locked?

**Explored**:
- **Option A — Recover to ready**: On failure (offer not accepted, RPC error, out-of-balance), set `state = 1` (ready), log event to `events` table, resume scanning. Only `state = 3` = permanent stop.
- **Option B — Stay locked**: On failure, keep `state = 2` (offer_pending), require `activate()` to resume. Prevents stale on-chain offers.

**Decision**: Recover to ready. The scanner loop itself is single-threaded so there's no risk of concurrent trades. A failed trade leaves no stale on-chain state (the offer was never completed).

### Events Table Schema

**Ambiguity**: The `events` table has no column types. What columns for retry/audit logging?

**Decision**: Add `details TEXT` column. Final schema:
```sql
events (
    id INTEGER PRIMARY KEY,
    bot_id INTEGER,
    event TEXT,           -- e.g., 'scan_error', 'trade_failed', 'retry_exhausted'
    event_status TEXT,    -- e.g., 'failed', 'retrying', 'resolved'
    details TEXT,         -- error message or context
    created_at TEXT
)
```

### File Organization — Single File

**Decision**: Keep everything in `trader.ps1`. Append config loader, retry wrapper, scanner loop, and bug fixes to the existing file. Preserves the single-file pattern established in commits 1–3.

## Architecture

### migrations.ps1:53-58 — MODIFY

Fix events table schema: add `details TEXT` column, add explicit types for `event`, `event_status`, `created_at`.

### migrations.ps1 — NEW (function)

Add `Invoke-MigrateEventsFix()` function that runs `ALTER TABLE events ADD COLUMN details TEXT IF NOT EXISTS` for safe migration of existing databases.

### trader.ps1:1-37 — MODIFY

Add `BotConfig` class, `Load-BotConfig` function, and script-level config loading after `Get-TTDatabase`:

```powershell
# ── Bot Configuration ──

class BotConfig {
    [string]$TokenY
    [string]$TokenYId
    [string]$Fingerprint
    [decimal]$StartPrice
    [decimal]$TargetPrice
    [decimal]$StartingAmount
    [boolean]$XIsDefault = $true
    [boolean]$XIsSpreadToken = $true
    [boolean]$InvertPrice = $false
    [int]$PollIntervalMs = 30000
    [int]$MaxRetries = 3
    [int]$RetryDelayBaseMs = 5000
    [string]$TibetSwapBaseUrl = "https://api.v2.tibetswap.io"
    [string]$DexieBaseUrl = "https://dexie.space/v1"
    [string]$DbPath = "~/.trader/tt.sqlite"
}

function Load-BotConfig {
    param (
        [string]$ConfigPath = "$PSScriptRoot\\bot-config.json"
    )

    if (-not (Test-Path $ConfigPath)) {
        Write-SpectreHost -Message "[red]Configuration file not found:[/] $ConfigPath"
        Write-SpectreHost -Message "Create one from the template: bot-config.json"
        throw "Missing bot-config.json"
    }

    try {
        $raw = Get-Content -Path $ConfigPath -Raw -ErrorAction Stop
        $data = $raw | ConvertFrom-Json

        $config = [BotConfig]::new()
        $config.TokenY           = $data.token_y
        $config.TokenYId         = if ($data.PSObject.Properties['token_y_id']) { $data.token_y_id } else { "" }
        $config.Fingerprint      = $data.fingerprint
        $config.StartPrice       = [decimal]$data.start_price
        $config.TargetPrice      = [decimal]$data.target_price
        $config.StartingAmount   = [decimal]$data.starting_amount
        $config.XIsDefault       = if ($data.PSObject.Properties['x_is_default']) { [bool]$data.x_is_default } else { $true }
        $config.XIsSpreadToken   = if ($data.PSObject.Properties['x_is_spread_token']) { [bool]$data.x_is_spread_token } else { $true }
        $config.InvertPrice      = if ($data.PSObject.Properties['invert_price']) { [bool]$data.invert_price } else { $false }
        $config.PollIntervalMs   = if ($data.PSObject.Properties['poll_interval_ms']) { [int]$data.poll_interval_ms } else { 30000 }
        $config.MaxRetries       = if ($data.PSObject.Properties['max_retries']) { [int]$data.max_retries } else { 3 }
        $config.RetryDelayBaseMs = if ($data.PSObject.Properties['retry_delay_base_ms']) { [int]$data.retry_delay_base_ms } else { 5000 }
        $config.TibetSwapBaseUrl = if ($data.PSObject.Properties['tibetswap_base_url']) { $data.tibetswap_base_url } else { "https://api.v2.tibetswap.io" }
        $config.DexieBaseUrl     = if ($data.PSObject.Properties['dexie_base_url'])     { $data.dexie_base_url }     else { "https://dexie.space/v1" }
        $config.DbPath           = if ($data.PSObject.Properties['db_path'])           { $data.db_path }           else { "~/.trader/tt.sqlite" }

        # Validate required fields
        $required = @('token_y', 'fingerprint', 'start_price', 'target_price', 'starting_amount')
        foreach ($field in $required) {
            $value = $data.PSObject.Properties[$field].Value
            if ($null -eq $value -or ($value -is [string] -and $value.Trim() -eq '')) {
                throw "Config field '$field' is required but was empty or missing."
            }
        }

        Write-SpectreHost -Message "[green]Config loaded:[/] Token=$($config.TokenY)  Fingerprint=$($config.Fingerprint)  Interval=$($config.PollIntervalMs)ms"
        return $config
    }
    catch {
        Write-SpectreHost -Message "[red]Failed to load config:[/] $_"
        throw
    }
}

# ── Load configuration at script start ──
$script:Config = Load-BotConfig
```

### bot-config.json — NEW

Template configuration file (gitignored):

```json
{
    "token_y": "MYTOKEN",
    "token_y_id": "",
    "fingerprint": "ABCD1234...",
    "start_price": 0.5,
    "target_price": 1.5,
    "starting_amount": 100,
    "x_is_default": true,
    "x_is_spread_token": true,
    "invert_price": false,
    "poll_interval_ms": 30000,
    "max_retries": 3,
    "retry_delay_base_ms": 5000,
    "tibetswap_base_url": "https://api.v2.tibetswap.io",
    "dexie_base_url": "https://dexie.space/v1",
    "db_path": "~/.trader/tt.sqlite"
}
```

### .gitignore — NEW

Exclude config, database, certs, and build artifacts:

```
# Configuration (contains wallet fingerprint)
bot-config.json
*.json

# Database
*.sqlite
.trader/

# Sage wallet certificates
*.pfx

# Build artifacts
build/
```

### trader.ps1:550-591 — MODIFY (Slice 2)

Fix TakeDexieOffer(): correct branch conditions, fix typo, fix state values, update error messages, ensure state recovery on all paths:

```powershell
    [void]TakeDexieOffer($dexie_offer){
        if($this.state -ne 1 -and $this.state -ne 2){
            Write-Error "System Not ready"
            return
        }

        # Enter trade lock state
        $this.state = 2
        $this.save()

        $check = $this.checkDexieOfferAgainstBot($dexie_offer)
        if(-Not $check.should_accept){
            Write-Error "This offer should not be accepted."
            $this.state = 1
            $this.save()
            return
        }

        if($check.bot.dx -gt 0){
            if(($this.yr + $check.bot.dy) -lt 0){
                Write-Error "Not enough $($this.token_y) to attempt"
                $this.state = 1
                $this.save()
                return
            } else {
                if((Read-SageOffer -offer $dexie_offer.offer) -eq "active"){
                    Complete-SageOffer -offer $dexie_offer.offer
                    Invoke-SQLDataUpdate -bot_id ($this.id) -offer_id ($dexie_offer.id) -profit_x 0 -profit_y ($check.profit) -dx ($check.bot.dx) -dy ($check.bot.dy)
                    $this.state = 1
                    $this.save()
                } else {
                    Write-Error "Offer not active."
                    $this.state = 1
                    $this.save()
                }
            }
        }
        if($check.bot.dy -gt 0){
            if(($this.xr + $check.bot.dx) -lt 0){
                Write-Error "Not enough $($this.token_x) to attempt"
                $this.state = 1
                $this.save()
                return
            } else {
                if((Read-SageOffer -offer $dexie_offer.offer) -eq "active"){
                    $accept = Complete-SageOffer -offer $dexie_offer.offer
                    Invoke-SQLDataUpdate -bot_id ($this.id) -offer_id ($dexie_offer.id) -profit_x 0 -profit_y ($check.profit) -dx ($check.bot.dx) -dy ($check.bot.dy)
                    $this.state = 1
                    $this.save()
                } else {
                    Write-Error "Offer not active."
                    $this.state = 1
                    $this.save()
                }
                
            }
        }

    }
```

### trader.ps1:after class — MODIFY (Slice 3)

Add `Invoke-WithRetry` function: generic retry wrapper with exponential backoff. Called by scanner loop for every API call. Logs to events table on exhaustion.

### trader.ps1:after retry — MODIFY (Slice 4)

Add `Run-ScannerLoop` function: main loop. Loads active bots from SQLite, polls Dexie offers, evaluates via `checkDexieOfferAgainstBot`, executes via `TakeDexieOffer` (fixed), sleeps interval. Ctrl-C handler registered.

### trader.ps1:after scanner — MODIFY (Slice 5)

Add `Get-PnLSummary` function: SQL aggregation queries for cumulative profit per token, per bot, and date range.

### trader.ps1:550-591 — MODIFY (Slice 6)

Fix branch inversion in `TakeDexieOffer()`: `dx -lt 0` → `dx -gt 0`, `dy -lt 0` → `dy -gt 0`. Update balance checks and error messages.

### trader.ps1:after trade methods — MODIFY (Slice 7)

Add `TakeTibetSwapOffer()` stub: method signature matching `TakeDexieOffer`, comment placeholder for user's offer-building function.

## Slices

### Slice 1: JSON Config Loader

**Files**: `trader.ps1` (NEW code appended), `bot-config.json` (NEW, gitignored), `.gitignore` (NEW)

#### Automated Verification:
- [ ] JSON config file parses without error: `Get-Content bot-config.json | ConvertFrom-Json`
- [ ] Required fields validated (throws if missing)
- [ ] Default values applied for optional fields
- [ ] `$script:Config` accessible from other functions after load

#### Manual Verification:
- [ ] Missing config file produces clear error message
- [ ] Invalid JSON produces parseable error
- [ ] Optional fields fall back to sensible defaults

### Slice 2: Trade Lock State Machine Fix

**Files**: `trader.ps1` (MODIFY `TakeDexieOffer`)

#### Automated Verification:
- [ ] State transitions: `state = 2` before trade, `state = 1` after success, `state = 1` after failure
- [ ] `$this.yr` referenced (not `$this.yx`) in Y-side branch
- [ ] Error message on Y-side branch says "Not enough [Y token] to attempt" (not "XCH")

#### Manual Verification:
- [ ] Bot resumes scanning after a successful trade (state = 1)
- [ ] Bot resumes scanning after a failed trade (state = 1)
- [ ] Bot stays disabled after `deactivate()` (state = 3)

### Slice 3: Retry Wrapper

**Files**: `trader.ps1` (NEW `Invoke-WithRetry` function)

#### Automated Verification:
- [ ] Retry counts attempts: 3 total calls before exhausting
- [ ] Delay doubles each retry: 5s, 10s, 20s (capped at 30s)
- [ ] Success on first try returns immediately
- [ ] Success on retry #2 returns result without logging event

#### Manual Verification:
- [ ] Retry exhaustion logs to events table with event = 'retry_exhausted'
- [ ] Spinner shown during retry wait
- [ ] Error message includes attempt count and operation name

### Slice 4: Main Scanner Loop

**Files**: `trader.ps1` (NEW `Run-ScannerLoop` function, Ctrl-C handler, entry point)

#### Automated Verification:
- [ ] Loop exits cleanly on Ctrl-C
- [ ] Sleep interval respected (within ±1s of configured value)
- [ ] Active bots loaded from database (state = 1)
- [ ] Failed API calls don't crash the loop

#### Manual Verification:
- [ ] Bot logs scan progress to console via Spectre output
- [ ] Profitable offers trigger `TakeDexieOffer`
- [ ] Unprofitable offers are skipped silently

### Slice 5: P&L Summary Queries

**Files**: `trader.ps1` (NEW `Get-PnLSummary` function)

#### Automated Verification:
- [ ] Query returns cumulative profit_y per bot
- [ ] Query supports date range filter (created_at BETWEEN)
- [ ] Query returns total cumulative profit_y across all bots
- [ ] SQL parameterized (no injection risk)

#### Manual Verification:
- [ ] Returns correct sums for known test data
- [ ] Empty trades table returns zero/null results gracefully

### Slice 6: Branch Inversion Fix

**Files**: `trader.ps1` (MODIFY `TakeDexieOffer` branch conditions)

#### Automated Verification:
- [ ] X-side trades (dx > 0, dy < 0) enter Y-side branch (checking yr balance)
- [ ] Y-side trades (dx < 0, dy > 0) enter X-side branch (checking xr balance)
- [ ] Balance check correctly compares reserves + delta

#### Manual Verification:
- [ ] X-for-Y trades execute correctly (bot gives Y, takes X)
- [ ] Y-for-X trades execute correctly (bot gives X, takes Y)
- [ ] Insufficient balance prevents trade execution

### Slice 7: TibetSwap Stub + Events Table Migration

**Files**: `trader.ps1` (NEW `TakeTibetSwapOffer` stub), `migrations.ps1` (MODIFY events schema, NEW migration function)

#### Automated Verification:
- [ ] `TakeTibetSwapOffer` method exists with correct parameter signature
- [ ] Events table has `details TEXT` column
- [ ] Migration function idempotent (safe to run multiple times)

#### Manual Verification:
- [ ] TibetSwap stub method is clearly marked as placeholder with TODO comment
- [ ] Migration runs without error on existing database

## Desired End State

```powershell
# 1. Run migrations
. "./migrations.ps1"
Invoke-MigrateSql
Invoke-MigrateEventsFix  # adds details column if missing

# 2. Configure
# Edit bot-config.json with your token, fingerprint, prices

# 3. Start the scanner
. "./trader.ps1"
Run-ScannerLoop  # starts scanning until Ctrl-C

# 4. Query P&L
Get-PnLSummary -BotId 1                    # per-bot summary
Get-PnLSummary -StartDate "2026-05-01"     # date range
Get-PnLSummary                             # all-time, all bots
```

**bot-config.json**:
```json
{
    "token_y": "MYTOKEN",
    "fingerprint": "ABCD1234...",
    "start_price": 0.5,
    "target_price": 1.5,
    "starting_amount": 100,
    "x_is_default": true,
    "poll_interval_ms": 30000,
    "max_retries": 3,
    "retry_delay_base_ms": 5000
}
```

## File Map

```
bot-config.json              # NEW — JSON configuration template (gitignored)
.gitignore                   # NEW — exclude config, database, PFX cert
trader.ps1                   # MODIFY — config loader, retry wrapper, scanner loop, bug fixes, TibetSwap stub
migrations.ps1               # MODIFY — events table schema fix + migration function
```

## Ordering Constraints

1. **Config loader** must come first (all other code depends on `$script:Config`)
2. **Retry wrapper** before scanner loop (scanner calls it)
3. **Scanner loop** before P&L and TibetSwap (consumers of the overall system)
4. **Trade lock fix** before scanner loop (scanner calls TakeDexieOffer, which is being fixed)
5. **Branch inversion fix** can happen with or after trade lock fix (same method)
6. **P&L queries** and **TibetSwap stub** are independent — can be in any order after config
7. **Events table migration** can run at any time — should run before scanner starts

## Verification Notes

- **Build check**: `pwsh -NoProfile -Command ". './trader.ps1'; Get-Command Invoke-WithRetry, Load-BotConfig, Run-ScannerLoop, Get-PnLSummary | Select-Object Name"`
- **Schema check**: After migration, `SELECT * FROM events LIMIT 1` should return 6 columns including `details`
- **State machine test**: Manually call `bot.TakeDexieOffer()` and verify `state` transitions to 2 then 1 (not 3)
- **Retry test**: Temporarily point API URL to `http://127.0.0.1:1` (unreachable) — retry should exhaust and log event
- **Branch test**: Verify X-side trade (dx > 0) checks `$this.yr` balance, Y-side trade (dy > 0) checks `$this.xr` balance
- **P&L test**: Insert known trade records, query with `Get-PnLSummary`, verify sums match

## Performance Considerations

- Scanner interval defaults to 30s — configurable via `poll_interval_ms`
- Each API call should complete within 10s before retry triggers (covered by retry wrapper)
- Retry backoff: 5s → 10s → 20s (max 3 retries) — total worst case ~35s per API call
- No high-frequency requirements — 30s scan is appropriate for Chia's 10-30s block time
- P&L queries use simple `SUM` aggregation — no indexing needed for small trade tables (<10K rows)

## Migration Notes

- **Events table**: Add `details TEXT` column via `ALTER TABLE events ADD COLUMN details TEXT IF NOT EXISTS` — safe for existing databases
- **No schema breaking changes**: All modifications are additive (new columns, no column renames or type changes)
- **Config file**: Not in git — user creates from template. No migration needed.
- **No data migration required**: Existing bot records in `bots` table are unchanged

## Pattern References

- `trader.ps1:11-23` — try/catch with `throw` (retry wrapper modeled after this pattern)
- `trader.ps1:186-190` — array-or-single-result handling (reused in P&L queries)
- `trader.ps1:289-402` — `save()` parameterized query pattern (reused in P&L queries)
- `trader.ps1:442-466` — `Adjust_X_Amount` pure function pattern (NOT modified — reference only)
- `trader.ps1:595-633` — `Invoke-SQLDataUpdate` INSERT pattern (reused for events table writes)

## Developer Context

**Retry Scope**: Per-API-call retry with exponential backoff. Each external API call gets its own retry wrapper. FRD says "on API error" — per-API-call is the most natural interpretation.

**TibetSwap Integration**: Stub only. `TakeTibetSwapOffer()` method defined but empty. User will provide the offer-building function later. No TibetSwap API calls in the scanner loop.

**Trade Lock Recovery**: On trade failure, set `state = 1` (ready) and resume scanning. Only `state = 3` = permanent stop. Scanner loop is single-threaded so no concurrent trade risk.

**Events Schema**: `bot_id INTEGER, event TEXT, event_status TEXT, details TEXT, created_at TEXT`. Used for retry exhaustion logging and trade failure recording.

**File Structure**: Single file (`trader.ps1`) — append all new code. Preserves existing pattern.

## Design History

- Slice 1: JSON Config Loader — approved as generated
- Slice 2: Trade Lock State Machine Fix — pending
- Slice 3: Retry Wrapper — pending
- Slice 4: Main Scanner Loop — pending
- Slice 5: P&L Summary Queries — pending
- Slice 6: Branch Inversion Fix — pending
- Slice 7: TibetSwap Stub + Events Table Migration — pending

## References

- `.rpiv/artifacts/research/2026-05-26_21-53-00_tibet-trader-amm-bot.md` — Research artifact (current code analysis)
- `.rpiv/artifacts/discover/2026-05-26_21-25-26_tibet-trader-amm-bot.md` — FRD (10 functional requirements)
- `trader.ps1` — SilentBot class and all business logic (~650 lines)
- `migrations.ps1` — SQLite schema definitions
- [PowerSage](https://github.com/AbandonedLand/PowerSage) — SageWallet RPC module (v1.0.19)
- [PowerDexie](https://github.com/AbandonedLand/dexiePowerShell) — Dexie.space API module (GitHub-only)
- [PowerTibetSwap](https://github.com/AbandonedLand/tibetswapPowerShell) — TibetSwap AMM module (v0.9.0)
- [PSSQLite](https://github.com/RamblingCookieMonster/PSSQLite) — SQLite query module (v1.1.0)
