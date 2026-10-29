---------------------------------------------------------------------------
-- Contracts (client): the target / wagon / guards of the player's contract, the side card with the
-- objective and time (fks-core sheet), the stealth meter, stealing wagons and the police alert blips.
---------------------------------------------------------------------------
local M = Config.Missions
local HEIST = joaat('FKS_GANGS_HEIST')
local PLAYER = joaat('PLAYER')

AddRelationshipGroup('FKS_GANGS_HEIST')

local cur                -- current contract: payload from the server + deadline (game timer)
local token              -- changes on every start / end (old loops stop)
local peds, objects, blips = {}, {}, {}
local wagons = {}        -- [netId] = gang (supply runs on the road, for the steal prompt)

local function Notify(msg, kind)
    Bridge.Notify({ title = _L('contracts'), description = msg, type = kind or 'inform' })
end

local function Pick(list) return list[math.random(#list)] end

local function Left()
    return cur and math.max(0, (cur.deadline - GetGameTimer()) / 1000) or 0
end

---------------------------------------------------------------------------
-- GPS route (RedM multi route natives; skipped when the build does not have them)
---------------------------------------------------------------------------
local function Route(coords)
    if type(ClearGpsMultiRoute) == 'function' then ClearGpsMultiRoute() end
    if not coords or not M.gpsRoute or type(StartGpsMultiRoute) ~= 'function' then return end
    StartGpsMultiRoute(joaat('COLOR_YELLOW'), true, true)
    AddPointToGpsMultiRoute(coords.x, coords.y, coords.z)
    SetGpsMultiRouteRender(true)
end

---------------------------------------------------------------------------
-- Small box at the top centre (fks-core tracker): time left + the detection bar. A new objective is a notification.
---------------------------------------------------------------------------
local lastObjective

local function Track(objective, bar)
    if not cur then return end
    if objective and objective ~= lastObjective then
        lastObjective = objective
        Notify((objective:gsub('%*%*', '')), 'inform')
    end
    UI.Tracker({ label = cur.label, seconds = Left(), bar = bar })
end

-- detection 0-100 -> bar of the tracker
local function DetectionBar(detect, spotted)
    if spotted then return { value = 1, label = _L('stealth_state', _L('spotted')), tone = 'bad' } end
    local state = detect < 35 and _L('hidden') or _L('suspicious')
    return { value = detect / 100, label = _L('stealth_state', state), tone = detect < 35 and 'good' or (detect < 70 and 'warn' or 'bad') }
end

---------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------
local function Cleanup()
    token = nil
    for _, ped in ipairs(peds) do
        if DoesEntityExist(ped) then
            if IsEntityDead(ped) then SetEntityAsNoLongerNeeded(ped) else DeleteEntity(ped) end
        end
    end
    for _, obj in ipairs(objects) do if DoesEntityExist(obj) then DeleteEntity(obj) end end
    for _, b in ipairs(blips) do Blips.Remove(b) end
    peds, objects, blips = {}, {}, {}
    Route(nil)
    UI.Tracker(false)
    lastObjective = nil
    SetRelationshipBetweenGroups(3, HEIST, PLAYER)
    SetRelationshipBetweenGroups(3, PLAYER, HEIST)
    cur = nil
end

local function Fail(reason)
    TriggerServerEvent('fks-gangs:mission:fail', reason)
end

local function ArmPed(ped, cfg)
    SetEntityAsMissionEntity(ped, true, true)
    if cfg.health then SetEntityMaxHealth(ped, cfg.health) SetEntityHealth(ped, cfg.health) end
    SetPedAccuracy(ped, cfg.accuracy or 35)
    SetPedCombatAbility(ped, 2)
    SetPedCombatRange(ped, 2)
    SetPedCombatMovement(ped, 2)
    SetPedCombatAttributes(ped, 46, true)
    SetPedFleeAttributes(ped, 0, false)
    local weapon = joaat(Pick(cfg.weapons))
    GiveWeaponToPed(ped, weapon, 200, false, true)
    SetCurrentPedWeapon(ped, weapon, true)
end

local function NewPed(model, c, network)
    local hash = LoadModel(model)
    if not hash then return nil end
    local ped = CreatePed(hash, c.x, c.y, c.z, c.w or 0.0, network ~= false, network ~= false, false, false)
    local t = GetGameTimer() + 1500
    while not DoesEntityExist(ped) and GetGameTimer() < t do Wait(10) end
    SetModelAsNoLongerNeeded(hash)
    if not DoesEntityExist(ped) then return nil end
    SetEntityAsMissionEntity(ped, true, true)
    PedOutfit(ped)
    peds[#peds + 1] = ped

    -- far from the player the ground has no collision yet: the ped waits frozen on its spot until it loads
    -- (otherwise it falls through the map), and goes back to its spot if it ever drops below it
    FreezeEntityPosition(ped, true)
    CreateThread(function()
        local frozen = true
        while DoesEntityExist(ped) and not IsEntityDead(ped) do
            if frozen then
                RequestCollisionAtCoord(c.x, c.y, c.z)
                if HasCollisionLoadedAroundEntity(ped) then
                    FreezeEntityPosition(ped, false)
                    frozen = false
                end
            elseif GetEntityCoords(ped).z < c.z - 8.0 then
                SetEntityCoords(ped, c.x, c.y, c.z, false, false, false, false)
                FreezeEntityPosition(ped, true)
                frozen = true
            end
            Wait(frozen and 250 or 1000)
        end
    end)
    return ped
end

---------------------------------------------------------------------------
-- 1. Hitman: stealth meter
---------------------------------------------------------------------------
local function Crouched(ped)
    local r = Citizen.InvokeNative(0xD5FE956C70FF370B, ped)  -- GetPedCrouchMovement
    return r == true or r == 1
end

-- is `ped` inside the field of view of `target` (cone in front of it)?
local function InFront(target, ped, fov)
    local f = GetEntityForwardVector(target)
    local d = GetEntityCoords(ped) - GetEntityCoords(target)
    local len = math.sqrt(d.x * d.x + d.y * d.y)
    if len < 0.01 then return true end
    local dot = (f.x * d.x + f.y * d.y) / len
    return dot >= math.cos(math.rad(fov))
end

local function Assassin(m)
    local c = M.assassin
    local s = c.stealth
    blips[#blips + 1] = Blips.Radius(m.area, c.areaRadius or 60.0, M.areaStyles.target, m.label)
    Route(m.area)
    Track(_L('obj_assassin'))

    local my = token
    CreateThread(function()
        local target, detect, spotted, shown = nil, 0.0, false, -1
        while token == my do
            local wait = 1000
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local d = #(pos - m.loc.xyz)

            if not target and d < 120.0 then
                target = NewPed(m.model, m.loc, true)
                if target then
                    SetBlockingOfNonTemporaryEvents(target, true)
                    SetPedKeepTask(target, true)
                    TaskStartScenarioInPlace(target, joaat(m.scenario), -1, true, false, false, false)
                end
            end

            if target and DoesEntityExist(target) then
                wait = 200
                if IsEntityDead(target) then
                    local killer = GetPedSourceOfDeath(target)
                    if killer == ped and not spotted then
                        TriggerServerEvent('fks-gangs:mission:assassinDone')
                    elseif not spotted then
                        Fail('target_dead')
                    end
                    break
                end

                local td = #(pos - GetEntityCoords(target))
                if not spotted and td < 60.0 then
                    local dt = 0.2
                    local crouch = Crouched(ped)
                    local running = IsPedRunning(ped) or IsPedSprinting(ped)
                    local sight = (crouch and s.sightCrouch or s.sight) + (running and s.runBonus or 0.0)
                    local sees = td <= sight and InFront(target, ped, 65.0) and HasEntityClearLosToEntity(target, ped, 17)
                    local hears = (not crouch and td <= s.hearing) or (running and td <= s.hearing + s.runBonus * 0.5)
                    if IsPedShooting(ped) and td <= 40.0 then detect = detect + 60.0 end
                    if sees or hears then
                        detect = detect + s.fill * dt * math.max(0.25, 1.0 - td / (sight + 1.0)) * (sees and 1.0 or 0.6) + 1.0
                    else
                        detect = detect - s.drain * dt
                    end
                    detect = math.max(0.0, math.min(100.0, detect))

                    if detect >= 100.0 then
                        spotted = true
                        SetBlockingOfNonTemporaryEvents(target, false)
                        ClearPedTasks(target)
                        pcall(TaskSmartFleePed, target, ped, 600.0, -1, 0, 3.0, 0)
                        Track(nil, DetectionBar(100, true))
                        if c.failOnSpotted then Fail('spotted') break end
                    end

                    local step = math.floor(detect / 2)
                    if step ~= shown and not spotted then
                        shown = step
                        Track(nil, DetectionBar(detect))
                    end
                elseif spotted and td > 250.0 then
                    Fail('escaped')
                    break
                elseif shown ~= -1 and td >= 60.0 and not spotted then
                    shown = -1
                    Track(nil)
                end
            end
            Wait(wait)
        end
    end)
end

---------------------------------------------------------------------------
-- 2. Supply run
---------------------------------------------------------------------------
local function Deliver(m)
    local c = M.supply
    -- area + icon: the area always shows, even if the icon sprite does not exist in this game build
    blips[#blips + 1] = Blips.Radius(m.dest, math.max(25.0, (c.deliverRadius or 10.0) * 2), M.areaStyles.target, _L('buyer_blip'))
    blips[#blips + 1] = Blips.Point(m.dest, M.sprites.delivery, _L('buyer_blip'))
    Route(m.dest)
    Track(m.stolen and _L('obj_supply_stolen') or _L('obj_supply'))

    local my = token
    CreateThread(function()
        local wagonBlip, lastTry = nil, 0
        while token == my do
            local veh = NetworkDoesNetworkIdExist(m.netId) and NetworkGetEntityFromNetworkId(m.netId) or 0
            if veh ~= 0 and DoesEntityExist(veh) then
                if not wagonBlip then
                    wagonBlip = Citizen.InvokeNative(0x23F74C2FDA6E7C61, -1749618580, veh)   -- BlipAddForEntity
                    blips[#blips + 1] = wagonBlip
                end
                local near = #(GetEntityCoords(veh) - m.dest) <= (c.deliverRadius or 10.0)
                local mine = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(veh)) <= 12.0
                if near and mine and GetGameTimer() - lastTry > 3000 then
                    lastTry = GetGameTimer()
                    TriggerServerEvent('fks-gangs:mission:deliver')
                end
            end
            Wait(500)
        end
    end)
end

local function Supply(m)
    if m.stage == 'deliver' then return Deliver(m) end
    Track(_L('obj_supply_pickup', M.supply.command))
end

RegisterCommand(M.supply.command, function()
    if not cur or cur.id ~= 'supply' then return Notify(_L('no_supply_contract'), 'error') end
    if Hideout and Hideout.id then return Notify(_L('wagon_outside'), 'error') end
    local ok, model = lib.callback.await('fks-gangs:mission:canSpawnWagon', false)
    if not ok then return Notify(model or _L('error'), 'error') end

    local hash = LoadModel(model)
    if not hash then return Notify(_L('error'), 'error') end
    local ped = PlayerPedId()
    local p = GetOffsetFromEntityInWorldCoords(ped, 0.0, 5.0, 0.0)
    local veh = CreateVehicle(hash, p.x, p.y, p.z, GetEntityHeading(ped), true, false, false, false)
    local t = GetGameTimer() + 3000
    while not DoesEntityExist(veh) and GetGameTimer() < t do Wait(10) end
    SetModelAsNoLongerNeeded(hash)
    if not DoesEntityExist(veh) then return Notify(_L('error'), 'error') end
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleOnGroundProperly(veh)
    -- wait until the game has given it a network id
    t = GetGameTimer() + 3000
    while not NetworkGetEntityIsNetworked(veh) and GetGameTimer() < t do
        NetworkRegisterEntityAsNetworked(veh)
        Wait(50)
    end
    local netId = NetworkGetNetworkIdFromEntity(veh)
    if not netId or netId == 0 then
        DeleteEntity(veh)
        return Notify(_L('wagon_failed', M.supply.command), 'error')
    end
    SetNetworkIdExistsOnAllMachines(netId, true)
    TaskEnterVehicle(ped, veh, 10000, -1, 2.0, 1, 0)
    TriggerServerEvent('fks-gangs:mission:wagonSpawned', netId)
end, false)

RegisterNetEvent('fks-gangs:client:missionUpdate', function(data)
    if not cur or cur.id ~= 'supply' then return end
    for k, v in pairs(data) do cur[k] = v end
    cur.deadline = GetGameTimer() + (data.seconds or 0) * 1000
    Deliver(cur)
end)

-- wagons on the road: players of another gang can steal one by climbing on it
RegisterNetEvent('fks-gangs:client:wagons', function(list)
    wagons = {}
    for _, w in ipairs(list or {}) do wagons[w.netId] = w.gang end
end)

Bridge.OnLoaded(function()
    local list = lib.callback.await('fks-gangs:mission:wagons', false) or {}
    wagons = {}
    for _, w in ipairs(list) do wagons[w.netId] = w.gang end
end)

local stealGroup = Prompts.Group()
local pSteal = Prompts.Make(stealGroup, Config.Keys.interact, _L('steal_wagon'), (M.supply.stealTime or 5) * 1000)

CreateThread(function()
    while true do
        local wait = 1000
        if next(wagons) and not cur then
            local ped = PlayerPedId()
            local job = MyJob()
            if Gangs.IsGang(job) and IsPedInAnyVehicle(ped, false) then
                wait = 300
                local veh = GetVehiclePedIsIn(ped, false)
                local netId = NetworkGetEntityIsNetworked(veh) and NetworkGetNetworkIdFromEntity(veh) or nil
                local gang = netId and wagons[netId]
                if gang and gang ~= job then
                    wait = 0
                    Prompts.Show(pSteal, true)
                    Prompts.Active(stealGroup, _L('supply_wagon'))
                    if Prompts.Done(pSteal, true) then
                        TriggerServerEvent('fks-gangs:mission:steal', netId)
                        Wait(2000)
                    end
                end
            end
        end
        Wait(wait)
    end
end)

---------------------------------------------------------------------------
-- 3. Organized heist
---------------------------------------------------------------------------
local customLockpick

-- another script can replace the lockpick minigame: fn() -> true (opened) / false
exports('SetLockpickMinigame', function(fn) customLockpick = fn end)

local function LockpickGame()
    if customLockpick then
        local ok, res = pcall(customLockpick)
        return ok and res == true
    end
    if type(Config.LockpickMinigame) == 'function' then return Config.LockpickMinigame() == true end
    return UI.Minigame('keys', M.heist.lockpick.minigame) == true
end

local function Aggro()
    SetRelationshipBetweenGroups(5, HEIST, PLAYER)
    SetRelationshipBetweenGroups(5, PLAYER, HEIST)
    local me = PlayerPedId()
    for _, ped in ipairs(peds) do
        if DoesEntityExist(ped) and not IsEntityDead(ped) then
            ClearPedTasks(ped)
            TaskCombatPed(ped, me, 0, 16)
        end
    end
end

local chestGroup = Prompts.Group()
local pPick = Prompts.Make(chestGroup, Config.Keys.interact, _L('pick_lock'), true)

local function Heist(m)
    local c = M.heist
    local area = c.areas[m.area]
    blips[#blips + 1] = Blips.Radius(area.chest, 50.0, M.areaStyles.danger, m.label)
    Route(area.chest)
    Track(_L('obj_heist'))

    local my = token
    CreateThread(function()
        local spawned, angry, busy = false, false, false
        while token == my do
            local wait = 1000
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local d = #(pos - area.chest)

            if not spawned and d < 120.0 then
                spawned = true
                SetRelationshipBetweenGroups(3, HEIST, PLAYER)
                for _, e in ipairs(area.enemies) do
                    local g = NewPed(Pick(c.enemies.models), e, true)
                    if g then
                        -- one guard failing to set up never stops the others
                        local ok, err = pcall(function()
                            ArmPed(g, c.enemies)
                            SetPedRelationshipGroupHash(g, HEIST)
                        end)
                        if not ok then print(('[fks-gangs] heist guard setup failed: %s'):format(err)) end
                        pcall(TaskStandGuard, g, e.x, e.y, e.z, e.w, 'WORLD_HUMAN_GUARD_MILITARY')
                    elseif Config.Debug then
                        print(('[fks-gangs] heist guard could not be created at %.1f, %.1f, %.1f'):format(e.x, e.y, e.z))
                    end
                end
                local hash = LoadModel(c.chestModel)
                if hash then
                    local obj = CreateObject(hash, area.chest.x, area.chest.y, area.chest.z, false, false, false, false, false)
                    FreezeEntityPosition(obj, true)
                    -- put it on the ground once the ground is there
                    CreateThread(function()
                        local t = GetGameTimer() + 60000
                        while DoesEntityExist(obj) and GetGameTimer() < t do
                            RequestCollisionAtCoord(area.chest.x, area.chest.y, area.chest.z)
                            if HasCollisionLoadedAroundEntity(obj) then PlaceObjectOnGroundProperly(obj) break end
                            Wait(250)
                        end
                    end)
                    SetModelAsNoLongerNeeded(hash)
                    objects[#objects + 1] = obj
                end
            end

            if spawned then
                wait = 250
                if not angry then
                    local hit = false
                    for _, g in ipairs(peds) do
                        if DoesEntityExist(g) and (IsEntityDead(g) or HasEntityBeenDamagedByAnyPed(g)) then hit = true end
                    end
                    if d <= (c.triggerRadius or 35.0) or hit then
                        angry = true
                        Aggro()
                        Track(_L('obj_heist_fight'))
                    end
                end
                if d <= 2.0 and not busy and CanAct() then
                    wait = 0
                    Prompts.Show(pPick, true)
                    Prompts.Active(chestGroup, _L('chest'))
                    if Prompts.Done(pPick, true) then
                        busy = true
                        local ok, err = lib.callback.await('fks-gangs:mission:lockpickCheck', false)
                        if not ok then
                            Notify(err or _L('error'), 'error')
                        else
                            TaskStartScenarioInPlace(ped, joaat('WORLD_HUMAN_CROUCH_INSPECT'), -1, true, false, false, false)
                            local passed = LockpickGame()
                            ClearPedTasks(ped)
                            local done, msg = lib.callback.await('fks-gangs:mission:lockpick', false, passed)
                            if not done then Notify(msg or _L('error'), 'error') end
                        end
                        Wait(1000)
                        busy = false
                    end
                end
            end
            Wait(wait)
        end
    end)
end

---------------------------------------------------------------------------
-- Start / end
---------------------------------------------------------------------------
RegisterNetEvent('fks-gangs:client:missionStart', function(m)
    Cleanup()
    cur = m
    cur.deadline = GetGameTimer() + (m.seconds or 0) * 1000
    token = {}
    PlaySoundFrontend('INFO', 'HUD_SHOP_SOUNDSET', true, 0)
    if m.id == 'assassin' then Assassin(m)
    elseif m.id == 'supply' then Supply(m)
    elseif m.id == 'heist' then Heist(m) end
end)

RegisterNetEvent('fks-gangs:client:missionEnd', function(success)
    if success then PlaySoundFrontend('PURCHASE', 'Ledger_Sounds', true, 0) end
    Cleanup()
end)

---------------------------------------------------------------------------
-- Police: a blip around the place for a while
---------------------------------------------------------------------------
RegisterNetEvent('fks-gangs:client:policeAlert', function(coords, label, seconds, radius)
    local area = Blips.Radius(coords, radius or 120.0, M.areaStyles.danger, _L('police_blip', label))
    local point = Blips.Point(coords, M.sprites.police, _L('police_blip', label))
    SetTimeout((seconds or 60) * 1000, function()
        Blips.Remove(area)
        Blips.Remove(point)
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    Cleanup()
    PromptDelete(pSteal)
    PromptDelete(pPick)
end)
