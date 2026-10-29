---------------------------------------------------------------------------
-- /managehideouts (admin): every hideout with its owner, give it to a player, put it back on sale, delete it,
-- or go to its door. Drawn by fks-core (client/admin.lua).
---------------------------------------------------------------------------
if not Config.Hideouts.enabled then return end

local C = Config.Hideouts

local function Notify(src, msg, kind)
    Bridge.Notify(src, { title = _L('hideout'), description = msg, type = kind or 'inform' })
end

Bridge.RegisterAdminCommand(C.manageCommand, _L('cmd_manage'), {}, function(src)
    if src == 0 then return print('[fks-gangs] use this command in game') end
    TriggerClientEvent('fks-gangs:client:manageHideouts', src)
end)

local function Admin(src)
    return src and src > 0 and Bridge.IsAdmin(src)
end

lib.callback.register('fks-gangs:admin:list', function(src)
    if not Admin(src) then return nil end
    local list = {}
    for _, h in pairs(Hideouts.H) do
        list[#list + 1] = {
            id = h.id, name = h.name, owned = h.owner ~= nil, ownerName = h.ownerName,
            gang = h.gang and Gangs.SideLabel(h.gang) or nil, forGang = h.forGang and Gangs.SideLabel(h.forGang) or nil,
            members = h.owner and Gang.MemberCount(h.id) or 0, ledger = h.owner and h.meta and h.meta.ledger or 0,
            price = h.price, currency = h.currency, interior = h.interior, inside = Hideouts.InsideCount(h.id),
            coords = ('%.1f, %.1f, %.1f'):format(h.coords.x, h.coords.y, h.coords.z),
        }
    end
    table.sort(list, function(a, b) return a.id < b.id end)

    local players = {}
    for _, id in ipairs(GetPlayers()) do
        local s = tonumber(id)
        local P = Bridge.GetPlayer(s)
        if P then players[#players + 1] = { id = s, name = P.name, job = P.job } end
    end
    table.sort(players, function(a, b) return a.name < b.name end)
    return { hideouts = list, players = players }
end)

-- door of a hideout (the admin goes there)
lib.callback.register('fks-gangs:admin:door', function(src, id)
    local h = Admin(src) and Hideouts.H[tonumber(id)]
    if not h then return nil end
    if Hideouts.Inside(src) then return nil, _L('admin_inside') end
    return h.coords
end)

lib.callback.register('fks-gangs:admin:reset', function(src, id)
    local h = Admin(src) and Hideouts.H[tonumber(id)]
    if not h then return false, _L('error') end
    Hideouts.Reset(h)
    print(('[fks-gangs] admin %s put hideout #%d "%s" back on sale'):format(GetPlayerName(src), h.id, h.name))
    return true, _L('reset', h.name)
end)

lib.callback.register('fks-gangs:admin:delete', function(src, id)
    local h = Admin(src) and Hideouts.H[tonumber(id)]
    if not h then return false, _L('error') end
    Hideouts.Delete(h)
    print(('[fks-gangs] admin %s deleted hideout #%d "%s"'):format(GetPlayerName(src), h.id, h.name))
    return true, _L('deleted', h.name)
end)

-- give it to an online player: a member of its gang keeps the gang, anyone else starts a new one
lib.callback.register('fks-gangs:admin:give', function(src, id, target)
    local h = Admin(src) and Hideouts.H[tonumber(id)]
    target = tonumber(target)
    local P = target and Bridge.GetPlayer(target)
    if not h or not P then return false, _L('error') end
    if h.owner == P.cid then return false, _L('admin_already_owner', P.name) end
    if Hideouts.Owned(P.cid) >= C.maxPerPlayer then return false, _L('transfer_max', P.name) end

    if h.owner and Gang.IsMember(P.cid, h.id) then
        Gang.Transfer(h, P.cid, P.name)
    else
        if Gang.IsMember(P.cid) then return false, _L('admin_other_gang', P.name) end
        if h.owner then Hideouts.Reset(h) end
        Hideouts.SetOwner(h, target, P)
    end
    Notify(target, _L('you_got_hideout', h.name), 'success')
    print(('[fks-gangs] admin %s gave hideout #%d "%s" to %s'):format(GetPlayerName(src), h.id, h.name, P.name))
    return true, _L('transferred', h.name, P.name)
end)
