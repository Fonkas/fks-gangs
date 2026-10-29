---------------------------------------------------------------------------
-- Inside a hideout (client): the ledger book (run the gang - drawn by fks-core), the stash and crafting
-- bench props, their prompts, and placing them.
---------------------------------------------------------------------------
if not Config.Hideouts.enabled then return end

Ledger = {}

local props = {}         -- [kind] = object
local open = false
local placing = false
local D                  -- last data from the server (fks-gangs:ledger:open)
local formSeq = 0        -- new rank forms get fresh field names (form values survive between pages)

local function Notify(msg, kind)
    Bridge.Notify({ title = _L('ledger'), description = msg, type = kind or 'inform' })
end

local function Money(n)
    if D and D.account == 'gold' then return ('%s %s'):format(Gangs.Fmt(n), _L('gold')) end
    return '$' .. Gangs.Fmt(n)
end

local function Can(perm) return D and D.me.perms[perm] == true end

local function Interior() return Hideout.interior and Config.Interiors[Hideout.interior] end

---------------------------------------------------------------------------
-- Props (local objects - the hideout is its own instance anyway)
---------------------------------------------------------------------------
local function ClearProps()
    for k, obj in pairs(props) do
        if DoesEntityExist(obj) then DeleteEntity(obj) end
        props[k] = nil
    end
end

local function SpawnProps()
    ClearProps()
    if not Hideout.id then return end
    for kind, c in pairs(Hideout.props or {}) do
        local hash = Config.Hideouts.props[kind] and LoadModel(Config.Hideouts.props[kind])
        if hash then
            local obj = CreateObject(hash, c.x, c.y, c.z, false, false, false, false, false)
            SetEntityHeading(obj, c.w or 0.0)
            FreezeEntityPosition(obj, true)
            SetModelAsNoLongerNeeded(hash)
            props[kind] = obj
        end
    end
end

AddEventHandler('fks-gangs:client:enteredHideout', SpawnProps)
AddEventHandler('fks-gangs:client:propsChanged', SpawnProps)
AddEventHandler('fks-gangs:client:leftHideout', function()
    ClearProps()
    if open then UI.Close() end
end)

