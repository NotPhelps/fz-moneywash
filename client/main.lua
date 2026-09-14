local Config = Config or {}
local Framework = nil
local frameworkReady = false

lib.locale()

-- =========================================================
-- FRAMEWORK INITIALIZATION
-- =========================================================

CreateThread(function()
    if Config.Framework == 'auto' then
        if GetResourceState('qbx_core') == 'started' then
            Framework = 'qbox'
        elseif GetResourceState('qb-core') == 'started' then
            Framework = 'qb'
            QBCore = exports['qb-core']:GetCoreObject()
        elseif GetResourceState('es_extended') == 'started' then
            Framework = 'esx'
            ESX = exports['es_extended']:getSharedObject()
        else
            print('^1[fz-moneywash] Missing a supported framework.^0')
        end
    elseif Config.Framework == 'qbox' then
        if GetResourceState('qbx_core') == 'started' then
            Framework = 'qbox'
        else
            print('^1[fz-moneywash] qbx_core is not started.^0')
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

    frameworkReady = true
end)

-- =========================================================
-- NOTIFICATIONS
-- =========================================================

RegisterNetEvent('fz-moneywash:notify', function(message, notifyType)
    if not message then return end
    notifyType = notifyType or 'inform'

    if Config.Notify == 'qb' then
        if QBCore and QBCore.Functions then
            QBCore.Functions.Notify(message, notifyType, 5000)
        end
    elseif Config.Notify == 'esx' then
        if ESX then
            ESX.ShowNotification(message, notifyType, 5000)
        end
    elseif Config.Notify == 'ox' then
        lib.notify({
            description = message,
            type = notifyType,
            duration = 5000
        })
    else
        print('^1[fz-moneywash] Invalid notification setting in config.lua.^0')
    end
end)

-- =========================================================
-- WASHING MACHINE CONTEXT MENU
-- =========================================================

RegisterNetEvent('fz-moneywash:openWashingMachine', function(washId, id)
    local timerLeft = lib.callback.await('fz-moneywash:checkTimer', false, washId, id)
    
    local collectTitle = locale('washing_machine.collect_money')
    local collectDesc = locale('washing_machine.collect_money_description')

    if type(timerLeft) == 'number' then
        local minutes = math.floor(timerLeft / 60)
        local seconds = math.floor(timerLeft % 60)
        collectTitle = string.format('Time Left: %02d:%02d', minutes, seconds)
        collectDesc = 'The washing machine is still running.'
    end

    lib.registerContext({
        id = 'washingmachine_' .. tostring(washId) .. '_' .. tostring(id),
        title = locale('washing_machine.title'),
        options = {
            {
                title = locale('currency.symbol')
                    .. lib.callback.await(
                        'fz-moneywash:getMoneywashAmount',
                        false,
                        washId,
                        id
                    )
                    .. ' '
                    .. locale('washing_machine.subtitle_wash_money'),
                description = locale('washing_machine.description_wash_money'),
                icon = 'fas fa-dollar-sign',
            },
            {
                title = collectTitle,
                description = collectDesc,
                icon = 'fas fa-dollar-sign',
                onSelect = function()
                    local currentTimer = lib.callback.await(
                        'fz-moneywash:checkTimer',
                        false,
                        washId,
                        id
                    )

                    if currentTimer == false then
                        TriggerServerEvent('fz-moneywash:collectMoney', washId, id)
                    elseif currentTimer == true then
                        TriggerEvent('fz-moneywash:notify', locale('washing_machine.not_started'), 'error')
                    else
                        local time = tonumber(currentTimer)
                        local minutes = math.floor(time / 60)
                        local seconds = math.floor(time % 60)

                        TriggerEvent(
                            'fz-moneywash:notify',
                            string.format('Time left: %02d:%02d', minutes, seconds),
                            'error'
                        )
                    end
                end,
            },
            {
                title = locale('washing_machine.stop_washing'),
                description = locale('washing_machine.stop_washing_description'),
                icon = 'fas fa-dollar-sign',
                onSelect = function()
                    local currentTimer = lib.callback.await(
                        'fz-moneywash:checkTimer',
                        false,
                        washId,
                        id
                    )

                    if currentTimer == false then
                        TriggerEvent('fz-moneywash:notify', locale('error.timer_finished'), 'error')
                    elseif currentTimer == true then
                        TriggerEvent('fz-moneywash:notify', locale('error.not_started'), 'error')
                    elseif currentTimer >= 10 then
                        TriggerServerEvent('fz-moneywash:stopWashing', washId, id)
                    else
                        TriggerEvent('fz-moneywash:notify', locale('error.too_late_to_cancel'), 'error')
                    end
                end,
            },
        }
    })

    lib.showContext('washingmachine_' .. tostring(washId) .. '_' .. tostring(id))
end)

