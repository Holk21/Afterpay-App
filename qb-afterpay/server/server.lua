local QBCore = exports['qb-core']:GetCoreObject()

local function debug(msg)
    if Config.Debug then print(('[qb-afterpay] %s'):format(msg)) end
end

-- ===== Access helpers =====
local function PlayerHasShopAccess(src, shopId)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return false end
    local job = Player.PlayerData.job and Player.PlayerData.job.name or nil
    if not job then return false end
    local allowed = Config.StaffJobs[job]
    if not allowed then return false end
    for _,id in ipairs(allowed) do
        if id == shopId then return true end
    end
    return false
end

-- ===== Anchored billing helpers =====
local function atTime(y, m, d, hour, min)
    return os.time({year = y, month = m, day = d, hour = hour or 9, min = min or 0, sec = 0})
end

local function nextWeekdayAnchor(fromTs)
    local t = os.date('*t', fromTs)
    local target = (Config.Billing and Config.Billing.weekday) or 2
    local h = Config.Billing and Config.Billing.charge_time and Config.Billing.charge_time.hour or 9
    local m = Config.Billing and Config.Billing.charge_time and Config.Billing.charge_time.min or 0
    local delta = (target - t.wday) % 7
    local candidate = atTime(t.year, t.month, t.day + delta, h, m)
    if candidate <= fromTs then candidate = atTime(t.year, t.month, t.day + delta + 7, h, m) end
    return candidate
end

local function nextMonthDayAnchor(fromTs)
    local t = os.date('*t', fromTs)
    local days = (Config.Billing and Config.Billing.month_days) or {1, 15}
    table.sort(days)
    local h = Config.Billing and Config.Billing.charge_time and Config.Billing.charge_time.hour or 9
    local m = Config.Billing and Config.Billing.charge_time and Config.Billing.charge_time.min or 0
    for _, d in ipairs(days) do
        local ok, candidate = pcall(function() return atTime(t.year, t.month, d, h, m) end)
        if ok and candidate and candidate > fromTs then return candidate end
    end
    local year, month = t.year, t.month + 1
    if month == 13 then month = 1; year = year + 1 end
    return atTime(year, month, days[1], h, m)
end

local function nextAnchor(fromTs)
    if not Config.Billing or not Config.Billing.mode then return fromTs end
    if Config.Billing.mode == 'WEEKDAY' then return nextWeekdayAnchor(fromTs)
    elseif Config.Billing.mode == 'MONTH_DAYS' then return nextMonthDayAnchor(fromTs) end
    return fromTs
end

-- ===== NUI callbacks =====
QBCore.Functions.CreateCallback('qb-afterpay:server:getShops', function(_, cb)
    cb(Config.Shops)
end)

QBCore.Functions.CreateCallback('qb-afterpay:server:getCatalog', function(_, cb, shopId)
    MySQL.query('SELECT name, label, price, image_url FROM afterpay_catalog WHERE shop_id = ? ORDER BY label ASC', {shopId}, function(rows)
        cb(rows or {})
    end)
end)

QBCore.Functions.CreateCallback('qb-afterpay:server:getOrders', function(src, cb)
    local xPlayer = QBCore.Functions.GetPlayer(src)
    if not xPlayer then cb({}); return end
    MySQL.query('SELECT o.id, o.shop_id, o.plan_id, o.total, o.status, o.created_at FROM afterpay_orders o WHERE o.citizenid = ? ORDER BY o.created_at DESC', {
        xPlayer.PlayerData.citizenid
    }, function(orders)
        if not orders or #orders == 0 then cb({}); return end
        local result = {}
        for _,o in ipairs(orders) do
            local installments = MySQL.query.await('SELECT id, due_at, amount, paid, paid_at FROM afterpay_installments WHERE order_id = ? ORDER BY due_at ASC', {o.id}) or {}
            o.installments = installments
            table.insert(result, o)
        end
        cb(result)
    end)
end)

