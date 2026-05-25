function Get-TTPairs{
    param (
        [string]$asset_id
    )
    $uri = "https://api.v2.tibetswap.io/pairs?skip=0&limit=1000"

    try{
        $response = Invoke-RestMethod -Uri $uri -Method Get

        if($asset_id.Length -eq 64){
            $response | Where-Object {$_.asset_id -eq $asset_id}
        } else {
            $response
        }
    } catch {

        throw "Could not contact tibetswap api to retrieve pairs."
    }
    

}

function Get-TTDatabase{
    $test = Test-Path -Path "~/.trader"
    if(-Not $test){
        New-Item -Path "~/.trader" -ItemType Directory
    }
    return "~/.trader/tt.sqlite"
}

function Build-TTDatabase{
    $database = Get-TTDatabase
}

class SilentBot {
    [string]$id
    [string]$fingerprint
    [string]$name
    $token_x
    $token_y
    [decimal]$pa # Mininum Price
    [decimal]$pb # Maximum Price
    [decimal]$spread_percentage 
    [boolean]$x_is_spread_token  = $true
    [boolean]$x_is_default = $true
    [boolean]$invert_price = $false
    [decimal]$starting_x_amount
    [decimal]$starting_y_amount
    [decimal]$xv
    [decimal]$yv
    [decimal]$xr
    [decimal]$yr 
    [decimal]$liquidity_squared
    [decimal]$liquidity
    [decimal]$fee_accumulated = 0
    [array]$attempts = @()
    [array]$trades = @()
    [bool]$active


    SilentBot(){
        $this.id = (New-Guid).Guid
        $this.active = $false
    }
    
    SilentBot([PSCustomobject]$props){
        $this.Init([PSCustomObject]$props)    
    }

    [void] Init([PSCustomobject]$props)  {
        $this.id = $props.id
        if($props.token_x){
            $this.token_x = (Get-SageToken -id ($props.token_x.ticker))
        }
        if($props.token_y){
            $this.token_y = (Get-SageToken -id ($props.token_y.ticker))
        }
        $this.name = $props.name
        $this.fingerprint = $props.fingerprint
        $this.pa = $props.pa
        $this.pb = $props.pb
        $this.starting_x_amount = $props.starting_x_amount
        $this.starting_y_amount = $props.starting_y_amount
        $this.spread_percentage = $props.spread_percentage
        $this.x_is_spread_token  = $props.x_is_spread_token    
        $this.x_is_default = $props.x_is_default
        $this.invert_price = $props.invert_price
        $this.xv = $props.xv
        $this.yv = $props.yv
        $this.xr = $props.xr
        $this.yr = $props.yr
        $this.liquidity_squared = $props.liquidity_squared
        $this.liquidity = $props.liquidity
        $this.fee_accumulated = $props.fee_accumulated
        $this.attempts = $props.attempts
        $this.trades = $props.trades
        $this.active = $props.active
    

    }


    [void] logOffer($log){
        $path = Get-SageTraderPath("offerlogs")
        $file = Join-Path -Path $path -ChildPath "$($this.id).csv"
        
        if(-not (Test-Path -Path $path)){
            New-Item -Path $path -ItemType Directory | Out-Null
        }
        if(-not (Test-Path -Path $file)){
            $log | Export-Csv -Path $file -NoTypeInformation
        } else {
            $log | Export-Csv -Path $file -NoTypeInformation -Append
        }

    }

    [void] updateLogOffer($offer_id,$status){
        $path = Get-SageTraderPath("offerlogs")
        $file = Join-Path -Path $path -ChildPath "$($this.id).csv"
        $offers = Import-Csv -Path $file
        $offer = $offers | Where-Object {$_.offer_id -eq $offer_id}
        if($offer){
            $offer.status = $status
            $offers | Export-Csv -Path $file -NoTypeInformation
        }
    }

    [bool] isLoggedIn(){
        $fp = (Invoke-SageRPC -endpoint get_key -json @{})
        if($null -eq $fp){
            Write-SpectreHost -Message "[red]Bot [/][blue]$($this.name)[/][red] does not have access to this wallet. 
            Please log in with the fingerprint: [/][blue]$($this.fingerprint)[/]"
            return $false
        }
        if($fp.key.fingerprint -eq $this.fingerprint){
            return $true
        }
        Write-SpectreHost -Message "
        [red]Bot [/][blue]$($this.name)[/][red] does not have access to this wallet. 
        Please log in with the fingerprint: [/][blue]$($this.fingerprint)[/]"
        return $false
    }