-- =========================================================
-- ENTER / EXIT MONEY WASH
-- =========================================================

local function enterMoneywash(moneywash, coords, requireCard)
    local playerPed = PlayerPedId()

    if moneywash == 'entrance' then
        if requireCard then
            local checkCard = lib.callback.await('fz-moneywash:checkMoneywashCard', false)
            if not checkCard then
                TriggerEvent('fz-moneywash:notify', locale('error.no_moneywash_card'), 'error')
                return
            end
        end
        TriggerEvent('fz-moneywash:notify', locale('info.entering_moneywash'), 'info')
    elseif moneywash == 'exit' then
        TriggerEvent('fz-moneywash:notify', locale('info.exiting_moneywash'), 'info')
    else
        TriggerEvent('fz-moneywash:notify', locale('error.invalid_moneywash'), 'error')
        return
    end

    DoScreenFadeOut(1000)
    Wait(1000)
    SetEntityCoords(playerPed, coords.xyz)
    Wait(1000)
    DoScreenFadeIn(1000)
end

-- =========================================================
-- SETUP ENTRANCE / EXIT
-- =========================================================

local function setupEnterAndExitMoneywash()
    for i, current in pairs(Config.moneywashes) do
        local entranceCoords = current.entrance
        local exitCoords = current.exit
        local requireCard = current.requireCard

        if Config.useTarget then
            exports.ox_target:addBoxZone({
                name = 'moneywash_entrance_' .. tostring(i),
                coords = entranceCoords.xyz,
                size = vec3(1.0, 1.0, 1.0),
                rotation = entranceCoords.w,
                debug = Config.debug,
                options = {
                    {
                        name = 'moneywash_enter_' .. tostring(i),
                        label = locale('moneywash.target_enter'),
                        icon = 'fas fa-door-open',
                        distance = 2.0,
                        onSelect = function()
                            enterMoneywash('entrance', exitCoords, requireCard)
                        end,
                    },
                },
            })

            exports.ox_target:addBoxZone({
                name = 'moneywash_exit_' .. tostring(i),
                coords = exitCoords.xyz,
                size = vec3(1.0, 1.0, 1.0),
                rotation = exitCoords.w,
                debug = Config.debug,
                options = {
                    {
                        name = 'moneywash_exit_' .. tostring(i),
                        label = locale('moneywash.target_exit'),
                        icon = 'fas fa-door-open',
                        distance = 2.0,
                        onSelect = function()
                            enterMoneywash('exit', entranceCoords, requireCard)
                        end,
                    },
                },
            })
        else
            lib.zones.box({
                name = 'moneywash_entrance_' .. tostring(i),
                coords = entranceCoords.xyz,
                size = vec3(1.0, 1.0, 1.0),
                rotation = entranceCoords.w,
                debug = Config.debug,
                onEnter = function()
                    lib.showTextUI(locale('moneywash.textui_enter'))
                end,
                onExit = function()
                    lib.hideTextUI()
                end,
                inside = function()
                    if IsControlJustPressed(0, Config.keybind) then
                        enterMoneywash('entrance', exitCoords, requireCard)
                        lib.hideTextUI()
                    end
                end,
            })

            lib.zones.box({
                name = 'moneywash_exit_' .. tostring(i),
                coords = exitCoords.xyz,
                size = vec3(1.0, 1.0, 1.0),
                rotation = exitCoords.w,
                debug = Config.debug,
                onEnter = function()
                    lib.showTextUI(locale('moneywash.textui_exit'))
                end,
                onExit = function()
                    lib.hideTextUI()
                end,
                inside = function()
                    if IsControlJustPressed(0, Config.keybind) then
                        enterMoneywash('exit', entranceCoords, requireCard)
                        lib.hideTextUI()
                    end
                end,
            })
        end
    end