-- ===== Payment helpers =====
local function TryCharge(src, Player, amount)
    for _,account in ipairs(Config.Accounts) do
        if Player.Functions.RemoveMoney(account, amount, 'afterpay-installment') then
            TriggerClientEvent('qb-afterpay:client:notify', src, ('Charged $%d from %s.'):format(amount, account), 'success')
            return true
        end
    end
    return false
end

-- ===== Merchant helpers =====
local function MerchantForShop(shop_id)
    if not Config.Merchant or not Config.Merchant.Enabled then return nil end
    return (Config.ShopBusinesses or {})[shop_id]
end

local function RecordMerchantPayout(shop_id, order_id, installment_id, gross, fee, net)
    MySQL.insert.await(
        'INSERT INTO afterpay_merchant_payouts (shop_id, order_id, installment_id, gross, fee, net) VALUES (?, ?, ?, ?, ?, ?)',
        { shop_id, order_id, installment_id, gross, fee, net }
    )
end

local function PayBusiness(shop_id, amount, order_id, installment_id)
    local job = MerchantForShop(shop_id)
    if not job or amount <= 0 then return end

    local fee = math.floor((amount * (Config.Merchant.FeePercent or 0)) / 100 + 0.5)
    local net = amount - fee
    if net < 0 then net = 0 end

    if Config.Merchant.UseQBManagement and GetResourceState('qb-management') == 'started' then
        exports['qb-management']:AddMoney(job, net)
    else
        for _, src in pairs(QBCore.Functions.GetPlayers()) do
            local P = QBCore.Functions.GetPlayer(src)
            if P and P.PlayerData.job and P.PlayerData.job.name == job then
                P.Functions.AddMoney('bank', net, 'afterpay-merchant-payout')
                break
            end
        end
    end

    RecordMerchantPayout(shop_id, order_id, installment_id, amount, fee, net)
end

