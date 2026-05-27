$bots_query = @"
CREATE TABLE bots (
    id INTEGER PRIMARY KEY,
    fingerprint NUMERIC,
    token_x TEXT,
    token_y TEXT,
    token_y_id TEXT,
    starting_x_amount NUMERIC,
    starting_y_amount NUMERIC,
    x_is_spread_token NUMERIC,
    spread_percentage NUMBERIC,
    x_is_default INTEGER,
    invert_price INTEGER,
    state INTEGER,
    pa NUMERIC,
    pb NUMERIC,
    xv NUMERIC,
    xr NUMERIC,
    yv NUMERIC,
    yr NUMERIC,
    liquidity_squared NUMERIC,
    liquidity NUMERIC,
    pair_id TEXT,
    created_at TEXT,
    updated_at TEXT
);
"@

$bot_state = @"
    CREATE TABLE states (
        id INTEGER PRIMARY KEY,
        name TEXT
    );
    INSERT INTO states (name) VALUES
    ('ready'),('offer_pending'),('disabled');
"@

$trades_query = @"
CREATE TABLE trades (
    id INTEGER PRIMARY KEY,
    bot_id INTEGER,
    offer_id TEXT,
    profit_x NUMERIC,
    profit_y NUMERIC,
    dx NUMERIC,
    dy NUMERIC,
    status TEXT,
    created_at TEXT,
    updated_at TEXT
);
"@

$event_query = @"
    CREATE TABLE events (
        id INTEGER PRIMARY KEY,
        bot_id INTEGER,
        event,
        event_status,
        created_at
    );
"@



function Invoke-MigrateSql{
    Invoke-SqliteQuery -DataSource (Get-TTDatabase) -Query $bots_query
    Invoke-SqliteQuery -DataSource (Get-TTDatabase) -Query $trades_query
    Invoke-SqliteQuery -DataSource (Get-TTDatabase) -Query $event_query
    Invoke-SqliteQuery -DataSource (Get-TTDatabase) -Query $bot_state
}

function Invoke-MigrateFresh {
    Remove-Item -Path (Get-TTDatabase)
    Invoke-MigrateSql
}