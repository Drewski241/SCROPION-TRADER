function Get-TTPairs{
    param (
        [string]$asset_id
    )

    $uri = "https://api.v2.tibetswap.io/pairs?skip=0&limit=1000"

    try{
        $response = Invoke-RestMethod -Uri $uri -Method Get

        if($asset_id.Length -eq 64){
            $msg = $response | Where-Object {$_.asset_id -eq $asset_id}
        } else {
            $dexie_uri = "https://dexie.space/v1/assets?page_size=25&filter=$asset_id"
            $dexie_response = Invoke-RestMethod -Uri $dexie_uri
            $assets = $dexie_response.assets | Where-Object {$_.code -eq $asset_id}

            $msg = $response | Where-Object {$_.asset_id -eq $assets.id}
        }
        if($msg){
            $msg
        } else {
            Write-Error "Please check the asset_id and try again."
        }
    } catch {

        throw "Could not contact tibetswap api to retrieve pairs."
    }
}


class TraderBot {
    [string]$id
    [string]$pair_id
    $token_y
    [decimal]$pa # Mininum Price
    [decimal]$pb # Maximum Price
    [boolean]$x_is_default = $true
    [boolean]$invert_price = $false
    [decimal]$starting_x_amount
    [decimal]$starting_y_amount
    [string]$token_y_id
    [decimal]$xv
    [decimal]$yv
    [decimal]$xr
    [decimal]$yr 
    [decimal]$liquidity_squared
    [decimal]$liquidity
    [decimal]$min_profit_x = 0
    [decimal]$min_profit_y = 0
    [decimal]$min_profit_bps = 5
    [int]$dexie_page_size = 10
    [int]$max_trade_attempts = 3
    [int]$retry_delay_seconds = 2
    [int]$max_consecutive_failures = 5
    [int]$consecutive_failures = 0
    [int]$cooldown_seconds = 60
    [datetime]$cooldown_until = [datetime]::MinValue
    [decimal]$default_tibet_x_amount = 0.2
    
    TraderBot(){}

    static [decimal]Prompt_Positive_Decimal([string]$promptText){
        while($true){
            $rawValue = Read-Host $promptText
            try{
                $parsedValue = [decimal]$rawValue
            } catch {
                Write-Host "Please enter a valid number." -ForegroundColor Yellow
                continue
            }

            if($parsedValue -le 0){
                Write-Host "Please enter a value greater than 0." -ForegroundColor Yellow
                continue
            }

            return $parsedValue
        }

        throw "Unexpected prompt flow while reading decimal value."
    }

    static [decimal]Prompt_Positive_DecimalWithDefault([string]$promptText, [decimal]$defaultValue){
        $hint = [math]::Round($defaultValue, 6)
        while($true){
            $rawValue = Read-Host "$promptText [suggested: $hint, Enter=accept]"
            if([string]::IsNullOrWhiteSpace($rawValue)){
                return $defaultValue
            }

            try{
                $parsedValue = [decimal]$rawValue
            } catch {
                Write-Host "Please enter a valid number." -ForegroundColor Yellow
                continue
            }

            if($parsedValue -le 0){
                Write-Host "Please enter a value greater than 0." -ForegroundColor Yellow
                continue
            }

            return $parsedValue
        }

        throw "Unexpected prompt flow while reading decimal value."
    }

    static [bool]Prompt_X_Is_Default(){
        while($true){
            $selection = (Read-Host "Is the starting amount for X or Y? Enter X or Y").Trim().ToUpperInvariant()
            if($selection -eq 'X'){
                return $true
            }
            if($selection -eq 'Y'){
                return $false
            }

            Write-Host "Please enter X or Y." -ForegroundColor Yellow
        }

        throw "Unexpected prompt flow while reading starting token selection."
    }

    static [string]Prompt_Name(){
        while($true){
            $botid = (Read-Host "Give your bot a name")
            if($botid.Length -gt 0){
                return $botid
            }
            
        }
        throw "Unexpected behavior naming bot."
    }

    static [TraderBot]Build([bool]$useMarketSuggestion, [decimal]$rangePercent, [decimal]$quoteXchAmount){
        $bot = [TraderBot]::new()

        $tokenInput = ""
        $pairInfo = $null
        while($true){
            $tokenInput = (Read-Host "Enter token_y ticker or asset_id").Trim()
            if([string]::IsNullOrWhiteSpace($tokenInput)){
                Write-Host "token_y is required." -ForegroundColor Yellow
                continue
            }

            try{
                $lookup = Get-TTPairs -asset_id $tokenInput
            } catch {
                Write-Host $_.Exception.Message -ForegroundColor Red
                continue
            }

            if(-not $lookup){
                Write-Host "No pair found for the provided token_y." -ForegroundColor Yellow
                continue
            }

            $pairInfo = if($lookup -is [System.Array]) { $lookup[0] } else { $lookup }
            break
        }

        $bot.pair_id = [string]$pairInfo.pair_id
        $bot.token_y_id = [string]$pairInfo.asset_id
        if(-not [string]::IsNullOrWhiteSpace([string]$pairInfo.asset_short_name)){
            $bot.token_y = [string]$pairInfo.asset_short_name
        } else {
            $bot.token_y = $tokenInput
        }

        $marketSuggestion = $null
        if($useMarketSuggestion){
            Write-Host ""
            Write-Host "Fetching live prices from TibetSwap and Dexie..." -ForegroundColor Cyan
            $marketSuggestion = Get-TraderBotSettingsSuggestion -TokenY $bot.token_y -RangePercent $rangePercent -QuoteXchAmount $quoteXchAmount
            $bot.default_tibet_x_amount = $quoteXchAmount
        }

        $bot.x_is_default = [TraderBot]::Prompt_X_Is_Default()

        $priceProfile = $null
        if($null -ne $marketSuggestion){
            if($bot.x_is_default){
                $priceProfile = $marketSuggestion.sell_xch_bot
                Write-Host "Using sell-XCH profile: $($priceProfile.note)" -ForegroundColor DarkCyan
            } else {
                $priceProfile = $marketSuggestion.buy_cat_bot
                Write-Host "Using buy-CAT profile: $($priceProfile.note)" -ForegroundColor DarkCyan
            }
        }

        while($true){
            if($null -ne $priceProfile){
                $bot.pa = [TraderBot]::Prompt_Positive_DecimalWithDefault("Enter minimum price (CAT per 1 XCH)", [decimal]$priceProfile.pa)
                $bot.pb = [TraderBot]::Prompt_Positive_DecimalWithDefault("Enter maximum price (CAT per 1 XCH)", [decimal]$priceProfile.pb)
            } else {
                $bot.pa = [TraderBot]::Prompt_Positive_Decimal("Enter minimum price (CAT per 1 XCH)")
                $bot.pb = [TraderBot]::Prompt_Positive_Decimal("Enter maximum price (CAT per 1 XCH)")
            }
            try{
                $bot.Validate_Price_Range()
                break
            } catch {
                Write-Host $_.Exception.Message -ForegroundColor Yellow
            }
        }

        if($bot.x_is_default){
            $defaultStartingAmount = if($null -ne $marketSuggestion){ [Math]::Max($quoteXchAmount, 1) } else { 1 }
            $startingPrompt = "Enter starting amount in XCH (recommend at least 1 XCH for Dexie fills)"
        } else {
            $defaultStartingAmount = if($null -ne $marketSuggestion){
                [math]::Round($marketSuggestion.reference_price * $quoteXchAmount, 6)
            } else {
                1
            }
            $startingPrompt = "Enter starting amount in $($bot.token_y) (CAT)"
        }

        if($null -ne $marketSuggestion){
            $startingAmount = [TraderBot]::Prompt_Positive_DecimalWithDefault($startingPrompt, $defaultStartingAmount)
        } else {
            $startingAmount = [TraderBot]::Prompt_Positive_Decimal($startingPrompt)
        }

        $bot.Starting_Token_Amount($startingAmount)
        $bot.id = [TraderBot]::Prompt_Name()
        $bot.save()
        return $bot

        throw "Unexpected prompt flow while building TraderBot."
    }

