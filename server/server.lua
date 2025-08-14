local QBCore = exports['qb-core']:GetCoreObject()

local function debug(msg)
    if Config.Debug then print(('[qb-afterpay] %s'):format(msg)) end
end

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
    local target = (Config.Billing and Config.Billing.weekday) or 2 -- default Monday
    local h = Config.Billing and Config.Billing.charge_time and Config.Billing.charge_time.hour or 9
    local m = Config.Billing and Config.Billing.charge_time and Config.Billing.charge_time.min or 0

    local delta = (target - t.wday) % 7
    local candidate = atTime(t.year, t.month, t.day + delta, h, m)
    if candidate <= fromTs then
        candidate = atTime(t.year, t.month, t.day + delta + 7, h, m)
    end
    return candidate
end

local function nextMonthDayAnchor(fromTs)
    local t = os.date('*t', fromTs)
    local days = (Config.Billing and Config.Billing.month_days) or {1, 15}
    table.sort(days)
    local h = Config.Billing and Config.Billing.charge_time and Config.Billing.charge_time.hour or 9
    local m = Config.Billing and Config.Billing.charge_time and Config.Billing.charge_time.min or 0

    for _, d in ipairs(days) do
        local ok, candidate = pcall(function()
            return atTime(t.year, t.month, d, h, m)
        end)
        if ok and candidate and candidate > fromTs then
            return candidate
        end
    end
    local year, month = t.year, t.month + 1
    if month == 13 then month = 1; year = year + 1 end
    return atTime(year, month, days[1], h, m)
end

local function nextAnchor(fromTs)
    if not Config.Billing or not Config.Billing.mode then
        return fromTs
    end
    if Config.Billing.mode == 'WEEKDAY' then
        return nextWeekdayAnchor(fromTs)
    elseif Config.Billing.mode == 'MONTH_DAYS' then
        return nextMonthDayAnchor(fromTs)
    end
    return fromTs
end

-- ===== Callbacks =====
QBCore.Functions.CreateCallback('qb-afterpay:server:getShops', function(src, cb)
    cb(Config.Shops)
end)

