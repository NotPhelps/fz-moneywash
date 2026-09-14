local Config = Config or {}
local activeWashingMachines = {}
local Framework = nil

lib.locale()

-- =========================================================
-- FRAMEWORK INITIALIZATION
-- =========================================================

CreateThread(function()
    if Config.Framework == 'auto' then
        if GetResourceState('qbx_core') == 'started' then
            Framework = 'qbox'
            print('^2[fz-moneywash] Qbox detected.^0')
        elseif GetResourceState('qb-core') == 'started' then
            Framework = 'qb'
            QBCore = exports['qb-core']:GetCoreObject()
            print('^2[fz-moneywash] QB-Core detected.^0')
        elseif GetResourceState('es_extended') == 'started' then
            Framework = 'esx'
            ESX = exports['es_extended']:getSharedObject()
            print('^2[fz-moneywash] ESX detected.^0')
        else
            print('^1[fz-moneywash] Missing a supported framework.^0')
        end
    elseif Config.Framework == 'qbox' then
        if GetResourceState('qbx_core') == 'started' then
            Framework = 'qbox'
            print('^2[fz-moneywash] Framework set to Qbox.^0')
        else
            print('^1[fz-moneywash] Config is set to qbox but qbx_core is not started.^0')
        end
    elseif Config.Framework == 'qb' then
        Framework = 'qb'
        QBCore = exports['qb-core']:GetCoreObject()
    elseif Config.Framework == 'esx' then
        Framework = 'esx'
        ESX = exports['es_extended']:getSharedObject()
    else
        print('^1[fz-moneywash] Invalid framework in config.lua.^0')
    end
end)

-- =========================================================
-- GET PLAYER
-- =========================================================

local function GetPlayer(source)
    if Framework == 'qbox' then
        return exports.qbx_core:GetPlayer(source)
    elseif Framework == 'qb' then
        return QBCore.Functions.GetPlayer(source)
    elseif Framework == 'esx' then
        return ESX.GetPlayerFromId(source)
    end
    return nil
end

-- =========================================================
-- CHECK MONEY WASH CARD
-- =========================================================

lib.callback.register('fz-moneywash:checkMoneywashCard', function(source)
    if not Config.moneywashCard then
        return true
    end

    local cardAmount = exports.ox_inventory:GetItem(
        source,
        Config.moneywashCard,
        nil,
        true
    )

    return cardAmount and cardAmount > 0 or false
end)

-- =========================================================
-- GET DIRTY MONEY
-- =========================================================

lib.callback.register('fz-moneywash:getMoney', function(source)
    local moneyAmount = exports.ox_inventory:GetItem(
        source,
        Config.dirtycashItem,
        nil,
        true
    )

    return moneyAmount or 0
end)

-- =========================================================
-- GET CURRENT WASH AMOUNT
-- =========================================================

lib.callback.register('fz-moneywash:getMoneywashAmount', function(source, washId, id)
    local machineKey = tostring(washId) .. '_' .. tostring(id)
    local machine = activeWashingMachines[machineKey]

    if not machine or machine.player ~= source then
        TriggerClientEvent(
            'fz-moneywash:notify',
            source,
            locale('error.not_your_machine'),
            'error'
        )
        return 0
    end

    return machine.moneywashAmount or 0
end)

-- =========================================================
-- CHECK TIMER
-- =========================================================

lib.callback.register('fz-moneywash:checkTimer', function(source, washId, id)
    local machineKey = tostring(washId) .. '_' .. tostring(id)
    local machine = activeWashingMachines[machineKey]

    if not machine or not machine.timer then
        return true
    end

    local currentTime = os.time()

    if currentTime >= machine.timer then
        return false
    end

    return machine.timer - currentTime
end)

-- =========================================================
-- ADD CLEAN MONEY
-- =========================================================