    [void]Init([pscustomobject]$props){
        $this.id = $props.id
        $this.pair_id = $props.pair_id
        $this.token_y = $props.token_y
        $this.pa = [decimal]$props.pa
        $this.pb = [decimal]$props.pb
        $this.x_is_default = [bool]$props.x_is_default
        $this.invert_price = [bool]$props.invert_price
        $this.starting_x_amount = [decimal]$props.starting_x_amount
        $this.starting_y_amount = [decimal]$props.starting_y_amount
        $this.token_y_id = $props.token_y_id
        $this.xv = [decimal]$props.xv
        $this.yv = [decimal]$props.yv
        $this.xr = [decimal]$props.xr
        $this.yr = [decimal]$props.yr
        $this.liquidity_squared = [decimal]$props.liquidity_squared
        $this.liquidity = [decimal]$props.liquidity
        if($null -ne $props.PSObject.Properties['min_profit_x']){ $this.min_profit_x = [decimal]$props.min_profit_x }
        if($null -ne $props.PSObject.Properties['min_profit_y']){ $this.min_profit_y = [decimal]$props.min_profit_y }
        if($null -ne $props.PSObject.Properties['min_profit_bps']){ $this.min_profit_bps = [decimal]$props.min_profit_bps }
        if($null -ne $props.PSObject.Properties['dexie_page_size']){ $this.dexie_page_size = [int]$props.dexie_page_size }
        if($null -ne $props.PSObject.Properties['max_trade_attempts']){ $this.max_trade_attempts = [int]$props.max_trade_attempts }
        if($null -ne $props.PSObject.Properties['retry_delay_seconds']){ $this.retry_delay_seconds = [int]$props.retry_delay_seconds }
        if($null -ne $props.PSObject.Properties['max_consecutive_failures']){ $this.max_consecutive_failures = [int]$props.max_consecutive_failures }
        if($null -ne $props.PSObject.Properties['cooldown_seconds']){ $this.cooldown_seconds = [int]$props.cooldown_seconds }
        if($null -ne $props.PSObject.Properties['default_tibet_x_amount']){ $this.default_tibet_x_amount = [decimal]$props.default_tibet_x_amount }
        $this.Validate_Price_Range()
    }

    static [string]Resolve_Bot_Directory([string]$directory){
        if([string]::IsNullOrWhiteSpace($directory)){
            throw "Directory path cannot be empty."
        }

        if($directory.StartsWith('~')){
            $homeDir = [Environment]::GetFolderPath('UserProfile')
            $resolvedDirectory = $directory -replace '^~', $homeDir
        } else {
            $resolvedDirectory = $directory
        }

        $resolvedDirectory = [System.IO.Path]::GetFullPath($resolvedDirectory)
        if(-not (Test-Path -Path $resolvedDirectory)){
            New-Item -Path $resolvedDirectory -ItemType Directory -Force | Out-Null
        }

        return $resolvedDirectory
    }

    static [string]Build_Bot_File_Path([string]$token_y, [string]$directory){
        if([string]::IsNullOrWhiteSpace($token_y)){
            throw "token_y is required to build the bot file name."
        }

        $invalidNameChars = [System.IO.Path]::GetInvalidFileNameChars()
        foreach($char in $invalidNameChars){
            if($token_y.Contains([string]$char)){
                throw "token_y contains invalid file name characters and cannot be used as a file name."
            }
        }

        $resolvedDirectory = [TraderBot]::Resolve_Bot_Directory($directory)
        return [System.IO.Path]::Combine($resolvedDirectory, "$token_y.json")
    }

    [void]SaveToJson(){
        $this.SaveToJson("~/.bots")
    }

    [void]SaveToJson([string]$directory){
        if([string]::IsNullOrWhiteSpace($this.token_y)){
            throw "token_y must be set before saving the bot to json."
        }

        if([string]::IsNullOrWhiteSpace($this.id)){
            $this.id = $this.token_y
        }

        $this.Validate_Price_Range()
        $filePath = [TraderBot]::Build_Bot_File_Path($this.id, $directory)

        $payload = [ordered]@{
            schema_version = 1
            id = $this.id
            pair_id = $this.pair_id
            token_y = $this.token_y
            pa = $this.pa
            pb = $this.pb
            x_is_default = $this.x_is_default
            invert_price = $this.invert_price
            starting_x_amount = $this.starting_x_amount
            starting_y_amount = $this.starting_y_amount
            token_y_id = $this.token_y_id
            xv = $this.xv
            yv = $this.yv
            xr = $this.xr
            yr = $this.yr
            liquidity_squared = $this.liquidity_squared
            liquidity = $this.liquidity
            min_profit_x = $this.min_profit_x
            min_profit_y = $this.min_profit_y
            min_profit_bps = $this.min_profit_bps
            dexie_page_size = $this.dexie_page_size
            max_trade_attempts = $this.max_trade_attempts
            retry_delay_seconds = $this.retry_delay_seconds
            max_consecutive_failures = $this.max_consecutive_failures
            cooldown_seconds = $this.cooldown_seconds
            default_tibet_x_amount = $this.default_tibet_x_amount
        }

        $payload | ConvertTo-Json -Depth 5 | Set-Content -Path $filePath -Encoding utf8
    }

    [void]DeleteBot(){
        $this.DeleteBot("~/.bots")
    }

    [void]save(){
        $this.SaveToJson()
    }
    
    [void]delete(){
        $this.DeleteBot()
    }

    [void]DeleteBot([string]$directory){
        $fileKey = $this.id
        if([string]::IsNullOrWhiteSpace($fileKey)){
            $fileKey = $this.token_y
        }

        if([string]::IsNullOrWhiteSpace($fileKey)){
            throw "Cannot delete bot file because both id and token_y are empty."
        }

        $filePath = [TraderBot]::Build_Bot_File_Path($fileKey, $directory)
        if(-not (Test-Path -Path $filePath)){
            throw "Bot file not found: $filePath"
        }

        Remove-Item -Path $filePath -Force
    }

    static [string]Resolve_Bot_File_Path([string]$botName, [string]$directory){
        if([string]::IsNullOrWhiteSpace($botName)){
            throw "Bot name is required."
        }

        $directPath = [TraderBot]::Build_Bot_File_Path($botName, $directory)
        if(Test-Path -Path $directPath){
            return $directPath
        }

        $resolvedDirectory = [TraderBot]::Resolve_Bot_Directory($directory)
        $files = @(Get-ChildItem -Path $resolvedDirectory -Filter *.json -ErrorAction SilentlyContinue)
        foreach($file in $files){
            try{
                $data = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
                if($data.id -ieq $botName -or $data.token_y -ieq $botName){
                    return $file.FullName
                }
            } catch {
                continue
            }
        }

        $available = @($files | ForEach-Object { $_.BaseName })
        $availableText = if($available.Count -gt 0){ $available -join ', ' } else { '(none)' }
        throw "Bot '$botName' not found in $resolvedDirectory. Available bot files: $availableText"
    }

