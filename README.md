# qb-afterpay — IRL‑style Afterpay (BNPL) for QBCore

## Overview
`qb-afterpay` lets players buy items/services in installments, just like Afterpay:
- `/afterpay` — player tablet to browse shops, add to cart, and checkout.
- `/staffafterpay` — staff tablet to add/update/remove shop items & prices.
- Anchored billing: charge on **specific days** (e.g., 1st & 15th, or every Wednesday).
- Optional **x-fuel** integration so players can Afterpay their fuel.

Requires: `qb-core`, `oxmysql`.

---

## Install
1. Drop the folder into `resources/[qb]/qb-afterpay`.
2. Run the SQL in `afterpay.sql` (creates `afterpay_*` tables).
3. Add to `server.cfg`:
   ```
   ensure qb-afterpay
   ```
4. Restart the server.

---

## Config (qb-afterpay/config.lua)
### Shops & Staff
Add shops you want to appear in the `/afterpay` dropdown, and map jobs to which shops they can manage with `/staffafterpay`:
```lua
Config.StaffJobs = {
    ['supermarket'] = { 'grocer' },
    ['mechanic']    = { 'mechshop' },
    ['kfc']         = { 'kfcshop' },        -- change to your real job name
    ['phonemart']   = { 'phonestore' },     -- change to your real job name
}

Config.Shops = {
    { id = 'grocer',      label = 'Grocery Mart' },
    { id = 'electronics', label = 'Electronics Hub' },
    { id = 'mechshop',    label = 'Mechanic Parts' },
    { id = 'kfcshop',     label = 'KFC Restaurant' },
    { id = 'phonestore',  label = 'Phone & Electronics Store' },
}
```

### Plans
```lua
Config.Plans = {
    { id = '4x_weekly',    label = '4 payments', parts = 4, days_between = 7,  first_due_today = true },
    { id = '4x_fortnight', label = '4 payments', parts = 4, days_between = 14, first_due_today = true },
}
```
> `days_between` is ignored when **Billing** (anchors) is enabled; only `parts` matters.

### Anchored Billing (payments on certain days)
Charge installments on fixed anchors instead of “every N days”.
```lua
Config.Billing = {
    mode = 'MONTH_DAYS',              -- 'WEEKDAY' or 'MONTH_DAYS'
    weekday = 4,                      -- used if mode='WEEKDAY' (1=Sun..7=Sat; 4=Wed)
    month_days = { 1, 15 },           -- used if mode='MONTH_DAYS'
    charge_time = { hour = 9, min = 0 },
    first_at_checkout = false         -- true = take 1st payment immediately; false = next anchor
}
```

### Fuel (x-fuel) — optional
```lua
Config.Fuel = {
    Enabled = true,
    DefaultPlanId = '4x_weekly',
    MinTotal = 50,
    MaxTotal = 10000,
    RequireFirstAtCheckout = true,
    ShopId = 'fuel',
    ItemLabel = 'Fuel Purchase'
}
```
Server has a callback `qb-afterpay:fuel:checkout` to approve/deny Afterpay for fuel and create the order + installments.

**x-fuel integration (server):**
```lua
QBCore.Functions.CreateCallback('xfuel:pay', function(src, cb, data)
    QBCore.Functions.TriggerCallback('qb-afterpay:fuel:checkout', src, function(ok, msg)
        if ok then
            cb(true)  -- continue refuel; do NOT remove money here
        else
            if msg then TriggerClientEvent('QBCore:Notify', src, msg, 'error') end
            cb(false)
        end
    end, {
        liters = data.liters,
        price_per_liter = data.price_per_liter,
        total = data.total,
        plate = data.plate,
        station_id = data.station_id,
        plan_id = '4x_weekly' -- optional
    })
end)
```

---

## Adding Items
### In‑game (recommended)
1. Be on a job that’s permitted for that shop (`Config.StaffJobs`).
2. `/staffafterpay` → choose shop → enter **name** (must match `qb-core/shared/items.lua`), **label**, **price**, **image_url** → **Save**.

### SQL
```sql
INSERT INTO afterpay_catalog (shop_id, name, label, price, image_url)
VALUES ('kfcshop', 'kfc-zingerburger', 'ZingerBurger', 120, 'nui://qb-inventory/html/images/kfc-zingerburger.png')
ON DUPLICATE KEY UPDATE label=VALUES(label), price=VALUES(price), image_url=VALUES(image_url);
```

### Images
For images stored in `qb-inventory`, set:
```
nui://qb-inventory/html/images/<filename>.png
```
**Do not** use OS paths like `/resources/[qb]/...` — NUI won’t load them.

---

## Commands
- `/afterpay` — open the player tablet.
- `/staffafterpay` — staff tablet (job-locked).

---

## Tables
- `afterpay_catalog` — products per shop.
- `afterpay_orders` — header/summary of each order.
- `afterpay_order_items` — line items in an order.
- `afterpay_installments` — payment schedule & status.

---

## Tips
- If no products show: ensure the shop has items in `afterpay_catalog` and that your **Shop ID** exists in `Config.Shops`.
- If images don’t show: use the `nui://qb-inventory/...` path and confirm the PNG file exists.
- The auto-charge loop runs every 5 minutes and charges **online** players. (Ask if you want offline charging.)

Enjoy!