local function AddMoney(source, moneyType, amount)
    amount = tonumber(amount)

    if not amount or amount <= 0 then
        print(('^1[fz-moneywash] Invalid money amount: %s^0'):format(tostring(amount)))
        return false
    end

    moneyType = moneyType or 'cash'

    if moneyType == 'money' then
        moneyType = 'cash'
    end

    if Framework == 'qbox' then
        if moneyType ~= 'cash' and moneyType ~= 'bank' and moneyType ~= 'crypto' then
            print(('^1[fz-moneywash] Invalid Qbox money type: %s^0'):format(tostring(moneyType)))
            return false
        end

        local success = exports.qbx_core:AddMoney(
            source,
            moneyType,
            amount,
            'moneywash-collection'
        )

        return success == true
    end

    if Framework == 'qb' then
        local Player = GetPlayer(source)
        if not Player then return false end

        Player.Functions.AddMoney(
            moneyType,
            amount,
            'moneywash-collection'
        )
        return true
    end

    if Framework == 'esx' then
        local xPlayer = GetPlayer(source)
        if not xPlayer then return false end

        if moneyType == 'cash' then
            xPlayer.addMoney(amount)
        else
            xPlayer.addAccountMoney(moneyType, amount)
        end
        return true
    end

    print('^1[fz-moneywash] Invalid framework.^0')
    return false
end

-- =========================================================
-- CHECK IF PLAYER IS USING ANOTHER MACHINE
-- =========================================================

local function isUsingMachineAlready(source, currentKey)
    for key, machine in pairs(activeWashingMachines) do
        if key ~= currentKey and machine.player == source then
            return true
        end
    end
    return false
end

-- =========================================================
-- COLLECT CLEAN MONEY
-- =========================================================

RegisterNetEvent('fz-moneywash:collectMoney', function(washId, id)
    local source = source
    local machineKey = tostring(washId) .. '_' .. tostring(id)
    local machine = activeWashingMachines[machineKey]

    if not machine or machine.player ~= source then
        TriggerClientEvent(
            'fz-moneywash:notify',
            source,
            locale('error.not_your_machine'),
            'error'
        )
        return
    end

    if machine.timer and os.time() < machine.timer then
        local remaining = machine.timer - os.time()

        TriggerClientEvent(
            'fz-moneywash:notify',
            source,
            locale('error.not_finished'),
            'error'
        )

        print(('^3[fz-moneywash] Player %s attempted early collection. %s seconds remaining.^0'):format(source, remaining))
        return
    end

    local moneywashAmount = tonumber(machine.moneywashAmount)

    if not moneywashAmount or moneywashAmount <= 0 then
        TriggerClientEvent(
            'fz-moneywash:notify',
            source,
            locale('error.invalid_amount'),
            'error'
        )
        activeWashingMachines[machineKey] = nil
        return
    end

    local siteTax = Config.tax
    if Config.moneywashes and Config.moneywashes[washId] and Config.moneywashes[washId].tax then
        siteTax = Config.moneywashes[washId].tax
    end

    local cleanmoney = math.floor(
        moneywashAmount * (1 - siteTax)
    )

    if cleanmoney <= 0 then
        TriggerClientEvent(
            'fz-moneywash:notify',
            source,
            locale('error.invalid_amount'),
            'error'
        )
        return
    end

    local paid = AddMoney(
        source,
        Config.MoneyType or 'cash',
        cleanmoney
    )

    if not paid then
        print(('^1[fz-moneywash] Failed to pay player %s $%s.^0'):format(source, cleanmoney))
        TriggerClientEvent(
            'fz-moneywash:notify',
            source,
            'Failed to give you the washed money. Please try again.',
            'error'
        )
        return
    end

    activeWashingMachines[machineKey] = nil

    TriggerClientEvent(
        'fz-moneywash:notify',
        source,
        locale(
            'success.money_washed',
            cleanmoney
        ),
        'success'
    )
end)

-- =========================================================
-- STOP WASHING / REFUND DIRTY CASH
-- =========================================================