    static [TraderBot]Import([string]$token_y){
        return [TraderBot]::Import($token_y, "~/.bots")
    }

    static [TraderBot]Import([string]$token_y, [string]$directory){
        $filePath = [TraderBot]::Resolve_Bot_File_Path($token_y, $directory)

        try{
            $data = Get-Content -Path $filePath -Raw | ConvertFrom-Json
        } catch {
            throw "Failed to parse bot json from $filePath."
        }

        $requiredProperties = @(
            'token_y',
            'pa',
            'pb',
            'x_is_default',
            'invert_price',
            'starting_x_amount',
            'starting_y_amount',
            'xv',
            'yv',
            'xr',
            'yr',
            'liquidity_squared',
            'liquidity'
        )

        $missing = @()
        foreach($propertyName in $requiredProperties){
            if($null -eq $data.PSObject.Properties[$propertyName]){
                $missing += $propertyName
            }
        }

        if($missing.Count -gt 0){
            throw "Bot json is missing required properties: $($missing -join ', ')"
        }

        $bot = [TraderBot]::new()
        $bot.Init([pscustomobject]$data)
        return $bot
    }

    [decimal]Calculate_yv(){
        return ($this.liquidity * ([math]::Sqrt($this.pa)))
    }

    [decimal]Calculate_xv(){
        return ($this.liquidity / ([math]::Sqrt($this.pb)))
    }

    [void]Validate_Price_Range(){
        if(($this.pa -le 0) -or ($this.pb -le 0)){
            throw "Invalid price range: pa and pb must both be greater than 0. Current pa=$($this.pa), pb=$($this.pb)."
        }
        if($this.pa -ge $this.pb){
            throw "Invalid price range: pa must be less than pb. Current pa=$($this.pa), pb=$($this.pb)."
        }
    }

    [void]Starting_Token_Amount($amount){
        if($this.xv -or $this.yv -or $this.xr -or $this.yr -or $this.liquidity -or $this.liquidity_squared){
            throw "Starting_Token_Amount can only be called once per instance."
        }
        $this.Validate_Price_Range()
        if($this.x_is_default){
            $this.starting_x_amount = $amount
            $this.starting_y_amount = 0
            $this.xr = $amount
            $solve = $amount / ((1/[math]::Sqrt($this.pa))-(1/[math]::Sqrt($this.pb)))
            $this.liquidity = $solve
            $this.liquidity_squared = $solve * $solve
            $this.xv = $this.Calculate_xv()
            $this.yv = $this.Calculate_yv()
            
        } else {
            $solve = $amount / (([math]::Sqrt($this.pb))-([math]::Sqrt($this.pa)))
            $this.yr = $amount
            $this.starting_x_amount = 0
            $this.starting_y_amount = $amount
            $this.liquidity = $solve
            $this.liquidity_squared = $solve * $solve
            $this.xv = $this.Calculate_xv()
            $this.yv = $this.Calculate_yv()
            
        }
    }

    [hashtable]CheckOffer($offer_string){
        
        $read = Read-SageOffer -offer $offer_string
        if($read.status -eq "expired"){
            throw "Offer is expired"
        }
        if($read.status -eq 'active' -AND ($read.offer.maker.count -eq 1) -AND ($read.offer.taker.count -eq 1)){
            if($read.offer.maker[0].asset.asset_id -eq $this.token_y_id -AND $null -eq $read.offer.taker[0].asset.asset_id){
                $requested_xch = $read.offer.taker[0].amount | ConvertFrom-XchMojo
                $offered_y = $read.offer.maker[0].amount | ConvertFrom-CatMojo
                if($requested_xch -gt $this.xr){
                    return @{ isProfitable = $false }
                }
                try{
                    $formula_says = $this.Adjust_X_Amount(-$requested_xch)
                } catch {
                    return @{ isProfitable = $false }
                }
                $yprofit = ($offered_y - $formula_says.dy)
                if($yprofit -gt 0){
                    Return @{
                        isProfitable = $true
                        dx = $formula_says.dx
                        dy = $formula_says.dy
                        xProfit = 0
                        yProfit = $yprofit
                        offer = $offer_string
                        TibetX = ([Math]::Abs($formula_says.dx))
                    }
                } else {
                    Return @{
                        isProfitable = $false
                        TibetX = ([Math]::Abs($formula_says.dx))
                    }
                }
            }
            if($null -eq ($read.offer.maker[0].asset.asset_id) -AND ($read.offer.taker[0].asset.asset_id) -eq $this.token_y_id){
                $offered_xch = $read.offer.maker[0].amount | ConvertFrom-XchMojo
                $requested_y = $read.offer.taker[0].amount | ConvertFrom-CatMojo

                if($requested_y -gt $this.yr){
                    return @{ isProfitable = $false }
                }
                try{
                    $formula_says = $this.Adjust_Y_Amount(-$requested_y)
                } catch {
                    return @{ isProfitable = $false }
                }
                $xprofit = ($offered_xch - $formula_says.dx)
                if($xprofit -gt 0) {
                    Return @{
                        isProfitable = $true
                        dx = $formula_says.dx
                        dy = $formula_says.dy
                        xProfit = $xprofit
                        yProfit = 0
                        offer = $offer_string
                        TibetY = ([Math]::Abs($formula_says.dy))
                    }
                } else {
                    Return @{
                        isProfitable = $false
                        TibetY = ([Math]::Abs($formula_says.dy))
                    }
                }
            }
        }
        Return @{isProfitable = $false}
    }

    [object]InvokeWithRetry([scriptblock]$Action, [string]$Operation){
        $lastError = $null
        for($attempt = 1; $attempt -le $this.max_trade_attempts; $attempt++){
            try{
                return & $Action
            } catch {
                $lastError = $_
                if($attempt -ge $this.max_trade_attempts){
                    break
                }
                $delay = [Math]::Pow(2, ($attempt - 1)) * $this.retry_delay_seconds
                Write-Host "$Operation failed on attempt $attempt. Retrying in $delay seconds..." -ForegroundColor Yellow
                Start-Sleep -Seconds $delay
            }
        }

        throw "$Operation failed after $($this.max_trade_attempts) attempts. Last error: $($lastError.Exception.Message)"
    }

    [decimal]GetProfitBps([hashtable]$checked_offer){
        if($checked_offer.xProfit -gt 0 -and [Math]::Abs([decimal]$checked_offer.dx) -gt 0){
            return [math]::Round((([decimal]$checked_offer.xProfit / [Math]::Abs([decimal]$checked_offer.dx)) * 10000), 3)
        }
        if($checked_offer.yProfit -gt 0 -and [Math]::Abs([decimal]$checked_offer.dy) -gt 0){
            return [math]::Round((([decimal]$checked_offer.yProfit / [Math]::Abs([decimal]$checked_offer.dy)) * 10000), 3)
        }
        return 0
    }

