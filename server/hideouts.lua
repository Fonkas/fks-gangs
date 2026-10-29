---------------------------------------------------------------------------
-- Gang hideouts: created by admins, bought by players, each one its own instance (routing bucket).
---------------------------------------------------------------------------
if not Config.Hideouts.enabled then return end

local C = Config.Hideouts
local H = {}          -- [id] = { id, name, coords = vector4, interior, price, currency, owner, ownerName, gang, forGang, meta }
local inside = {}     -- [src] = hideout id
local knocks = {}     -- [hideoutId] = { src, name, at }
local knockSpam = {}  -- [src] = os.time()

local function Notify(src, msg, kind)
    Bridge.Notify(src, { title = _L('hideout'), description = msg, type = kind or 'inform' })
end

local function Bucket(id) return C.bucketOffset + id end

local function Row(r)
    local ok, c = pcall(json.decode, r.coords)
    if not ok or type(c) ~= 'table' then return nil end
    local okM, meta = pcall(json.decode, r.meta or '{}')
    meta = okM and type(meta) == 'table' and meta or {}
    local h = {
        id = r.id, name = r.name, coords = vector4(c.x, c.y, c.z, c.w or 0.0),
        interior = Config.Interiors[r.interior] and r.interior or Config.DefaultInterior,
        price = tonumber(r.price) or 0, currency = r.currency == 'gold' and 'gold' or 'cash',
        owner = r.owner, ownerName = r.owner_name, gang = r.gang, forGang = meta.forGang, meta = meta,
    }
    if h.owner then Gang.FixMeta(h) end
    return h
end

local function Changed()
    TriggerClientEvent('fks-gangs:client:hideoutsChanged', -1)
end

-- owner, hired members, and (memberAccess) everyone with the gang's job
local function Access(P, h)
    if not P or not h.owner then return false end
    if P.cid == h.owner or Gang.IsMember(P.cid, h.id) then return true end
    return C.memberAccess and h.gang ~= nil and P.job == h.gang
end

local function NearDoor(src, h, dist)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or GetPlayerRoutingBucket(src) ~= 0 then return false end
    return #(GetEntityCoords(ped) - h.coords.xyz) <= (dist or Config.InteractDistance + 2.0)
end

