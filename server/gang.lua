---------------------------------------------------------------------------
-- The gang behind a hideout: members, ranks, the ledger (gang money), where the stash / crafting bench are
-- and the stash itself. Everything the ledger book shows comes from here (fks-gangs:ledger:open).
--
-- h.meta = { ledger = money, ranks = { { id, name, level, perms = { 'deposit', ... } } }, nextRank,
--            stash = { x, y, z, w }, craft = { x, y, z, w } }
---------------------------------------------------------------------------
Gang = {}

local RK = Config.Ranks
local members = {}       -- [hideoutId] = { [cid] = { cid, name, rank, joined } }
local memberOf = {}      -- [cid] = hideoutId
local PERM = {}
for _, p in ipairs(RK.permissions) do PERM[p] = true end

local function Notify(src, msg, kind)
    Bridge.Notify(src, { title = _L('ledger'), description = msg, type = kind or 'inform' })
end

local function Trim(s, max)
    return tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', ''):sub(1, max)
end

local function SaveMeta(h)
    DB.SaveHideoutMeta(h.id, h.meta)
end

---------------------------------------------------------------------------
-- Ranks
---------------------------------------------------------------------------
local function Rank(h, id)
    for _, r in ipairs(h.meta.ranks or {}) do
        if r.id == id then return r end
    end
end

