## Concentrated Liquidity AMM (taker bot)
Maybe not the best name for this bot, but it's what got published.  This code isn't finished or polished.
Use at your own risk.  


## How it works



## Install
Required modules

```PowerShell
Install-Module -name PowerSage
Install-Module -name PowerDexie
Install-Module -name PowerTibetSwap
```

Clone the repo
```
git clone https://github.com/AbandonedLand/TibetTrader.git
```

Use dot sourcing to import into your powershell session.

```PowerShell
. ./TibetTrader/clamm.ps1
```

## Build your first bot

> Keep in mind that the price is CAT/XCH = Price

```PowerShell
$bot = New-TraderBot
Enter token_y ticker or asset_id: <token_id or ticker>
Enter minimum price: <min price>
Enter maximum price: <max price>
Is the starting amount for X or Y? Enter X or Y: <X = XCH, Y = CAT>
Enter starting amount: <enter your starting amount>
Give your bot a name: <name>
```

### INFO
> The bots start out as one way but will trade in both directions (bid/ask)
> If your starting token is X (xch) You will trade xch for the CAT token so you want to set the min price to the current price.
> If your starting token is Y then you want to set the max price to the current price and the min price to how low you want to buy to.
> At the min price, all of your Tokens will be in X, at the max price all your tokens will be in Y.
> If you want to buy and sell, you need two bots to run.


## Bot storage

Bots are saved as JSON files in `~/.bots/` (for example `/home/<you>/.bots/BILL.json`).  
List bots with `Show-TraderBots`. If none exist, create one with `New-TraderBot`.

## Run your bot

```powershell
$bot = Import-TraderBot -botName <name>
$bot.longrun()          # uses default_tibet_x_amount (0.2 XCH)
$bot.longrun(0.5)       # optional: custom Tibet quote size in XCH
```

This fork tracks [AbandonedLand/TibetTrader](https://github.com/AbandonedLand/TibetTrader) for core AMM math and adds execution safeguards (profit thresholds, multi-offer ranking, retries, cooldowns). Tibet quote display amounts use `ConvertFrom-CatMojo` / `ConvertFrom-XchMojo` (not hardcoded `/1000` divisors).