local function Insiders(id)
    local list = {}
    for src, hid in pairs(inside) do
        if hid == id then list[#list + 1] = src end
    end
    return list
end

local function PutInside(src, h)
    SetPlayerRoutingBucket(src, Bucket(h.id))
    inside[src] = h.id
end

-- the stash / crafting bench moved: everyone inside sees it at once
local function PropsChanged(h)
    local props = { stash = h.meta and h.meta.stash, craft = h.meta and h.meta.craft }
    for _, s in ipairs(Insiders(h.id)) do TriggerClientEvent('fks-gangs:client:hideoutProps', s, h.id, props) end
end

Hideouts = {
    H = H, loaded = false, Changed = Changed, PropsChanged = PropsChanged,
    Inside = function(src) return inside[src] end,
}

-- back to the normal world, at the door
local function PutOutside(src, h)
    inside[src] = nil
    SetPlayerRoutingBucket(src, 0)
    TriggerClientEvent('fks-gangs:client:leaveHideout', src, h and h.coords or nil)
end

---------------------------------------------------------------------------
-- Load
---------------------------------------------------------------------------
CreateThread(function()
    for _, r in ipairs(DB.LoadHideouts()) do
        local h = Row(r)
        if h then
            H[h.id] = h
            SetRoutingBucketPopulationEnabled(Bucket(h.id), false)
        end
    end
    -- resource restarted with players inside: they keep their bucket, so they are still inside
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local hid = GetPlayerRoutingBucket(src) - C.bucketOffset
        if H[hid] then inside[src] = hid end
    end
    Hideouts.loaded = true
    Changed()
end)

-- list for one player (with what they can do at each door)
lib.callback.register('fks-gangs:hideouts', function(src)
    local P = Bridge.GetPlayer(src)
    local list = {}
    for _, h in pairs(H) do
        list[#list + 1] = {
            id = h.id, name = h.name, coords = h.coords, interior = h.interior,
            price = h.price, currency = h.currency, owned = h.owner ~= nil, ownerName = h.ownerName,
            mine = P ~= nil and h.owner == P.cid, access = Access(P, h),
            gangMember = P ~= nil and h.owner ~= nil and ((h.gang ~= nil and P.job == h.gang) or Gang.IsMember(P.cid, h.id)),
            forGang = h.forGang and Gangs.SideLabel(h.forGang) or nil,
        }
    end
    return list, inside[src]
end)

---------------------------------------------------------------------------
-- Admin: create / delete / reset
---------------------------------------------------------------------------
Bridge.RegisterAdminCommand(C.createCommand, _L('cmd_create'), {}, function(src)
    if src == 0 then return print('[fks-gangs] use this command in game') end
    if GetPlayerRoutingBucket(src) ~= 0 then return Notify(src, _L('not_here'), 'error') end
    TriggerClientEvent('fks-gangs:client:createHideout', src)
end)

lib.callback.register('fks-gangs:hideout:create', function(src, data)
    if not Bridge.IsAdmin(src) or type(data) ~= 'table' then return false end
    local name = tostring(data.name or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, 60)
    local price = math.floor(tonumber(data.price) or -1)
    local currency = data.currency == 'gold' and 'gold' or 'cash'
    local interior = Config.Interiors[data.interior] and data.interior or Config.DefaultInterior
    local forGang = Gangs.IsGang(data.gang) and data.gang or nil
    if name == '' then return false, _L('invalid_name') end
    if price < 0 then return false, _L('invalid_price') end

    local ped = GetPlayerPed(src)
    local pos = GetEntityCoords(ped)
    local c = { x = pos.x, y = pos.y, z = pos.z, w = GetEntityHeading(ped) }
    local id = DB.CreateHideout(name, json.encode(c), interior, price, currency)
    if not id then return false, _L('error') end

    H[id] = { id = id, name = name, coords = vector4(c.x, c.y, c.z, c.w), interior = interior, price = price, currency = currency,
              forGang = forGang, meta = { forGang = forGang } }
    DB.SaveHideoutMeta(id, H[id].meta)
    SetRoutingBucketPopulationEnabled(Bucket(id), false)
    print(('[fks-gangs] %s created hideout #%d "%s" (%s %s, %s)'):format(GetPlayerName(src), id, name, price, currency, interior))
    Changed()
    return true, _L('created', name)
end)

local function Nearest(src, maxDist)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local pos = GetEntityCoords(ped)
    local best, bestD
    for _, h in pairs(H) do
        local d = #(pos - h.coords.xyz)
        if d <= maxDist and (not bestD or d < bestD) then best, bestD = h, d end
    end
    return best
end

local function EmptyIt(h)
    for _, s in ipairs(Insiders(h.id)) do PutOutside(s, h) end
    knocks[h.id] = nil
end

-- gone for good (everyone inside goes out, the gang and its stash are removed)
function Hideouts.Delete(h)
    EmptyIt(h)
    if h.owner then Gang.Disband(h) end
    H[h.id] = nil
    DB.DeleteHideout(h.id)
    Changed()
end

-- back on sale
function Hideouts.Reset(h)
    EmptyIt(h)
    Gang.Disband(h)
    h.meta = { forGang = h.forGang }
    DB.SaveHideoutMeta(h.id, h.meta)
    h.owner, h.ownerName, h.gang = nil, nil, nil
    DB.SetHideoutOwner(h.id, nil, nil, nil)
    Changed()
end

-- a new owner (bought / given by an admin): a fresh gang with them as the boss
function Hideouts.SetOwner(h, src, P)
    h.owner, h.ownerName = P.cid, P.name
    h.gang = Gangs.IsGang(P.job) and P.job or nil
    DB.SetHideoutOwner(h.id, h.owner, h.ownerName, h.gang)
    Gang.Init(h, P)
    h.meta.forGang = h.forGang
    DB.SaveHideoutMeta(h.id, h.meta)
    if h.gang and Config.Ranks.setGrade then Framework.SetJob(src, h.gang, Config.Ranks.bossLevel) end
    Changed()
end

function Hideouts.Owned(cid)
    local n = 0
    for _, o in pairs(H) do if o.owner == cid then n = n + 1 end end
    return n
end

function Hideouts.InsideCount(id) return #Insiders(id) end

Bridge.RegisterAdminCommand(C.deleteCommand, _L('cmd_delete'), {}, function(src)
    if src == 0 then return end
    local h = Nearest(src, 5.0)
    if not h then return Notify(src, _L('none_near'), 'error') end
    Hideouts.Delete(h)
    Notify(src, _L('deleted', h.name), 'success')
end)

Bridge.RegisterAdminCommand(C.resetCommand, _L('cmd_reset'), {}, function(src)
    if src == 0 then return end
    local h = Nearest(src, 5.0)
    if not h then return Notify(src, _L('none_near'), 'error') end
    Hideouts.Reset(h)
    Notify(src, _L('reset', h.name), 'success')
end)

---------------------------------------------------------------------------
-- Players: buy / enter / leave / knock / open the door
---------------------------------------------------------------------------
lib.callback.register('fks-gangs:hideout:buy', function(src, id)
    local h, P = H[id], Bridge.GetPlayer(src)
    if not h or not P then return false, _L('error') end
    if h.owner then return false, _L('already_owned') end
    if not NearDoor(src, h) then return false, _L('too_far') end

    if Hideouts.Owned(P.cid) >= C.maxPerPlayer then return false, _L('max_hideouts', C.maxPerPlayer) end

    -- made for one gang / only gangs can buy (and one hideout per gang)
    if h.forGang and P.job ~= h.forGang then return false, _L('hideout_for_gang', Gangs.SideLabel(h.forGang)) end
    if C.requireGang then
        if not Gangs.IsGang(P.job) then return false, _L('hideout_need_gang') end
        for _, o in pairs(H) do
            if o.owner and o.gang == P.job then return false, _L('gang_has_hideout') end
        end
    end
    if Gang.IsMember(P.cid) then return false, _L('already_in_gang') end

    if P.money(h.currency) < h.price then return false, _L(h.currency == 'gold' and 'no_gold' or 'no_cash') end
    if h.price > 0 and not P.remove(h.currency, h.price, 'fks-gangs hideout') then
        return false, _L(h.currency == 'gold' and 'no_gold' or 'no_cash')
    end

    Hideouts.SetOwner(h, src, P)
    print(('[fks-gangs] %s bought hideout #%d "%s"'):format(P.name, h.id, h.name))
    TriggerEvent('fks-gangs:hideoutBought', src, h.id)
    return true, _L('bought', h.name)
end)

lib.callback.register('fks-gangs:hideout:enter', function(src, id)
    local h = H[id]
    if not h then return false, _L('error') end
    if not Access(Bridge.GetPlayer(src), h) then return false, _L('no_access') end
    if not NearDoor(src, h) then return false, _L('too_far') end
    PutInside(src, h)
    return true, h.interior
end)

lib.callback.register('fks-gangs:hideout:leave', function(src)
    local h = H[inside[src]]
    inside[src] = nil
    SetPlayerRoutingBucket(src, 0)
    return h and h.coords or nil
end)

RegisterNetEvent('fks-gangs:hideout:knock', function(id)
    local src = source
    local h = H[id]
    if not h or not h.owner or not NearDoor(src, h) then return end
    local now = os.time()
    if (knockSpam[src] or 0) + 10 > now then return end
    knockSpam[src] = now

    local list = Insiders(id)
    if #list == 0 then return Notify(src, _L('nobody_home'), 'inform') end
    local name = Bridge.CharacterName(src)
    knocks[id] = { src = src, name = name, at = now }
    for _, s in ipairs(list) do
        Notify(s, _L('someone_knocking', name), 'warning')
        TriggerClientEvent('fks-gangs:client:knock', s, name, C.knockTimeout)
    end
    Notify(src, _L('knocked'), 'inform')
end)

lib.callback.register('fks-gangs:hideout:letIn', function(src)
    local id = inside[src]
    local h, k = H[id], knocks[id]
    if not h or not k then return false, _L('nobody_door') end
    knocks[id] = nil
    if os.time() - k.at > C.knockTimeout or not GetPlayerName(k.src) or not NearDoor(k.src, h, 8.0) then
        return false, _L('nobody_door')
    end
    PutInside(k.src, h)
    TriggerClientEvent('fks-gangs:client:enterHideout', k.src, h.id, h.interior)
    Notify(k.src, _L('door_opened'), 'success')
    return true, _L('let_in', k.name)
end)

-- stash / crafting bench of the hideout the player is in
lib.callback.register('fks-gangs:hideout:props', function(src)
    local h = H[inside[src]]
    if not h or not h.meta then return nil end
    return { stash = h.meta.stash, craft = h.meta.craft }
end)

-- relog / crash inside: the character comes back at the door
lib.callback.register('fks-gangs:hideout:restore', function(src, id)
    if inside[src] then return nil end
    local h = H[tonumber(id)]
    SetPlayerRoutingBucket(src, 0)
    return h and h.coords or nil
end)

AddEventHandler('playerDropped', function()
    inside[source] = nil
    knockSpam[source] = nil
end)

exports('GetHideout', function(id) return H[id] end)
exports('GetPlayerHideout', function(src) return inside[src] end)