    [bool] isActive(){
        if($this.active -eq $true){
            Write-SpectreHost -Message "[green]Bot [/][blue]$($this.name)[/][green] is active.[/]"
            return $true
        } else {
            Write-SpectreHost -Message "[red]Bot [/][blue]$($this.name)[/][red] is not active.[/]"
            return $false    
        }
        
    }

    [void] showMenu(){
    $choice=0
    do{
        Clear-Host
        
        Write-SpectreHost -message ($this.summary())

        Write-SpectreHost -Message "
[cyan]BOT MENU
---------------------------------
1. $($this.active ? "[red]Deactivate Bot[/]" : "[green]Activate Bot[/]")
2. Destroy Bot

9. Back to main menu
[/]

"

$choices = @(1,2,9)
$choice = Read-ValidMenu -choices $choices -message "Select an option:"

    switch ($choice) {
        1 {
            if ($this.active) {
                $this.deactivate()
                Write-SpectreHost -Message "[red]Bot [/][blue]$($this.name)[/] [red]is now deactivated.[/]"
                
            } else {
                $this.activate()
                Write-SpectreHost -Message "[green]Bot [/][blue]$($this.name)[/] [green]is now active.[/]"
                
            }
        }
        2 {$this.destroy()
            $choice = 9
        }
        }}until ($choice -eq 9)
        
        (Show-Screen -name Home)
    }

    [void] deactivate(){
        $this.active = $false
        $this.save()
    }

    

    [void] destroy(){
        $path = Get-SageTraderPath("SilentBots")
        $path = Join-Path -Path $path -ChildPath "$($this.id).json"
        
        $check = Read-SpectreConfirm -Message "Are you sure you want to delete this bot?" -DefaultAnswer "n"
        if($check -eq $true){
            if(Test-Path -Path $path){
                Remove-Item -Path $path -Force
                Write-SpectreHost -Message "[green]Bot deleted successfully.[/]"
            } else {
                Write-SpectreHost -Message "[red]Bot not found.[/]"
            }
        } else {
            Write-SpectreHost -Message "[yellow]Bot deletion cancelled.[/]"
        }

    }

    [void] activate(){
       
        $this.active = $true
        $this.save()
    }

    [void] GetQuoteToXCH($amount){
        if($this.yr -gt 0){
            $try = $this.Adjust_X_Amount($amount)
            if($try.newyr -gt 0){
                $dq = Get-DexieQuote -from ($this.token_y.ticker) -to xch -to_amount ($try.dx | ConvertTo-XchMojo)
                $y_bonus =($dq.quote.from_amount) - ([Math]::Abs(($try.dy | ConvertTo-catMojo)) )
                if(($dq.quote.from_amount) -le ([Math]::Abs(($try.dy | ConvertTo-catMojo)) )){
                    $offer = Build-SageOffer
                    $offer.requestXch(($dq.quote.to_amount))
                    $offer.offercat(($this.token_y.asset_id),([Math]::Abs($try.dy) | ConvertTo-CatMojo))
                    $offer.createoffer()
                    $this.attempts += @{
                        fee_available = ($try.fee | ConvertTo-XchMojo)
                        offer = ($offer)
                        buildStructure = $try
                        submitted = $false
                    }     
                    $this.save()                                   
                } else {
                    Write-Host "Should not take trade ( $($dq.quote.from_amount) is > $([Math]::Abs(($try.dy | ConvertTo-catMojo))))"
                }
            } else {
                Write-Host "Not enough $($this.token_y.ticker) available to take trade"
            }
        } else {
            Write-Host "Not enough $($this.token_y.ticker) available to take trade"
        }
    }

