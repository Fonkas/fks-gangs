---------------------------------------------------------------------------
-- Territories (client): map blips, the shot that starts a capture, the progress bar (fks-core) and the
-- enemy waves (client/enemies.lua) of the player who started it.
---------------------------------------------------------------------------
Territory = { state = {} }

local state = Territory.state      -- [id] = { owner, capture = { side, starter } }
local blips = {}                   -- [id] = { area, name, style }
local mine                         -- capture started by this player: { id, bar = true while our bar runs }

function Territory.Owner(id)
    return state[id] and state[id].owner
end

function Territory.Inside(t)
    return #(GetEntityCoords(PlayerPedId()) - t.coords) <= t.radius
end

---------------------------------------------------------------------------
-- Map: the colour of an area blip is its style, so a colour change creates the blip again
---------------------------------------------------------------------------
local function CanSee(t)
    if not Gangs.MapCfg(t, 'visible') then return false end
    if Gangs.MapCfg(t, 'visibleTo') == 'gangs' then return Gangs.Side(MyJob()) ~= nil end
    return true
end

-- false = no area on the map (a territory without owner, when Config.Map.showNeutral is false)
local function StyleNow(t, blinkOn)
    local s = state[t.id] or {}
    if s.capture and Gangs.MapCfg(t, 'blink') and blinkOn then return Gangs.SideStyle(s.capture.side) end
    if not s.owner and Gangs.MapCfg(t, 'showNeutral') == false then return false end
    return Gangs.SideStyle(s.owner)
end

local function ClearBlip(id)
    local b = blips[id]
    if not b then return end
    Blips.Remove(b.area)
    Blips.Remove(b.name)
    blips[id] = nil
end

local function RefreshBlip(t, blinkOn)
    if not CanSee(t) then return ClearBlip(t.id) end
    local style = StyleNow(t, blinkOn)
    local b = blips[t.id] or {}
    if b.style == style and (b.area or style == false) then return end
    Blips.Remove(b.area)
    b.area = style and Blips.Radius(t.coords, t.radius, style) or nil
    b.style = style
    if Config.Map.showName and not b.name then
        b.name = Blips.Point(t.coords, Config.Map.nameSprite, t.label)
    end
    blips[t.id] = b
end

local function RefreshAll()
    for _, t in ipairs(Config.Territories) do RefreshBlip(t, false) end
end

CreateThread(function()
    local on = true
    while true do
        local any = false
        for _, t in ipairs(Config.Territories) do
            local s = state[t.id]
            if s and s.capture and Gangs.MapCfg(t, 'blink') then
                any = true
                RefreshBlip(t, on)
            end
        end
        on = not on
        Wait(any and Config.Map.blinkEvery or 1000)
    end
end)

---------------------------------------------------------------------------
-- Sync
---------------------------------------------------------------------------
RegisterNetEvent('fks-gangs:client:territory', function(id, data)
    local t = Gangs.Territory(id)
    if not t then return end
    state[id] = data
    RefreshBlip(t, false)
    if Shop then Shop.Refresh() end
end)

local function Load()
    local all = lib.callback.await('fks-gangs:territories', false) or {}
    for id, data in pairs(all) do state[id] = data end
    RefreshAll()
    if Shop then Shop.Refresh() end
end

Bridge.OnLoaded(Load)
Bridge.OnJobUpdate(function()
    RefreshAll()
    if Shop then Shop.Refresh() end
end)

---------------------------------------------------------------------------
-- The shot: a player of a side that can capture fires inside the area
---------------------------------------------------------------------------
-- (the job is checked by the server, so a client that reads the job late or wrong still works)
CreateThread(function()
    local lastShot = 0
    while true do
        local wait = 1000
        if not mine then
            for _, t in ipairs(Config.Territories) do
                if Territory.Inside(t) then
                    wait = 0
                    if IsPedShooting(PlayerPedId()) and GetGameTimer() - lastShot > 2000 then
                        lastShot = GetGameTimer()
                        if Config.Debug then print(('[fks-gangs] shot inside %s'):format(t.id)) end
                        TriggerServerEvent('fks-gangs:server:shot', t.id)
                    end
                    break
                end
            end
        end
        Wait(wait)
    end
end)

---------------------------------------------------------------------------
-- Our capture: progress bar, enemies, and telling the server the moment we die / leave
---------------------------------------------------------------------------
RegisterNetEvent('fks-gangs:client:captureStart', function(id, duration)
    local t = Gangs.Territory(id)
    if not t then return end
    local cap = { id = id, bar = true }
    mine = cap

    CreateThread(function()
        Bridge.Progress({
            duration = duration * 1000,
            label = Config.Capture.progressLabel or _L('progress_label'),
            canCancel = false,
            useWhileDead = false,
            disable = {},
        })
        cap.bar = false
    end)

    Enemies.Start(t)

    CreateThread(function()
        while mine == cap do
            local ped = PlayerPedId()
            if IsEntityDead(ped) or not Territory.Inside(t) then
                TriggerServerEvent('fks-gangs:server:captureLeft', id)
                break
            end
            Wait(500)
        end
    end)
end)

RegisterNetEvent('fks-gangs:client:captureStop', function(id, success)
    local cap = mine
    if not cap or cap.id ~= id then return end
    mine = nil
    Enemies.Stop()
    -- a finished capture lets the bar reach 100%; a cancelled one stops it (only if it is still ours)
    if not success and cap.bar and Bridge.ProgressActive() then Bridge.CancelProgress() end
end)

---------------------------------------------------------------------------
-- Reputation: dying inside a territory tells the server who killed us (it checks the rest)
---------------------------------------------------------------------------
CreateThread(function()
    local wasDead = false
    while true do
        local ped = PlayerPedId()
        local dead = IsEntityDead(ped)
        if dead and not wasDead and Config.Reputation.enabled then
            local killer = GetPedSourceOfDeath(ped)
            if killer and killer ~= 0 and killer ~= ped and IsPedAPlayer(killer) then
                for _, t in ipairs(Config.Territories) do
                    if Territory.Inside(t) then
                        local idx = NetworkGetPlayerIndexFromPed(killer)
                        if idx and idx ~= -1 then TriggerServerEvent('fks-gangs:server:killedBy', GetPlayerServerId(idx)) end
                        break
                    end
                end
            end
        end
        wasDead = dead
        Wait(dead and 500 or 1000)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(blips) do ClearBlip(id) end
    if mine and mine.bar and Bridge.ProgressActive() then Bridge.CancelProgress() end
end)