    [bool]MeetsProfitThresholds([hashtable]$checked_offer){
        $profitBps = $this.GetProfitBps($checked_offer)
        $xProfit = [decimal]$checked_offer.xProfit
        $yProfit = [decimal]$checked_offer.yProfit

        if($xProfit -le 0 -and $yProfit -le 0){
            return $false
        }
        if($yProfit -gt 0 -and $yProfit -lt $this.min_profit_y){
            return $false
        }
        if($xProfit -gt 0 -and $xProfit -lt $this.min_profit_x){
            return $false
        }

        return ($profitBps -ge $this.min_profit_bps)
    }

    [array]RankDexieOffers([array]$offers){
        $ranked = @()
        foreach($offerItem in $offers){
            try{
                $offerText = if($offerItem -is [string]) { $offerItem } else { $offerItem.offer }
                if([string]::IsNullOrWhiteSpace($offerText)){ continue }
                $checked = $this.CheckOffer($offerText)
                if(-not $checked.isProfitable){ continue }
                if(-not $this.MeetsProfitThresholds($checked)){ continue }
                $ranked += [pscustomobject]@{
                    checked_offer = $checked
                    source_offer = $offerItem
                    profit_bps = $this.GetProfitBps($checked)
                }
            } catch {
                if($_.Exception.Message -notmatch 'Insufficient (xr|yr) reserve'){
                    Write-Host "Skipping invalid offer during ranking: $($_.Exception.Message)" -ForegroundColor DarkYellow
                }
            }
        }

        return @($ranked | Sort-Object -Property @{Expression='profit_bps';Descending=$true}, @{Expression={$_.checked_offer.yProfit};Descending=$true}, @{Expression={$_.checked_offer.xProfit};Descending=$true})
    }

