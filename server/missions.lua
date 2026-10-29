---------------------------------------------------------------------------
-- Contracts (config/missions.lua): started from the ledger, one per player, cooldown per gang + contract.
-- The server picks the place, keeps the time, checks the end and pays; the client spawns the target /
-- wagon / guards and reports what happened.
---------------------------------------------------------------------------
Missions = {}

local M = Config.Missions
local KINDS = { 'assassin', 'supply', 'heist' }
local active = {}        -- [src] = { id, gang, startedAt, deadline, ... }
local cooldowns = {}     -- ["gang:id"] = os.time() until which the gang cannot take it again
local wagons = {}        -- [netId] = { holder = src, gang } (supply runs on the road)

local function Notify(src, msg, kind, duration)
    Bridge.Notify(src, { title = _L('contracts'), description = msg, type = kind or 'inform', duration = duration })
end

local function Enabled(id)
    local c = M[id]
    return M.enabled and c ~= nil and c.enabled ~= false
end

local function Pick(list) return list[math.random(#list)] end

local function CooldownLeft(gang, id)
    return math.max(0, (cooldowns[(gang or '?') .. ':' .. id] or 0) - os.time())
end

local function Bonus(gang) return Rep.Perk(gang, 'missionBonus') end

local function SyncWagons()
    local list = {}
    for netId, w in pairs(wagons) do list[#list + 1] = { netId = netId, gang = w.gang } end
    TriggerClientEvent('fks-gangs:client:wagons', -1, list)
end

local function Entity(netId)
    local e = netId and NetworkGetEntityFromNetworkId(netId) or 0
    if e ~= 0 and DoesEntityExist(e) then return e end
end

local function PedPos(src)
    local ped = GetPlayerPed(src)
    return ped and ped ~= 0 and GetEntityCoords(ped) or nil
end

---------------------------------------------------------------------------
-- Police
---------------------------------------------------------------------------
local function PoliceAlert(id, coords)
    local c = M[id]
    local on = c.policeAlert
    if on == nil then on = M.policeAlert end
    if not on or not coords then return end
    for _, pid in ipairs(GetPlayers()) do
        local src = tonumber(pid)
        local P = Bridge.GetPlayer(src)
        if P and Gangs.IsLaw(P.job) then
            Bridge.Notify(src, { title = _L('police_alert_title'), description = _L('police_alert', c.label), type = 'warning', duration = 10000 })
            if (M.alertBlip or 0) > 0 then
                TriggerClientEvent('fks-gangs:client:policeAlert', src, vector3(coords.x, coords.y, coords.z), c.label, M.alertBlip, M.alertRadius)
            end
        end
    end
end

---------------------------------------------------------------------------
-- End
---------------------------------------------------------------------------
local function DropWagon(m)
    if not m or not m.netId then return end
    local e = Entity(m.netId)
    if e then DeleteEntity(e) end
    wagons[m.netId] = nil
    SyncWagons()
end

local function Fail(src, reason, keepWagon)
    local m = active[src]
    if not m then return end
    active[src] = nil
    if not keepWagon then DropWagon(m) end
    if GetPlayerName(src) then
        TriggerClientEvent('fks-gangs:client:missionEnd', src, false)
        Notify(src, _L('mission_fail_' .. reason), 'error', 8000)
    end
    TriggerEvent('fks-gangs:missionFailed', src, m.id, reason)
end

local function Pay(src, P, m, amount)
    if amount <= 0 then return '' end
    amount = math.floor(amount * (1 + Bonus(m.gang)) + 0.5)
    local h = M.payTo == 'ledger' and Gang.Of(P)
    if h then
        Gang.LedgerAdd(h.id, amount, P.name, 'mission')
        return _L('paid_ledger', Gangs.Fmt(amount))
    end
    P.add('cash', amount, 'fks-gangs contract')
    return _L('paid', Gangs.Fmt(amount))
end

local function Complete(src)
    local m = active[src]
    local P = Bridge.GetPlayer(src)
    if not m or not P then return end
    active[src] = nil
    local c = M[m.id]
    for _, it in ipairs(c.items or {}) do Bridge.AddItem(src, it.item, it.amount) end
    local paid = Pay(src, P, m, c.reward or 0)
    Rep.Add(m.gang, 'mission', c.rep)
    TriggerClientEvent('fks-gangs:client:missionEnd', src, true)
    Notify(src, _L('mission_done', c.label, paid), 'success', 8000)
    TriggerEvent('fks-gangs:missionDone', src, m.id, m.gang)
end

---------------------------------------------------------------------------
-- The board (ledger tab "Contracts")
---------------------------------------------------------------------------
function Missions.Board(src, ctx)
    local list = {}
    local mine = active[src]
    for _, id in ipairs(KINDS) do
        if Enabled(id) then
            local c = M[id]
            local items = {}
            for _, it in ipairs(c.items or {}) do items[#items + 1] = { amount = it.amount, label = Bridge.ItemLabel(it.item) } end
            list[#list + 1] = {
                id = id, label = c.label, desc = c.desc, icon = c.icon,
                reward = math.floor((c.reward or 0) * (1 + Bonus(ctx.h.gang)) + 0.5), items = items,
                rep = c.rep or Config.Reputation.points.mission, timeLimit = c.timeLimit,
                cooldown = CooldownLeft(ctx.h.gang or ctx.P.job, id),
                active = mine ~= nil and mine.id == id, busy = mine ~= nil,
            }
        end
    end
    return list
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
lib.callback.register('fks-gangs:mission:start', function(src, id)
    local ctx, err = Gang.Inside(src, 'missions')
    if not ctx then return false, err end
    if not Enabled(id) then return false, _L('error') end
    if active[src] then return false, _L('mission_busy') end
    local gang = ctx.h.gang or ctx.P.job
    local left = CooldownLeft(gang, id)
    if left > 0 then return false, _L('mission_cooldown', Gangs.Clock(left)) end

    local c = M[id]
    local now = os.time()
    local m = { id = id, gang = gang, startedAt = now, deadline = now + math.floor((c.timeLimit or 30) * 60) }
    local payload = { id = id, label = c.label, seconds = m.deadline - now }
    local alertAt

    if id == 'assassin' then
        m.loc = Pick(c.locations)
        payload.loc = m.loc
        payload.model = Pick(c.models)
        payload.scenario = Pick(c.scenarios)
        -- the area on the map is not centred on the target
        local a, d = math.random() * 2 * math.pi, math.random() * (c.areaRadius or 60.0) * 0.6
        payload.area = vector3(m.loc.x + math.cos(a) * d, m.loc.y + math.sin(a) * d, m.loc.z)
        alertAt = payload.area
    elseif id == 'supply' then
        m.stage = 'pickup'
        m.deadline = now + math.floor((c.spawnWithin or 10) * 60)
        payload.stage, payload.seconds = 'pickup', m.deadline - now
    elseif id == 'heist' then
        m.area = math.random(#c.areas)
        payload.area = m.area
        alertAt = c.areas[m.area].chest
    end

    active[src] = m
    cooldowns[gang .. ':' .. id] = now + math.floor((M.cooldown or 15) * 60)
    TriggerClientEvent('fks-gangs:client:missionStart', src, payload)
    if alertAt then PoliceAlert(id, alertAt) end
    TriggerEvent('fks-gangs:missionStarted', src, id, gang)
    return true, _L('mission_started', c.label)
end)

lib.callback.register('fks-gangs:mission:abandon', function(src)
    if not active[src] then return false, _L('error') end
    Fail(src, 'abandon')
    return true, _L('mission_abandoned')
end)

-- the client reports a failure of its own contract (spotted, target ran away...): only ends it
RegisterNetEvent('fks-gangs:mission:fail', function(reason)
    local ok = { spotted = true, escaped = true, target_dead = true, wagon_lost = true }
    Fail(source, ok[reason] and reason or 'abandon')
end)

---------------------------------------------------------------------------
-- 1. Hitman
---------------------------------------------------------------------------
RegisterNetEvent('fks-gangs:mission:assassinDone', function()
    local src = source
    local m = active[src]
    if not m or m.id ~= 'assassin' then return end
    local pos = PedPos(src)
    if not pos or #(pos - m.loc.xyz) > 200.0 or os.time() - m.startedAt < 10 then return end
    Complete(src)
end)

---------------------------------------------------------------------------
-- 2. Supply run
---------------------------------------------------------------------------
lib.callback.register('fks-gangs:mission:canSpawnWagon', function(src)
    local m = active[src]
    if not m or m.id ~= 'supply' then return false, _L('no_supply_contract') end
    if m.stage ~= 'pickup' then return false, _L('wagon_already') end
    if GetPlayerRoutingBucket(src) ~= 0 then return false, _L('wagon_outside') end
    return true, M.supply.model
end)

RegisterNetEvent('fks-gangs:mission:wagonSpawned', function(netId)
    local src = source
    local m = active[src]
    local c = M.supply
    if not m or m.id ~= 'supply' or m.stage ~= 'pickup' or m.spawning then return end
    m.spawning = true

    -- a wagon the client just created takes a moment to reach the server (and to get its real position)
    local e, pos
    for _ = 1, 50 do
        e, pos = Entity(netId), PedPos(src)
        if e and pos and #(GetEntityCoords(e) - pos) <= 40.0 then break end
        e = nil
        Wait(100)
    end
    m.spawning = nil
    if active[src] ~= m then return end
    if not e then
        local bad = Entity(netId)
        if bad then DeleteEntity(bad) end
        return Notify(src, _L('wagon_failed', c.command), 'error')
    end

    local now = os.time()
    m.stage, m.netId = 'deliver', netId
    m.dest = Pick(c.destinations)
    m.deadline = now + math.floor((c.timeLimit or 30) * 60)
    wagons[netId] = { holder = src, gang = m.gang }
    SyncWagons()
    TriggerClientEvent('fks-gangs:client:missionUpdate', src, { stage = 'deliver', dest = m.dest, netId = netId, seconds = m.deadline - now })
    PoliceAlert('supply', pos)
end)

RegisterNetEvent('fks-gangs:mission:steal', function(netId)
    local thief = source
    local w = wagons[netId]
    local T = Bridge.GetPlayer(thief)
    if not w or not T or not Gangs.IsGang(T.job) or T.job == w.gang then return end
    if active[thief] then return Notify(thief, _L('mission_busy'), 'error') end
    local e = Entity(netId)
    local pos = PedPos(thief)
    if not e or not pos or #(GetEntityCoords(e) - pos) > 6.0 then return end

    local old = active[w.holder]
    if not old or old.netId ~= netId then return end
    active[w.holder] = nil
    if GetPlayerName(w.holder) then
        TriggerClientEvent('fks-gangs:client:missionEnd', w.holder, false)
        Notify(w.holder, _L('mission_fail_stolen'), 'error', 10000)
    end

    active[thief] = {
        id = 'supply', gang = T.job, stage = 'deliver', netId = netId, dest = old.dest,
        startedAt = old.startedAt, deadline = old.deadline, stolen = true,
    }
    wagons[netId] = { holder = thief, gang = T.job }
    SyncWagons()
    TriggerClientEvent('fks-gangs:client:missionStart', thief, {
        id = 'supply', label = M.supply.label, stage = 'deliver', dest = old.dest, netId = netId,
        seconds = math.max(0, old.deadline - os.time()), stolen = true,
    })
    Notify(thief, _L('wagon_stolen'), 'success', 8000)
end)

RegisterNetEvent('fks-gangs:mission:deliver', function()
    local src = source
    local m = active[src]
    if not m or m.id ~= 'supply' or m.stage ~= 'deliver' then return end
    local e = Entity(m.netId)
    if not e then return Fail(src, 'wagon_lost') end
    if #(GetEntityCoords(e) - m.dest) > (M.supply.deliverRadius or 10.0) + 5.0 then return end
    DropWagon(m)
    Complete(src)
end)

---------------------------------------------------------------------------
-- 3. Organized heist
---------------------------------------------------------------------------
local function AtChest(src)
    local m = active[src]
    if not m or m.id ~= 'heist' then return nil end
    local pos = PedPos(src)
    local chest = M.heist.areas[m.area].chest
    if not pos or #(pos - chest) > 3.5 then return nil end
    return m
end

lib.callback.register('fks-gangs:mission:lockpickCheck', function(src)
    if not AtChest(src) then return false, _L('too_far') end
    local item = M.heist.lockpick.item
    if Bridge.ItemCount(src, item) < 1 then return false, _L('need_lockpick', Bridge.ItemLabel(item)) end
    return true
end)

lib.callback.register('fks-gangs:mission:lockpick', function(src, passed)
    if not AtChest(src) then return false, _L('too_far') end
    local L = M.heist.lockpick
    if Bridge.ItemCount(src, L.item) < 1 then return false, _L('need_lockpick', Bridge.ItemLabel(L.item)) end
    if not passed then
        if math.random(100) <= (L.breakChance or 0) then
            Bridge.RemoveItem(src, L.item, 1)
            return false, _L('lockpick_broke')
        end
        return false, _L('lockpick_failed')
    end
    if L.consume then Bridge.RemoveItem(src, L.item, 1) end
    Complete(src)
    return true
end)

---------------------------------------------------------------------------
-- Time limits, lost wagons, players leaving
---------------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(1000)
        local now = os.time()
        for src, m in pairs(active) do
            if not GetPlayerName(src) then
                Fail(src, 'abandon')
            elseif now >= m.deadline then
                Fail(src, 'time')
            elseif m.netId and not Entity(m.netId) then
                Fail(src, 'wagon_lost')
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    if active[source] then Fail(source, 'abandon') end
end)

-- new players see the wagons on the road
lib.callback.register('fks-gangs:mission:wagons', function()
    local list = {}
    for netId, w in pairs(wagons) do list[#list + 1] = { netId = netId, gang = w.gang } end
    return list
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for netId in pairs(wagons) do
        local e = Entity(netId)
        if e then DeleteEntity(e) end
    end
end)

exports('GetActiveMission', function(src) return active[src] and active[src].id end)
