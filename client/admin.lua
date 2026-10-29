---------------------------------------------------------------------------
-- /managehideouts (admin): every hideout with its owner; give / reset / delete / go there. Drawn by fks-core.
---------------------------------------------------------------------------
if not Config.Hideouts.enabled then return end

local D                  -- last data from the server (fks-gangs:admin:list)
local open = false

local function Notify(msg, kind)
    Bridge.Notify({ title = _L('hideout'), description = msg, type = kind or 'inform' })
end

local function Price(n, cur)
    if cur == 'gold' then return ('%s %s'):format(Gangs.Fmt(n), _L('gold')) end
    return '$' .. Gangs.Fmt(n)
end

local function Box(label, children)
    local list = { { type = 'section', label = label } }
    for _, c in ipairs(children) do list[#list + 1] = c end
    return { type = 'grid', cols = 1, class = 'box', children = list }
end

local function ListPage()
    local players = {}
    for _, p in ipairs(D.players) do
        players[#players + 1] = { value = p.id, label = ('%s (%s) · %s'):format(p.name, p.id, Gangs.SideLabel(Gangs.Side(p.job)) ~= _L('neutral') and Gangs.SideLabel(Gangs.Side(p.job)) or (p.job or '-')) }
    end

    local items, owned = {}, 0
    for _, h in ipairs(D.hideouts) do
        if h.owned then owned = owned + 1 end
        local actions = {
            { label = _L('admin_goto'), icon = 'fwd', small = true, action = 'adminGoto' },
        }
        if #players > 0 then
            actions[#actions + 1] = { label = _L('admin_give'), icon = 'transfer', small = true, action = 'adminGive',
                prompt = { title = _L('admin_give_title', h.name), text = _L('admin_give_text'), ok = _L('admin_give'), cancel = _L('cancel'), fields = {
                    { type = 'select', name = 'target', label = _L('player'), value = players[1].value, options = players },
                } } }
        end
        actions[#actions + 1] = { label = _L('admin_reset'), icon = 'undo', small = true, style = 'ghost', action = 'adminReset', disabled = not h.owned,
            confirm = { title = _L('admin_reset_title', h.name), text = _L('admin_reset_text'), danger = true, ok = _L('admin_reset'), cancel = _L('cancel') } }
        actions[#actions + 1] = { label = _L('delete'), icon = 'x', small = true, style = 'danger', action = 'adminDelete',
            prompt = { title = _L('admin_delete_title', h.name), text = _L('admin_delete_text', h.name), danger = true, ok = _L('delete'), cancel = _L('cancel'),
                fields = { { name = 'confirm', match = h.name } } } }

        items[#items + 1] = {
            value = h.id, title = ('#%s · %s'):format(h.id, h.name),
            tag = h.owned and h.ownerName or _L('for_sale_tag'),
            flag = h.inside > 0 and { text = _L('admin_inside_now', h.inside), tone = 'gold' } or nil,
            sub = h.owned and _L('admin_sub', h.gang or '-', h.members, Price(h.ledger, 'cash')) or _L('admin_sub_sale', Price(h.price, h.currency)),
            details = { { type = 'kv', cols = 4, items = {
                { label = _L('price'), value = Price(h.price, h.currency) },
                { label = _L('hideout_gang'), value = h.forGang or _L('any_gang') },
                { label = _L('interior'), value = h.interior },
                { label = _L('admin_coords'), value = h.coords },
            } } },
            actions = actions,
        }
    end

    return {
        body = { { type = 'grid', cols = 2, gap = 2.2, class = 'fill', template = 'minmax(0, 2.2fr) minmax(0, 1fr)', children = {
            Box(_L('admin_hideouts'), {
                #items > 0 and { type = 'list', id = 'hideouts', items = items } or { type = 'empty', text = _L('admin_none') },
            }),
            Box(_L('admin_summary'), {
                { type = 'kv', class = 'big', cols = 2, items = {
                    { label = _L('admin_total'), value = tostring(#D.hideouts), tone = 'gold' },
                    { label = _L('admin_owned'), value = tostring(owned) },
                } },
                { type = 'kv', class = 'big', cols = 2, items = {
                    { label = _L('for_sale_tag'), value = tostring(#D.hideouts - owned), tone = 'good' },
                    { label = _L('online'), value = tostring(#D.players) },
                } },
                { type = 'text', style = 'note', text = _L('admin_help', Config.Hideouts.createCommand) },
            }),
        } } },
        footer = { main = { label = _L('admin_create_here'), action = 'adminCreate', pulse = true } },
        hints = { { 'ESC', _L('close') } },
    }
end

local function View()
    return {
        eyebrow = _L('admin_eyebrow'), title = _L('admin_title'), page = 'list', layout = 'wide',
        pages = { list = ListPage() },
    }
end

local function Fetch()
    local d = lib.callback.await('fks-gangs:admin:list', false)
    if d then D = d end
    return d
end

local function Done(ok, msg)
    if not ok then return { ok = false, error = msg or _L('error') } end
    Fetch()
    return { toast = { text = msg, type = 'success' }, view = View() }
end

UI.On('adminGive', function(d)
    local ok, msg = lib.callback.await('fks-gangs:admin:give', false, d.value, tonumber((d.values or {}).target))
    return Done(ok, msg)
end)

UI.On('adminReset', function(d)
    local ok, msg = lib.callback.await('fks-gangs:admin:reset', false, d.value)
    return Done(ok, msg)
end)

UI.On('adminDelete', function(d)
    local ok, msg = lib.callback.await('fks-gangs:admin:delete', false, d.value)
    return Done(ok, msg)
end)

UI.On('adminGoto', function(d)
    local c, err = lib.callback.await('fks-gangs:admin:door', false, d.value)
    if not c then return { ok = false, error = err or _L('error') } end
    SetTimeout(0, function()
        local ped = PlayerPedId()
        DoScreenFadeOut(400)
        while not IsScreenFadedOut() do Wait(10) end
        SetEntityCoords(ped, c.x, c.y, c.z, false, false, false, false)
        SetEntityHeading(ped, c.w or 0.0)
        Wait(500)
        DoScreenFadeIn(600)
    end)
    open = false   -- a `close` answer does not run the close handler
    return { close = true }
end)

UI.On('adminCreate', function()
    SetTimeout(200, function() ExecuteCommand(Config.Hideouts.createCommand) end)
    open = false
    return { close = true }
end)

OnUIClose(function()
    open = false
end)

RegisterNetEvent('fks-gangs:client:manageHideouts', function()
    if open and UI.IsOpen() then return end
    if not Fetch() then return Notify(_L('error'), 'error') end
    open = UI.Open(View()) == true
end)
