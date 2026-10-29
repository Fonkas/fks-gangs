---------------------------------------------------------------------------
-- Territories: capture state, validation and sync. The server decides everything; the client reports the
-- shot that starts a capture, shows the progress bar and spawns the enemies.
--
-- A capture belongs to the player who fired the shot: it is cancelled when that player dies, leaves the
-- area or disconnects.
---------------------------------------------------------------------------
Territories = {}

local S = {}                   -- [id] = { owner, capturedAt, cooldownUntil, capture = {...} | nil }
local gangCooldown = {}        -- [side] = os.time() until which that side cannot start a capture (cooldownScope 'gang')
local shotSpam = {}            -- [src] = os.time() of the last "cannot capture" message

for _, t in ipairs(Config.Territories) do
    S[t.id] = { owner = nil, cooldownUntil = 0 }
end

local function Debug(msg, ...)
    if Config.Debug then print(('[fks-gangs] ' .. msg):format(...)) end
end

local function Notify(src, msg, kind, duration)
    Bridge.Notify(src, { title = _L('territory'), description = msg, type = kind or 'inform', duration = duration })
end

-- what clients get for one territory
local function Public(id)
    local s = S[id]
    local c = s.capture
    return { owner = s.owner, capture = c and { side = c.side, starter = c.starter } or nil }
end

local function Sync(id)
    TriggerClientEvent('fks-gangs:client:territory', -1, id, Public(id))
end

function Territories.Owner(id)
    return S[id] and S[id].owner
end

lib.callback.register('fks-gangs:territories', function()
    local all = {}
    for id in pairs(S) do all[id] = Public(id) end
    return all
end)

-- load owners / cooldowns
CreateThread(function()
    for _, row in ipairs(DB.LoadTerritories()) do
        local s = S[row.id]
        if s then
            -- an owner whose gang was removed from the config goes back to neutral
            s.owner = (row.owner and Gangs.IsGang(row.owner)) and row.owner or nil
            s.capturedAt = row.captured_at
            s.cooldownUntil = tonumber(row.cooldown_until) or 0
        end
    end
    for id in pairs(S) do Sync(id) end
end)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
-- only position + instance: the server cannot read a RedM player's health (it reads 0), so deaths are reported
-- by the starter's client (fks-gangs:server:captureLeft)
local function Inside(src, t)
    if not GetPlayerName(src) or GetPlayerRoutingBucket(src) ~= 0 then return false end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - t.coords) <= t.radius + 5.0   -- a small margin for sync lag
end

local function Save(t)
    local s = S[t.id]
    DB.SaveTerritory(t.id, s.owner, s.capturedAt, s.cooldownUntil)
end

-- seconds left of the cooldown that blocks `side` on `t` (0 = free)
local function CooldownLeft(t, side)
    if side == Gangs.LAW and Config.Police.noCooldown then return 0 end
    local now = os.time()
    if Gangs.Cfg(t, 'cooldownScope') == 'territory' then return math.max(0, S[t.id].cooldownUntil - now) end
    return math.max(0, (gangCooldown[side] or 0) - now)
end

local function StartCooldown(t, side)
    if side == Gangs.LAW and Config.Police.noCooldown then return end
    local untilT = os.time() + math.floor(Gangs.Cfg(t, 'cooldown') * 60)
    if Gangs.Cfg(t, 'cooldownScope') == 'territory' then
        S[t.id].cooldownUntil = untilT
    else
        gangCooldown[side] = untilT
    end
end

local function IsStarter(src)
    for id, s in pairs(S) do
        if s.capture and s.capture.starter == src then return id end
    end
end

---------------------------------------------------------------------------
-- Start: a player of a side that can capture fires a shot inside the area
---------------------------------------------------------------------------
RegisterNetEvent('fks-gangs:server:shot', function(id)
    local src = source
    local t = Gangs.Territory(id)
    if not t or IsStarter(src) then return end
    local P = Bridge.GetPlayer(src)
    if not P then return Debug('shot by %s ignored: no character', src) end
    if not Gangs.CanCapture(t, P.job) then return Debug('shot by %s ignored: job "%s" cannot capture %s', P.name, tostring(P.job), id) end
    if not Inside(src, t) then return Debug('shot by %s ignored: not inside %s', P.name, id) end

    local side = Gangs.Side(P.job)
    local s = S[id]

    if s.capture and s.capture.side == side then return end   -- own side already capturing: nothing to do
    local reason
    if s.capture then
        reason = _L('already_capturing', t.label)
    elseif side ~= Gangs.LAW and s.owner == side then
        reason = _L('already_yours')
    elseif side == Gangs.LAW and not s.owner then
        reason = _L('nothing_to_clean')
    else
        local left = CooldownLeft(t, side)
        if left > 0 then reason = _L('on_cooldown', Gangs.Clock(left)) end
    end
    if reason then
        local now = os.time()
        if (shotSpam[src] or 0) + 10 <= now then
            shotSpam[src] = now
            Notify(src, reason, 'error')
        end
        return
    end

    local capture = {
        side = side, starter = src, starterName = P.name,
        startedAt = os.time(), duration = math.floor(Gangs.Cfg(t, 'duration') * 60),
    }
    s.capture = capture
    Debug('%s (%s) started capturing %s', P.name, Gangs.SideLabel(side), id)

    TriggerClientEvent('fks-gangs:client:captureStart', src, id, capture.duration)
    Notify(src, _L('capture_started'), 'warning', 6000)
    Sync(id)
    TriggerEvent('fks-gangs:captureStarted', id, side, src)

    -- general alert a few seconds later (if the capture is still going)
    SetTimeout(math.max(0, Gangs.Cfg(t, 'alertDelay') or 0) * 1000, function()
        if s.capture ~= capture then return end
        local msg = side == Gangs.LAW and _L('announce_start_law') or _L('announce_start')
        Bridge.Notify(-1, { title = _L('alert_title'), description = msg, type = 'warning', duration = 10000 })
    end)
end)

