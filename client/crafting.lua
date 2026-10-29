---------------------------------------------------------------------------
-- Gang crafting bench (client): a card per recipe, and a page per recipe where the amount updates what is
-- needed / what the player has, without leaving the menu. Drawn by fks-core.
---------------------------------------------------------------------------
if not Config.Hideouts.enabled then return end

Crafting = {}

local D                  -- last data from the server (fks-gangs:craft:open)
local open = false

local function Notify(msg, kind)
    Bridge.Notify({ title = _L('craft_bench'), description = msg, type = kind or 'inform' })
end

local function Find(id)
    for _, r in ipairs(D.recipes) do if r.id == id then return r end end
end

-- how many crafts the bag allows
local function MaxCraftable(r)
    local max = D.max
    for _, ing in ipairs(r.ingredients) do max = math.min(max, math.floor(ing.have / ing.need)) end
    return math.max(0, max)
end

local function Secs(s)
    s = math.floor(s + 0.5)
    if s >= 60 then return ('%dm %02ds'):format(s // 60, s % 60) end
    return ('%ds'):format(s)
end

-- one medal per ingredient: picture, "have / need", warning ring when short
local function IngredientRows(r, n)
    local items = {}
    for _, ing in ipairs(r.ingredients) do
        local need = ing.need * n
        items[#items + 1] = { img = ing.img, icon = 'bag', label = ing.label, sub = _L('have_need', ing.have, need), badge = need, warn = ing.have < need }
    end
    return items
end

local function Summary(r, n)
    local can = MaxCraftable(r)
    return {
        { label = _L('craft_makes'), value = ('%sx'):format(r.amount * n), tone = 'gold' },
        { label = _L('craft_time'), value = Secs(r.time * n) },
        { label = _L('craft_can_make'), value = tostring(can), tone = can >= n and 'good' or 'bad' },
    }
end

local function MainButton(r, n)
    local ok = MaxCraftable(r) >= n and n > 0
    return { label = ok and _L('craft_do', n) or _L('craft_missing_short'), action = 'craftDo', value = r.id, pulse = ok, disabled = not ok }
end

local function BenchPage()
    local cards = {}
    for _, r in ipairs(D.recipes) do
        local lines = {}
        for _, ing in ipairs(r.ingredients) do lines[#lines + 1] = { img = ing.img, amount = ing.need, label = ing.label } end
        local can = MaxCraftable(r)
        cards[#cards + 1] = {
            value = r.id, img = r.img, title = r.label,
            text = can > 0 and _L('craft_card_ready', Secs(r.time), can) or _L('craft_card', Secs(r.time)),
            lines = lines,
        }
    end
    local sub = D.speed > 0 and _L('craft_speed', D.tier, D.speed) or _L('craft_sub')
    return {
        body = {
            { type = 'text', style = 'sub', text = sub },
            #cards > 0 and { type = 'cards', cols = math.max(2, math.min(4, #cards)), action = 'craftPick', items = cards } or { type = 'empty', text = _L('no_recipes') },
        },
        footer = { main = false },
        hints = { { 'ESC', _L('close') } },
    }
end

local function RecipePage(r)
    local n = math.max(1, math.min(MaxCraftable(r), D.max))
    return {
        title = r.label,
        -- wide panel: the item and the amount on the left, what it takes on the right
        body = { { type = 'grid', cols = 2, gap = 2.2, class = 'fill', template = 'minmax(0, 0.9fr) minmax(0, 1.1fr)', children = {
            { type = 'grid', cols = 1, class = 'box', children = {
                { type = 'section', label = _L('craft_what') },
                { type = 'medals', size = 'big', cols = 1, action = 'noop', items = {
                    { img = r.img, icon = 'hammer', label = r.label, sub = _L('craft_per', r.amount, Secs(r.time)), badge = MaxCraftable(r) },
                } },
                { type = 'number', name = 'craft_' .. r.id, label = _L('amount'), value = n, min = 1, max = D.max, step = 1, quick = { 1, 5, 10 }, action = 'craftAmount' },
            } },
            { type = 'grid', cols = 1, class = 'box', children = {
                { type = 'section', label = _L('ingredients') },
                { type = 'medals', id = 'ingr', cols = math.max(2, math.min(4, #r.ingredients)), action = 'noop', items = IngredientRows(r, n) },
                { type = 'section', label = _L('craft_summary') },
                { type = 'kv', id = 'summary', class = 'big', cols = 3, items = Summary(r, n) },
            } },
        } } },
        footer = {
            main = MainButton(r, n),
            buttons = { { type = 'button', label = _L('craft_check'), icon = 'bag', small = true, style = 'ghost', action = 'craftCheck', value = r.id } },
        },
        hints = { { 'ESC', _L('back') } },
    }
end

local function View()
    return {
        eyebrow = _L('craft_eyebrow'), title = _L('craft_bench'), page = 'bench', layout = 'wide',
        pages = { bench = BenchPage() },
    }
end

local function Patch(r, n)
    return { patch = {
        ingr = { items = IngredientRows(r, n) },
        summary = { items = Summary(r, n) },
        main = MainButton(r, n),
    } }
end

UI.On('craftPick', function(d)
    local r = D and Find(d.value)
    if r then return { go = 'recipe', data = RecipePage(r) } end
end)

UI.On('craftAmount', function(d)
    local r = D and Find(tostring(d.name or ''):gsub('^craft_', ''))
    if not r then return end
    return Patch(r, math.max(1, math.floor(tonumber(d.value) or 1)))
end)

-- "Check my bag": fresh counts from the inventory
UI.On('craftCheck', function(d)
    local r = D and Find(d.value)
    if not r then return end
    local counts = lib.callback.await('fks-gangs:craft:counts', false, r.id)
    if not counts then return { ok = false, error = _L('error') } end
    for _, ing in ipairs(r.ingredients) do ing.have = counts[ing.item] or 0 end
    local n = math.max(1, math.floor(tonumber(d.values and d.values['craft_' .. r.id]) or 1))
    local res = Patch(r, n)
    local can = MaxCraftable(r)
    res.toast = { text = can >= n and _L('craft_check_ok', n) or _L('craft_check_bad', can), type = can >= n and 'success' or 'error' }
    return res
end)

UI.On('craftDo', function(d)
    local r = D and Find(d.value)
    if not r then return end
    local n = math.max(1, math.floor(tonumber(d.values and d.values['craft_' .. r.id]) or 1))
    local ok, res = lib.callback.await('fks-gangs:craft:start', false, r.id, n)
    if not ok then return { ok = false, error = res or _L('error') } end

    SetTimeout(0, function()
        local done = Bridge.Progress({
            duration = res, label = _L('crafting', r.amount * n, r.label), canCancel = true,
            anim = Config.Crafting.anim, disable = { move = true, combat = true, mount = true, sprint = true },
        })
        if not done then
            TriggerServerEvent('fks-gangs:server:craftCancel')
            return Notify(_L('craft_cancelled'), 'error')
        end
        local fin, msg = lib.callback.await('fks-gangs:craft:finish', false)
        Notify(msg or _L('error'), fin and 'success' or 'error')
    end)
    open = false   -- a `close` answer does not run the close handler
    return { close = true }
end)

OnUIClose(function()
    open = false
end)

function Crafting.Open()
    if open and UI.IsOpen() then return end
    local d = lib.callback.await('fks-gangs:craft:open', false)
    if not d or not d.ok then return Notify(d and d.error or _L('error'), 'error') end
    D = d
    open = UI.Open(View()) == true
end
