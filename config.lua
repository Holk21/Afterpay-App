Config = {}

-- ============ Staff Access ============
Config.StaffJobs = {
    ['mechanic'] = {'mechshop'},
    ['supermarket'] = {'grocer'},
    ['kfc'] = {'kfcshop'}, ['phonemart'] = {'phonestore'}
}

-- ============ Shops ============
Config.Shops = {
    { id = 'grocer', label = 'Grocery Mart' },
    { id = 'electronics', label = 'Electronics Hub' },
    { id = 'mechshop', label = 'Mechanic Parts' },
    { id = 'kfcshop', label = 'KFC Restaurant' },
    { id = 'phonestore', label = 'Phone & Electronics Store' },
}

-- ============ Plans (number of parts) ============
Config.Plans = {
    { id = '4x_weekly', label = '4 payments (anchored)', parts = 4, days_between = 7, first_due_today = true },
    { id = '4x_fortnight', label = '4 payments (anchored)', parts = 4, days_between = 14, first_due_today = true }
}
-- Note: days_between is ignored when Billing anchors are enabled; we keep it to remain backward compatible.

-- ============ Anchored Billing Schedule ============
-- Choose WHEN installments are due. Set mode & options below.
-- Modes:
--  'WEEKDAY'    -> charges happen on a fixed weekday (1=Sun..7=Sat) at charge_time
--  'MONTH_DAYS' -> charges happen on fixed calendar days each month (e.g., 1st & 15th) at charge_time
Config.Billing = {
    mode = 'MONTH_DAYS',        -- 'WEEKDAY' or 'MONTH_DAYS'
    weekday = 4,                -- only used if mode='WEEKDAY' (4=Wednesday)
    month_days = {1, 15},       -- only used if mode='MONTH_DAYS'
    charge_time = { hour = 9, min = 0 },
    first_at_checkout = true   -- false = first payment scheduled on next anchor; true = taken at checkout
}

-- ============ Payments & Items ============
Config.ChargeFirstInstallment = true     -- kept for back-compat; superseded by Billing.first_at_checkout when Billing enabled
Config.Accounts = { 'bank' }             -- remove from first matching account in this list
Config.LateFee = 0
Config.GiveItemsOnCheckout = true
Config.Debug = false