---------------------------------------------------------------------------
-- End
---------------------------------------------------------------------------
local function Cancel(t, why)
    local s = S[t.id]
    local c = s.capture
    if not c then return end
    s.capture = nil
    StartCooldown(t, c.side)
    Save(t)
    Debug('capture of %s by %s cancelled (%s)', t.id, Gangs.SideLabel(c.side), why)

    if GetPlayerName(c.starter) then
        TriggerClientEvent('fks-gangs:client:captureStop', c.starter, t.id, false)
        local mins = Gangs.Cfg(t, 'cooldown')
        local noCd = c.side == Gangs.LAW and Config.Police.noCooldown
        Notify(c.starter, noCd and _L('capture_cancelled_nocd') or _L('capture_cancelled', mins), 'error', 6000)
    end
    Sync(t.id)
    TriggerEvent('fks-gangs:captureFailed', t.id, c.side, why)
end

local function Complete(t)
    local s = S[t.id]
    local c = s.capture
    if not c then return end
    s.capture = nil
    local law = c.side == Gangs.LAW

    s.owner = (not law) and c.side or nil     -- the law leaves it neutral
    s.capturedAt = os.time()
    StartCooldown(t, c.side)
    Save(t)
    if not law then Rep.Add(c.side, 'capture') end
    Debug('%s captured by %s', t.id, Gangs.SideLabel(c.side))

    if GetPlayerName(c.starter) then
        TriggerClientEvent('fks-gangs:client:captureStop', c.starter, t.id, true)
        local reward = Config.Police.reward or {}
        local amount = law and math.random(reward.min or 0, math.max(reward.min or 0, reward.max or 0)) or 0
        local P = amount > 0 and Bridge.GetPlayer(c.starter)
        if P then
            P.add('cash', amount, 'fks-gangs territory cleaned')
            Notify(c.starter, _L('cleaned_reward', Gangs.Fmt(amount)), 'success', 6000)
        else
            Notify(c.starter, law and _L('cleaned') or _L('captured'), 'success', 6000)
        end
    end

    if Gangs.Cfg(t, 'announceEnd') then
        local msg = law and _L('announce_cleaned') or _L('announce_captured')
        Bridge.Notify(-1, { title = _L('alert_title'), description = msg, type = 'inform', duration = 8000 })
    end
    Sync(t.id)
    TriggerEvent('fks-gangs:territoryCaptured', t.id, s.owner, c.side, c.starter)
end

-- capture loop: the starter must stay alive and inside until the time is up
CreateThread(function()
    while true do
        Wait(1000)
        local now = os.time()
        for _, t in ipairs(Config.Territories) do
            local c = S[t.id].capture
            if c then
                if not GetPlayerName(c.starter) then
                    Cancel(t, 'disconnected')
                elseif not Inside(c.starter, t) then
                    Cancel(t, 'left or died')
                elseif now - c.startedAt >= c.duration then
                    Complete(t)
                end
            end
        end
    end
end)

-- the starter's client saw them die / leave first (the loop above would catch it a moment later anyway)
-- (only the starter can cancel their own capture this way, so it is safe to trust)
RegisterNetEvent('fks-gangs:server:captureLeft', function(id)
    local t = Gangs.Territory(id)
    local c = t and S[id].capture
    if c and c.starter == source then Cancel(t, 'left or died') end
end)

AddEventHandler('playerDropped', function()
    shotSpam[source] = nil
end)

---------------------------------------------------------------------------
-- Admin: /territoryreset <id> - removes the owner and the cooldowns (and stops a capture)
---------------------------------------------------------------------------
Bridge.RegisterAdminCommand('territoryreset', _L('cmd_territory_reset'), { { name = 'id', help = 'territory id' } }, function(src, args)
    local t = Gangs.Territory(args[1] or '')
    if not t then
        if src > 0 then Notify(src, _L('unknown_territory'), 'error') else print('[fks-gangs] unknown territory') end
        return
    end
    local s = S[t.id]
    if s.capture and GetPlayerName(s.capture.starter) then
        TriggerClientEvent('fks-gangs:client:captureStop', s.capture.starter, t.id, false)
    end
    s.capture, s.owner, s.capturedAt, s.cooldownUntil = nil, nil, nil, 0
    gangCooldown = {}
    Save(t)
    Sync(t.id)
    if src > 0 then Notify(src, _L('territory_reset', t.label), 'success') end
end)

exports('GetTerritoryOwner', Territories.Owner)
exports('IsTerritoryBeingCaptured', function(id) return S[id] and S[id].capture ~= nil end)
