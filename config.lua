Config = {}

-- =========================
-- Staff Access (map to YOUR job names)
-- =========================
Config.StaffJobs = {
    ['supermarket'] = { 'grocer' },
    ['mechanic']    = { 'mechshop' },
    ['kfc']         = { 'kfcshop' },
    ['phonemart']   = { 'phonestore' },
    -- add more job -> {shop_ids}
}

-- =========================
-- Shops (what appears in the /afterpay dropdown)
-- =========================
Config.Shops = {
    { id = 'grocer',      label = 'Grocery Mart' },
    { id = 'electronics', label = 'Electronics Hub' },
    { id = 'mechshop',    label = 'Mechanic Parts' },
    { id = 'kfcshop',     label = 'KFC Restaurant' },
    { id = 'phonestore',  label = 'Phone & Electronics Store' },
    { id = 'fuel',        label = 'Fuel' },
}

-- =========================
-- Plans
-- =========================
Config.Plans = {
    { id = '4x_weekly',    label = '4 payments', parts = 4, days_between = 7,  first_due_today = true },
    { id = '4x_fortnight', label = '4 payments', parts = 4, days_between = 14, first_due_today = true },
}

-- =========================
-- Anchored Billing Schedule (payments on certain days)
-- =========================
Config.Billing = {
    mode = 'MONTH_DAYS',                  -- 'WEEKDAY' or 'MONTH_DAYS'
    weekday = 4,                          -- if WEEKDAY: 1=Sun..7=Sat (4=Wed)
    month_days = { 1, 15 },               -- if MONTH_DAYS
    charge_time = { hour = 9, min = 0 },  -- server time
    first_at_checkout = false             -- true = charge first now; false = next anchor
}

-- =========================
-- Fuel Afterpay (x-fuel integration) â€” optional
-- =========================
Config.Fuel = {
    Enabled = true,
    DefaultPlanId = '4x_weekly',   -- must exist in Config.Plans
    MinTotal = 50,
    MaxTotal = 10000,
    RequireFirstAtCheckout = true, -- require first installment now
    ShopId = 'fuel',
    ItemLabel = 'Fuel Purchase'
}

-- =========================
-- Merchant (player-owned business) payouts
-- =========================
-- Map shop_id -> job name to receive payouts
Config.ShopBusinesses = {
    grocer      = 'supermarket',
    electronics = 'electronics',
    mechshop    = 'mechanic',
    kfcshop     = 'kfc',
    phonestore  = 'phonemart',
    fuel        = 'fuel'
}

Config.Merchant = {
    Enabled = true,
    PayoutMode = 'PER_INSTALLMENT',   -- 'UPFRONT' or 'PER_INSTALLMENT'
    FeePercent = 6.0,                 -- fee % charged to the merchant
    UseQBManagement = true,           -- uses qb-management: AddMoney(job, amount)
    BusinessAccount = 'bank'          -- fallback if UseQBManagement=false
}

-- =========================
-- Offline Charging & Late Fee
-- =========================
Config.OfflineCharging = {
    Enabled = true,
    Mode = 'QB_PLAYERS',           -- 'QB_PLAYERS' or 'QB_BANKING' (adjust SQL in server.lua)
    Account = 'bank',
    AttemptIntervalMinutes = 10
}

Config.LateFeePolicy = {
    type = 'fixed',    -- 'fixed' or 'percent'
    amount = 100,      -- if fixed
    percent = 10,      -- if percent
    min = 50,
    cap = 500
}

-- =========================
-- Payments & General
-- =========================
Config.Accounts = { 'bank' }       -- order of accounts to attempt
Config.GiveItemsOnCheckout = true
Config.Debug = false

-- Image tip: image_url should be "nui://qb-inventory/html/images/<file>.png"
