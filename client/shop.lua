---------------------------------------------------------------------------
-- Territory shops (client): buyer NPCs, prompt and the shop window (drawn by fks-core).
---------------------------------------------------------------------------
Shop = {}

local npcs = {}            -- [territoryId] = ped
local current              -- territory id of the open shop
local allowed = {}         -- [territoryId] = true when this player may see the buyer (npcForAll / can sell)

local group = Prompts.Group()
local talk = Prompts.Make(group, Config.Keys.shop, _L('talk_buyer'), false)

-- who sees each buyer: everyone (npcForAll) or only the players who can sell to him
function Shop.Refresh()
    local job = MyJob()
    for _, t in ipairs(Config.Territories) do
        local shop = t.shop
        allowed[t.id] = shop and shop.enabled and shop.npc
            and (shop.npcForAll or Gangs.CanSell(t, job, Territory.Owner(t.id))) or nil
    end
end

local function Notify(msg, kind)
    Bridge.Notify({ title = _L('shop'), description = msg, type = kind or 'inform' })
end

local function NpcPos(t)
    local c = t.shop.npc.coords
    return vector3(c.x, c.y, c.z)
end

---------------------------------------------------------------------------
-- Window: a counter with a card (picture, price, how many you carry) per item, and a page per item
-- to choose how many to sell. Drawn by fks-core.
---------------------------------------------------------------------------
local D                    -- last data from the server (fks-gangs:shop:open)

local function Price(n, account)
    if account == 'gold' then return ('%s %s'):format(Gangs.Fmt(n), _L('gold')) end
    return '$' .. Gangs.Fmt(n)
end

local function Find(item)
    for _, it in ipairs(D.items) do if it.item == item then return it end end
end

local function Worth()
    local total, units = 0, 0
    for _, it in ipairs(D.items) do
        total, units = total + it.price * it.count, units + it.count
    end
    return total, units
end