end

-- =========================================================
-- SETUP WASHING MACHINES
-- =========================================================

local function setupWashingMachines()
    for washId, current in pairs(Config.moneywashes) do
        for id, washingmachine in pairs(current.washingmachines) do
            local coords = washingmachine.coords

            if Config.useTarget then
                exports.ox_target:addBoxZone({
                    name = 'washingmachine_' .. tostring(washId) .. '_' .. tostring(id),
                    coords = coords.xyz,
                    size = vec3(1.0, 1.0, 1.0),
                    rotation = coords.w,
                    debug = Config.debug,
                    options = {
                        {
                            name = 'washingmachine_' .. tostring(washId) .. '_' .. tostring(id),
                            label = locale('washing_machine.target_open_washing_machine'),
                            icon = 'fas fa-dollar-sign',
                            distance = 2.0,
                            onSelect = function()
                                TriggerServerEvent('fz-moneywash:checkWashingMachine', washId, id)
                            end,
                        },
                    },
                })
            else
                local options = current.zoneOptions
                if options then
                    lib.zones.box({
                        name = 'washingmachine_zone_' .. tostring(washId) .. '_' .. tostring(id),
                        coords = coords.xyz,
                        size = vec3(options.length, options.width, 2.0),
                        rotation = coords.w,
                        debug = Config.debug,
                        onEnter = function()
                            lib.showTextUI(locale('washing_machine.textui_open_washing_machine'))
                        end,
                        onExit = function()
                            lib.hideTextUI()
                        end,
                        inside = function()
                            if IsControlJustPressed(0, Config.keybind) then
                                TriggerServerEvent('fz-moneywash:checkWashingMachine', washId, id)
                                lib.hideTextUI()
                            end
                        end,
                    })
                end
            end
        end
    end
end

-- =========================================================
-- START WASHING MACHINE
-- =========================================================

RegisterNetEvent('fz-moneywash:startWashingMachine', function(washId, id)
    local max = lib.callback.await('fz-moneywash:getMoney', false)

    if not max or max <= 0 then
        TriggerEvent('fz-moneywash:notify', locale('error.missing_items'), 'error')
        return
    end

    local input = lib.inputDialog(
        'Wash Amount',
        {
            {
                type = 'slider',
                label = 'How much cash do you want to wash?',
                default = 0,
                min = 0,
                max = max,
            }
        }
    )

    if not input then
        return
    end

    local moneywashAmount = tonumber(input[1])

    if not moneywashAmount or moneywashAmount <= 0 then
        TriggerEvent('fz-moneywash:notify', locale('error.invalid_amount'), 'error')
        return
    end

    TriggerServerEvent('fz-moneywash:washMoney', washId, id, moneywashAmount)
end)

-- =========================================================
-- SETUP
-- =========================================================

RegisterNetEvent('fz-moneywash:setup', function()
    setupEnterAndExitMoneywash()
    setupWashingMachines()
end)

-- =========================================================
-- RESOURCE START
-- =========================================================

AddEventHandler('onResourceStart', function(resource)
    if resource ~= cache.resource then
        return
    end

    Wait(500)
    TriggerEvent('fz-moneywash:setup')
end)

-- =========================================================
-- QBOX / QB PLAYER LOADED
-- =========================================================

AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    TriggerEvent('fz-moneywash:setup')
end)

