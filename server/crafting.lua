---------------------------------------------------------------------------
-- Gang crafting bench: what the gang can make (Config.Gangs[job].recipes), the ingredients the player has,
-- and the craft itself. The ingredients are only taken at the end of the progress bar, after checking that
-- the time really passed.
---------------------------------------------------------------------------
local CR = Config.Crafting
local pending = {}       -- [src] = { id, n, startedAt, duration (ms) }

local function RecipesOf(gang)
    local g = gang and Config.Gangs[gang]
    return (g and g.recipes) or CR.defaultRecipes or {}
end

local function Allowed(gang, id)
    for _, r in ipairs(RecipesOf(gang)) do
        if r == id then return Config.Recipes[id] end
    end
end

-- ms one craft of `n` takes for this gang (reputation -> craftTime)
local function Duration(recipe, n, gang)
    return math.floor((recipe.time or 5) * n * Rep.Perk(gang, 'craftTime') * 1000)
end

local function Bench(src)
    local ctx, err = Gang.Inside(src, 'craft')
    if not ctx then return nil, err end
    if not ctx.h.meta.craft then return nil, _L('no_bench') end
    if not Gang.NearPoint(src, ctx.h.meta.craft) then return nil, _L('too_far') end
    return ctx
end

local function HasAll(src, recipe, n)
    for _, ing in ipairs(recipe.ingredients or {}) do
        if Bridge.ItemCount(src, ing.item) < ing.amount * n then return false, ing end
    end
    return true
end

lib.callback.register('fks-gangs:craft:open', function(src)
    local ctx, err = Bench(src)
    if not ctx then return { ok = false, error = err } end
    local gang = ctx.h.gang
    local list = {}
    for _, id in ipairs(RecipesOf(gang)) do
        local r = Config.Recipes[id]
        if r then
            local ings = {}
            for _, ing in ipairs(r.ingredients or {}) do
                ings[#ings + 1] = {
                    item = ing.item, label = Bridge.ItemLabel(ing.item), img = ItemImage({ item = ing.item }),
                    need = ing.amount, have = Bridge.ItemCount(src, ing.item),
                }
            end
            list[#list + 1] = {
                id = id, item = id, label = r.label or Bridge.ItemLabel(id), img = ItemImage({ item = id, image = r.image }),
                amount = r.amount or 1, time = Duration(r, 1, gang) / 1000, ingredients = ings,
            }
        end
    end
    local _, tier = Rep.Tier(gang)
    return {
        ok = true, recipes = list, max = CR.maxAmount or 25,
        speed = math.floor((1 - Rep.Perk(gang, 'craftTime')) * 100 + 0.5), tier = tier and tier.label,
    }
end)

-- fresh counts of the ingredients ("Check my bag")
lib.callback.register('fks-gangs:craft:counts', function(src, id)
    local ctx = Bench(src)
    local r = ctx and Allowed(ctx.h.gang, id)
    if not r then return nil end
    local counts = {}
    for _, ing in ipairs(r.ingredients or {}) do counts[ing.item] = Bridge.ItemCount(src, ing.item) end
    return counts
end)

lib.callback.register('fks-gangs:craft:start', function(src, id, n)
    local ctx, err = Bench(src)
    if not ctx then return false, err end
    local r = Allowed(ctx.h.gang, id)
    if not r then return false, _L('error') end
    n = math.floor(tonumber(n) or 0)
    if n < 1 or n > (CR.maxAmount or 25) then return false, _L('invalid_amount') end
    local ok, missing = HasAll(src, r, n)
    if not ok then return false, _L('craft_missing', missing.amount * n, Bridge.ItemLabel(missing.item)) end
    if not Bridge.CanCarry(src, id, (r.amount or 1) * n) then return false, _L('craft_no_room') end
    local duration = Duration(r, n, ctx.h.gang)
    pending[src] = { id = id, n = n, startedAt = GetGameTimer(), duration = duration }
    return true, duration
end)

lib.callback.register('fks-gangs:craft:finish', function(src)
    local job = pending[src]
    pending[src] = nil
    if not job then return false, _L('error') end
    if GetGameTimer() - job.startedAt < job.duration - 1500 then return false, _L('error') end
    local ctx, err = Bench(src)
    if not ctx then return false, err end
    local r = Allowed(ctx.h.gang, job.id)
    if not r then return false, _L('error') end
    local ok, missing = HasAll(src, r, job.n)
    if not ok then return false, _L('craft_missing', missing.amount * job.n, Bridge.ItemLabel(missing.item)) end

    for _, ing in ipairs(r.ingredients or {}) do
        if not Bridge.RemoveItem(src, ing.item, ing.amount * job.n) then return false, _L('error') end
    end
    local made = (r.amount or 1) * job.n
    Bridge.AddItem(src, job.id, made)
    TriggerEvent('fks-gangs:crafted', src, job.id, made)
    return true, _L('crafted', made, r.label or Bridge.ItemLabel(job.id))
end)

RegisterNetEvent('fks-gangs:server:craftCancel', function()
    pending[source] = nil
end)

AddEventHandler('playerDropped', function()
    pending[source] = nil
end)