    [void] GetQuoteFromXCH($amount){
        if($this.xr -gt 0){
            $try = $this.Adjust_X_Amount(-$amount)
            if($try.newxr -gt 0){
                $dq = Get-DexieQuote -from xch -to ($this.token_y.ticker) -to_amount ($try.dy | ConvertTo-CatMojo)
                if(($dq.quote.from_amount) -le ([Math]::Abs(($try.dx | ConvertTo-xchMojo)) )){
                    $offer = Build-SageOffer
                    $offer.offerXch(($dq.quote.from_amount))
                    $offer.requestCat(($this.token_y.asset_id),($try.dy | ConvertTo-CatMojo))
                    $offer.createoffer()
                    $this.attempts += @{
                        fee_available = (([Math]::Abs(($try.dx))|  ConvertTo-XchMojo)-($dq.quote.from_amount ))
                        offer = ($offer)
                        buildStructure = $try
                        submitted = $false
                    }     
                    $this.save()                                   
                } else {
                    Write-Host "Should not take trade ( $($dq.quote.from_amount) is > $([Math]::Abs(($try.dx | ConvertTo-xchMojo))))"
                }
            } else {
                Write-Host "Not enough XCH available to take trade"
            }
        } else {
            Write-Host "Not enough XCH available to take trade"
        }
    }

    [void]SubmitAttempt(){
        
        $submit = Submit-DexieSwap -offer ($this.attempts[0].offer.offer_data.offer)
        
        if($submit.success){
            Write-Host "Submitted to DexieSwap"
            $this.attempts[0].submitted = $true
            $this.save()
        } else {
            Write-Host "Failed to submit to DexieSwap"
        }
        
    }


    [void]CheckOffer(){
            $offer_id = $this.attempts[0].offer.offer_data.offer_id
            $offer = get-sageoffer -offer_id $offer_id
            if($offer.status -eq 'completed'){
                 $this.trades += ($this.attempts[0])
            $this.fee_accumulated += ($this.attempts[0].fee_available)
            $this.xr = $this.attempts[0].buildStructure.newxr
            $this.yr = $this.attempts[0].buildStructure.newyr
            $this.attempts = @()
            $this.save()
            }
           
    }

    [void] Handle(){
        

        if($this.attempts.count -eq 0){
            $this.GetQuoteFromXCH(0.5)
            
        }
        if($this.attempts.count -eq 0){
            $this.GetQuoteToXCH(0.5)
        }

        if($this.attempts.count -eq 1 ){
            $this.CheckOffer()
            $this.SubmitAttempt()
        }
        $sleep = (Get-Random -Minimum 60 -Maximum 300)
        Write-SpectreHost -Message "
Name: $($this.name)
XCH : $($this.xr)
$($this.token_y.ticker): $($this.yr)
------------------------------------
Fees: $($this.fee_accumulated / 1000000000000)
Trades: $($this.trades.count)
------------------------------------

Sleeping for $sleep
        "
        
        start-sleep $sleep
    }

    

    
    [array] getLog(){
        $path = Get-SageTraderPath("offerlogs")
        $file = Join-Path -Path $path -ChildPath "$($this.id).csv"
        
        if(-not (Test-Path -Path $file)){
            Write-SpectreHost -Message "[red]No logs found for this bot.[/]"
            return @()
        }
        $log = Import-Csv -Path $file
        if($null -eq $log){
            Write-SpectreHost -Message "[red]No logs found for this bot.[/]"
            return @()
        }
        if($log.count -eq 0){
            Write-SpectreHost -Message "[red]No logs found for this bot.[/]"
            return @()
        }
        return $log
    }

    [decimal]Calculate_yv(){
        return ($this.liquidity * ([math]::Sqrt($this.pa)))
    }

    [decimal]Calculate_xv(){
        return ($this.liquidity / ([math]::Sqrt($this.pb)))
    }

    [void]save(){
        $path = Get-SageTraderPath("SilentBots")
        $file = Join-Path -Path $path -ChildPath "$($this.id).json"
        $this | ConvertTo-Json -Depth 20 | Out-File -FilePath $file -Encoding utf8
    }