RegisterNetEvent('fz-moneywash:stopWashing', function(washId, id)
    local source = source
    local machineKey = tostring(washId) .. '_' .. tostring(id)
    local machine = activeWashingMachines[machineKey]

    if not machine or machine.player ~= source then
        TriggerClientEvent(
            'fz-moneywash:notify',
            source,
            locale('error.not_your_machine'),
            'error'
        )
        return
    end

    local moneywashAmount = tonumber(machine.moneywashAmount)

    if not moneywashAmount or moneywashAmount < 0 then
        TriggerClientEvent(
            'fz-moneywash:notify',
            source,
            locale('error.invalid_amount'),
            'error'
        )
        return
    end

    local siteTax = Config.tax
    if Config.moneywashes and Config.moneywashes[washId] and Config.moneywashes[washId].tax then
        siteTax = Config.moneywashes[washId].tax
    end

    local dirtycash = math.floor(
        moneywashAmount * (1 - siteTax)
    )

    if dirtycash <= 0 then
        activeWashingMachines[machineKey] = nil
        return
    end

    if not exports.ox_inventory:CanCarryItem(
        source,
        Config.dirtycashItem,
        dirtycash
    ) then
        TriggerClientEvent(
            'fz-moneywash:notify',
            source,
            locale('error.not_enough_inventory_space'),
            'error'
        )
        return
    end

    local success = exports.ox_inventory:AddItem(
        source,
        Config.dirtycashItem,
        dirtycash
    )

    if not success then
        TriggerClientEvent(
            'fz-moneywash:notify',
            source,
            locale('error.not_enough_inventory_space'),
            'error'
        )
        return
    end

    activeWashingMachines[machineKey] = nil

    TriggerClientEvent(
        'fz-moneywash:notify',
        source,
        locale('success.washing_stopped')
        .. locale('currency.symbol')
        .. dirtycash,
        'success'
    )
end)

-- =========================================================
-- CHECK WASHING MACHINE
-- =========================================================

RegisterNetEvent('fz-moneywash:checkWashingMachine', function(washId, id)
    local source = source
    local machineKey = tostring(washId) .. '_' .. tostring(id)

    if isUsingMachineAlready(source, machineKey) then
        TriggerClientEvent(
            'fz-moneywash:notify',
            source,
            locale('error.already_using_machine'),
            'error'
        )
        return
    end

    if activeWashingMachines[machineKey]
    and activeWashingMachines[machineKey].player == source then
        TriggerClientEvent(
            'fz-moneywash:openWashingMachine',
            source,
            washId,
            id
        )
        return
    end

    if activeWashingMachines[machineKey] then
        TriggerClientEvent(
            'fz-moneywash:notify',
            source,
            locale('error.washing_machine_busy'),
            'error'
        )
        return
    end

    TriggerClientEvent(
        'fz-moneywash:startWashingMachine',
        source,
        washId,
        id
    )
end)

-- =========================================================
-- START WASHING
-- =========================================================

RegisterNetEvent('fz-moneywash:washMoney', function(washId, id, moneywashAmount)
    local source = source
    local machineKey = tostring(washId) .. '_' .. tostring(id)

    moneywashAmount = tonumber(moneywashAmount)

    if not moneywashAmount or moneywashAmount <= 0 then
        TriggerClientEvent(
            'fz-moneywash:notify',
            source,
            locale('error.invalid_amount'),
            'error'
        )
        return
    end

    if activeWashingMachines[machineKey] then
        TriggerClientEvent(
            'fz-moneywash:notify',
            source,
            locale('error.washing_machine_busy'),
            'error'
        )
        return
    end

    local maxwashtime = Config.maxwashtime * 60
    local washingTime = moneywashAmount * 0.007 + 10

    if washingTime > maxwashtime then
        washingTime = maxwashtime
    end

    local playerdirtycash = exports.ox_inventory:GetItem(
        source,
        Config.dirtycashItem,
        nil,
        true
    )

    playerdirtycash = tonumber(playerdirtycash) or 0

    if playerdirtycash < moneywashAmount then
        TriggerClientEvent(
            'fz-moneywash:notify',
            source,
            locale('error.missing_items'),
            'error'
        )
        return
    end

    local removed, reason = exports.ox_inventory:RemoveItem(
        source,
        Config.dirtycashItem,
        moneywashAmount,
        nil
    )

    if not removed then
        print(('^1[fz-moneywash] Failed to remove dirty cash from %s. Reason: %s^0'):format(source, tostring(reason)))
        TriggerClientEvent(
            'fz-moneywash:notify',
            source,
            locale('error.missing_items'),
            'error'
        )
        return
    end

    activeWashingMachines[machineKey] = {
        player = source,
        moneywashAmount = moneywashAmount,
        timer = os.time() + washingTime
    }

    TriggerClientEvent(
        'fz-moneywash:notify',
        source,
        locale('info.money_is_being_washed'),
        'info'
    )
end)

-- =========================================================
-- ESX PLAYER LOADED
-- =========================================================

AddEventHandler('esx:playerLoaded', function(playerId)
    TriggerClientEvent(
        'fz-moneywash:setup',
        playerId
    )
end)