-- highest level first
local function Ranks(h)
    local list = {}
    for _, r in ipairs(h.meta.ranks or {}) do list[#list + 1] = r end
    table.sort(list, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        return a.id < b.id
    end)
    return list
end

local function LowestRank(h)
    local list = Ranks(h)
    return list[#list]
end

local function TopRank(h)
    return Ranks(h)[1]
end

local function CleanPerms(list)
    local out, seen = {}, {}
    for _, p in ipairs(type(list) == 'table' and list or {}) do
        if PERM[p] and not seen[p] then out[#out + 1] = p seen[p] = true end
    end
    return out
end

local function DefaultMeta()
    local meta = { ledger = 0, ranks = {}, nextRank = 1 }
    for _, r in ipairs(RK.default) do
        meta.ranks[#meta.ranks + 1] = { id = meta.nextRank, name = r.name, level = r.level, perms = CleanPerms(r.perms) }
        meta.nextRank = meta.nextRank + 1
    end
    return meta
end

-- old hideouts / broken meta get the default ranks
function Gang.FixMeta(h)
    h.meta = type(h.meta) == 'table' and h.meta or {}
    if type(h.meta.ranks) ~= 'table' or #h.meta.ranks == 0 then
        local d = DefaultMeta()
        h.meta.ranks, h.meta.nextRank = d.ranks, d.nextRank
    end
    h.meta.ledger = math.max(0, math.floor(tonumber(h.meta.ledger) or 0))
    h.meta.nextRank = tonumber(h.meta.nextRank) or (#h.meta.ranks + 1)
end

---------------------------------------------------------------------------
-- Members
---------------------------------------------------------------------------
local function List(hid)
    members[hid] = members[hid] or {}
    return members[hid]
end

local function AddMember(h, cid, name, rankId)
    local m = { cid = cid, name = name, rank = rankId, joined = os.time() }
    local old = memberOf[cid]
    if old and old ~= h.id and members[old] then members[old][cid] = nil end
    List(h.id)[cid] = m
    memberOf[cid] = h.id
    DB.SaveMember(m, h.id)
    return m
end

local function RemoveMember(h, cid)
    if members[h.id] then members[h.id][cid] = nil end
    if memberOf[cid] == h.id then memberOf[cid] = nil end
    DB.DeleteMember(cid)
end

function Gang.IsMember(cid, hid)
    return cid ~= nil and memberOf[cid] ~= nil and (hid == nil or memberOf[cid] == hid)
end

function Gang.MemberCount(hid)
    local n = 0
    for _ in pairs(members[hid] or {}) do n = n + 1 end
    return n
end

-- a new owner: default ranks, the owner on the books with the top rank
function Gang.Init(h, P)
    h.meta = DefaultMeta()
    for cid in pairs(members[h.id] or {}) do memberOf[cid] = nil end
    members[h.id] = {}
    AddMember(h, P.cid, P.name, TopRank(h).id)
    SaveMeta(h)
end

-- hideout reset / deleted: the gang is gone (jobs stay as they are)
function Gang.Disband(h)
    for cid in pairs(members[h.id] or {}) do memberOf[cid] = nil end
    members[h.id] = nil
    DB.DeleteMembers(h.id)
    h.meta = {}
    SaveMeta(h)
    if h.id then pcall(Bridge.DeleteStash, Gang.StashId(h)) end
end

CreateThread(function()
    while not Hideouts or not Hideouts.loaded do Wait(200) end
    for _, row in ipairs(DB.LoadMembers()) do
        local h = Hideouts.H[row.hideout_id]
        if h and h.owner then
            List(h.id)[row.cid] = { cid = row.cid, name = row.name, rank = tonumber(row.rank_id), joined = tonumber(row.joined_at) or 0 }
            memberOf[row.cid] = h.id
        end
    end
    -- every owner is on the books
    for _, h in pairs(Hideouts.H) do
        if h.owner and not List(h.id)[h.owner] then AddMember(h, h.owner, h.ownerName or '?', TopRank(h).id) end
    end
end)

---------------------------------------------------------------------------
-- Who am I in a gang?
--   ctx = { P, h, member, rank, level, boss, owner }
---------------------------------------------------------------------------
-- the hideout of this player's gang: the one they are on the books of, else (memberAccess) the one of their job
function Gang.Of(P)
    if not P then return nil end
    local hid = memberOf[P.cid]
    local h = hid and Hideouts.H[hid]
    if h and h.owner then return h end
    if Config.Hideouts.memberAccess and Gangs.IsGang(P.job) then
        for _, o in pairs(Hideouts.H) do
            if o.owner and o.gang == P.job then return o end
        end
    end
end

function Gang.Context(src, h)
    local P = Bridge.GetPlayer(src)
    h = h or Gang.Of(P)
    if not P or not h or not h.owner then return nil end
    local m = List(h.id)[P.cid]
    local owner = h.owner == P.cid
    if not m and not owner and not (Config.Hideouts.memberAccess and h.gang and P.job == h.gang) then return nil end

    local rank = (m and Rank(h, m.rank)) or (owner and TopRank(h)) or LowestRank(h)
    local level = owner and RK.bossLevel or (rank and rank.level or 0)
    local ctx = { P = P, h = h, member = m, rank = rank, level = level, owner = owner, boss = level >= RK.bossLevel }
    ctx.perms = {}
    for _, p in ipairs(RK.permissions) do ctx.perms[p] = ctx.boss end
    if not ctx.boss and rank then
        for _, p in ipairs(rank.perms or {}) do ctx.perms[p] = true end
    end
    return ctx
end

function Gang.Can(ctx, perm)
    return ctx ~= nil and (ctx.boss or ctx.perms[perm] == true)
end

-- the player's gang context, only while they are inside that hideout
local function Inside(src, perm)
    local hid = Hideouts.Inside(src)
    local h = hid and Hideouts.H[hid]
    local ctx = h and Gang.Context(src, h)
    if not ctx then return nil, _L('not_member') end
    if perm and not Gang.Can(ctx, perm) then return nil, _L('no_permission') end
    return ctx
end
Gang.Inside = Inside

---------------------------------------------------------------------------
-- Ledger money
---------------------------------------------------------------------------
local ACC = Config.Ledger.account == 'gold' and 'gold' or 'cash'

function Gang.LedgerAdd(hid, amount, name, reason)
    local h = Hideouts.H[hid]
    amount = math.floor(tonumber(amount) or 0)
    if not h or not h.owner or amount == 0 then return false end
    Gang.FixMeta(h)
    h.meta.ledger = math.max(0, h.meta.ledger + amount)
    SaveMeta(h)
    DB.LedgerLog(hid, name or '?', amount, reason or 'other')
    return true
end

local function Money(amount)
    if ACC == 'gold' then return ('%s %s'):format(Gangs.Fmt(amount), _L('gold')) end
    return '$' .. Gangs.Fmt(amount)
end

lib.callback.register('fks-gangs:ledger:deposit', function(src, amount)
    local ctx, err = Inside(src, 'deposit')
    if not ctx then return false, err end
    amount = math.floor(tonumber(amount) or 0)
    if amount < 1 then return false, _L('invalid_amount') end
    if ctx.P.money(ACC) < amount or not ctx.P.remove(ACC, amount, 'fks-gangs ledger deposit') then
        return false, _L(ACC == 'gold' and 'no_gold' or 'no_cash')
    end
    Gang.LedgerAdd(ctx.h.id, amount, ctx.P.name, 'deposit')
    return true, _L('deposited', Money(amount))
end)

lib.callback.register('fks-gangs:ledger:withdraw', function(src, amount)
    local ctx, err = Inside(src, 'withdraw')
    if not ctx then return false, err end
    amount = math.floor(tonumber(amount) or 0)
    if amount < 1 then return false, _L('invalid_amount') end
    if amount > ctx.h.meta.ledger then return false, _L('ledger_short') end
    Gang.LedgerAdd(ctx.h.id, -amount, ctx.P.name, 'withdraw')
    ctx.P.add(ACC, amount, 'fks-gangs ledger withdraw')
    return true, _L('withdrew', Money(amount))
end)

---------------------------------------------------------------------------
-- Hire / fire / promote
---------------------------------------------------------------------------
local function GradeOf(rank)
    return RK.setGrade and rank.level or 0
end

-- can ctx put someone in / take someone out of a rank of `level`?
local function Outranks(ctx, level)
    return ctx.boss or level < ctx.level
end

-- players close to me, inside the same hideout, that can be hired
local function Nearby(ctx, src)
    local list = {}
    local me = GetEntityCoords(GetPlayerPed(src))
    local bucket = GetPlayerRoutingBucket(src)
    for _, id in ipairs(GetPlayers()) do
        local o = tonumber(id)
        if o ~= src and GetPlayerRoutingBucket(o) == bucket then
            local ped = GetPlayerPed(o)
            if ped and ped ~= 0 and #(GetEntityCoords(ped) - me) <= Config.Ledger.hireRange then
                local P = Bridge.GetPlayer(o)
                if P and not memberOf[P.cid] then list[#list + 1] = { id = o, name = P.name } end
            end
        end
    end
    return list
end

lib.callback.register('fks-gangs:ledger:hire', function(src, target, rankId)
    local ctx, err = Inside(src, 'hire')
    if not ctx then return false, err end
    target = tonumber(target)
    local rank = Rank(ctx.h, tonumber(rankId))
    if not rank then return false, _L('error') end
    if not Outranks(ctx, rank.level) then return false, _L('rank_too_high') end

    local ok = false
    for _, n in ipairs(Nearby(ctx, src)) do if n.id == target then ok = true end end
    if not ok then return false, _L('hire_too_far') end
    local T = Bridge.GetPlayer(target)
    if not T then return false, _L('error') end
    if Gangs.IsGang(T.job) and T.job ~= ctx.h.gang then return false, _L('hire_other_gang', T.name) end

    -- the player has to accept
    local accepted = lib.callback.await('fks-gangs:client:invite', target, ctx.h.name, rank.name, ctx.P.name)
    if not accepted then return false, _L('hire_refused', T.name) end
    if memberOf[T.cid] then return false, _L('error') end

    if ctx.h.gang then
        local done, why = Framework.SetJob(target, ctx.h.gang, GradeOf(rank))
        if not done then return false, why or _L('error') end
    end
    AddMember(ctx.h, T.cid, T.name, rank.id)
    Notify(target, _L('you_joined', ctx.h.name, rank.name), 'success')
    Hideouts.Changed()
    return true, _L('hired', T.name, rank.name)
end)

lib.callback.register('fks-gangs:ledger:fire', function(src, cid)
    local ctx, err = Inside(src, 'fire')
    if not ctx then return false, err end
    local m = List(ctx.h.id)[cid]
    if not m then return false, _L('error') end
    if cid == ctx.h.owner then return false, _L('cannot_fire_owner') end
    if cid == ctx.P.cid then return false, _L('cannot_fire_self') end
    local rank = Rank(ctx.h, m.rank)
    if rank and not Outranks(ctx, rank.level) then return false, _L('rank_too_high') end

    RemoveMember(ctx.h, cid)
    if ctx.h.gang then
        local tsrc, T = Framework.Online(cid)
        if tsrc then
            if T.job == ctx.h.gang then Framework.SetJob(tsrc, RK.firedJob, 0) end
            Notify(tsrc, _L('you_were_fired', ctx.h.name), 'error')
        else
            Framework.SetJobOffline(cid, RK.firedJob, 0)
        end
    end
    Hideouts.Changed()
    return true, _L('fired', m.name)
end)

lib.callback.register('fks-gangs:ledger:setRank', function(src, cid, rankId)
    local ctx, err = Inside(src, 'hire')
    if not ctx then return false, err end
    local m = List(ctx.h.id)[cid]
    local rank = Rank(ctx.h, tonumber(rankId))
    if not m or not rank then return false, _L('error') end
    if cid == ctx.h.owner then return false, _L('owner_rank') end
    local cur = Rank(ctx.h, m.rank)
    if (cur and not Outranks(ctx, cur.level)) or not Outranks(ctx, rank.level) then return false, _L('rank_too_high') end

    m.rank = rank.id
    DB.SaveMember(m, ctx.h.id)
    if ctx.h.gang and RK.setGrade then Framework.SetJobAny(cid, ctx.h.gang, GradeOf(rank)) end
    local tsrc = Framework.Online(cid)
    if tsrc then Notify(tsrc, _L('your_rank', rank.name), 'inform') end
    return true, _L('rank_set', m.name, rank.name)
end)

---------------------------------------------------------------------------
-- Hand the hideout over to a member of the gang (the old owner stays, with the top rank)
---------------------------------------------------------------------------
function Gang.Transfer(h, cid, name)
    local top = TopRank(h)
    local old = h.owner
    h.owner, h.ownerName = cid, name
    DB.SetHideoutOwner(h.id, cid, name, h.gang)
    local m = List(h.id)[cid] or AddMember(h, cid, name, top.id)
    m.rank = top.id
    DB.SaveMember(m, h.id)
    if old and List(h.id)[old] then
        List(h.id)[old].rank = top.id
        DB.SaveMember(List(h.id)[old], h.id)
    end
    if h.gang and RK.setGrade then Framework.SetJobAny(cid, h.gang, RK.bossLevel) end
    Hideouts.Changed()
end

lib.callback.register('fks-gangs:ledger:transfer', function(src, cid)
    local ctx, err = Inside(src)
    if not ctx then return false, err end
    if not Config.Hideouts.allowTransfer then return false, _L('error') end
    if not ctx.owner then return false, _L('only_owner') end
    local m = List(ctx.h.id)[cid]
    if not m or cid == ctx.P.cid then return false, _L('error') end
    if Hideouts.Owned(cid) >= Config.Hideouts.maxPerPlayer then return false, _L('transfer_max', m.name) end
    Gang.Transfer(ctx.h, cid, m.name)
    local tsrc = Framework.Online(cid)
    if tsrc then Notify(tsrc, _L('you_got_hideout', ctx.h.name), 'success') end
    print(('[fks-gangs] %s handed hideout #%d "%s" to %s'):format(ctx.P.name, ctx.h.id, ctx.h.name, m.name))
    return true, _L('transferred', ctx.h.name, m.name)
end)

---------------------------------------------------------------------------
-- Ranks: create / edit / delete
---------------------------------------------------------------------------
local function BossRanks(h, except)
    local n = 0
    for _, r in ipairs(h.meta.ranks) do
        if r.id ~= except and r.level >= RK.bossLevel then n = n + 1 end
    end
    return n
end

local function RankCount(h, id)
    local n = 0
    for _, m in pairs(members[h.id] or {}) do if m.rank == id then n = n + 1 end end
    return n
end

lib.callback.register('fks-gangs:ledger:saveRank', function(src, id, data)
    local ctx, err = Inside(src, 'ranks')
    if not ctx then return false, err end
    if type(data) ~= 'table' then return false, _L('error') end
    local h = ctx.h
    local name = Trim(data.name, 24)
    local level = math.floor(tonumber(data.level) or -1)
    if name == '' then return false, _L('invalid_name') end
    if level < 0 or level > RK.bossLevel then return false, _L('error') end
    if not Outranks(ctx, level) then return false, _L('rank_too_high') end

    local r = id and Rank(h, tonumber(id))
    if r then
        if not Outranks(ctx, r.level) then return false, _L('rank_too_high') end
        if r.level >= RK.bossLevel and level < RK.bossLevel and BossRanks(h, r.id) == 0 then
            return false, _L('last_boss_rank')
        end
        r.name, r.level, r.perms = name, level, CleanPerms(data.perms)
        -- the grade of the members follows the new level
        if h.gang and RK.setGrade then
            for cid, m in pairs(members[h.id] or {}) do
                if m.rank == r.id and cid ~= h.owner then Framework.SetJobAny(cid, h.gang, GradeOf(r)) end
            end
        end
    else
        if #h.meta.ranks >= RK.max then return false, _L('max_ranks', RK.max) end
        r = { id = h.meta.nextRank, name = name, level = level, perms = CleanPerms(data.perms) }
        h.meta.nextRank = h.meta.nextRank + 1
        h.meta.ranks[#h.meta.ranks + 1] = r
    end
    SaveMeta(h)
    return true, _L('rank_saved', name)
end)

lib.callback.register('fks-gangs:ledger:deleteRank', function(src, id)
    local ctx, err = Inside(src, 'ranks')
    if not ctx then return false, err end
    local h = ctx.h
    local r = Rank(h, tonumber(id))
    if not r then return false, _L('error') end
    if not Outranks(ctx, r.level) then return false, _L('rank_too_high') end
    if RankCount(h, r.id) > 0 then return false, _L('rank_in_use') end
    if #h.meta.ranks <= 1 or (r.level >= RK.bossLevel and BossRanks(h, r.id) == 0) then return false, _L('last_boss_rank') end
    for i, o in ipairs(h.meta.ranks) do
        if o.id == r.id then table.remove(h.meta.ranks, i) break end
    end
    SaveMeta(h)
    return true, _L('rank_deleted', r.name)
end)

---------------------------------------------------------------------------
-- Stash / crafting bench placement
---------------------------------------------------------------------------
local function InInterior(h, c)
    local int = Config.Interiors[h.interior]
    return int and #(vector3(c.x, c.y, c.z) - int.inside.xyz) <= 40.0
end

lib.callback.register('fks-gangs:ledger:place', function(src, kind, c)
    local ctx, err = Inside(src, 'place')
    if not ctx then return false, err end
    if kind ~= 'stash' and kind ~= 'craft' then return false, _L('error') end
    if type(c) ~= 'table' or not tonumber(c.x) or not tonumber(c.y) or not tonumber(c.z) then return false, _L('error') end
    c = { x = c.x + 0.0, y = c.y + 0.0, z = c.z + 0.0, w = (tonumber(c.w) or 0.0) + 0.0 }
    if not InInterior(ctx.h, c) or #(GetEntityCoords(GetPlayerPed(src)) - vector3(c.x, c.y, c.z)) > 8.0 then
        return false, _L('place_too_far')
    end
    ctx.h.meta[kind] = c
    SaveMeta(ctx.h)
    Hideouts.PropsChanged(ctx.h)
    return true, _L(kind == 'stash' and 'stash_placed' or 'craft_placed')
end)

---------------------------------------------------------------------------
-- Stash
---------------------------------------------------------------------------
function Gang.StashId(h) return 'fks_gang_stash_' .. h.id end

local function NearPoint(src, c, dist)
    return c and #(GetEntityCoords(GetPlayerPed(src)) - vector3(c.x, c.y, c.z)) <= (dist or Config.InteractDistance + 2.0)
end
Gang.NearPoint = NearPoint

RegisterNetEvent('fks-gangs:server:openStash', function()
    local src = source
    local ctx, err = Inside(src, 'stash')
    if not ctx then return Notify(src, err, 'error') end
    if not NearPoint(src, ctx.h.meta.stash) then return Notify(src, _L('too_far'), 'error') end
    local S = Config.Stash
    Bridge.OpenStash(src, Gang.StashId(ctx.h), _L('stash_label', ctx.h.name), S.slots, S.size * 1000, S.size)
end)

---------------------------------------------------------------------------
-- What the ledger book shows
---------------------------------------------------------------------------
lib.callback.register('fks-gangs:ledger:open', function(src)
    local ctx, err = Inside(src)
    if not ctx then return { ok = false, error = err } end
    local h, P = ctx.h, ctx.P
    Gang.FixMeta(h)

    -- the name on the books follows the character
    if ctx.member and ctx.member.name ~= P.name then
        ctx.member.name = P.name
        DB.SaveMember(ctx.member, h.id)
    end

    local online = {}
    for _, id in ipairs(GetPlayers()) do
        local O = Bridge.GetPlayer(tonumber(id))
        if O then online[O.cid] = true end
    end

    local mlist = {}
    for cid, m in pairs(members[h.id] or {}) do
        local r = Rank(h, m.rank)
        local level = cid == h.owner and RK.bossLevel or (r and r.level or 0)
        mlist[#mlist + 1] = {
            cid = cid, name = m.name, rank = m.rank, rankName = r and r.name or '?', level = level,
            online = online[cid] == true, joined = os.date('%d/%m/%Y', m.joined or 0), owner = cid == h.owner, me = cid == P.cid,
        }
    end
    table.sort(mlist, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        return a.name < b.name
    end)

    local rlist = {}
    for _, r in ipairs(Ranks(h)) do
        rlist[#rlist + 1] = { id = r.id, name = r.name, level = r.level, perms = r.perms, count = RankCount(h, r.id) }
    end

    local history = {}
    if Gang.Can(ctx, 'deposit') or Gang.Can(ctx, 'withdraw') then
        for _, row in ipairs(DB.LedgerHistory(h.id, Config.Ledger.history)) do
            history[#history + 1] = { name = row.name, amount = tonumber(row.amount), reason = row.reason, when = os.date('%d/%m %H:%M', tonumber(row.at) or 0) }
        end
    end

    return {
        ok = true,
        id = h.id, name = h.name, gang = h.gang, gangLabel = h.gang and Gangs.SideLabel(h.gang) or nil, ownerName = h.ownerName,
        me = {
            cid = P.cid, rankName = ctx.rank and ctx.rank.name or '?', level = ctx.level, boss = ctx.boss,
            owner = ctx.owner, perms = ctx.perms, member = ctx.member ~= nil,
        },
        ledger = h.meta.ledger, account = ACC, history = history,
        members = mlist, ranks = rlist,
        rep = Rep.Public(h.gang),
        missions = Missions and Missions.Board(src, ctx) or {},
        placed = { stash = h.meta.stash ~= nil, craft = h.meta.craft ~= nil },
        nearby = Gang.Can(ctx, 'hire') and Nearby(ctx, src) or {},
        money = { cash = P.money('cash'), gold = P.money('gold') },
        bossLevel = RK.bossLevel, maxRanks = RK.max, permissions = RK.permissions,
        allowTransfer = Config.Hideouts.allowTransfer == true,
    }
end)

exports('GetGangLedger', function(hid) local h = Hideouts.H[hid] return h and h.meta and h.meta.ledger or 0 end)
exports('AddGangLedger', function(hid, amount, reason) return Gang.LedgerAdd(hid, amount, 'script', reason) end)
exports('GetPlayerGangHideout', function(src) local h = Gang.Of(Bridge.GetPlayer(src)) return h and h.id end)
