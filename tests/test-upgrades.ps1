$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

. "$PSScriptRoot/../clamm.ps1"

function ConvertFrom-XchMojo { param($amount) return [decimal]$amount }
function ConvertFrom-CatMojo { param($amount) return [decimal]$amount }
function ConvertTo-XchMojo { param($amount) return [decimal]$amount }
function ConvertTo-CatMojo { param($amount) return [decimal]$amount }

$script:readCalls = 0
$script:completeCalls = 0
$script:pendingCount = 0

function Get-SageCats {
    return [pscustomobject]@{
        cats = @([pscustomobject]@{
            asset_id = "token-y-id"
            balance = 999999
        })
    }
}

function Get-SagePendingTransactions {
    return @()
}

function Read-SageOffer {
    param([string]$offer)
    $script:readCalls++
    return [pscustomobject]@{
        status = "active"
        offer = [pscustomobject]@{
            maker = @([pscustomobject]@{
                amount = 101
                asset = [pscustomobject]@{ asset_id = "token-y-id" }
            })
            taker = @([pscustomobject]@{
                amount = 1
                asset = [pscustomobject]@{ asset_id = $null }
            })
        }
    }
}

function Complete-SageOffer {
    param([string]$offer)
    $script:completeCalls++
    return $true
}

function Get-DexieOffers {
    param(
        [string]$offered,
        [string]$requested,
        [int]$page_size
    )
    return [pscustomobject]@{
        offers = @(
            [pscustomobject]@{ offer = "offer-a" },
            [pscustomobject]@{ offer = "offer-b" },
            [pscustomobject]@{ offer = "offer-c" }
        )
    }
}

function Assert-True {
    param(
        [bool]$Value,
        [string]$Message
    )
    if(-not $Value){
        throw "Assertion failed: $Message"
    }
}

$bot = [TraderBot]::new()
$bot.id = "testbot"
$bot.token_y = "TOK"
$bot.token_y_id = "token-y-id"
$bot.pa = 0.5
$bot.pb = 1.5
$bot.x_is_default = $true
$bot.Starting_Token_Amount(100)
$bot.min_profit_y = 0.5
$bot.min_profit_bps = 20
$bot.max_trade_attempts = 2
$bot.retry_delay_seconds = 0
$bot.dexie_page_size = 25

# Ranking/threshold checks using deterministic stubs.
$checkA = @{ isProfitable = $true; dx = -1; dy = 10; xProfit = 0; yProfit = 1.0; offer = "offer-a" }
$checkB = @{ isProfitable = $true; dx = -1; dy = 10; xProfit = 0; yProfit = 0.1; offer = "offer-b" }
Assert-True -Value ($bot.MeetsProfitThresholds($checkA)) -Message "Offer A should pass thresholds"
Assert-True -Value (-not $bot.MeetsProfitThresholds($checkB)) -Message "Offer B should fail min profit threshold"

# Ensure typo fix path in CheckTibetQuote does not explode under strict mode.
$quote = [pscustomobject]@{ amount_in = 1; amount_out = 2 }
$tibetCheck = $bot.CheckTibetQuote($quote)
Assert-True -Value ($null -ne $tibetCheck) -Message "CheckTibetQuote should return hashtable"

# Retry wrapper should execute and return.
$result = $bot.InvokeWithRetry({ return 42 }, "unit-test")
Assert-True -Value ($result -eq 42) -Message "InvokeWithRetry should return successful result"

# Cooldown behavior.
$bot.cooldown_until = (Get-Date).AddSeconds(5)
$blocked = $bot.TakeOffer(@{ offer = "offer-a" })
Assert-True -Value (-not $blocked) -Message "TakeOffer should not execute during cooldown"

# CheckTibetQuote must assign xProfit with correct casing (upstream had $xprofit typo).
$quote = [pscustomobject]@{
    amount_in = 1000
    amount_out = 2000000000000
}
$checkedTibet = $bot.CheckTibetQuote($quote)
if($checkedTibet.isProfitable -and $null -eq $checkedTibet.xProfit){
    throw "CheckTibetQuote returned null xProfit for profitable quote."
}

Write-Host "All upgrade checks passed."
