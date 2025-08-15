Config = {}

-- =========================
-- Staff Access (map to YOUR job names)
-- =========================
-- The job on the left controls which shop IDs (right) they can manage with /staffafterpay
Config.StaffJobs = {
    ['supermarket'] = { 'grocer' },            -- change to your grocery job name
    ['mechanic']    = { 'mechshop' },          -- change to your mechanic job name
    ['kfc']         = { 'kfcshop' },           -- change to your KFC job name
    ['phonemart']   = { 'phonestore' },        -- change to your phone store job name
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
    -- Add/remove shops as you like
}

-- =========================
-- Plans (how many payments)
-- =========================
-- days_between is ignored when Billing anchors are enabled; parts is still used.
Config.Plans = {
    { id = '4x_weekly',    label = '4 payments', parts = 4, days_between = 7,  first_due_today = true },
    { id = '4x_fortnight', label = '4 payments', parts = 4, days_between = 14, first_due_today = true },
}

-- =========================
-- Anchored Billing Schedule (payments on certain days)
-- =========================
-- mode = 'WEEKDAY' (1=Sun..7=Sat)  OR  'MONTH_DAYS' (fixed calendar dates)
Config.Billing = {
    mode = 'MONTH_DAYS',         -- choose 'WEEKDAY' or 'MONTH_DAYS'
    weekday = 4,                 -- only used if mode='WEEKDAY' (4 = Wednesday)
    month_days = { 1, 15 },      -- only used if mode='MONTH_DAYS'
    charge_time = { hour = 9, min = 0 },  -- when to run (server time)
    first_at_checkout = false    -- false = first payment waits until next anchor; true = take first immediately
}

-- =========================
-- Fuel Afterpay (x-fuel integration) — optional
-- =========================
-- Fuel orders follow the same anchored billing above.
Config.Fuel = {
    Enabled = true,
    DefaultPlanId = '4x_weekly',   -- must match a plan in Config.Plans
    MinTotal = 50,                 -- set nil to disable minimum
    MaxTotal = 10000,              -- safety cap
    RequireFirstAtCheckout = true, -- require first installment now for fuel
    ShopId = 'fuel',               -- appears in order history
    ItemLabel = 'Fuel Purchase'    -- line item label in /afterpay
}

-- =========================
-- Offline Charging (attempts charges even when player is offline)
-- =========================
-- Mode:
--   'QB_PLAYERS'  -> uses stock QBCore `players.money` JSON
--   'QB_BANKING'  -> adjust queries in server.lua to match your banking table
Config.OfflineCharging = {
    Enabled = true,
    Mode = 'QB_PLAYERS',           -- 'QB_PLAYERS' or 'QB_BANKING'
    Account = 'bank',              -- which account to charge
    AttemptIntervalMinutes = 10    -- background loop cadence
}

-- =========================
-- Late Fee Policy (applied when a due charge fails)
-- =========================
-- 'fixed'   -> flat amount
-- 'percent' -> % of installment amount (with optional min/cap)
Config.LateFeePolicy = {
    type = 'fixed',          -- 'fixed' or 'percent'
    amount = 100,            -- used if type='fixed'
    percent = 10,            -- used if type='percent'
    min = 50,                -- floor for percent fee
    cap = 500                -- cap for percent fee
}

-- =========================
-- Payments & General
-- =========================
-- Remove from the first account in this list that has sufficient funds
Config.Accounts = { 'bank' }

-- If you add late fees later, you can implement logic in server.lua auto-charge loop
Config.LateFee = 0  -- (legacy; unused when LateFeePolicy is set)

-- Give items immediately on checkout (for shops that sell inventory items)
Config.GiveItemsOnCheckout = true

-- Debug prints
Config.Debug = false

-- =========================
-- Image Tips
-- =========================
-- For product images from qb-inventory, set image_url (via /staffafterpay or SQL) to:
--   nui://qb-inventory/html/images/<filename>.png
-- Example: nui://qb-inventory/html/images/kfc-zingerburger.png
