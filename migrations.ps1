$bots_query = @"
CREATE TABLE bots (
    id INTEGER PRIMARY KEY,
    wallet_fingerprint NUMERIC,
    name TEXT,
    token_x TEXT,
    token_y TEXT,
    starting_x NUMERIC,
    starting_y NUMERIC,
    trading_premium NUMBERIC,
    pa NUMERIC,
    pb NUMERIC,
    xv NUMERIC,
    xr NUMERIC,
    yv NUMERIC,
    yr NUMERIC,
    liquidity_squared NUMERIC,
    liquidity NUMERIC,
    pair_id TEXT
);
"@

$trades_query = @"
CREATE TABLE trades (
    id INTEGER PRIMARY KEY,
    bot_id INTEGER
    offer_id TEXT,
    token_x NUMERIC,
    token_y NUMERIC,
    profit_x NUMERIC,
    profit_y NUMERIC,
    xr NUMERIC,
    xv NUMERIC,
    yr NUMERIC,
    yv NUMERIC,
    status TEXT
);
"@