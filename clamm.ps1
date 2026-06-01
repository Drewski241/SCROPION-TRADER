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

    static [TraderBot]Build(){
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

        while($true){
            $bot.pa = [TraderBot]::Prompt_Positive_Decimal("Enter minimum price")
            $bot.pb = [TraderBot]::Prompt_Positive_Decimal("Enter maximum price")
            try{
                $bot.Validate_Price_Range()
                break
            } catch {
                Write-Host $_.Exception.Message -ForegroundColor Yellow
            }
        }

        $bot.x_is_default = [TraderBot]::Prompt_X_Is_Default()
        $startingAmount = [TraderBot]::Prompt_Positive_Decimal("Enter starting amount")
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

    static [TraderBot]Import([string]$token_y){
        return [TraderBot]::Import($token_y, "~/.bots")
    }

    static [TraderBot]Import([string]$token_y, [string]$directory){
        $filePath = [TraderBot]::Build_Bot_File_Path($token_y, $directory)
        if(-not (Test-Path -Path $filePath)){
            throw "Bot file not found: $filePath"
        }

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
                $formula_says = $this.Adjust_X_Amount(-$requested_xch)
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

                $formula_says = $this.Adjust_Y_Amount(-$requested_y)
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


        $trade = [ordered]@{
            'price' = [math]::Round(([math]::Abs($dy) / [math]::Abs($dx)),3)
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

        $trade = [ordered]@{
            'price' = [math]::Round(([math]::Abs($dy) / [math]::Abs($dx)),3)
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
        $offer = Get-DexieOffers -offered $($this.token_y) -requested "xch" -page_size 1
        return $offer.offers
    }

    [array]GetDexieFromY(){
        $offer = Get-DexieOffers -requested $($this.token_y) -offered "xch" -page_size 1
        return $offer.offers
    }



    [void]HandleDexieFromX(){
        $offer = $this.GetDexieFromX()
        
        $this.HandleOffer($offer.offer)
        
        
    }

    [void]HandleDexieFromY(){
        $offer = $this.GetDexieFromY()
        $this.HandleOffer($offer.offer)
        
        
    }

    [array]Trades(){
        $resolvedDirectory = [TraderBot]::Resolve_Bot_Directory("~/.bots")
        $csvPath = [System.IO.Path]::Combine($resolvedDirectory, "completed_trades.csv")
        $trades = Import-Csv -Path $csvPath | Where-Object {$_.bot_name -eq $this.id}
        return $trades
    }

    [bool]TakeOffer($checked_offer){
        Write-Host "Trying to take an offer with TakeOffer()"
        $pretrade_y = ((get-sagecats).cats | Where-Object {$_.asset_id -eq $($this.token_y_id)}).selectable_balance
        Write-Host "PreTrade TokenY = $($pretrade_y)"
        $read = read-sageoffer -offer $checked_offer.offer
        if($read.status -eq "active"){
            $take = Complete-SageOffer -offer $checked_offer.offer
            
            if(-not $take){
                throw "Offer coult not be taken"
            }
            Write-Host "Offer taken - waiting for completion"
            start-sleep 2
            $count = (Get-SagePendingTransactions).count
            while($count -gt 0){
                start-sleep 10
                Write-Host "waiting for transactions to process"
                $count = (Get-SagePendingTransactions).count
            }
            
            $posttrade_y = ((get-sagecats).cats | Where-Object {$_.asset_id -eq $($this.token_y_id)}).selectable_balance
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
        
        # Check for profitability
        $checked_offer = $this.CheckOffer($offer_string)
        
        if($checked_offer.isProfitable){

            # Take profitable offer
            $take_offer = $this.TakeOffer($checked_offer)
            
            
            if($take_offer){
                # Record Transaction
                $this.CommitTrade($checked_offer)
            }
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
                    xProfit = $xprofit
                    yProfit = 0 
                    quote = $quote
                }
            } 

        } else {
            # wants XCH
            $requested_xch = $quote.amount_in | ConvertFrom-XchMojo
            $offered_y = $quote.amount_out | ConvertFrom-catMojo
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
        return @{isProfitable=$false}
    }

    [bool]AttemptTibetOffer($checked_quote){
        if(-Not $checked_quote.isProfitable){
            Write-Host "Tibet offer not profitable"
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
        Write-Host "offer submitted to tibetswap, waiting 5 sec to test"
        start-sleep 5
        $trackedOffer = Get-SageOffer -offer_id $offer.offer_id
        while($trackedOffer.status -eq "active"){
            Start-Sleep 10
            $trackedOffer = Get-SageOffer -offer_id $offer.offer_id
        }
        if($trackedOffer.status -eq "completed"){
            $this.CommitTrade($checked_quote)
            return $true
        } else {
            start-sleep 60
            $trackedOffer = Get-SageOffer -offer_id $offer.offer_id
            if($trackedOffer.status -eq "completed"){
                $this.CommitTrade($checked_quote)
                return $true
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
        while($true){
            try{
                $sell = ($this.Adjust_X_Amount(-1)).dy
            } catch {
                $sell = "NA"
            }
            try{
                $buy = ($this.Adjust_X_Amount(1)).dy
            } catch {
                $buy = "NA"
            }
            
            
            Write-Host ""
            Write-Host "-------------------------------------------------" -ForegroundColor Cyan
            Write-Host "Currently trading [ $($buy) ] $($this.token_y) for [ 1 XCH ]" -ForegroundColor Cyan
            Write-Host "Currently trading [ 1 XCH ] for [ $($sell) $($this.token_y) ]" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "Current XCH Balance: $($this.xr)" -ForegroundColor Cyan
            Write-Host "Current $($this.token_y) Balance: $($this.yr)"  -ForegroundColor Cyan
            Write-Host "-------------------------------------------------" -ForegroundColor Cyan
            Write-Host ""

            Write-Host "Checking Dexie for offers from XCH"
            
            
            try{
                $this.HandleDexieFromX()
            } catch {
                Write-Host "Exception: $($_.Exception.Message)" 
            }   

            
            Write-Host "Checking Dexie for offers from $($this.token_y)"
            try{
                $this.HandleDexieFromY()
            } catch {
                Write-Host "Exception: $($_.Exception.Message)" 
            }
            
            
            Write-Host "Waiting 30 seconds"
            start-sleep 30
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
        throw "Could not load bot with name $($botName)"
    }
}

function Show-TraderBots{
    $directory = "~/.bots"
    $files = Get-ChildItem -Path $directory -Filter *.json
    if($files.count -gt 0){
        $files.BaseName
    } else {
        Write-Error "No bots found"
    }
}

function New-TraderBot{
    $bot = [TraderBot]::Build()
    return $bot
}