---------------------------------------------------------------------------
-- Territory shops: prices (rolled once per restart in 'random' mode) and selling.
---------------------------------------------------------------------------
local Prices = {}   -- [territoryId][item] = price

math.randomseed(os.time())
for _, t in ipairs(Config.Territories) do
    local shop = t.shop
    if shop and shop.enabled then
        Prices[t.id] = {}
        for _, it in ipairs(shop.items or {}) do
            local lo, hi = tonumber(it.min) or 0, tonumber(it.max) or tonumber(it.min) or 0
            if hi < lo then lo, hi = hi, lo end
            local price
            if shop.priceMode == 'fixed' then
                price = tonumber(it.price) or lo
            else
                price = math.random(math.floor(lo), math.floor(hi))
            end
            Prices[t.id][it.item] = price
        end
    end
end

local function Notify(src, msg, kind)
    Bridge.Notify(src, { title = _L('shop'), description = msg, type = kind or 'inform' })
end

local function NearNpc(src, t)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or GetPlayerRoutingBucket(src) ~= 0 then return false end
    local c = t.shop.npc.coords
    return #(GetEntityCoords(ped) - vector3(c.x, c.y, c.z)) <= Config.InteractDistance + 3.0
end

-- returns the territory + player when this player may sell here, or nil + error text
local function Check(src, id)
    local t = Gangs.Territory(id)
    if not t or not t.shop or not t.shop.enabled then return nil, nil, _L('shop_closed') end
    local P = Bridge.GetPlayer(src)
    if not P then return nil end
    if not NearNpc(src, t) then return nil, nil, _L('too_far') end
    if Gangs.IsLaw(P.job) then return nil, nil, _L('shop_law') end
    if not Gangs.CanSell(t, P.job, Territories.Owner(id)) then return nil, nil, _L('shop_no_access') end
    return t, P
end

-- item picture from the inventory in use (Config.ItemImagePath or the item's own `image` win)
-- (also used by the crafting bench)
function ItemImage(it)
    if it.image then return it.image end
    if Config.ItemImagePath then return (Config.ItemImagePath:gsub('{name}', it.item)) end
    local inv = Bridge.Inventory()
    if inv == 'rsg-inventory' then
        local rsg = Bridge.RSG and Bridge.RSG()
        local data = rsg and rsg.Shared and rsg.Shared.Items and rsg.Shared.Items[it.item]
        return 'nui://rsg-inventory/html/images/' .. (data and data.image or (it.item .. '.png'))
    elseif inv == 'ox_inventory' then
        local ok, data = pcall(function() return exports.ox_inventory:Items(it.item) end)
        local img = ok and data and data.client and data.client.image
        if img and img:find('://') then return img end
        return 'nui://ox_inventory/web/images/' .. (img or (it.item .. '.png'))
    end
    return 'nui://vorp_inventory/html/img/items/' .. it.item .. '.png'
end

local function Account(t) return t.shop.account == 'gold' and 'gold' or 'cash' end

-- price for this seller: the reputation of their gang can add a bonus (Config.Reputation -> shopBonus)
local function PriceFor(t, item, job)
    local base = Prices[t.id][item]
    if not base then return nil end
    return math.floor(base * (1 + Rep.Perk(job, 'shopBonus')) + 0.5)
end

-- what the shop window shows
lib.callback.register('fks-gangs:shop:open', function(src, id)
    local t, P, err = Check(src, id)
    if not t then return { ok = false, error = err } end
    local items = {}
    for _, it in ipairs(t.shop.items or {}) do
        items[#items + 1] = {
            item = it.item,
            label = it.label or Bridge.ItemLabel(it.item),
            desc = it.desc,
            img = ItemImage(it),
            price = PriceFor(t, it.item, P.job),
            count = Bridge.ItemCount(src, it.item),
        }
    end
    return {
        ok = true,
        label = t.shop.label or t.label,
        territory = t.label,
        owner = Gangs.SideLabel(Territories.Owner(id)),
        account = Account(t),
        priceMode = t.shop.priceMode == 'fixed' and 'fixed' or 'random',
        maxPerSale = tonumber(t.shop.maxPerSale) or 0,
        bonus = math.floor(Rep.Perk(P.job, 'shopBonus') * 100 + 0.5),
        money = { cash = P.money('cash'), gold = P.money('gold') },
        items = items,
    }
end)

-- sells up to `amount` (or everything with 'all'): ok, sold amount, total paid, label | false, error
local function Sell(src, t, P, item, amount)
    local price = PriceFor(t, item, P.job)
    if not price then return false, _L('shop_unknown_item') end
    local have = Bridge.ItemCount(src, item)
    amount = amount == 'all' and have or math.floor(tonumber(amount) or 0)
    local max = tonumber(t.shop.maxPerSale) or 0
    if max > 0 and amount > max then amount = max end
    if amount < 1 then return false, _L('invalid_amount') end
    if have < amount then return false, _L('not_enough_items') end
    if not Bridge.RemoveItem(src, item, amount) then return false, _L('not_enough_items') end

    local total = price * amount
    P.add(Account(t), total, 'fks-gangs territory shop')
    if Config.Debug then print(('[fks-gangs] %s sold %dx %s for %d %s (%s)'):format(P.name, amount, item, total, Account(t), t.id)) end
    TriggerEvent('fks-gangs:itemSold', src, t.id, item, amount, total)
    return true, amount, total, Bridge.ItemLabel(item)
end

local function Paid(t, total)
    return Account(t) == 'gold' and _L('paid_gold', Gangs.Fmt(total)) or _L('paid', Gangs.Fmt(total))
end

-- sell `amount` of `item` (amount = 'all' sells all of it)
lib.callback.register('fks-gangs:shop:sell', function(src, id, item, amount)
    local t, P, err = Check(src, id)
    if not t then return false, err end
    local ok, n, total, label = Sell(src, t, P, item, amount)
    if not ok then return false, n end
    return true, _L('sold', n, label, Paid(t, total))
end)

-- sell every item the buyer wants, in one go
lib.callback.register('fks-gangs:shop:sellAll', function(src, id)
    local t, P, err = Check(src, id)
    if not t then return false, err end
    local units, total = 0, 0
    for _, it in ipairs(t.shop.items or {}) do
        if Bridge.ItemCount(src, it.item) > 0 then
            local ok, n, paid = Sell(src, t, P, it.item, 'all')
            if ok then units, total = units + n, total + paid end
        end
    end
    if units == 0 then return false, _L('nothing_to_sell') end
    return true, _L('sold_all', units, Paid(t, total))
end)

exports('GetShopPrice', function(id, item) return Prices[id] and Prices[id][item] end)
