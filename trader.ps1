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

function Get-TTDatabase{
    $test = Test-Path -Path "~/.trader"
    if(-Not $test){
        New-Item -Path "~/.trader" -ItemType Directory
    }
    return "~/.trader/tt.sqlite"
}




class SilentBot {
    [string]$id
    [string]$fingerprint
    [string]$pair_id
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
    [string]$token_y_id
    [decimal]$xv
    [decimal]$yv
    [decimal]$xr
    [decimal]$yr 
    [decimal]$liquidity_squared
    [decimal]$liquidity
    [int]$state = 3
    [datetime]$created_at
    [datetime]$updated_at


    SilentBot(){
        Clear-Host
        $this.created_at = (Get-Date)
        $this.token_x = 'xch'
        $this.token_y = Read-SpectreText -Message @"
Enter the ticker or asset_id of the token you wish to trade
"@
        Invoke-SpectreCommandWithStatus -Spinner OrangePulse -Title "Fetching Token Data" -ScriptBlock {
            $tokenInfo = (Get-TTPairs -asset_id ($this.token_y))
            $this.pair_id = $tokenInfo.pair_id
            $this.token_y = $tokenInfo.asset_short_name
            $this.token_y_id = $tokenInfo.asset_id
        }

        $choice = Read-SpectreSelection -Message "Which token will be sold?" -Choices @('xch',($this.token_y))
        if($choice -eq 'xch') {
            $this.x_is_default = $true
        } else {
            $this.x_is_default = $false
        }

        $c2 = Read-SpectreSelection -Message "What token do you want to collect your trading fees in?" -Choices @('xch',($this.token_y))
        if($c2 -eq 'xch') {
            $this.x_is_spread_token = $true
        } else {
            $this.x_is_spread_token = $false
        }

        if($this.x_is_default){
            Write-SpectreHost -Message "Starting price should be lower than Target price"    
        } else {
            Write-SpectreHost -Message "Starting price should be higher than Target price"
        }
        [decimal]$starting_price=0
        [decimal]$target_price=0
        while($starting_price -eq 0){
            try{
                [decimal]$starting_price = Read-SpectreText -Message "Staring price"
                
            } catch {
                Write-Error "Please enter a number greather than 0"
            }
            
        }
        while($target_price -eq 0){
            try{
                [decimal]$target_price = Read-SpectreText -Message "Target price"
            } catch {
                Write-Error "Please enter a number greather than 0"
            }
            
        }      
        if($this.x_is_default){
            
            $this.pa = $starting_price
            $this.pb = $target_price
        } else {
            
            $this.pb = $starting_price
            $this.pa = $choice
        }

        [decimal]$starting_amount = 0
        while($starting_amount -eq 0){
            try{
                if($this.x_is_default){
                    [decimal]$starting_amount = Read-SpectreText -Message "Enter the amount of [green]xch[/] the bot will use"
                } else {
                    [decimal]$starting_amount = Read-SpectreText -Message "Enter the amount of [green]$($this.token_y)[/] the bot will use"
                }
            } catch {
                Write-Error "Please enter a number above 0"
            }
        }
        $this.Starting_Token_Amount($starting_amount)
        Clear-Host
        [decimal]$fee_percent = 0
        while($fee_percent -lt 0.00000001){
            try {
                [decimal]$fee_percent = Read-SpectreText -Message "How much fee to collect on each trade? ie (0.005)"
            } catch {
                Write-Error "Please enter a number greater than 0"
            }
        }
        $this.spread_percentage = $fee_percent
        $fingerprints = (Get-SageKeys).keys
        $lifp = (Invoke-SageRPC -endpoint get_key -json @{}).key.fingerprint
        Write-SpectreHost -Message "Currently logged in with [green]$lifp[/]"
        $fp = Read-SpectreSelection -Message "Which wallet will the bot operate from" -Choices $fingerprints -ChoiceLabelProperty fingerprint 
        $this.fingerprint = $fp.fingerprint

    }
    
    SilentBot([PSCustomobject]$props){
        $this.Init([PSCustomObject]$props)    
    }

    [void] Init([PSCustomobject]$props)  {
        $this.id = $props.id
        $this.token_x = $props.token_x
        $this.token_y = $props.token_y
        $this.token_y_id = $props.token_y_id
        $this.fingerprint = $props.fingerprint
        $this.pair_id = $props.pair_id
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
        $this.state = $props.state
        $this.created_at = $props.created_at
        $this.updated_at = $props.updated_at
    

    }

    static [SilentBot] Load([int]$id) {
        if($id -le 0){
            throw "Load requires an id greater than 0."
        }

        $query = @"
        SELECT
            id,
            fingerprint,
            token_x,
            token_y,
            token_y_id,
            starting_x_amount,
            starting_y_amount,
            x_is_spread_token,
            spread_percentage,
            x_is_default,
            invert_price,
            state,
            pa,
            pb,
            xv,
            xr,
            yv,
            yr,
            liquidity_squared,
            liquidity,
            pair_id,
            created_at,
            updated_at
        FROM bots
        WHERE id = @id
        LIMIT 1;
"@

        $result = Invoke-SqliteQuery -DataSource (Get-TTDatabase) -Query $query -SqlParameters @{ id = $id }
        if($null -eq $result){
            throw "SilentBot with id '$id' was not found."
        }

        $row = if($result -is [System.Array]) { $result[0] } else { $result }
        if($null -eq $row){
            throw "SilentBot with id '$id' was not found."
        }

        return [SilentBot]::new([PSCustomObject]$row)
    }