    [void]CommitTrade([hashtable]$checked_offer){
        if([string]::IsNullOrWhiteSpace($this.id)){
            throw "Bot id must be set before committing a trade. Call SaveToJson first or assign an id."
        }
        $requiredKeys = @('dx', 'dy', 'xProfit', 'yProfit')
        foreach($key in $requiredKeys){
            if(-not $checked_offer.ContainsKey($key)){
                throw "CommitTrade rejected for bot $($this.id): checked_offer is missing required key '$key'."
            }
        }

        try{
            $dx = [decimal]$checked_offer.dx
            $dy = [decimal]$checked_offer.dy
            $xProfit = [decimal]$checked_offer.xProfit
            $yProfit = [decimal]$checked_offer.yProfit
        } catch {
            throw "CommitTrade rejected for bot $($this.id): dx, dy, xProfit, and yProfit must be numeric."
        }

        if($xProfit -lt 0 -or $yProfit -lt 0){
            throw "CommitTrade rejected for bot $($this.id): profits must be non-negative. xProfit=$xProfit yProfit=$yProfit"
        }
        if($dx -eq 0 -and $dy -eq 0){
            throw "CommitTrade rejected for bot $($this.id): trade deltas cannot both be zero."
        }

        $newxr = [math]::Round($this.xr + $dx, 12)

        $newyr = [math]::Round($this.liquidity_squared / ($newxr + $this.xv) - $this.yv, 6)


        $resolvedDirectory = [TraderBot]::Resolve_Bot_Directory("~/.bots")
        $csvPath = [System.IO.Path]::Combine($resolvedDirectory, "completed_trades.csv")

        $row = [pscustomobject][ordered]@{
            trade_id  = if($checked_offer.ContainsKey('trade_id')){ $checked_offer.trade_id } else { [string]::Format("{0}-{1}", $this.id, [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) }
            bot_name  = $this.id
            dx        = $dx
            dy        = $dy
            xprofit   = $xProfit
            yprofit   = $yProfit
            timestamp = (Get-Date).ToString('o')
        }

        $row | Export-Csv -Path $csvPath -Append -NoTypeInformation

        $this.xr = $newxr
        $this.yr = $newyr
        $this.SaveToJson()
    }

    [ordered]Adjust_X_Amount([decimal]$amount){
        $_xr = $this.xr 
        $newxr = $_xr + $amount
        if($newxr -lt 0){
            throw "Insufficient xr reserve to adjust by $amount. Available xr: $_xr"
        }
        $_xv = $this.xv
        $_yv = $this.yv
        $_yr = [math]::Round($this.liquidity_squared / ($_xr + $_xv) - $_yv, 6)
        $_y = $this.liquidity_squared / ($newxr + $_xv)
        $newyr = [math]::round($_y - $_yv,6)
        if($newyr -lt 0){
            throw "Insufficient yr reserve for this x adjustment. Available yr: $_yr"
        }
        $dy = $newyr - $_yr
        $dx = $amount

        $price = 0
        if([math]::Abs($dx) -gt 0){
            $price = [math]::Round(([math]::Abs($dy) / [math]::Abs($dx)), 3)
        }

        $trade = [ordered]@{
            'price' = $price
            'newyr' = $newyr
            'newxr' = $newxr
            'amount' = $amount
            'yr' = $_yr
            'xr' = $_xr
            'dx' = $dx
            'dy' = $dy
        }

        return $trade
        
    }

    [ordered]Adjust_Y_Amount([decimal]$amount){
        $_yr = $this.yr 
        $newyr = $_yr + $amount
        if($newyr -lt 0){
            throw "Insufficient yr reserve to adjust by $amount. Available yr: $_yr"
        }
        $_xv = $this.xv
        $_yv = $this.yv
        $_xr = [math]::Round($this.liquidity_squared / ($_yr + $_yv) - $_xv, 12)
        $_x = $this.liquidity_squared / ($newyr + $_yv)
        $newxr = [math]::round($_x - $_xv,12)
        if($newxr -lt 0){
            throw "Insufficient xr reserve for this y adjustment. Available xr: $_xr"
        }
        $dx = $newxr - $_xr
        $dy = $amount

        $price = 0
        if([math]::Abs($dx) -gt 0){
            $price = [math]::Round(([math]::Abs($dy) / [math]::Abs($dx)), 3)
        }

        $trade = [ordered]@{
            'price' = $price
            'newyr' = $newyr
            'newxr' = $newxr
            'amount' = $amount
            'yr' = $_yr
            'xr' = $_xr
            'dx' = $dx
            'dy' = $dy
            
        }
        return $trade        
    }

    [array]GetDexieFromX(){
        $offer = $this.InvokeWithRetry({
            Get-DexieOffers -offered $($this.token_y) -requested "xch" -page_size $($this.dexie_page_size)
        }, "GetDexieFromX")
        return @($offer.offers)
    }

    [array]GetDexieFromY(){
        $offer = $this.InvokeWithRetry({
            Get-DexieOffers -requested $($this.token_y) -offered "xch" -page_size $($this.dexie_page_size)
        }, "GetDexieFromY")
        return @($offer.offers)
    }



    [void]HandleDexieFromX(){
        if($this.xr -le 0){
            Write-Host "Skipping Dexie XCH-side offers: no XCH reserve (xr=$($this.xr))." -ForegroundColor DarkYellow
            return
        }
        $offers = $this.GetDexieFromX()
        $ranked = $this.RankDexieOffers($offers)
        if($ranked.Count -gt 0){
            $this.ExecuteCheckedOffer($ranked[0].checked_offer)
        }
    }

    [void]HandleDexieFromY(){
        if($this.yr -le 0){
            Write-Host "Skipping Dexie $($this.token_y)-side offers: no $($this.token_y) reserve (yr=0). Start with Y or wait until you hold $($this.token_y)." -ForegroundColor DarkYellow
            return
        }
        $offers = $this.GetDexieFromY()
        $ranked = $this.RankDexieOffers($offers)
        if($ranked.Count -gt 0){
            $this.ExecuteCheckedOffer($ranked[0].checked_offer)
        }
    }

    [array]Trades(){
        $resolvedDirectory = [TraderBot]::Resolve_Bot_Directory("~/.bots")
        $csvPath = [System.IO.Path]::Combine($resolvedDirectory, "completed_trades.csv")
        if(-not (Test-Path -Path $csvPath)){
            return @()
        }
        $trades = Import-Csv -Path $csvPath | Where-Object {$_.bot_name -eq $this.id}
        return $trades
    }

    [bool]TakeOffer($checked_offer){
        Write-Host "Trying to take an offer with TakeOffer()"
        if((Get-Date) -lt $this.cooldown_until){
            Write-Host "Bot is cooling down until $($this.cooldown_until.ToString('o'))" -ForegroundColor Yellow
            return $false
        }

        $pretrade_y = ((get-sagecats).cats | Where-Object {$_.asset_id -eq $($this.token_y_id)}).balance
        Write-Host "PreTrade TokenY = $($pretrade_y)"
        $read = $this.InvokeWithRetry({ read-sageoffer -offer $checked_offer.offer }, "Read-SageOffer")
        if($read.status -eq "active"){
            $take = $this.InvokeWithRetry({ Complete-SageOffer -offer $checked_offer.offer }, "Complete-SageOffer")
            
            if(-not $take){
                throw "Offer coult not be taken"
            }
            Write-Host "Offer taken - waiting for completion"
            start-sleep 2
            $count = (Get-SagePendingTransactions).count
            $deadline = (Get-Date).AddSeconds(90)
            while($count -gt 0){
                if((Get-Date) -gt $deadline){
                    throw "Timed out waiting for pending transactions to clear."
                }
                start-sleep 10
                Write-Host "waiting for transactions to process"
                $count = (Get-SagePendingTransactions).count
            }
            
            $posttrade_y = ((get-sagecats).cats | Where-Object {$_.asset_id -eq $($this.token_y_id)}).balance
            Write-Host "Offer has completed. Post Trade TokenY = $($posttrade_y)"
            # This is a stupid way to check, but need to do some troubleshooting.
            if($pretrade_y -ne $posttrade_y){
                Write-Host "TakeOffer returns true"
                return $true
            }
        }
        Write-Host "TakeOffer returns false"
        return $false
    }

    [void]HandleOffer($offer_string){
        $checked_offer = $this.CheckOffer($offer_string)
        if($checked_offer.isProfitable){
            $this.ExecuteCheckedOffer($checked_offer)
        }
    }

    [void]RecordFailure([string]$reason){
        $this.consecutive_failures = $this.consecutive_failures + 1
        Write-Host "Trade failure #$($this.consecutive_failures): $reason" -ForegroundColor Red
        if($this.consecutive_failures -ge $this.max_consecutive_failures){
            $this.cooldown_until = (Get-Date).AddSeconds($this.cooldown_seconds)
            Write-Host "Failure limit reached. Cooling down for $($this.cooldown_seconds)s." -ForegroundColor Yellow
            $this.consecutive_failures = 0
        }
    }

    [void]RecordSuccess(){
        $this.consecutive_failures = 0
    }

    [void]ExecuteCheckedOffer([hashtable]$checked_offer){
        if(-not $checked_offer.isProfitable){
            return
        }
        if(-not $this.MeetsProfitThresholds($checked_offer)){
            Write-Host "Offer profitable but below configured thresholds." -ForegroundColor DarkYellow
            return
        }

        Write-Host ""
        Write-Host "Offer has $($checked_offer.yProfit) of $($this.token_y) profit" -ForegroundColor Green
        Write-Host "Offer has $($checked_offer.xProfit) of XCH profit" -ForegroundColor Green
        Write-Host ""

        $checked_offer.trade_id = [string]::Format("{0}-{1}", $checked_offer.offer.GetHashCode(), [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
        try{
            $take_offer = $this.TakeOffer($checked_offer)
            if($take_offer){
                $this.CommitTrade($checked_offer)
                $this.RecordSuccess()
            } else {
                $this.RecordFailure("Offer was not completed.")
            }
        } catch {
            $this.RecordFailure($_.Exception.Message)
            throw
        }
    }

    [bool]HandleTibetFromX($amount){
        $quote = $this.GetTibetQuoteFromX($amount)
        $check = $this.CheckTibetQuote($quote)
        $attempt = $this.AttemptTibetOffer($check)
        return $attempt
    }

    [bool]HandleTibetFromY($amount){
        $quote = $this.GetTibetQuoteFromY($amount)
        $check = $this.CheckTibetQuote($quote)
        $attempt = $this.AttemptTibetOffer($check)
        return $attempt
    }

    [pscustomobject]GetTibetQuoteFromX($amount){
        if($amount -le 0){
            throw "The amount for tibet quotes must be greater than 0"
        }
        $quote = Get-TibetQuote -pair_id $this.pair_id -amount_in ($amount | ConvertTo-XchMojo) -xch_is_input
        return $quote
    }

    [pscustomobject]GetTibetQuoteFromY($amount){
        if($amount -le 0){
            throw "The amount for tibet quotes must be greater than 0"
        }
        $quote = Get-TibetQuote -pair_id $this.pair_id -amount_in ($amount | ConvertTo-CatMojo)
        return $quote
    }

    [hashtable]CheckTibetQuote($quote){
        try{
            if($quote.amount_in -lt $quote.amount_out){
                # wants cat
                $requested_y = $quote.amount_in | ConvertFrom-CatMojo
                $offered_xch = $quote.amount_out | ConvertFrom-XchMojo
                $formula_says = $this.Adjust_Y_Amount(-($requested_y))
                $xProfit = $offered_xch - ($formula_says.dx)
                if($xProfit -gt 0){
                    return @{
                        isProfitable = $true
                        dx = $formula_says.dx
                        dy = $formula_says.dy
                        xProfit = $xProfit
                        yProfit = 0 
                        quote = $quote
                    }
                } 

            } else {
                # wants XCH
                $requested_xch = $quote.amount_in | ConvertFrom-XchMojo
                $offered_y = $quote.amount_out | ConvertFrom-CatMojo
                $formula_says = $this.Adjust_X_Amount(-($requested_xch))
                $yProfit = $offered_y - ($formula_says.dy)
                if($yProfit -gt 0){
                    return @{
                        isProfitable = $true
                        dx = $formula_says.dx
                        dy = $formula_says.dy
                        xProfit = 0
                        yProfit = $yProfit  
                        quote = $quote 
                    }
                } 
            }
        } catch {
            return @{ isProfitable = $false; reason = $_.Exception.Message }
        }
        return @{isProfitable=$false}
    }

    [bool]AttemptTibetOffer($checked_quote){
        if(-Not $checked_quote.isProfitable){
            Write-Host "Tibet offer not profitable"
            return $false
        }
        if(-not $this.MeetsProfitThresholds($checked_quote)){
            Write-Host "Tibet offer profitable but below configured thresholds." -ForegroundColor DarkYellow
            return $false
        }
        $offered_amount = $checked_quote.quote.amount_in 
        $requested_amount = $checked_quote.quote.amount_out
        $genOffer = Build-SageOffer
        if($offered_amount -gt $requested_amount){
            # Wants XCH
            $genOffer.offerXch($offered_amount)
            $genOffer.requestCat(($this.token_y_id),$requested_amount)
        } elseif($requested_amount -gt $offered_amount) {
            # Wants TokenY
            $genOffer.offerCat(($this.token_y_id),$offered_amount)
            $genOffer.requestXch($requested_amount)
        } else {
            Throw "could not determin offer."
        }
        $genOffer.setMinutesUntilExpires(5)
        $genOffer.createoffer()
        $offer = $genOffer.offer_data
        $submit = Submit-TibetOffer -pair_id $this.pair_id -offer $offer.offer -action SWAP
        if(-NOT $submit.success){
            Write-Host "Failed to submit offer to tibetswap"
            Remove-SageOffer -offer_id $offer.offer_id
            return $false
        }
        Write-Host "Offer submitted to tibetswap." -ForegroundColor Yellow
        start-sleep 5
        $trackedOffer = Get-SageOffer -offer_id $offer.offer_id
        Write-Host "Checking offer Status..." -ForegroundColor Yellow
        Write-Host "Status: $($trackedOffer.status)" -ForegroundColor Yellow
        while($trackedOffer.status -eq "active"){
            Start-Sleep 10
            $trackedOffer = Get-SageOffer -offer_id $offer.offer_id
            Write-Host "Checking offer Status..." -ForegroundColor Yellow
            Write-Host "Status: $($trackedOffer.status)" -ForegroundColor Yellow
        }
        if($trackedOffer.status -eq "completed"){
            $this.CommitTrade($checked_quote)
            $this.RecordSuccess()
            Write-Host "Tibet Trade Successful!" -ForegroundColor Green
            return $true
        } else {
            Write-Host "Something happened.  Waiting 60 seconds and checking again." -ForegroundColor Red
            Write-Host "Status: $($trackedOffer.status)" -ForegroundColor Red
            Start-Sleep 60
            $trackedOffer = Get-SageOffer -offer_id $offer.offer_id
            Write-Host "Status: $($trackedOffer.status)" -ForegroundColor Red
            if($trackedOffer.status -eq "completed"){
                Write-Host "Trade shows as completed now." -ForegroundColor Green
                $this.CommitTrade($checked_quote)
                $this.RecordSuccess()
                return $true
            } else {
                Write-Host "Trade Failed.. offer should expire on it's own." -ForegroundColor Red
                $this.RecordFailure("Tibet offer did not complete.")
            }
        }
        return $false
    }

    [hashtable]AvailableProfit(){
        $trades = $this.Trades()
        $measure = $trades | Measure-Object -sum xprofit, yprofit
        $xprofit = (($measure | Where-Object {$_.Property -eq "xprofit"}).sum)
        $yprofit = (($measure | Where-Object {$_.Property -eq "yprofit"}).sum)
        return @{
            xProfit = $xprofit
            yProfit = $yprofit
        }
    }

    [pscustomobject]ProfitReport(){
        $trades = $this.Trades() | Where-Object { -not ( $_.xprofit -lt 0 -or $_.yprofit -lt 0 )}
        $measure = $trades | Measure-Object -sum dx, dy, xprofit, yprofit
        $dx = (($measure | Where-Object {$_.Property -eq "dx"}).sum)
        $dy = (($measure | Where-Object {$_.Property -eq "dy"}).sum)
        $xprofit = (($measure | Where-Object {$_.Property -eq "xprofit"}).sum)
        $yprofit = (($measure | Where-Object {$_.Property -eq "yprofit"}).sum)
        if($dx -ne 0){
            $xPercent = $xprofit / $dx
        } else {
            $xPercent = 0
        }
        if($dy -ne 0){
            $yPercent = $yprofit / $dy
        } else {
            $yPercent = 0
        }
        
        
        return [pscustomobject]@{
            dx = $dx
            xProfit = $xprofit
            xPercent = $xPercent
            dy = $dy
            yProfit = $yprofit
            yPercent = $yPercent
        }
    }

    [hashtable]AuditReport(){
        $pr = $this.ProfitReport()
        $calculatedX = $this.starting_x_amount + $pr.dx
        $CalculatedY = $this.starting_y_amount + $pr.dy
        $availableProfit = $this.AvailableProfit()
        $totalX = $this.xr + $availableProfit.xprofit
        $totalY = $this.yr + $availableProfit.yprofit
        $walletX = (Get-SageSyncStatus).selectable_balance | ConvertFrom-XchMojo
        $walletY = (get-sagecat -asset_id $this.token_y_id).token.balance | ConvertFrom-CatMojo

        return @{
            xTradesMatchXR = ($calculatedX -eq $this.xr)
            yTradesMatchYR = ($calculatedY -eq $this.yr)
            exactBallanceX = ($walletX -eq $totalX)
            exactBallanceY = ($walletY -eq $totalY)
            xBalanceOk = ($walletX -ge $this.xr)
            yBalanceOk = ($walletY -ge $this.yr)
        }
    }

    # [bool]Handle(){

    #     $dexieX = $this.GetDexieFromX()
    #     $dexieXcheck = $this.CheckOffer($dexieX.offer)
    #     $tibetXCheck = $this.CheckTibetQuote($this.GetTibetQuoteFromX($dexieXcheck.TibetX))
    #     if($dexieXcheck.isProfitable){
    #         # check if tibet is profitable
    #         if($tibetXCheck.isProfitable){
    #             # both profiable, pick the best one.
    #             if($dexieXcheck.yProfit -gt $tibetXCheck.yProfit){
    #                 # x better
    #                 $this.HandleDexieFromX()
    #                 return $true
    #             } else {
    #                 $this.AttemptTibetOffer($tibetXCheck)
    #                 return $true
    #             }
    #         } 
    #         $this.HandleDexieFromX()
    #         return $true
    #     }

    #     $dexieY = $this.GetDexieFromY()
    #     $dexieYcheck = $this.checkoffer($dexieY.offer)
    #     $tibetYcheck = $this.CheckTibetQuote($this.GetTibetQuoteFromY($dexieYcheck.TibetY))
    #     if($dexieYcheck.isProfitable){
    #         if($tibetYcheck.isProfitable){
    #             if($dexieYcheck.xProfit -gt $tibetYcheck.xProfit){
    #                 $this.HandleDexieFromY()
    #                 return $true
    #             } else {
    #                 $this.AttemptTibetOffer($tibetYcheck)
    #                 return $true
    #             }
    #         }
    #         $this.HandleDexieFromY()
    #         return $true
    #     }
    #     return $false
    # }


    longrun(){
        $this.longrun($this.default_tibet_x_amount)
    }

    longrun([decimal]$tibet_X_amount){
        if($tibet_X_amount -le 0){
            throw "You must set the tibet_x_amount to be a decimal number greater than 0."
        }
        while($true){
            $probeX = [Math]::Min(1, [decimal]$this.xr)
            if($probeX -le 0){ $probeX = [decimal]0.01 }
            try{
                $sell = ($this.Adjust_X_Amount(-$probeX)).dy
                $sellLabel = "$probeX XCH"
            } catch {
                $sell = "NA"
                $sellLabel = "$probeX XCH"
            }
            try{
                $buy = ($this.Adjust_X_Amount($probeX)).dy
                $buyLabel = "$probeX XCH"
            } catch {
                $buy = "NA"
                $buyLabel = "$probeX XCH"
            }
            
            
            Write-Host ""
            Write-Host "-------------------------------------------------" -ForegroundColor Cyan
            Write-Host "Currently trading [ $($buy) ] $($this.token_y) for [ $($buyLabel) ]" -ForegroundColor Cyan
            Write-Host "Currently trading [ $($sellLabel) ] for [ $($sell) $($this.token_y) ]" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "Current XCH Balance: $($this.xr)" -ForegroundColor Cyan
            Write-Host "Current $($this.token_y) Balance: $($this.yr)"  -ForegroundColor Cyan
            if($this.yr -le 0){
                Write-Host "Note: yr=0 at this price — only XCH->CAT Dexie fills are possible until price moves." -ForegroundColor DarkYellow
            }
            if($this.xr -lt 1){
                Write-Host "Note: xr is under 1 XCH — most Dexie offers will be skipped as too large." -ForegroundColor DarkYellow
            }
            Write-Host "-------------------------------------------------" -ForegroundColor Cyan
            Write-Host ""

            Write-Host "Checking Dexie for offers from XCH"
            
            
            try{
                $this.HandleDexieFromX()
            } catch {
                Write-Error "Exception: $($_.Exception.Message)"
            }   

            
            Write-Host "Checking Dexie for offers from $($this.token_y)"
            try{
                $this.HandleDexieFromY()
            } catch {
                Write-Error "Exception: $($_.Exception.Message)"
            }

            Write-Host ""
            Write-Host "-------------------------------------------------" -ForegroundColor Cyan
            Write-Host "Checking Tibet Offers XCH -> $($this.token_y)" -ForegroundColor Cyan
            Write-Host ""

            try{
                $tibxch = $this.InvokeWithRetry({ $this.GetTibetQuoteFromX($tibet_X_amount) }, "GetTibetQuoteFromX")
                $tby = $tibxch.amount_out | ConvertFrom-CatMojo
                $tiby = $this.InvokeWithRetry({ $this.GetTibetQuoteFromY($tby) }, "GetTibetQuoteFromY")
                $tbx = $tiby.amount_out | ConvertFrom-XchMojo
                $checkx = $this.CheckTibetQuote($tibxch)
                $checky = $this.CheckTibetQuote($tiby)
                if($checkx.isProfitable){
                    Write-Host "Tibetswap offers [ $($tby) $($this.token_y) ] for [ $($tibet_X_amount) XCH ]"  -ForegroundColor Green
                    Write-Host "This offer has $($checkx.yProfit) $($this.token_y) of profit." -ForegroundColor Green
                    $this.AttemptTibetOffer($checkx)
                    Write-Host "-------------------------------------------------" -ForegroundColor Cyan
                    Write-Host ""
                } else {
                    Write-Host "Tibetswap offers [ $($tby) $($this.token_y) ] for [ $($tibet_X_amount) XCH ]"  -ForegroundColor Red
                    Write-Host "This offer is not profitable." -ForegroundColor Red
                    Write-Host "-------------------------------------------------" -ForegroundColor Cyan
                    Write-Host ""
                }
                Write-Host ""
                Write-Host "-------------------------------------------------" -ForegroundColor Cyan
                Write-Host "Checking Tibet Offers $($this.token_y) -> XCH" -ForegroundColor Cyan
                if($checky.isProfitable){
                    Write-Host "Tibetswap offers [ $($tbx) XCH ] for [ $($tby) $($this.token_y) ]" -ForegroundColor Green
                    Write-Host "This offer has $($checky.xProfit) XCH of profit." -ForegroundColor Green
                    $this.AttemptTibetOffer($checky)
                    Write-Host "-------------------------------------------------" -ForegroundColor Cyan
                    Write-Host ""
                } else {
                    Write-Host "Tibetswap offers [ $($tbx) XCH ] for [ $($tby) $($this.token_y) ]" -ForegroundColor Red
                    Write-Host "This offer is not profitable." -ForegroundColor Red
                    Write-Host "-------------------------------------------------" -ForegroundColor Cyan
                    Write-Host ""
                }
            } catch {
                Write-Error "Exception: $($_.Exception.Message)"
            }
            
            $waitSeconds = 30
            if((Get-Date) -lt $this.cooldown_until){
                $waitSeconds = [Math]::Max(5, [int][Math]::Ceiling(($this.cooldown_until - (Get-Date)).TotalSeconds))
            } elseif($this.consecutive_failures -gt 0){
                $waitSeconds = [Math]::Min(120, (30 + ($this.consecutive_failures * 10)))
            }
            Write-Host "Waiting $waitSeconds seconds"
            start-sleep $waitSeconds
        }
    }

}


function Import-TraderBot{
    param(
        [string]$botName
    )
    try {
        $bot =  [TraderBot]::Import($botName)
        return $bot
    }
    catch {
        throw "Could not load bot with name $($botName): $($_.Exception.Message)"
    }
}

function Get-TraderBotDirectory{
    return [TraderBot]::Resolve_Bot_Directory("~/.bots")
}

function Show-TraderBots{
    $resolvedDirectory = [TraderBot]::Resolve_Bot_Directory("~/.bots")
    Write-Host "Bot directory: $resolvedDirectory"
    $files = @(Get-ChildItem -Path $resolvedDirectory -Filter *.json -ErrorAction SilentlyContinue)
    if($files.Count -eq 0){
        Write-Host "No bots found in $resolvedDirectory"
        return
    }

    foreach($file in $files){
        try{
            $data = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
            $id = if($data.id){ [string]$data.id } else { $file.BaseName }
            $token = if($data.token_y){ [string]$data.token_y } else { "?" }
            Write-Host "$id  (file: $($file.Name), token_y: $token)"
        } catch {
            Write-Host "$($file.BaseName)  (invalid json)"
        }
    }
}

function Get-CatPerXchFromDexieOffer {
    param(
        [Parameter(Mandatory = $true)]
        $DexieOffer
    )

    $xchAmount = [decimal]0
    $catAmount = [decimal]0
    foreach($leg in @($DexieOffer.offered; $DexieOffer.requested)){
        foreach($asset in $leg){
            if($asset.code -eq "XCH" -or $asset.id -eq "xch"){
                $xchAmount += [decimal]$asset.amount
            } else {
                $catAmount += [decimal]$asset.amount
            }
        }
    }

    if($xchAmount -le 0){
        return $null
    }

    return [math]::Round($catAmount / $xchAmount, 6)
}

function Get-DexieMarketPrices {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TokenY,
        [int]$PageSize = 5
    )

    $baseUri = "https://dexie.space/v1/offers"
    $buyCatUri = "${baseUri}?offered=xch&requested=$TokenY&page_size=$PageSize"
    $sellCatUri = "${baseUri}?offered=$TokenY&requested=xch&page_size=$PageSize"

    $buyCatPrices = @()
    $sellCatPrices = @()

    try{
        $buyCatResponse = Invoke-RestMethod -Uri $buyCatUri -Method Get
        foreach($offer in @($buyCatResponse.offers)){
            $price = Get-CatPerXchFromDexieOffer -DexieOffer $offer
            if($null -ne $price){ $buyCatPrices += $price }
        }
    } catch {
        Write-Warning "Dexie buy-cat query failed: $($_.Exception.Message)"
    }

    try{
        $sellCatResponse = Invoke-RestMethod -Uri $sellCatUri -Method Get
        foreach($offer in @($sellCatResponse.offers)){
            $price = Get-CatPerXchFromDexieOffer -DexieOffer $offer
            if($null -ne $price){ $sellCatPrices += $price }
        }
    } catch {
        Write-Warning "Dexie sell-cat query failed: $($_.Exception.Message)"
    }

    return [pscustomobject]@{
        buy_cat_prices = $buyCatPrices
        sell_cat_prices = $sellCatPrices
        buy_cat_best = if($buyCatPrices.Count -gt 0){ ($buyCatPrices | Measure-Object -Minimum).Minimum } else { $null }
        sell_cat_best = if($sellCatPrices.Count -gt 0){ ($sellCatPrices | Measure-Object -Maximum).Maximum } else { $null }
        mid_price = if(($buyCatPrices.Count -gt 0) -and ($sellCatPrices.Count -gt 0)){
            [math]::Round((($buyCatPrices | Measure-Object -Minimum).Minimum + ($sellCatPrices | Measure-Object -Maximum).Maximum) / 2, 6)
        } else { $null }
    }
}

function Get-TibetMarketPrice {
    param(
        [Parameter(Mandatory = $true)]
        $PairInfo,
        [decimal]$QuoteXchAmount = 0.2
    )

    $xchReserve = [decimal]$PairInfo.xch_reserve / 1000000000000
    $catReserve = [decimal]$PairInfo.token_reserve / 1000
    $reservePrice = if($xchReserve -gt 0){ [math]::Round($catReserve / $xchReserve, 6) } else { $null }

    $quotePrice = $null
    if((Get-Command Get-TibetQuote -ErrorAction SilentlyContinue) -and (Get-Command ConvertTo-XchMojo -ErrorAction SilentlyContinue)){
        try{
            $quote = Get-TibetQuote -pair_id $PairInfo.pair_id -amount_in ($QuoteXchAmount | ConvertTo-XchMojo) -xch_is_input
            if((Get-Command ConvertFrom-CatMojo -ErrorAction SilentlyContinue)){
                $catOut = $quote.amount_out | ConvertFrom-CatMojo
            } else {
                $catOut = [decimal]$quote.amount_out / 1000
            }
            if($QuoteXchAmount -gt 0){
                $quotePrice = [math]::Round($catOut / $QuoteXchAmount, 6)
            }
        } catch {
            Write-Warning "Tibet quote lookup failed: $($_.Exception.Message)"
        }
    }

    $spot = if($null -ne $quotePrice){ $quotePrice } else { $reservePrice }
    return [pscustomobject]@{
        reserve_price = $reservePrice
        quote_price = $quotePrice
        spot_price = $spot
        quote_xch_amount = $QuoteXchAmount
    }
}

function Get-TraderBotSettingsSuggestion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TokenY,
        [decimal]$RangePercent = 10,
        [decimal]$QuoteXchAmount = 0.2,
        [switch]$Quiet
    )