QBCore.Functions.CreateCallback('qb-afterpay:server:getCatalog', function(src, cb, shopId)
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

-- ===== Payment operations =====
local function TryCharge(src, Player, amount)
    for _,account in ipairs(Config.Accounts) do
        if Player.Functions.RemoveMoney(account, amount, 'afterpay-installment') then
            TriggerClientEvent('qb-afterpay:client:notify', src, ('Charged $%d from %s.'):format(amount, account), 'success')
            return true
        end
    end
    return false
end

RegisterNetEvent('qb-afterpay:server:checkout', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local shopId = data.shop_id
    local items = data.items or {}
    local planId = data.plan_id

    if not shopId or not planId or #items == 0 then
        TriggerClientEvent('qb-afterpay:client:notify', src, 'Invalid checkout data', 'error')
        return
    end

    local plan
    for _,p in ipairs(Config.Plans) do
        if p.id == planId then plan = p break end
    end
    if not plan then
        TriggerClientEvent('qb-afterpay:client:notify', src, 'Unknown plan', 'error')
        return
    end

    local total = 0
    for _,it in ipairs(items) do
        local price = tonumber(it.price) or 0
        local qty = tonumber(it.qty) or 1
        total = total + (price * qty)
    end
    total = math.floor(total + 0.5)

    local orderId = MySQL.insert.await('INSERT INTO afterpay_orders (citizenid, shop_id, plan_id, total, status) VALUES (?, ?, ?, ?, ?)',
        { Player.PlayerData.citizenid, shopId, planId, total, 'active' })
    if not orderId then
        TriggerClientEvent('qb-afterpay:client:notify', src, 'Failed to create order', 'error')
        return
    end

    for _,it in ipairs(items) do
        local qty = tonumber(it.qty) or 1
        MySQL.insert('INSERT INTO afterpay_order_items (order_id, item_name, label, price, qty) VALUES (?, ?, ?, ?, ?)', {
            orderId, it.name, it.label, it.price, qty
        })
    end

    -- ===== Create installments aligned to anchors =====
    local per = math.floor((total / plan.parts) + 0.5)
    local remaining = total
    local now = os.time()
    local dueList = {}

    local firstDue
    if Config.Billing and Config.Billing.first_at_checkout == false then
        firstDue = nextAnchor(now)
    else
        firstDue = now
    end

    for idx = 1, plan.parts do
        local amount = (idx == plan.parts) and remaining or per
        remaining = remaining - amount

        local dueAt
        if idx == 1 then
            dueAt = firstDue
        else
            local prev = dueList[#dueList] or firstDue
            dueAt = nextAnchor(prev + 60)
        end

        if idx == 1 and firstDue == now then
            dueAt = now
        end

        local id = MySQL.insert.await(
            'INSERT INTO afterpay_installments (order_id, due_at, amount, paid) VALUES (?, FROM_UNIXTIME(?), ?, 0)',
            { orderId, dueAt, amount }
        )
        table.insert(dueList, dueAt)
    end

    -- If taking first at checkout, try to charge immediately
    if not (Config.Billing and Config.Billing.first_at_checkout == false) then
        local firstRow = MySQL.single.await('SELECT * FROM afterpay_installments WHERE order_id = ? ORDER BY due_at ASC LIMIT 1', {orderId})
        if firstRow then
            local ok = TryCharge(src, Player, firstRow.amount)
            if ok then
                MySQL.update.await('UPDATE afterpay_installments SET paid = 1, paid_at = NOW() WHERE id = ?', {firstRow.id})
            else
                MySQL.update.await('UPDATE afterpay_orders SET status = ? WHERE id = ?', {'cancelled', orderId})
                MySQL.update.await('DELETE FROM afterpay_installments WHERE order_id = ?', {orderId})
                MySQL.update.await('DELETE FROM afterpay_order_items WHERE order_id = ?', {orderId})
                TriggerClientEvent('qb-afterpay:client:notify', src, 'Payment declined. Order cancelled.', 'error')
                return
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

    TriggerClientEvent('qb-afterpay:client:notify', src, ('Afterpay set up! Total $%d over %d payments.'):format(total, plan.parts), 'success')
end)

RegisterNetEvent('qb-afterpay:server:payInstallment', function(installmentId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local row = MySQL.single.await('SELECT i.*, o.status FROM afterpay_installments i JOIN afterpay_orders o ON o.id = i.order_id WHERE i.id = ?', {installmentId})
    if not row then
        TriggerClientEvent('qb-afterpay:client:notify', src, 'Installment not found', 'error'); return
    end
    if row.paid == 1 then
        TriggerClientEvent('qb-afterpay:client:notify', src, 'Already paid', 'primary'); return
    end

    local amount = row.amount
    local ok = TryCharge(src, Player, amount)
    if not ok then
        TriggerClientEvent('qb-afterpay:client:notify', src, 'Insufficient funds', 'error'); return
    end

    MySQL.update.await('UPDATE afterpay_installments SET paid = 1, paid_at = NOW() WHERE id = ?', {installmentId})
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

-- ===== Auto-charge loop (online players only) =====
CreateThread(function()
    while true do
        local rows = MySQL.query.await([[
            SELECT i.id, i.amount, i.due_at, o.citizenid, i.order_id
            FROM afterpay_installments i
            JOIN afterpay_orders o ON o.id = i.order_id
            WHERE i.paid = 0 AND i.due_at <= NOW() AND o.status = 'active'
        ]])

        if rows and #rows > 0 then
            for _, r in ipairs(rows) do
                local Player = QBCore.Functions.GetPlayerByCitizenId(r.citizenid)
                if Player then
                    local src = Player.PlayerData.source
                    local ok = TryCharge(src, Player, r.amount)
                    if ok then
                        MySQL.update.await('UPDATE afterpay_installments SET paid = 1, paid_at = NOW() WHERE id = ?', {r.id})
                        local remaining = MySQL.scalar.await('SELECT COUNT(*) FROM afterpay_installments WHERE order_id = ? AND paid = 0', {r.order_id})
                        if remaining and tonumber(remaining) == 0 then
                            MySQL.update.await('UPDATE afterpay_orders SET status = "completed" WHERE id = ?', {r.order_id})
                            TriggerClientEvent('qb-afterpay:client:notify', src, 'Your Afterpay order is fully paid. Thank you!', 'success')
                        end
                    else
                        TriggerClientEvent('qb-afterpay:client:notify', src, ('Afterpay attempt failed for $%d. Pay in the app when you can.'):format(r.amount), 'error')
                    end
                end
            end
        end

        Wait(5 * 60 * 1000) -- every 5 minutes
    end
end)
