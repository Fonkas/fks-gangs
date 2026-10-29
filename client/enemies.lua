---------------------------------------------------------------------------
-- Armed enemies during a capture. They are spawned by the client of the player who started the capture
-- (networked, so everyone sees them), come in waves and attack that player. Settings: Config.Enemies,
-- per territory `enemies = { ... }` / `spawnPoints = { ... }`.
---------------------------------------------------------------------------
Enemies = {}

local alive = {}          -- peds of the current capture
local running             -- token of the current capture (a new Start / Stop invalidates the old loop)
local GROUP = joaat('FKS_GANGS_ENEMIES')

AddRelationshipGroup('FKS_GANGS_ENEMIES')
SetRelationshipBetweenGroups(5, GROUP, joaat('PLAYER'))
SetRelationshipBetweenGroups(5, joaat('PLAYER'), GROUP)

local function Pick(list) return list[math.random(#list)] end

local function Range(r, fallback)
    if type(r) ~= 'table' then return tonumber(r) or fallback end
    local lo, hi = tonumber(r.min) or fallback, tonumber(r.max) or tonumber(r.min) or fallback
    if hi < lo then lo, hi = hi, lo end
    return math.random(math.floor(lo), math.floor(hi))
end

local function SellerPos(t)
    local c = t.shop and t.shop.npc and t.shop.npc.coords
    return c and vector3(c.x, c.y, c.z)
end

local function FarFromSeller(t, pos)
    local s = SellerPos(t)
    return not s or #(pos - s) >= (Gangs.EnemyCfg(t, 'sellerSafe') or 0)
end

-- a spawn spot: one of the territory's spawnPoints, else a random spot on the ground around the player
local function SpawnPos(t, me)
    local points = t.spawnPoints or {}
    if #points > 0 then
        for _ = 1, 10 do
            local p = Pick(points)
            if FarFromSeller(t, p) then return p end
        end
        return points[1]
    end

    local minD, maxD = Gangs.EnemyCfg(t, 'minDistance') or 25.0, Gangs.EnemyCfg(t, 'maxDistance') or 60.0
    for _ = 1, 15 do
        local a = math.random() * 2 * math.pi
        local d = minD + math.random() * (maxD - minD)
        local x, y = me.x + math.cos(a) * d, me.y + math.sin(a) * d
        local pos = vector3(x, y, me.z)
        if #(pos - t.coords) <= t.radius and FarFromSeller(t, pos) then
            local found, z = GetGroundZFor_3dCoord(x, y, me.z + 50.0, false)
            if found and math.abs(z - me.z) < 15.0 then return vector3(x, y, z) end
        end
    end
    return nil
end

local function SpawnOne(t, target)
    local me = GetEntityCoords(target)
    local pos = SpawnPos(t, me)
    if not pos then return end

    local hash = LoadModel(Pick(Gangs.EnemyCfg(t, 'models')))
    if not hash then return end
    local ped = CreatePed(hash, pos.x, pos.y, pos.z, 0.0, true, true, false, false)
    local timeout = GetGameTimer() + 1000
    while not DoesEntityExist(ped) and GetGameTimer() < timeout do Wait(10) end
    SetModelAsNoLongerNeeded(hash)
    if not DoesEntityExist(ped) then return end

    PedOutfit(ped)
    SetEntityAsMissionEntity(ped, true, true)
    SetPedRelationshipGroupHash(ped, GROUP)

    local hp = Gangs.EnemyCfg(t, 'health')
    if hp then SetEntityMaxHealth(ped, hp) SetEntityHealth(ped, hp) end
    SetPedAccuracy(ped, Gangs.EnemyCfg(t, 'accuracy') or 35)
    SetPedCombatAbility(ped, 2)
    SetPedCombatRange(ped, 2)
    SetPedCombatMovement(ped, 2)
    SetPedCombatAttributes(ped, 46, true)                   -- always fight
    SetPedCombatAttributes(ped, 5, true)                    -- fight armed peds when not armed
    SetPedFleeAttributes(ped, 0, false)
    SetPedKeepTask(ped, true)

    local weapon = joaat(Pick(Gangs.EnemyCfg(t, 'weapons')))
    GiveWeaponToPed(ped, weapon, 200, false, true)
    SetCurrentPedWeapon(ped, weapon, true)

    if Gangs.EnemyCfg(t, 'blip') then
        Citizen.InvokeNative(0x23F74C2FDA6E7C61, Gangs.EnemyCfg(t, 'blipStyle'), ped)  -- BlipAddForEntity
    end

    TaskCombatPed(ped, target, 0, 16)
    alive[#alive + 1] = ped
end

local function Clean()
    for i = #alive, 1, -1 do
        local ped = alive[i]
        if not DoesEntityExist(ped) or IsEntityDead(ped) then
            if DoesEntityExist(ped) then SetEntityAsNoLongerNeeded(ped) end
            table.remove(alive, i)
        end
    end
end

local function Wave(t)
    local target = PlayerPedId()
    local n = Range(Gangs.EnemyCfg(t, 'perWave'), 1)
    local max = Gangs.EnemyCfg(t, 'max') or 4
    for _ = 1, n do
        Clean()
        if #alive >= max then break end
        SpawnOne(t, target)
        Wait(150)
    end
end

function Enemies.Start(t)
    Enemies.Stop()
    if not Gangs.EnemyCfg(t, 'models') then return end   -- enemies disabled for this territory
    local token = {}
    running = token

    -- waves
    CreateThread(function()
        local nextWave = 0
        while running == token do
            if GetGameTimer() >= nextWave then
                Wave(t)
                nextWave = GetGameTimer() + Range(Gangs.EnemyCfg(t, 'interval'), 30) * 1000
            end
            Wait(1000)
        end
    end)

    -- keep them on the player (re-arm / re-task / replace the ones that fell under the map)
    CreateThread(function()
        while running == token do
            Wait(2000)
            Clean()
            local me = PlayerPedId()
            local myPos = GetEntityCoords(me)
            for i = #alive, 1, -1 do
                local ped = alive[i]
                local pos = GetEntityCoords(ped)
                if myPos.z - pos.z > 15.0 then
                    DeleteEntity(ped)
                    table.remove(alive, i)
                elseif not IsPedInCombat(ped, me) or #(pos - myPos) > 60.0 then
                    TaskCombatPed(ped, me, 0, 16)
                end
            end
        end
    end)
end

-- removes the enemies still alive (dead bodies are left to the game)
function Enemies.Stop()
    running = nil
    for _, ped in ipairs(alive) do
        if DoesEntityExist(ped) then
            if IsEntityDead(ped) then SetEntityAsNoLongerNeeded(ped) else DeleteEntity(ped) end
        end
    end
    alive = {}
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then Enemies.Stop() end
end)