local function Quote()
    local quotes = Locale.shop_quotes or { _L('shop_sub') }
    return quotes[math.random(#quotes)]
end

local function CounterPage()
    local cards = {}
    for _, it in ipairs(D.items) do
        local none = it.count < 1
        cards[#cards + 1] = {
            value = it.item,
            img = it.img,
            title = it.label,
            text = _L('each', Price(it.price, D.account)),
            lines = { none and { label = _L('none_in_bag') } or { amount = it.count, label = _L('in_bag') } },
            disabled = none,
        }
    end

    local total, units = Worth()
    return {
        body = {
            { type = 'text', style = 'sub', text = Quote() },
            { type = 'kv', cols = 2, items = {
                { label = _L('owner'), value = D.owner, tone = 'gold' },
                { label = _L('prices'), value = D.priceMode == 'fixed' and _L('prices_fixed') or _L('prices_random') },
                (D.bonus or 0) > 0 and { label = _L('rep_bonus'), value = ('+%s%%'):format(D.bonus), tone = 'good' } or nil,
            } },
            { type = 'section', label = _L('items') },
            #cards > 0 and { type = 'cards', cols = 2, action = 'pick', items = cards } or { type = 'empty', text = _L('no_items') },
            units > 0 and { type = 'kv', cols = 1, items = { { label = _L('worth_all', units), value = Price(total, D.account), tone = 'good' } } } or nil,
        },
        footer = {
            main = units > 0 and {
                label = _L('sell_everything'), action = 'sellEverything', pulse = true,
                confirm = { title = _L('sell_everything_title'), text = _L('sell_everything_text', units, Price(total, D.account)), ok = _L('sell'), cancel = _L('cancel') },
            } or false,
        },
        hints = { { 'ESC', _L('close') } },
    }
end

-- "Sell · $984": the main button follows the amount
local function SellLabel(it, n)
    return _L('sell_for', Price(it.price * math.max(0, n), D.account))
end

local function ItemPage(it)
    local max = it.count
    if D.maxPerSale > 0 then max = math.min(max, D.maxPerSale) end
    return {
        title = it.label,
        body = {
            { type = 'medals', size = 'big', cols = 1, action = 'noop', items = {
                { img = it.img, icon = 'bag', label = it.label, sub = _L('each', Price(it.price, D.account)), badge = it.count },
            } },
            it.desc and { type = 'text', style = 'desc', text = it.desc } or nil,
            { type = 'kv', cols = 3, items = {
                { label = _L('price_each_label'), value = Price(it.price, D.account), tone = 'gold' },
                { label = _L('in_bag_label'), value = tostring(it.count) },
                { label = _L('worth'), value = Price(it.price * it.count, D.account), tone = 'good' },
                D.maxPerSale > 0 and { label = _L('max_per_sale'), value = tostring(D.maxPerSale) } or nil,
            } },
            { type = 'number', name = 'amount_' .. it.item, label = _L('amount'), value = max, min = 1, max = math.max(1, max), step = 1,
              quick = { 1, 5, 10 }, action = 'amount' },
        },
        footer = {
            main = { label = SellLabel(it, max), action = 'sellAmount', value = it.item, pulse = true },
            buttons = {
                { type = 'button', label = _L('sell_all'), icon = 'coin', small = true, style = 'ghost', action = 'sellItemAll', value = it.item,
                  confirm = { title = _L('sell_all_title'), text = _L('sell_all_text', it.count, it.label, Price(it.price * it.count, D.account)), ok = _L('sell'), cancel = _L('cancel') } },
            },
        },
        hints = { { 'ESC', _L('back') } },
    }
end

local function View()
    return {
        eyebrow = D.territory,
        title = D.label,
        page = 'counter',
        pages = { counter = CounterPage() },
        footer = { money = D.money },
    }
end

local function Fetch()
    local d = lib.callback.await('fks-gangs:shop:open', false, current)
    if d and d.ok then D = d end
    return d
end

-- after a sale: coin sound, fresh data, back to the counter
local function Done(ok, msg, fromItem)
    if not ok then return { ok = false, error = msg or _L('error') } end
    PlaySoundFrontend('PURCHASE', 'Ledger_Sounds', true, 0)
    local d = Fetch()
    if not d or not d.ok then
        current, D = nil, nil   -- a `close` answer does not run the close handler
        return { toast = { text = msg, type = 'success' }, close = true }
    end
    return { toast = { text = msg, type = 'success' }, back = fromItem or nil, view = View() }
end

UI.On('pick', function(d)
    local it = Find(d.value)
    if not it or it.count < 1 then return end
    return { go = 'item', data = ItemPage(it) }
end)

UI.On('noop', function() end)

UI.On('amount', function(d)
    local it = D and Find(tostring(d.name or ''):gsub('^amount_', ''))
    if not it then return end
    local n = math.min(math.floor(tonumber(d.value) or 0), it.count)
    return { patch = { main = { label = SellLabel(it, n) } } }
end)

UI.On('sellAmount', function(d)
    local n = tonumber(d.values and d.values['amount_' .. tostring(d.value)]) or 0
    local ok, msg = lib.callback.await('fks-gangs:shop:sell', false, current, d.value, n)
    return Done(ok, msg, true)
end)

UI.On('sellItemAll', function(d)
    local ok, msg = lib.callback.await('fks-gangs:shop:sell', false, current, d.value, 'all')
    return Done(ok, msg, true)
end)

UI.On('sellEverything', function()
    local ok, msg = lib.callback.await('fks-gangs:shop:sellAll', false, current)
    return Done(ok, msg)
end)

OnUIClose(function()
    current, D = nil, nil
end)

local function Open(t)
    current = t.id
    local d = Fetch()
    if not d or not d.ok then
        current = nil
        return Notify(d and d.error or _L('error'), 'error')
    end
    local ok = UI.Open(View())
    if not ok then current = nil return end

    -- walking away closes it
    CreateThread(function()
        local pos = NpcPos(t)
        while current == t.id do
            if #(GetEntityCoords(PlayerPedId()) - pos) > Config.InteractDistance + 3.0 then UI.Close() break end
            Wait(500)
        end
    end)
end

---------------------------------------------------------------------------
-- NPCs + prompt
---------------------------------------------------------------------------
CreateThread(function()
    while true do
        local pos = GetEntityCoords(PlayerPedId())
        for _, t in ipairs(Config.Territories) do
            if t.shop and t.shop.npc then
                local near = allowed[t.id] and #(pos - NpcPos(t)) < Config.NpcDistance
                if near and not npcs[t.id] then
                    npcs[t.id] = SpawnNpc(t.shop.npc.model, t.shop.npc.coords)
                elseif not near and npcs[t.id] then
                    DeleteEntity(npcs[t.id])
                    npcs[t.id] = nil
                end
            end
        end
        Wait(1500)
    end
end)

CreateThread(function()
    while true do
        local wait = 750
        if Bridge.IsLoggedIn() and not current then
            local pos = GetEntityCoords(PlayerPedId())
            for _, t in ipairs(Config.Territories) do
                if npcs[t.id] and #(pos - NpcPos(t)) <= Config.InteractDistance then
                    wait = 0
                    if CanAct() then
                        Prompts.Show(talk, true)
                        Prompts.Active(group, t.shop.label or t.label)
                        if Prompts.Done(talk) then Open(t) end
                    end
                    break
                end
            end
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, ped in pairs(npcs) do DeleteEntity(ped) end
    PromptDelete(talk)
end)