    [void]Starting_Token_Amount($amount){
        if($this.xv -or $this.yv -or $this.xr -or $this.yr -or $this.liquidity -or $this.liquidity_squared){
            throw "Starting_Token_Amount can only be called once per instance."
        }
        if($this.x_is_default){
            $this.xr = $amount
            $solve = $amount / ((1/[math]::Sqrt($this.pa))-(1/[math]::Sqrt($this.pb)))
            $this.liquidity = $solve
            $this.liquidity_squared = $solve * $solve
            $this.xv = $this.Calculate_xv()
            $this.yv = $this.Calculate_yv()
            
        } else {
            $solve = $amount / (([math]::Sqrt($this.pb))-([math]::Sqrt($this.pa)))
            $this.yr = $amount
            $this.liquidity = $solve
            $this.liquidity_squared = $solve * $solve
            $this.xv = $this.Calculate_xv()
            $this.yv = $this.Calculate_yv()
            
        }
    }

    [decimal]Get_Price(){
        if($this.invert_price){
            $price = ($this.xv + $this.xr) / ($this.yv + $this.yr)
        } else {
            $price = ($this.yv + $this.yr) / ($this.xv + $this.xr)
        }
        return [math]::Round($price,3)
    }

    static [array]All(){
        $path = Get-SageTraderPath("SilentBots")
        if(-not (Test-Path -Path $path)){
            return @()
        }
        $files = Get-ChildItem -Path $path -Filter *.json
        $bots = @()
        foreach($file in $files){
            $content = Get-Content -Path $file.FullName -Raw
            $json = ConvertFrom-Json -InputObject $content
            $bot = [SilentBot]::new($json)
            $bots += $bot
        }
        return $bots
    }

    
    [ordered]Adjust_X_Amount([decimal]$amount){
        $_xr = $this.xr 
        $newxr = $_xr + $amount
        $_xv = $this.xv
        $_yv = $this.yv
        $_yr = $this.yr
        $_y = $this.liquidity_squared / ($newxr + $_xv)
        $newyr = [math]::round($_y - $_yv,3)
        
        if($this.x_is_spread_token){
            $fee_token = $this.token_x.ticker
            $dy = $newyr - $_yr
            $_fee = [math]::Abs([math]::Round($amount * ($this.spread_percentage / 2),12))
            if($amount -lt 0){
                $dx = $amount + $_fee
            } else {
                $dx = $amount + $_fee
            }
        } else {
            $fee_token = $this.token_y.ticker
            $dx = $newxr - $_xr
            $_fee = [math]::Abs([math]::Round(($newyr - $_yr) * ($this.spread_percentage / 2),12))
            if($amount -lt 0){
                $dy = $newyr - $_yr + $_fee
            } else {
                $dy = $newyr - $_yr + $_fee
            }
            
        }


        $trade = [ordered]@{
            'price' = [math]::Round(([math]::Abs($dy) / [math]::Abs($dx)),3)
            'fee_token' = $fee_token
            'fee' = ([math]::Abs($_fee))
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
        $_xv = $this.xv
        $_yv = $this.yv
        $_xr = $this.xr
        $_x = $this.liquidity_squared / ($newyr + $_yv)
        $newxr = [math]::round($_x - $_xv,12)
        if(-not $this.x_is_spread_token){
            
            $fee_token = $this.token_y.ticker
            $dx = $newxr - $_xr
            $_fee = [math]::Abs([math]::Round($dx * ($this.spread_percentage / 2),3))
            if($amount -lt 0){
                $dy = $amount + $_fee
            } else {
                $dy = $amount + $_fee
            }
        } else {
            $fee_token = $this.token_x.ticker
            $dy = $newyr - $_yr
            $_fee = [math]::Abs([math]::Round(($newxr - $_xr) * ($this.spread_percentage / 2),3))
            if($amount -lt 0){
                $dx = $newxr - $_xr - $_fee
            } else {
                $dx = $newxr - $_xr - $_fee
            }
            
        }


        $trade = [ordered]@{
            'price' = [math]::Round(([math]::Abs($dy) / [math]::Abs($dx)),3)
            'fee_token' = $fee_token
            'fee' = ([math]::Abs($_fee))
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

    [PSCustomObject]Swap_From_X([decimal]$amount){
        $from = $this.token_x.ticker
        $to = $this.token_y.ticker
        $from_amount = [math]::round(($amount * [math]::Pow(10, $this.token_x.precision)),0)
        
        return Get-DexieQuote -from $from -to $to -from_amount $from_amount
        
    }

}