    if($RangePercent -le 0){
        throw "RangePercent must be greater than 0."
    }

    $pairLookup = Get-TTPairs -asset_id $TokenY
    $pair = if($pairLookup -is [System.Array]){ $pairLookup[0] } else { $pairLookup }
    if(-not $pair){
        throw "No TibetSwap pair found for token '$TokenY'."
    }

    $ticker = if(-not [string]::IsNullOrWhiteSpace([string]$pair.asset_short_name)){
        [string]$pair.asset_short_name
    } else {
        $TokenY
    }

    $tibet = Get-TibetMarketPrice -PairInfo $pair -QuoteXchAmount $QuoteXchAmount
    $dexie = Get-DexieMarketPrices -TokenY $ticker

    $candidates = @()
    if($null -ne $tibet.spot_price){ $candidates += $tibet.spot_price }
    if($null -ne $dexie.mid_price){ $candidates += $dexie.mid_price }
    if($null -ne $dexie.buy_cat_best){ $candidates += $dexie.buy_cat_best }
    if($null -ne $dexie.sell_cat_best){ $candidates += $dexie.sell_cat_best }

    if($candidates.Count -eq 0){
        throw "Could not determine a market price from TibetSwap or Dexie for '$TokenY'."
    }

    $referencePrice = [math]::Round((($candidates | Measure-Object -Average).Average), 6)
    $rangeFactor = ($RangePercent / 100)