---------------------------------------------------------------------------
-- Ledger pages
---------------------------------------------------------------------------
-- `than` = perks already active: only what is better than them is listed
local function PerkFacts(perks, than)
    local out = {}
    than = than or {}
    perks = {
        craftTime = (perks.craftTime or 1) < (than.craftTime or 1) and perks.craftTime or nil,
        shopBonus = (perks.shopBonus or 0) > (than.shopBonus or 0) and perks.shopBonus or nil,
        missionBonus = (perks.missionBonus or 0) > (than.missionBonus or 0) and perks.missionBonus or nil,
    }
    if perks.craftTime and perks.craftTime < 1 then
        out[#out + 1] = { icon = 'hammer', text = _L('perk_craft', math.floor((1 - perks.craftTime) * 100 + 0.5)), badge = true }
    end
    if (perks.shopBonus or 0) > 0 then
        out[#out + 1] = { icon = 'coin', text = _L('perk_shop', math.floor(perks.shopBonus * 100 + 0.5)), badge = true }
    end
    if (perks.missionBonus or 0) > 0 then
        out[#out + 1] = { icon = 'spur', text = _L('perk_mission', math.floor(perks.missionBonus * 100 + 0.5)), badge = true }
    end
    return out
end

local REASONS = { deposit = 'reason_deposit', withdraw = 'reason_withdraw', mission = 'reason_mission' }

-- a framed card: ornamented title + its components (fks-core `box` class)
local function Box(label, children, extra)
    local list = { { type = 'section', label = label } }
    for _, c in ipairs(children) do list[#list + 1] = c end
    local box = { type = 'grid', cols = 1, class = 'box', children = list }
    for k, v in pairs(extra or {}) do box[k] = v end
    return box
end

local function HistoryRows(max)
    local hist = {}
    for i, h in ipairs(D.history) do
        if max and i > max then break end
        hist[#hist + 1] = { value = i, title = h.name, tag = (h.amount >= 0 and '+' or '-') .. Money(math.abs(h.amount)),
            sub = ('%s · %s'):format(_L(REASONS[h.reason] or 'reason_other'), h.when) }
    end
    return hist
end

-- the reputation, big, across the top
local function RepHero()
    local r = D.rep
    local progress, ringText, nextText = 1, _L('rep_max'), _L('rep_top_text')
    if r.next then
        progress = (r.points - r.min) / math.max(1, r.next.min - r.min)
        ringText = _L('rep_to_next', r.next.label)
        nextText = _L('rep_progress', Gangs.Fmt(r.points), Gangs.Fmt(r.next.min), r.next.label)
    end
    local perks = PerkFacts(r.perks)
    local middle = {
        { type = 'tier', class = 'hero', label = _L('rep_tier'), value = r.tier, text = r.label },
        { type = 'text', style = 'note', text = nextText },
        #perks > 0 and { type = 'facts', items = perks } or { type = 'text', style = 'note', text = _L('no_perks') },
    }
    if r.next then
        local nextPerks = PerkFacts(r.next.perks, r.perks)
        if #nextPerks > 0 then
            middle[#middle + 1] = { type = 'text', style = 'note', text = _L('rep_next_perks', r.next.label) }
            middle[#middle + 1] = { type = 'facts', items = nextPerks }
        end
    end
    return { type = 'grid', cols = 3, gap = 3, class = 'box', template = 'minmax(0, 0.7fr) minmax(0, 1.3fr) minmax(0, 1fr)', children = {
        { type = 'ring', class = 'hero', value = math.max(0, math.min(1, progress)), label = ringText },
        { type = 'grid', cols = 1, gap = 0.6, children = middle },
        { type = 'kv', class = 'big', cols = 2, items = {
            { label = _L('rep_points'), value = Gangs.Fmt(r.points), tone = 'gold' },
            { label = _L('rep_kills'), value = Gangs.Fmt(r.kills) },
            { label = _L('rep_captures'), value = Gangs.Fmt(r.captures) },
            { label = _L('rep_missions'), value = Gangs.Fmt(r.missions) },
        } },
    } }
end

-- second row: the gang (+ who is on the books), contracts, last movements
local function QuickLists()
    local members = {}
    for i, m in ipairs(D.members) do
        if i > 3 then break end
        members[#members + 1] = { value = i, title = m.name, tag = m.rankName, sub = m.online and _L('online') or _L('offline') }
    end
    local contracts = {}
    for i, m in ipairs(D.missions) do
        local state = m.active and _L('in_progress') or (m.cooldown > 0 and _L('available_in_min', math.ceil(m.cooldown / 60)) or _L('available'))
        contracts[#contracts + 1] = { value = i, icon = m.icon, title = m.label, tag = Money(m.reward), sub = state }
    end
    local cols = {
        Box(_L('the_gang'), {
            { type = 'kv', cols = 2, items = {
                { label = _L('gang'), value = D.gangLabel or '-', tone = 'gold' },
                { label = _L('boss'), value = D.ownerName or '-' },
                { label = _L('members'), value = tostring(#D.members) },
                { label = _L('gang_money'), value = (Can('deposit') or Can('withdraw')) and Money(D.ledger) or nil, tone = 'good' },
            } },
            { type = 'list', expand = 'none', selected = -1, items = members },
        }),
        Box(_L('tab_contracts'), {
            #contracts > 0 and { type = 'list', expand = 'none', selected = -1, items = contracts } or { type = 'empty', text = _L('no_contracts') },
        }),
    }
    if Can('deposit') or Can('withdraw') then
        local hist = HistoryRows(4)
        cols[#cols + 1] = Box(_L('history'), {
            #hist > 0 and { type = 'list', expand = 'none', selected = -1, items = hist } or { type = 'empty', text = _L('no_history') },
        })
    end
    return cols
end

local function HomePage()
    local rows = {}
    if D.rep.enabled then rows[#rows + 1] = RepHero() end
    local quick = QuickLists()
    rows[#rows + 1] = { type = 'grid', cols = #quick, gap = 2.2, class = 'fill', children = quick }
    return {
        body = {
            { type = 'text', style = 'sub', text = _L('ledger_welcome', D.me.rankName) },
            { type = 'grid', cols = 1, gap = 2.2, children = rows },
        },
        hints = { { 'ESC', _L('close') } },
    }
end

-- ranks this player may give (below their level, any for level 4)
local function RankOptions()
    local out = {}
    for _, r in ipairs(D.ranks) do
        if D.me.boss or r.level < D.me.level then
            out[#out + 1] = { value = r.id, label = ('%s (%s)'):format(r.name, _L('level_n', r.level)) }
        end
    end
    return out
end

local function MembersPage()
    local rankOpts = RankOptions()
    local items = {}
    for _, m in ipairs(D.members) do
        local canTouch = not m.owner and not m.me and (D.me.boss or m.level < D.me.level)
        local actions = {}
        if canTouch and Can('hire') and #rankOpts > 0 then
            actions[#actions + 1] = { label = _L('change_rank'), icon = 'quill', small = true, action = 'setRank',
                prompt = { title = _L('change_rank_of', m.name), ok = _L('save'), cancel = _L('cancel'), fields = {
                    { type = 'select', name = 'rank', label = _L('rank'), value = m.rank, options = rankOpts },
                } } }
        end
        if canTouch and Can('fire') then
            actions[#actions + 1] = { label = _L('fire'), icon = 'x', small = true, style = 'danger', action = 'fire',
                confirm = { title = _L('fire_title', m.name), text = _L('fire_text', m.name), danger = true, ok = _L('fire'), cancel = _L('cancel') } }
        end
        items[#items + 1] = {
            value = m.cid, title = m.name, tag = m.rankName,
            flag = m.owner and { text = _L('owner_flag'), tone = 'gold' } or (m.me and { text = _L('you'), tone = 'gold' }) or nil,
            sub = (m.online and _L('online') or _L('offline')) .. ' · ' .. _L('level_n', m.level),
            details = { { type = 'kv', cols = 2, items = { { label = _L('joined'), value = m.joined }, { label = _L('rank'), value = m.rankName } } } },
            actions = actions,
        }
    end

    local online = 0
    for _, m in ipairs(D.members) do if m.online then online = online + 1 end end

    local footer = {}
    if Can('hire') then
        if #D.nearby > 0 and #rankOpts > 0 then
            local people = {}
            for _, n in ipairs(D.nearby) do people[#people + 1] = { value = n.id, label = ('%s (%s)'):format(n.name, n.id) } end
            footer.main = { label = _L('hire'), action = 'hire', pulse = true,
                prompt = { title = _L('hire_title'), text = _L('hire_text'), ok = _L('hire'), cancel = _L('cancel'), fields = {
                    { type = 'select', name = 'target', label = _L('player'), value = people[1].value, options = people },
                    { type = 'select', name = 'rank', label = _L('rank'), value = rankOpts[#rankOpts].value, options = rankOpts },
                } } }
        else
            footer.main = { label = _L('hire_nobody'), disabled = true }
        end
    else
        footer.main = false
    end

    return {
        body = { { type = 'grid', cols = 2, gap = 2.2, class = 'fill', template = 'minmax(0, 1.7fr) minmax(0, 1fr)', children = {
            Box(_L('members'), {
                #items > 0 and { type = 'list', id = 'members', items = items } or { type = 'empty', text = _L('no_members') },
            }),
            Box(_L('the_gang'), {
                { type = 'kv', class = 'big', cols = 2, items = {
                    { label = _L('members'), value = tostring(#D.members), tone = 'gold' },
                    { label = _L('online'), value = tostring(online) },
                } },
                { type = 'text', style = 'note', text = Can('hire') and _L('members_desc_hire') or _L('members_desc') },
            }),
        } } },
        footer = footer,
        hints = { { 'ESC', _L('close') } },
    }
end

local function PermLabels(perms, level)
    if level >= D.bossLevel then return { { text = _L('perm_all'), tone = 'gold' } } end
    local out = {}
    for _, p in ipairs(perms or {}) do out[#out + 1] = { text = _L('perm_' .. p) } end
    if #out == 0 then out[1] = { text = _L('perm_none') } end
    return out
end

local function RanksPage()
    local items = {}
    for _, r in ipairs(D.ranks) do
        local mine = D.me.boss or r.level < D.me.level
        local actions = {}
        if mine and Can('ranks') then
            actions[#actions + 1] = { label = _L('edit'), icon = 'quill', small = true, action = 'editRank' }
            actions[#actions + 1] = { label = _L('delete'), icon = 'x', small = true, style = 'danger', action = 'deleteRank', disabled = r.count > 0,
                confirm = { title = _L('delete_rank_title', r.name), text = _L('delete_rank_text'), danger = true, ok = _L('delete'), cancel = _L('cancel') } }
        end
        items[#items + 1] = {
            value = r.id, title = r.name, tag = _L('level_n', r.level),
            sub = _L('rank_members', r.count),
            details = { { type = 'badges', items = PermLabels(r.perms, r.level) } },
            actions = actions,
        }
    end
    return {
        body = { { type = 'grid', cols = 2, gap = 2.2, class = 'fill', template = 'minmax(0, 1.7fr) minmax(0, 1fr)', children = {
            Box(_L('tab_ranks'), { { type = 'list', id = 'ranks', items = items } }),
            Box(_L('how_ranks_work'), {
                { type = 'kv', class = 'big', cols = 2, items = {
                    { label = _L('tab_ranks'), value = ('%s/%s'):format(#D.ranks, D.maxRanks), tone = 'gold' },
                    { label = _L('rank_level'), value = '0-' .. D.bossLevel },
                } },
                { type = 'text', style = 'note', text = _L('ranks_desc', D.bossLevel) },
            }),
        } } },
        footer = { main = (Can('ranks') and #D.ranks < D.maxRanks) and { label = _L('new_rank'), action = 'newRank', pulse = true } or false },
        hints = { { 'ESC', _L('close') } },
    }
end

-- create / edit one rank (field names are unique per form: form values outlive the page)
local function RankPage(r)
    formSeq = formSeq + 1
    local key = (r and r.id or 'new') .. '_' .. formSeq
    local maxLevel = D.me.boss and D.bossLevel or (D.me.level - 1)
    local levels = {}
    for l = 0, math.max(0, maxLevel) do levels[#levels + 1] = { value = l, label = tostring(l) } end
    local perms = {}
    for _, p in ipairs(D.permissions) do perms[#perms + 1] = { value = p, label = _L('perm_' .. p) } end
    return {
        title = r and _L('edit_rank', r.name) or _L('new_rank'),
        body = { { type = 'grid', cols = 2, gap = 2.2, class = 'fill', children = {
            Box(_L('rank_identity'), {
                { type = 'input', name = 'rname_' .. key, label = _L('rank_name'), value = r and r.name or '', max = 24, placeholder = _L('rank_name_ph') },
                { type = 'segmented', name = 'rlevel_' .. key, label = _L('rank_level'), value = r and math.min(r.level, maxLevel) or 0, options = levels },
                { type = 'text', style = 'note', text = _L('rank_level_note', D.bossLevel) },
            }),
            Box(_L('rank_perms'), {
                { type = 'chips', name = 'rperms_' .. key, value = r and r.perms or {}, options = perms },
            }),
        } } },
        footer = {
            main = { label = _L('save'), action = 'saveRank', value = key, pulse = true },
        },
        hints = { { 'ESC', _L('back') } },
    }
end

local function MoneyPage()
    local hist = HistoryRows()
    local amountField = function(max)
        return { { type = 'number', name = 'amount', label = _L('amount'), value = math.min(100, math.max(1, max)), min = 1,
                   max = math.max(1, max), step = 1, quick = { 10, 100, 1000 } } }
    end
    local cash = D.account == 'gold' and D.money.gold or D.money.cash
    return {
        body = { { type = 'grid', cols = 2, gap = 2.2, class = 'fill', template = 'minmax(0, 0.9fr) minmax(0, 1.1fr)', children = {
          { type = 'grid', cols = 1, class = 'box', children = {
            { type = 'section', label = _L('gang_money') },
            { type = 'seals', items = {
                { cur = D.account, amount = D.ledger, label = _L('gang_money') },
                { cur = D.account, amount = cash, label = _L('your_money') },
            } },
            { type = 'row', align = 'center', children = {
                { type = 'button', label = _L('deposit'), icon = 'take', action = 'deposit', disabled = not Can('deposit') or cash < 1,
                  prompt = { title = _L('deposit_title'), text = _L('deposit_text', Money(cash)), ok = _L('deposit'), cancel = _L('cancel'), fields = amountField(cash) } },
                { type = 'button', label = _L('withdraw'), icon = 'coin', style = 'ghost', action = 'withdraw', disabled = not Can('withdraw') or D.ledger < 1,
                  prompt = { title = _L('withdraw_title'), text = _L('withdraw_text', Money(D.ledger)), ok = _L('withdraw'), cancel = _L('cancel'), fields = amountField(D.ledger) } },
            } },
          } },
          { type = 'grid', cols = 1, class = 'box', children = {
            { type = 'section', label = _L('history') },
            #hist > 0 and { type = 'list', expand = 'none', selected = -1, items = hist } or { type = 'empty', text = _L('no_history') },
          } },
        } } },
        footer = { main = false },
        hints = { { 'ESC', _L('close') } },
    }
end

local function ContractsPage()
    local items, busy, free = {}, false, 0
    for _, m in ipairs(D.missions) do
        busy = busy or m.busy
        if m.cooldown <= 0 and not m.active then free = free + 1 end
        local reward = { { label = _L('reward'), value = Money(m.reward), tone = 'good' }, { label = _L('reputation'), value = '+' .. m.rep, tone = 'gold' } }
        for _, it in ipairs(m.items) do reward[#reward + 1] = { label = _L('items_reward'), value = ('%sx %s'):format(it.amount, it.label) } end
        reward[#reward + 1] = { label = _L('time_limit'), value = _L('minutes', m.timeLimit) }
        local details = { { type = 'kv', cols = 2, items = reward } }
        if m.cooldown > 0 then details[#details + 1] = { type = 'timers', items = { { label = _L('available_in'), seconds = m.cooldown } } } end
        local actions = {}
        if m.active then
            actions[1] = { label = _L('abandon'), icon = 'x', style = 'danger', small = true, action = 'abandon',
                confirm = { title = _L('abandon_title'), text = _L('abandon_text'), danger = true, ok = _L('abandon'), cancel = _L('cancel') } }
        else
            actions[1] = { label = _L('take_contract'), icon = 'quill', small = true, action = 'startMission', disabled = m.busy or m.cooldown > 0,
                confirm = { title = m.label, text = _L('take_contract_text', m.label), ok = _L('take_contract'), cancel = _L('cancel') } }
        end
        items[#items + 1] = {
            value = m.id, icon = m.icon, title = m.label, tag = Money(m.reward),
            flag = m.active and { text = _L('in_progress'), tone = 'gold' } or (m.cooldown > 0 and { text = _L('on_cooldown_flag'), tone = 'bad' }) or nil,
            sub = m.desc, details = details, actions = actions,
        }
    end
    return {
        body = { { type = 'grid', cols = 2, gap = 2.2, class = 'fill', template = 'minmax(0, 1.7fr) minmax(0, 1fr)', children = {
            Box(_L('tab_contracts'), {
                #items > 0 and { type = 'list', id = 'contracts', items = items } or { type = 'empty', text = _L('no_contracts') },
            }),
            Box(_L('contract_board'), {
                { type = 'kv', class = 'big', cols = 2, items = {
                    { label = _L('available'), value = tostring(free), tone = 'good' },
                    { label = _L('on_cooldown_flag'), value = tostring(#D.missions - free) },
                } },
                { type = 'text', style = 'note', text = busy and _L('contracts_busy') or _L('contracts_desc') },
            }),
        } } },
        footer = { main = false },
        hints = { { 'ESC', _L('close') } },
    }
end

-- owner only (Config.Hideouts.allowTransfer): hand the hideout to a member
local function TransferButton()
    if not (D.allowTransfer and D.me.owner) then return nil end
    local opts = {}
    for _, m in ipairs(D.members) do
        if not m.me then opts[#opts + 1] = { value = m.cid, label = ('%s · %s'):format(m.name, m.rankName) } end
    end
    if #opts == 0 then return { type = 'text', style = 'note', text = _L('transfer_nobody') } end
    return { type = 'button', label = _L('transfer'), icon = 'transfer', style = 'ghost', wide = true, action = 'transfer',
        prompt = { title = _L('transfer_title'), text = _L('transfer_text', D.name), danger = true, ok = _L('transfer'), cancel = _L('cancel'), fields = {
            { type = 'select', name = 'target', label = _L('transfer_to'), value = opts[1].value, options = opts },
            { name = 'confirm', label = _L('transfer_confirm', D.name), match = D.name },
        } } }
end

local function HideoutPage()
    return {
        body = {
            { type = 'text', style = 'desc', text = _L('hideout_desc') },
            { type = 'grid', cols = 2, gap = 2.2, class = 'fill', template = 'minmax(0, 1.7fr) minmax(0, 1fr)', children = {
              Box(_L('furniture'), {
                { type = 'medals', size = 'big', cols = 2, action = 'place', items = {
                    { value = 'stash', icon = 'box', label = _L('stash'), sub = D.placed.stash and _L('move_it') or _L('not_placed') },
                    { value = 'craft', icon = 'hammer', label = _L('craft_bench'), sub = D.placed.craft and _L('move_it') or _L('not_placed') },
                } },
              }),
              Box(_L('tab_hideout'), {
                { type = 'kv', class = 'big', cols = 2, items = {
                    { label = _L('stash_size'), value = tostring(Config.Stash.size), tone = 'gold' },
                    { label = _L('recipes'), value = tostring(#((Config.Gangs[D.gang or ''] or {}).recipes or Config.Crafting.defaultRecipes)) },
                } },
                TransferButton(),
              }),
            } },
        },
        footer = { main = false },
        hints = { { 'ESC', _L('close') } },
    }
end

local function View()
    local tabs = { { page = 'home', label = _L('tab_home') }, { page = 'members', label = _L('tab_members') } }
    local pages = { home = HomePage(), members = MembersPage() }
    if Can('ranks') then tabs[#tabs + 1] = { page = 'ranks', label = _L('tab_ranks') } pages.ranks = RanksPage() end
    if Can('deposit') or Can('withdraw') then tabs[#tabs + 1] = { page = 'money', label = _L('tab_money') } pages.money = MoneyPage() end
    if Can('missions') then tabs[#tabs + 1] = { page = 'contracts', label = _L('tab_contracts') } pages.contracts = ContractsPage() end
    if Can('place') then tabs[#tabs + 1] = { page = 'hideout', label = _L('tab_hideout') } pages.hideout = HideoutPage() end
    return {
        eyebrow = _L('ledger_eyebrow'), title = D.name, page = 'home', layout = 'wide',
        tabs = tabs, pages = pages,
        footer = { money = D.money },
    }
end

local function Fetch()
    local d = lib.callback.await('fks-gangs:ledger:open', false)
    if d and d.ok then D = d end
    return d
end

-- after an action: toast + fresh data
local function Done(ok, msg, extra)
    if not ok then return { ok = false, error = msg or _L('error') } end
    local d = Fetch()
    if not d or not d.ok then open = false return { toast = { text = msg, type = 'success' }, close = true } end
    local res = { toast = { text = msg, type = 'success' }, view = View() }
    for k, v in pairs(extra or {}) do res[k] = v end
    return res
end

---------------------------------------------------------------------------
-- Ledger actions
---------------------------------------------------------------------------
UI.On('hire', function(d)
    local v = d.values or {}
    UI.Toast(_L('hire_waiting'), 'inform')
    local ok, msg = lib.callback.await('fks-gangs:ledger:hire', false, tonumber(v.target), tonumber(v.rank))
    return Done(ok, msg)
end)

UI.On('setRank', function(d)
    local ok, msg = lib.callback.await('fks-gangs:ledger:setRank', false, d.value, tonumber((d.values or {}).rank))
    return Done(ok, msg)
end)

UI.On('fire', function(d)
    local ok, msg = lib.callback.await('fks-gangs:ledger:fire', false, d.value)
    return Done(ok, msg)
end)

local editing = {}       -- [form key] = rank id (nil = new)

UI.On('newRank', function()
    local page = RankPage(nil)
    editing[page.footer.main.value] = false
    return { go = 'rank', data = page }
end)

UI.On('editRank', function(d)
    for _, r in ipairs(D.ranks) do
        if r.id == d.value then
            local page = RankPage(r)
            editing[page.footer.main.value] = r.id
            return { go = 'rank', data = page }
        end
    end
end)

UI.On('saveRank', function(d)
    local key, v = d.value, d.values or {}
    local id = editing[key] or nil
    local ok, msg = lib.callback.await('fks-gangs:ledger:saveRank', false, id, {
        name = v['rname_' .. key], level = tonumber(v['rlevel_' .. key]) or 0, perms = v['rperms_' .. key] or {},
    })
    return Done(ok, msg, { back = true })
end)

UI.On('deleteRank', function(d)
    local ok, msg = lib.callback.await('fks-gangs:ledger:deleteRank', false, d.value)
    return Done(ok, msg)
end)

UI.On('deposit', function(d)
    local ok, msg = lib.callback.await('fks-gangs:ledger:deposit', false, tonumber((d.values or {}).amount))
    if ok then PlaySoundFrontend('PURCHASE', 'Ledger_Sounds', true, 0) end
    return Done(ok, msg)
end)

UI.On('withdraw', function(d)
    local ok, msg = lib.callback.await('fks-gangs:ledger:withdraw', false, tonumber((d.values or {}).amount))
    if ok then PlaySoundFrontend('PURCHASE', 'Ledger_Sounds', true, 0) end
    return Done(ok, msg)
end)

UI.On('startMission', function(d)
    local ok, msg = lib.callback.await('fks-gangs:mission:start', false, d.value)
    if not ok then return { ok = false, error = msg or _L('error') } end
    open = false   -- a `close` answer does not run the close handler
    return { toast = { text = msg, type = 'success' }, close = true }
end)

UI.On('abandon', function()
    local ok, msg = lib.callback.await('fks-gangs:mission:abandon', false)
    return Done(ok, msg)
end)

UI.On('transfer', function(d)
    local ok, msg = lib.callback.await('fks-gangs:ledger:transfer', false, (d.values or {}).target)
    return Done(ok, msg)
end)

UI.On('place', function(d)
    local kind = d.value
    SetTimeout(0, function() Ledger.Place(kind) end)
    open = false
    return { close = true }
end)

OnUIClose(function()
    open = false
end)

function Ledger.Open()
    if open and UI.IsOpen() then return end
    local d = Fetch()
    if not d or not d.ok then return Notify(d and d.error or _L('error'), 'error') end
    open = UI.Open(View()) == true
    if not open then return end
    PlaySoundFrontend('INFO', 'HUD_SHOP_SOUNDSET', true, 0)

    local int = Interior()
    CreateThread(function()
        while open do
            local pos = GetEntityCoords(PlayerPedId())
            if not int or not Hideout.id or #(pos - int.points.ledger) > Config.InteractDistance + 3.0 then UI.Close() break end
            Wait(500)
        end
    end)
end

---------------------------------------------------------------------------
-- Placing the stash / crafting bench: a see-through prop in front of the player, G to put it there
---------------------------------------------------------------------------
function Ledger.Place(kind)
    if placing or not Hideout.id then return end
    local hash = LoadModel(Config.Hideouts.props[kind])
    if not hash then return Notify(_L('error'), 'error') end
    placing = true

    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local ghost = CreateObject(hash, pos.x, pos.y, pos.z, false, false, false, false, false)
    SetEntityAlpha(ghost, 160, false)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)
    local heading = GetEntityHeading(ped) + 180.0

    Notify(_L('place_hint_' .. kind), 'inform')
    UI.Caption({ text = _L('place_caption_' .. kind), hints = { { 'G', _L('place_confirm') }, { '← →', _L('place_rotate') }, { 'BACKSPACE', _L('cancel') } } })

    local result
    while placing do
        Wait(0)
        ped = PlayerPedId()
        local fwd = GetEntityForwardVector(ped)
        local p = GetEntityCoords(ped) + fwd * 1.3
        SetEntityCoords(ghost, p.x, p.y, p.z - 0.9, false, false, false, false)
        PlaceObjectOnGroundProperly(ghost)
        SetEntityHeading(ghost, heading)

        DisableControlAction(0, Config.Keys.place, true)
        DisableControlAction(0, Config.Keys.cancel, true)
        if IsControlPressed(0, Config.Keys.rotate) or IsDisabledControlPressed(0, Config.Keys.rotate) then heading = heading - 1.5 end
        if IsControlPressed(0, Config.Keys.rotateBack) or IsDisabledControlPressed(0, Config.Keys.rotateBack) then heading = heading + 1.5 end

        if IsDisabledControlJustPressed(0, Config.Keys.place) then
            local c = GetEntityCoords(ghost)
            result = { x = c.x, y = c.y, z = c.z, w = heading % 360.0 }
            placing = false
        elseif IsDisabledControlJustPressed(0, Config.Keys.cancel) or IsEntityDead(ped) or not Hideout.id then
            placing = false
        end
    end

    DeleteEntity(ghost)
    SetModelAsNoLongerNeeded(hash)
    UI.Caption(false)
    if not result then return Notify(_L('place_cancelled'), 'inform') end
    local ok, msg = lib.callback.await('fks-gangs:ledger:place', false, kind, result)
    Notify(msg or _L('error'), ok and 'success' or 'error')
end

---------------------------------------------------------------------------
-- Invitation to join a gang (asked by the server when someone hires this player)
---------------------------------------------------------------------------
lib.callback.register('fks-gangs:client:invite', function(hideout, rank, by)
    local ok = UI.Confirm({
        title = _L('invite_title', hideout),
        text = _L('invite_text', by, hideout, rank),
        ok = _L('join'), cancel = _L('refuse'),
    })
    return ok == true
end)

---------------------------------------------------------------------------
-- Prompts: ledger, stash, crafting bench
---------------------------------------------------------------------------
local group = Prompts.Group()
local pLedger = Prompts.Make(group, Config.Keys.interact, _L('open_ledger'), false)
local pStash = Prompts.Make(group, Config.Keys.interact, _L('open_stash'), false)
local pCraft = Prompts.Make(group, Config.Keys.interact, _L('open_craft'), false)

local function Near(pos, c)
    return c and #(pos - vector3(c.x, c.y, c.z)) <= Config.InteractDistance
end

CreateThread(function()
    while true do
        local wait = 1000
        local int = Interior()
        if Hideout.id and int and not placing then
            wait = 250
            local pos = GetEntityCoords(PlayerPedId())
            local which, label
            if Near(pos, int.points and int.points.ledger) then which, label = pLedger, _L('ledger')
            elseif Near(pos, Hideout.props.stash) then which, label = pStash, _L('stash')
            elseif Near(pos, Hideout.props.craft) then which, label = pCraft, _L('craft_bench') end

            if which and CanAct() then
                wait = 0
                Prompts.Show(pLedger, which == pLedger)
                Prompts.Show(pStash, which == pStash)
                Prompts.Show(pCraft, which == pCraft)
                Prompts.Active(group, label)
                if Prompts.Done(which) then
                    if which == pLedger then Ledger.Open()
                    elseif which == pStash then TriggerServerEvent('fks-gangs:server:openStash')
                    elseif Crafting then Crafting.Open() end
                end
            end
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    ClearProps()
    if placing then UI.Caption(false) end
    for _, p in ipairs({ pLedger, pStash, pCraft }) do PromptDelete(p) end
end)
