---------------------------------------------------------------------------
-- Reputation of every gang (job): points from kills in territories, captures and contracts, a tier with
-- perks (Config.Reputation) and the decay that makes a gang keep it up.
---------------------------------------------------------------------------
Rep = {}

local R = Config.Reputation
local data = {}          -- [gang] = { points, kills, captures, missions, decayedAt }
local killPairs = {}     -- ["killer:victim"] = os.time() of the last kill that counted

local function Get(gang)
    local r = data[gang]
    if not r then
        r = { points = 0, kills = 0, captures = 0, missions = 0, decayedAt = os.time() }
        data[gang] = r
    end
    return r
end

CreateThread(function()
    for _, row in ipairs(DB.LoadReputation()) do
        data[row.gang] = {
            points = tonumber(row.points) or 0, kills = tonumber(row.kills) or 0, captures = tonumber(row.captures) or 0,
            missions = tonumber(row.missions) or 0, decayedAt = tonumber(row.decayed_at) or os.time(),
        }
    end
end)

-- tier index, tier, next tier (nil at the top)
function Rep.Tier(gang)
    local points = gang and Get(gang).points or 0
    local idx = 1
    for i, t in ipairs(R.tiers) do
        if points >= (t.min or 0) then idx = i end
    end
    return idx, R.tiers[idx], R.tiers[idx + 1]
end

-- perk of the gang's tier: craftTime (multiplier, 1 = none), shopBonus / missionBonus (0 = none)
function Rep.Perk(gang, name)
    local default = name == 'craftTime' and 1.0 or 0.0
    if not R.enabled or not gang then return default end
    local _, tier = Rep.Tier(gang)
    local v = tier and tier.perks and tier.perks[name]
    return tonumber(v) or default
end

-- kind: 'kill' | 'capture' | 'mission'; points = nil -> Config.Reputation.points[kind]
function Rep.Add(gang, kind, points)
    if not R.enabled or not Gangs.IsGang(gang) then return end
    local r = Get(gang)
    points = math.floor(tonumber(points) or R.points[kind] or 0)
    r.points = math.max(0, r.points + points)
    if kind == 'kill' then r.kills = r.kills + 1
    elseif kind == 'capture' then r.captures = r.captures + 1
    elseif kind == 'mission' then r.missions = r.missions + 1 end
    DB.SaveReputation(gang, r)
    TriggerEvent('fks-gangs:reputationChanged', gang, r.points, kind, points)
end

-- what the ledger shows
function Rep.Public(gang)
    local r = gang and Get(gang) or { points = 0, kills = 0, captures = 0, missions = 0 }
    local idx, tier, nextTier = Rep.Tier(gang)
    return {
        enabled = R.enabled, points = r.points, kills = r.kills, captures = r.captures, missions = r.missions,
        tier = idx, label = tier.label, min = tier.min or 0, perks = tier.perks or {},
        next = nextTier and { label = nextTier.label, min = nextTier.min, perks = nextTier.perks or {} } or nil,
        tiers = #R.tiers,
    }
end

---------------------------------------------------------------------------
-- Kills inside territories: reported by the victim's client (who killed me), checked here
---------------------------------------------------------------------------
local function InTerritory(src)
    if GetPlayerRoutingBucket(src) ~= 0 then return nil end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local pos = GetEntityCoords(ped)
    for _, t in ipairs(Config.Territories) do
        if #(pos - t.coords) <= t.radius + 10.0 then return t end
    end
end

RegisterNetEvent('fks-gangs:server:killedBy', function(killer)
    local victim = source
    killer = tonumber(killer)
    if not R.enabled or not killer or killer == victim or not GetPlayerName(killer) then return end
    local K, V = Bridge.GetPlayer(killer), Bridge.GetPlayer(victim)
    if not K or not V or not Gangs.IsGang(K.job) or K.job == V.job then return end
    if not InTerritory(victim) or not InTerritory(killer) then return end

    local key = ('%s:%s'):format(K.cid, V.cid)
    local now = os.time()
    if (killPairs[key] or 0) + (R.killCooldown or 0) > now then return end
    killPairs[key] = now
    Rep.Add(K.job, 'kill')
end)

---------------------------------------------------------------------------
-- Decay
---------------------------------------------------------------------------
CreateThread(function()
    local d = R.decay or {}
    if not R.enabled or not d.enabled then return end
    while true do
        Wait(10 * 60000)
        local now, every = os.time(), math.max(1, (d.everyHours or 24) * 3600)
        for gang, r in pairs(data) do
            if now - (r.decayedAt or now) >= every then
                r.decayedAt = now
                if r.points > 0 then r.points = math.max(0, r.points - (d.amount or 0)) end
                DB.SaveReputation(gang, r)
            end
        end
    end
end)

exports('GetReputation', function(gang) return gang and Get(gang).points or 0 end)
exports('AddReputation', function(gang, points) Rep.Add(gang, 'other', points) end)