    $sellXchSuggestion = [pscustomobject]@{
        strategy = "Start with XCH (sell XCH for CAT as price rises)"
        x_is_default = $true
        pa = $referencePrice
        pb = [math]::Round($referencePrice * (1 + $rangeFactor), 6)
        note = "Set pa near current price; pb above current."
    }

    $buyCatSuggestion = [pscustomobject]@{
        strategy = "Start with CAT (buy CAT with XCH as price falls)"
        x_is_default = $false
        pa = [math]::Round($referencePrice * (1 - $rangeFactor), 6)
        pb = $referencePrice
        note = "Set pb near current price; pa below current."
    }

    if($sellXchSuggestion.pa -ge $sellXchSuggestion.pb){
        throw "Suggested sell-XCH range is invalid (pa >= pb). Try a larger RangePercent."
    }
    if($buyCatSuggestion.pa -ge $buyCatSuggestion.pb){
        throw "Suggested buy-CAT range is invalid (pa >= pb). Try a smaller RangePercent."
    }

    $suggestion = [pscustomobject]@{
        token_y = $ticker
        token_y_id = [string]$pair.asset_id
        pair_id = [string]$pair.pair_id
        price_unit = "CAT per 1 XCH"
        reference_price = $referencePrice
        range_percent = $RangePercent
        tibet = $tibet
        dexie = $dexie
        sell_xch_bot = $sellXchSuggestion
        buy_cat_bot = $buyCatSuggestion
        generated_at = (Get-Date).ToString("o")
    }

