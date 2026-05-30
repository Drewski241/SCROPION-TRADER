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

    [string]CheckOffer($offer_string){
        
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
                    Return "You should take this for a profit of $($yprofit) $($this.token_y)"
                } else {
                    Return "The trade is unprofitable."
                }
            }
            if($null -eq ($read.offer.maker[0].asset.asset_id) -AND ($read.offer.taker[0].asset.asset_id) -eq $this.token_y_id){
                $offered_xch = $read.offer.maker[0].amount | ConvertFrom-XchMojo
                $requested_y = $read.offer.taker[0].amount | ConvertFrom-CatMojo

                $formula_says = $this.Adjust_Y_Amount(-$requested_y)
                $xprofit = ($offered_xch - $formula_says.dx)
                if($xprofit -gt 0) {
                    Return "You should take this for a profit of $($xprofit) XCH"
                } else {
                    Return "This is not a favorable trade. "
                }

            }
        }
        Return "hi"
        
    }

    [void]CommitTrade([decimal]$dx, [decimal]$dy, [decimal]$xProfit, [decimal]$yProfit){
        if([string]::IsNullOrWhiteSpace($this.id)){
            throw "Bot id must be set before committing a trade. Call SaveToJson first or assign an id."
        }

        $newXTotal = $this.xr + $dx + $this.xv
        $newYTotal = $this.yr + $dy + $this.yv
        $actualProduct = $newXTotal * $newYTotal
        $tolerance = [math]::Abs($newXTotal) * 0.0005
        if([math]::Abs($actualProduct - $this.liquidity_squared) -gt $tolerance){
            throw "CommitTrade rejected: dx=$dx dy=$dy violates the liquidity invariant. Expected product ~$($this.liquidity_squared), got $actualProduct (tolerance $tolerance)."
        }

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

        $this.xr = [math]::Round($this.xr + $dx, 12)
        $this.yr = [math]::Round($this.yr + $dy, 3)
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
        $_yr = $this.yr
        $_y = $this.liquidity_squared / ($newxr + $_xv)
        $newyr = [math]::round($_y - $_yv,3)
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
        $_xr = $this.xr
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

    static [bool]TakeOffer($offer_string){

        $read = read-sageoffer -$offer_string
        if($read.status -eq "active"){
            $take = Complete-SageOffer -offer $offer_string
            start-sleep 2
            $count = Get-SagePendingTransactions
            while($count -gt 0){
                start-sleep 2
                Write-Host "waiting for transactions to process"
                $count = Get-SagePendingTransactions
            }


        }

    }
}