-- ===== Checkout (player self-checkout) =====
RegisterNetEvent('qb-afterpay:server:checkout', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local shopId = data.shop_id
    local items = data.items or {}
    local planId = data.plan_id

    if not shopId or not planId or #items == 0 then
        TriggerClientEvent('qb-afterpay:client:notify', src, 'Invalid checkout data', 'error'); return
    end

    local plan; for _,p in ipairs(Config.Plans) do if p.id == planId then plan = p break end end
    if not plan then TriggerClientEvent('qb-afterpay:client:notify', src, 'Unknown plan', 'error'); return end

    local total = 0
    for _,it in ipairs(items) do total = total + (tonumber(it.price) or 0) * (tonumber(it.qty) or 1) end
    total = math.floor(total + 0.5)

    local orderId = MySQL.insert.await('INSERT INTO afterpay_orders (citizenid, shop_id, plan_id, total, status) VALUES (?, ?, ?, ?, ?)', {
        Player.PlayerData.citizenid, shopId, planId, total, 'active'
    })
    if not orderId then TriggerClientEvent('qb-afterpay:client:notify', src, 'Failed to create order', 'error'); return end

    for _,it in ipairs(items) do
        local qty = tonumber(it.qty) or 1
        MySQL.insert.await('INSERT INTO afterpay_order_items (order_id, item_name, label, price, qty) VALUES (?, ?, ?, ?, ?)', {
            orderId, it.name, it.label, it.price, qty
        })
    end

    local per = math.floor((total / plan.parts) + 0.5)
    local remaining = total
    local now = os.time()
    local dueList = {}
    local firstDue = (Config.Billing and Config.Billing.first_at_checkout == false) and nextAnchor(now) or now

    for idx = 1, plan.parts do
        local amount = (idx == plan.parts) and remaining or per
        remaining = remaining - amount
        local dueAt = (idx == 1) and firstDue or nextAnchor((dueList[#dueList] or firstDue) + 60)
        MySQL.insert.await('INSERT INTO afterpay_installments (order_id, due_at, amount, paid) VALUES (?, FROM_UNIXTIME(?), ?, 0)', {
            orderId, dueAt, amount
        })
        table.insert(dueList, dueAt)
    end

    if not (Config.Billing and Config.Billing.first_at_checkout == false) then
        local firstRow = MySQL.single.await('SELECT * FROM afterpay_installments WHERE order_id = ? ORDER BY due_at ASC LIMIT 1', {orderId})
        if firstRow then
            local ok = TryCharge(src, Player, firstRow.amount)
            if not ok then
                MySQL.update.await('UPDATE afterpay_orders SET status = ? WHERE id = ?', {'cancelled', orderId})
                MySQL.update.await('DELETE FROM afterpay_installments WHERE order_id = ?', {orderId})
                MySQL.update.await('DELETE FROM afterpay_order_items WHERE order_id = ?', {orderId})
                TriggerClientEvent('qb-afterpay:client:notify', src, 'Payment declined. Order cancelled.', 'error'); return
            end
            MySQL.update.await('UPDATE afterpay_installments SET paid = 1, paid_at = NOW() WHERE id = ?', {firstRow.id})
            -- PER_INSTALLMENT merchant payout for first part
            if Config.Merchant and Config.Merchant.Enabled and Config.Merchant.PayoutMode == 'PER_INSTALLMENT' then
                PayBusiness(shopId, firstRow.amount, orderId, firstRow.id)
            end
        end
    end

    if Config.GiveItemsOnCheckout then
        for _,it in ipairs(items) do
            local qty = tonumber(it.qty) or 1
            Player.Functions.AddItem(it.name, qty)
            TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[it.name], "add", qty)
        end
    end

    -- UPFRONT payout (business gets net immediately for full total)
    if Config.Merchant and Config.Merchant.Enabled and Config.Merchant.PayoutMode == 'UPFRONT' then
        PayBusiness(shopId, total, orderId, nil)
    end

    TriggerClientEvent('qb-afterpay:client:notify', src, ('Afterpay set up! Total $%d over %d payments.'):format(total, plan.parts), 'success')
end)

-- ===== Manual pay (from UI) =====
RegisterNetEvent('qb-afterpay:server:payInstallment', function(installmentId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local row = MySQL.single.await('SELECT i.*, o.status FROM afterpay_installments i JOIN afterpay_orders o ON o.id = i.order_id WHERE i.id = ?', {installmentId})
    if not row then TriggerClientEvent('qb-afterpay:client:notify', src, 'Installment not found', 'error'); return end
    if row.paid == 1 then TriggerClientEvent('qb-afterpay:client:notify', src, 'Already paid', 'primary'); return end

    local ok = TryCharge(src, Player, row.amount)
    if not ok then TriggerClientEvent('qb-afterpay:client:notify', src, 'Insufficient funds', 'error'); return end

    MySQL.update.await('UPDATE afterpay_installments SET paid = 1, paid_at = NOW() WHERE id = ?', {installmentId})

    -- PER_INSTALLMENT merchant payout
    if Config.Merchant and Config.Merchant.Enabled and Config.Merchant.PayoutMode == 'PER_INSTALLMENT' then
        local inst = MySQL.single.await('SELECT i.id, i.amount, i.order_id, o.shop_id FROM afterpay_installments i JOIN afterpay_orders o ON o.id = i.order_id WHERE i.id = ?', {installmentId})
        if inst and MerchantForShop(inst.shop_id) then
            PayBusiness(inst.shop_id, inst.amount, inst.order_id, inst.id)
        end
    end

    local remaining = MySQL.scalar.await('SELECT COUNT(*) FROM afterpay_installments WHERE order_id = ? AND paid = 0', {row.order_id})
    if remaining == 0 then
        MySQL.update.await('UPDATE afterpay_orders SET status = ? WHERE id = ?', {'completed', row.order_id})
        TriggerClientEvent('qb-afterpay:client:notify', src, 'Order fully paid. Thank you!', 'success')
    else
        TriggerClientEvent('qb-afterpay:client:notify', src, 'Installment paid.', 'success')
    end
end)

-- ===== Staff management =====
RegisterNetEvent('qb-afterpay:server:staff:addItem', function(data)
    local src = source
    if not data or not data.shop_id then return end
    if not PlayerHasShopAccess(src, data.shop_id) then
        TriggerClientEvent('qb-afterpay:client:notify', src, 'No access to this shop', 'error'); return
    end
    MySQL.insert.await('INSERT INTO afterpay_catalog (shop_id, name, label, price, image_url) VALUES (?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE label=VALUES(label), price=VALUES(price), image_url=VALUES(image_url)', {
        data.shop_id, data.name, data.label, tonumber(data.price) or 0, data.image_url or nil
    })
    TriggerClientEvent('qb-afterpay:client:notify', src, 'Item saved', 'success')
end)

RegisterNetEvent('qb-afterpay:server:staff:updatePrice', function(data)
    local src = source
    if not PlayerHasShopAccess(src, data.shop_id) then
        TriggerClientEvent('qb-afterpay:client:notify', src, 'No access to this shop', 'error'); return
    end
    MySQL.update.await('UPDATE afterpay_catalog SET price = ? WHERE shop_id = ? AND name = ?', {
        tonumber(data.price) or 0, data.shop_id, data.name
    })
    TriggerClientEvent('qb-afterpay:client:notify', src, 'Price updated', 'success')
end)

RegisterNetEvent('qb-afterpay:server:staff:removeItem', function(data)
    local src = source
    if not PlayerHasShopAccess(src, data.shop_id) then
        TriggerClientEvent('qb-afterpay:client:notify', src, 'No access to this shop', 'error'); return
    end
    MySQL.update.await('DELETE FROM afterpay_catalog WHERE shop_id = ? AND name = ?', {
        data.shop_id, data.name
    })
    TriggerClientEvent('qb-afterpay:client:notify', src, 'Item removed', 'success')
end)

-- ===== Merchant: staff creates order for a customer =====
RegisterNetEvent('qb-afterpay:server:merchant:createOrder', function(data)
    local src = source
    local Staff = QBCore.Functions.GetPlayer(src)
    if not Staff then return end

    local shopId = data.shop_id
    if not PlayerHasShopAccess(src, shopId) then
        TriggerClientEvent('qb-afterpay:client:notify', src, 'No access to this shop', 'error'); return
    end

    local targetSrc = tonumber(data.target_src)
    local Customer = targetSrc and QBCore.Functions.GetPlayer(targetSrc) or nil
    if not Customer then
        TriggerClientEvent('qb-afterpay:client:notify', src, 'Customer not found/nearby', 'error'); return
    end

    local planId = data.plan_id
    local plan; for _,p in ipairs(Config.Plans) do if p.id == planId then plan = p break end end
    if not plan then TriggerClientEvent('qb-afterpay:client:notify', src, 'Unknown plan', 'error'); return end

    local items = data.items or {}
    if #items == 0 then TriggerClientEvent('qb-afterpay:client:notify', src, 'No items added', 'error'); return end

    local total = 0
    for _,it in ipairs(items) do total = total + (tonumber(it.price) or 0) * (tonumber(it.qty) or 1) end
    total = math.floor(total + 0.5)

    local orderId = MySQL.insert.await('INSERT INTO afterpay_orders (citizenid, shop_id, plan_id, total, status) VALUES (?, ?, ?, ?, ?)', {
        Customer.PlayerData.citizenid, shopId, planId, total, 'active'
    })
    if not orderId then TriggerClientEvent('qb-afterpay:client:notify', src, 'Order create failed', 'error'); return end

    for _,it in ipairs(items) do
        local qty = tonumber(it.qty) or 1
        MySQL.insert.await('INSERT INTO afterpay_order_items (order_id, item_name, label, price, qty) VALUES (?, ?, ?, ?, ?)', {
            orderId, it.name or 'custom', it.label or 'Item', tonumber(it.price) or 0, qty
        })
    end

    local per = math.floor((total / plan.parts) + 0.5)
    local remaining = total
    local now = os.time()
    local dueList = {}
    local firstDue = (Config.Billing and Config.Billing.first_at_checkout == false) and nextAnchor(now) or now

    for idx = 1, plan.parts do
        local amount = (idx == plan.parts) and remaining or per
        remaining = remaining - amount
        local dueAt = (idx == 1) and firstDue or nextAnchor((dueList[#dueList] or firstDue) + 60)
        MySQL.insert.await('INSERT INTO afterpay_installments (order_id, due_at, amount, paid) VALUES (?, FROM_UNIXTIME(?), ?, 0)', {
            orderId, dueAt, amount
        })
        table.insert(dueList, dueAt)
    end

    if not (Config.Billing and Config.Billing.first_at_checkout == false) then
        local firstRow = MySQL.single.await('SELECT * FROM afterpay_installments WHERE order_id = ? ORDER BY due_at ASC LIMIT 1', {orderId})
        if firstRow then
            local ok = (function()
                for _,account in ipairs(Config.Accounts) do
                    if Customer.Functions.RemoveMoney(account, firstRow.amount, 'afterpay-first-merchant') then
                        TriggerClientEvent('qb-afterpay:client:notify', targetSrc, ('Charged $%d from %s.'):format(firstRow.amount, account), 'success')
                        return true
                    end
                end
                return false
            end)()
            if not ok then
                MySQL.update.await('UPDATE afterpay_orders SET status = ? WHERE id = ?', {'cancelled', orderId})
                MySQL.update.await('DELETE FROM afterpay_installments WHERE order_id = ?', {orderId})
                MySQL.update.await('DELETE FROM afterpay_order_items WHERE order_id = ?', {orderId})
                TriggerClientEvent('qb-afterpay:client:notify', src, 'Customer payment declined. Order cancelled.', 'error')
                TriggerClientEvent('qb-afterpay:client:notify', targetSrc, 'Payment declined. Order cancelled.', 'error')
                return
            end
            MySQL.update.await('UPDATE afterpay_installments SET paid = 1, paid_at = NOW() WHERE id = ?', {firstRow.id})
            if Config.Merchant and Config.Merchant.Enabled and Config.Merchant.PayoutMode == 'PER_INSTALLMENT' then
                PayBusiness(shopId, firstRow.amount, orderId, firstRow.id)
            end
        end
    end

    if Config.Merchant and Config.Merchant.Enabled and Config.Merchant.PayoutMode == 'UPFRONT' then
        PayBusiness(shopId, total, orderId, nil)
    end

    TriggerClientEvent('qb-afterpay:client:notify', src, ('Created Afterpay order for customer: $%d over %d payments.'):format(total, plan.parts), 'success')
    TriggerClientEvent('qb-afterpay:client:notify', targetSrc, ('Afterpay created: $%d over %d payments.'):format(total, plan.parts), 'success')
end)

-- ===== Fuel Afterpay (x-fuel) =====
QBCore.Functions.CreateCallback('qb-afterpay:fuel:checkout', function(src, cb, data)
    if not (Config.Fuel and Config.Fuel.Enabled) then cb(false, 'Afterpay for fuel is disabled'); return end
    local Player = QBCore.Functions.GetPlayer(src); if not Player then cb(false, 'No player'); return end

    local planId = (data and data.plan_id) or (Config.Fuel.DefaultPlanId)
    local plan; for _,p in ipairs(Config.Plans) do if p.id == planId then plan = p break end end
    if not plan then cb(false, 'Unknown plan'); return end

    local total = tonumber(data and data.total) or 0
    local liters = tonumber(data and data.liters) or 0
    local ppl = tonumber(data and data.price_per_liter) or 0
    if total <= 0 or liters <= 0 or ppl <= 0 then cb(false, 'Invalid fuel data'); return end
    local recomputed = math.floor((liters * ppl) + 0.5)
    if math.abs(recomputed - total) > 2 then cb(false, 'Total mismatch'); return end
    if Config.Fuel.MinTotal and total < Config.Fuel.MinTotal then cb(false, ('Min total is $%d'):format(Config.Fuel.MinTotal)); return end
    if Config.Fuel.MaxTotal and total > Config.Fuel.MaxTotal then cb(false, ('Max total is $%d'):format(Config.Fuel.MaxTotal)); return end

    local orderId = MySQL.insert.await('INSERT INTO afterpay_orders (citizenid, shop_id, plan_id, total, status) VALUES (?, ?, ?, ?, ?)', {
        Player.PlayerData.citizenid, Config.Fuel.ShopId or 'fuel', planId, total, 'active'
    })
    if not orderId then cb(false, 'Order create failed'); return end

    MySQL.insert.await('INSERT INTO afterpay_order_items (order_id, item_name, label, price, qty) VALUES (?, ?, ?, ?, ?)', {
        orderId, 'fuel', Config.Fuel.ItemLabel or 'Fuel Purchase', total, 1
    })

    local parts = plan.parts
    local per = math.floor((total / parts) + 0.5)
    local remaining = total
    local now = os.time()
    local dueList = {}
    local firstAtCheckout = Config.Billing and (Config.Billing.first_at_checkout ~= false)
    if Config.Fuel.RequireFirstAtCheckout then firstAtCheckout = true end
    local firstDue = firstAtCheckout and now or nextAnchor(now)

    for idx = 1, parts do
        local amount = (idx == parts) and remaining or per
        remaining = remaining - amount
        local dueAt = (idx == 1) and firstDue or nextAnchor((dueList[#dueList] or firstDue) + 60)
        MySQL.insert.await('INSERT INTO afterpay_installments (order_id, due_at, amount, paid) VALUES (?, FROM_UNIXTIME(?), ?, 0)', {
            orderId, dueAt, amount
        })
        table.insert(dueList, dueAt)
    end

    if firstAtCheckout then
        local firstRow = MySQL.single.await('SELECT * FROM afterpay_installments WHERE order_id = ? ORDER BY due_at ASC LIMIT 1', {orderId})
        if firstRow then
            local ok = (function()
                for _,account in ipairs(Config.Accounts) do
                    if Player.Functions.RemoveMoney(account, firstRow.amount, 'afterpay-fuel-first') then
                        TriggerClientEvent('qb-afterpay:client:notify', src, ('Charged $%d from %s.'):format(firstRow.amount, account), 'success')
                        return true
                    end
                end
                return false
            end)()
            if not ok then
                MySQL.update.await('UPDATE afterpay_orders SET status = ? WHERE id = ?', {'cancelled', orderId})
                MySQL.update.await('DELETE FROM afterpay_installments WHERE order_id = ?', {orderId})
                MySQL.update.await('DELETE FROM afterpay_order_items WHERE order_id = ?', {orderId})
                cb(false, 'Insufficient funds for first installment'); return
            end
            MySQL.update.await('UPDATE afterpay_installments SET paid = 1, paid_at = NOW() WHERE id = ?', {firstRow.id})
            if Config.Merchant and Config.Merchant.Enabled and Config.Merchant.PayoutMode == 'PER_INSTALLMENT' then
                PayBusiness(Config.Fuel.ShopId or 'fuel', firstRow.amount, orderId, firstRow.id)
            end
        end
    end

    if Config.Merchant and Config.Merchant.Enabled and Config.Merchant.PayoutMode == 'UPFRONT' then
        PayBusiness(Config.Fuel.ShopId or 'fuel', total, orderId, nil)
    end

    TriggerClientEvent('qb-afterpay:client:notify', src, ('Afterpay set up for fuel: $%d over %d payments.'):format(total, parts), 'success')
    cb(true)
end)

-- ===== OFFLINE charging + Late fee =====
local function computeLateFee(amount)
    local p = Config.LateFeePolicy or {}
    if (p.type == 'percent') then
        local fee = math.floor((amount * (p.percent or 0)) / 100 + 0.5)
        if p.min and fee < p.min then fee = p.min end
        if p.cap and fee > p.cap then fee = p.cap end
        return fee
    else
        return tonumber(p.amount or 0) or 0
    end
end

local function OfflineRemoveMoney(citizenid, account, amount)
    local mode = Config.OfflineCharging and Config.OfflineCharging.Mode or 'QB_PLAYERS'
    if mode == 'QB_BANKING' then
        -- Adjust to your banking schema if you use one
        return false
    else
        local row = MySQL.single.await('SELECT money FROM players WHERE citizenid = ? LIMIT 1', { citizenid })
        if not row or not row.money then return false end
        local ok, money = pcall(function() return json.decode(row.money) end)
        if not ok or type(money) ~= 'table' then return false end
        local bal = tonumber(money[account] or 0) or 0
        if bal < amount then return false end
        money[account] = bal - amount
        local newJson = json.encode(money)
        local upd = MySQL.update.await('UPDATE players SET money = ? WHERE citizenid = ?', { newJson, citizenid })
        return upd and upd > 0
    end
end

local function AttemptChargeForInstallment(inst)
    local Player = QBCore.Functions.GetPlayerByCitizenId(inst.citizenid)
    local success = false
    if Player then
        local src = Player.PlayerData.source
        success = TryCharge(src, Player, inst.amount)
    else
        success = OfflineRemoveMoney(inst.citizenid, Config.OfflineCharging.Account or 'bank', inst.amount)
    end

    if success then
        MySQL.update.await('UPDATE afterpay_installments SET paid = 1, paid_at = NOW(), attempts = COALESCE(attempts,0)+1, last_attempt_at = NOW() WHERE id = ?', {inst.id})
        -- PER_INSTALLMENT merchant payout
        if Config.Merchant and Config.Merchant.Enabled and Config.Merchant.PayoutMode == 'PER_INSTALLMENT' then
            local shopId = MySQL.scalar.await('SELECT shop_id FROM afterpay_orders WHERE id = ?', {inst.order_id})
            if shopId and MerchantForShop(shopId) then
                PayBusiness(shopId, inst.amount, inst.order_id, inst.id)
            end
        end
        local remaining = MySQL.scalar.await('SELECT COUNT(*) FROM afterpay_installments WHERE order_id = ? AND paid = 0', {inst.order_id})
        if remaining and tonumber(remaining) == 0 then
            MySQL.update.await('UPDATE afterpay_orders SET status = "completed" WHERE id = ?', {inst.order_id})
        end
        return true
    else
        MySQL.update.await('UPDATE afterpay_installments SET attempts = COALESCE(attempts,0)+1, last_attempt_at = NOW() WHERE id = ?', {inst.id})
        local row = MySQL.single.await('SELECT fee_applied, amount FROM afterpay_installments WHERE id = ?', {inst.id})
        if row and tonumber(row.fee_applied or 0) == 0 then
            local fee = computeLateFee(row.amount or inst.amount)
            if fee and fee > 0 then
                MySQL.update.await('UPDATE afterpay_installments SET amount = amount + ?, fee_applied = 1 WHERE id = ?', { fee, inst.id })
            end
        end
        return false
    end
end

CreateThread(function()
    while true do
        local rows = MySQL.query.await([[
            SELECT i.id, i.amount, i.due_at, i.order_id, o.citizenid
            FROM afterpay_installments i
            JOIN afterpay_orders o ON o.id = i.order_id
            WHERE i.paid = 0 AND i.due_at <= NOW() AND o.status = 'active'
        ]])
        if rows and #rows > 0 then
            for _, inst in ipairs(rows) do
                AttemptChargeForInstallment(inst)
            end
        end
        local mins = (Config.OfflineCharging and Config.OfflineCharging.AttemptIntervalMinutes) or 5
        Wait((mins > 0 and mins or 5) * 60 * 1000)
    end
end)