    if(-not $Quiet){
        Write-Host ""
        Write-Host "Settings suggestion for $($suggestion.token_y) ($($suggestion.price_unit))" -ForegroundColor Cyan
        Write-Host "Reference price: $($suggestion.reference_price)"
        Write-Host "Tibet reserve: $($tibet.reserve_price)  |  Tibet quote ($QuoteXchAmount XCH): $($tibet.quote_price)"
        Write-Host "Dexie best buy-CAT: $($dexie.buy_cat_best)  |  best sell-CAT: $($dexie.sell_cat_best)  |  mid: $($dexie.mid_price)"
        Write-Host ""
        Write-Host "Sell-XCH bot (start with X):" -ForegroundColor Green
        Write-Host "  min price (pa): $($sellXchSuggestion.pa)"
        Write-Host "  max price (pb): $($sellXchSuggestion.pb)"
        Write-Host "  suggested starting amount: $([Math]::Max($QuoteXchAmount, 1)) XCH"
        Write-Host ""
        Write-Host "Buy-CAT bot (start with Y):" -ForegroundColor Green
        Write-Host "  min price (pa): $($buyCatSuggestion.pa)"
        Write-Host "  max price (pb): $($buyCatSuggestion.pb)"
        Write-Host "  suggested starting amount: $([math]::Round($referencePrice * $QuoteXchAmount, 6)) $($ticker)"
        Write-Host ""
    }

    return $suggestion
}

function New-TraderBot{
    param(
        [switch]$UseMarketSuggestion,
        [decimal]$RangePercent = 10,
        [decimal]$QuoteXchAmount = 0.2
    )

    $bot = [TraderBot]::Build($UseMarketSuggestion.IsPresent, $RangePercent, $QuoteXchAmount)
    return $bot
}