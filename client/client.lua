local QBCore = exports['qb-core']:GetCoreObject()

local isOpen = false

RegisterCommand('afterpay', function()
    openAfterpay(false)
end, false)

RegisterCommand('staffafterpay', function()
    openAfterpay(true)
end, false)

RegisterKeyMapping('afterpay', 'Open Afterpay (Player)', 'keyboard', 'F6')
RegisterKeyMapping('staffafterpay', 'Open Afterpay (Staff)', 'keyboard', 'F7')

function openAfterpay(isStaff)
    if isOpen then return end
    isOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', staff = isStaff, plans = Config.Plans })
end

RegisterNUICallback('close', function(_, cb)
    isOpen = false
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('getShops', function(_, cb)
    QBCore.Functions.TriggerCallback('qb-afterpay:server:getShops', function(shops)
        cb(shops)
    end)
end)

RegisterNUICallback('getCatalog', function(data, cb)
    QBCore.Functions.TriggerCallback('qb-afterpay:server:getCatalog', function(items)
        cb(items)
    end, data.shop_id)
end)

RegisterNUICallback('getOrders', function(_, cb)
    QBCore.Functions.TriggerCallback('qb-afterpay:server:getOrders', function(orders)
        cb(orders)
    end)
end)

RegisterNUICallback('checkout', function(data, cb)
    TriggerServerEvent('qb-afterpay:server:checkout', data)
    cb('ok')
end)

RegisterNUICallback('payInstallment', function(data, cb)
    TriggerServerEvent('qb-afterpay:server:payInstallment', data.installment_id)
    cb('ok')
end)

RegisterNUICallback('staff:addItem', function(data, cb)
    TriggerServerEvent('qb-afterpay:server:staff:addItem', data)
    cb('ok')
end)

RegisterNUICallback('staff:updatePrice', function(data, cb)
    TriggerServerEvent('qb-afterpay:server:staff:updatePrice', data)
    cb('ok')
end)

RegisterNUICallback('staff:removeItem', function(data, cb)
    TriggerServerEvent('qb-afterpay:server:staff:removeItem', data)
    cb('ok')
end)

RegisterNetEvent('qb-afterpay:client:notify', function(msg, typ)
    if typ == nil then typ = 'primary' end
    QBCore.Functions.Notify(msg, typ)
end)