    [bool] isLoggedIn(){
        $fp = (Invoke-SageRPC -endpoint get_key -json @{})
        if($null -eq $fp){
            Write-SpectreHost -Message "[red]Bot [/][blue]$($this.id)[/][red] does not have access to this wallet. 
            Please log in with the fingerprint: [/][blue]$($this.fingerprint)[/]"
            return $false
        }
        if($fp.key.fingerprint -eq $this.fingerprint){
            return $true
        }
        Write-SpectreHost -Message @"
[red]Bot [/][blue]$($this.id)[/][red] does not have access to this wallet. 

Please log in with the fingerprint: [/][blue]$($this.fingerprint)[/]
"@
        return $false
    }

    [bool] isActive(){
        if($this.state -eq 1){
            Write-SpectreHost -Message "[green]Bot [/][blue]$($this.id)[/][green] is active.[/]"
            return $true
        } else {
            Write-SpectreHost -Message "[red]Bot [/][blue]$($this.id)[/][red] is not active.[/]"
            return $false    
        }
        
    }

    
    [void] deactivate(){
        $this.state = 3
        $this.save()
    }

    
    [void] activate(){
       
        $this.state = 1
        $this.save()
    }

    [decimal]Calculate_yv(){
        return ($this.liquidity * ([math]::Sqrt($this.pa)))
    }

    [decimal]Calculate_xv(){
        return ($this.liquidity / ([math]::Sqrt($this.pb)))
    }

    [void]save(){

        $parameters = @{
            token_y_id = ($this.token_y_id)
            fingerprint = ($this.fingerprint)
            token_x = ($this.token_x)
            token_y = ($this.token_y)
            starting_x_amount = ($this.starting_x_amount)
            starting_y_amount = ($this.starting_y_amount)
            x_is_spread_token = ($this.x_is_spread_token)
            spread_percentage = ($this.spread_percentage)
            x_is_default = ($this.x_is_default)
            invert_price = ($this.invert_price)
            state = ($this.state)
            pa = ($this.pa)
            pb = ($this.pb)
            xv = ($this.xv)
            xr = ($this.xr)
            yv = ($this.yv)
            yr = ($this.yr)
            liquidity = ($this.liquidity)
            liquidity_squared = ($this.liquidity_squared)
            pair_id = ($this.pair_id)
            created_at = ($this.created_at)
            updated_at = (Get-Date)
        }

        if($this.id){
            $parameters.id = ($this.id)
        }

        $new_query = @"
        INSERT INTO bots (
            fingerprint, 
            token_x, 
            token_y, 
            token_y_id,
            starting_x_amount, 
            starting_y_amount, 
            spread_percentage, 
            state, 
            pa, 
            pb, 
            xv, 
            xr, 
            yv, 
            yr, 
            x_is_default,
            x_is_spread_token,
            invert_price,
            liquidity_squared, 
            liquidity, 
            pair_id, 
            created_at,
            updated_at) VALUES (@fingerprint, @token_x, @token_y, @token_y_id, @starting_x_amount, @starting_y_amount,
            @spread_percentage, @state, @pa, @pb, @xv, @xr, @yv, @yr, @x_is_default, @x_is_spread_token, @invert_price, @liquidity_squared,
            @liquidity, @pair_id, @created_at, @updated_at);
"@
        $update_query = @"
        UPDATE bots SET
            fingerprint = @fingerprint,
            token_x = @token_x,
            token_y = @token_y,
            token_y_id = @token_y_id,
            starting_x_amount = @starting_x_amount,
            starting_y_amount = @starting_y_amount,
            x_is_spread_token = @x_is_spread_token,
            spread_percentage = @spread_percentage,
            x_is_default = @x_is_default,
            invert_price = @invert_price,
            state = @state,
            pa = @pa,
            pb = @pb,
            xv = @xv,
            xr = @xr,
            yv = @yv,
            yr = @yr,
            liquidity_squared = @liquidity_squared,
            liquidity = @liquidity,
            pair_id = @pair_id,
            created_at = @created_at,
            updated_at = @updated_at
        WHERE id = @id;
"@

        if($this.id -gt 0){
            Invoke-SqliteQuery -DataSource (Get-TTDatabase) -Query $update_query -SqlParameters $parameters
        } else {
            Invoke-SqliteQuery -DataSource (Get-TTDatabase) -Query $new_query -SqlParameters $parameters

            # Retrieve the generated id for the first save and hydrate the current instance.
            $id_query = @"
            SELECT id
            FROM bots
            WHERE fingerprint = @fingerprint
                AND pair_id = @pair_id
                AND created_at = @created_at
            ORDER BY id DESC
            LIMIT 1;
"@
            $id_result = Invoke-SqliteQuery -DataSource (Get-TTDatabase) -Query $id_query -SqlParameters @{
                fingerprint = $this.fingerprint
                pair_id = $this.pair_id
                created_at = $this.created_at
            }

            if($id_result){
                $row = if($id_result -is [System.Array]) { $id_result[0] } else { $id_result }
                if($row.id){
                    $this.id = [string]$row.id
                }
            }
        }
        
    }


    [void]Starting_Token_Amount($amount){
        if($this.xv -or $this.yv -or $this.xr -or $this.yr -or $this.liquidity -or $this.liquidity_squared){
            throw "Starting_Token_Amount can only be called once per instance."
        }
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

    [decimal]Get_Price(){
        if($this.invert_price){
            $price = ($this.xv + $this.xr) / ($this.yv + $this.yr)
        } else {
            $price = ($this.yv + $this.yr) / ($this.xv + $this.xr)
        }
        return [math]::Round($price,3)
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
            $fee_token = $this.token_x
            $dy = $newyr - $_yr
            $_fee = [math]::Abs([math]::Round($amount * ($this.spread_percentage / 2),12))
            if($amount -lt 0){
                $dx = $amount + $_fee
            } else {
                $dx = $amount + $_fee
            }
        } else {
            $fee_token = $this.token_y
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

}
