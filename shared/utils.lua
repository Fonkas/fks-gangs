-- Shared helpers: gangs, law, territories.
Gangs = {}

Gangs.LAW = '@law'   -- "side" of the law in captures (never a job name)

local law = {}
for _, j in ipairs(Config.Police.jobs or {}) do law[j] = true end

local byId = {}
for i, t in ipairs(Config.Territories) do
    t.index = i
    byId[t.id] = t
end

function Gangs.Territory(id) return byId[id] end

function Gangs.IsGang(job) return job ~= nil and Config.Gangs[job] ~= nil end
function Gangs.IsLaw(job) return Config.Police.enabled and job ~= nil and law[job] == true end

-- side of a job in captures: gang job | Gangs.LAW | nil
function Gangs.Side(job)
    if Gangs.IsGang(job) then return job end
    if Gangs.IsLaw(job) then return Gangs.LAW end
    return nil
end

function Gangs.SideLabel(side)
    if not side then return _L('neutral') end
    if side == Gangs.LAW then return Config.Police.label end
    local g = side and Config.Gangs[side]
    return g and g.label or tostring(side)
end

-- map colour (area blip style) of a side; no side = neutral
function Gangs.SideStyle(side)
    if side == Gangs.LAW then return Config.Police.blipStyle end
    local g = side and Config.Gangs[side]
    return g and g.blipStyle or Config.Map.baseStyle
end

-- enemy setting of a territory (its own `enemies` table, else Config.Enemies); nil when it has no enemies
function Gangs.EnemyCfg(t, key)
    if t.enemies == false or not Config.Enemies.enabled then return nil end
    if type(t.enemies) == 'table' and t.enemies[key] ~= nil then return t.enemies[key] end
    return Config.Enemies[key]
end

-- capture setting of a territory (its own value, else Config.Capture)
function Gangs.Cfg(t, key)
    if t[key] ~= nil then return t[key] end
    return Config.Capture[key]
end

-- map setting of a territory (its own `map` table, else Config.Map)
function Gangs.MapCfg(t, key)
    if t.map and t.map[key] ~= nil then return t.map[key] end
    return Config.Map[key]
end

-- can this job capture this territory?
function Gangs.CanCapture(t, job)
    if Gangs.IsLaw(job) then return t.police ~= false and Config.Police.enabled end
    for _, j in ipairs(t.jobs or {}) do
        if j == job then return true end
    end
    return false
end

-- can this job sell in this territory's shop? (owner = current owner side)
function Gangs.CanSell(t, job, owner)
    local shop = t.shop
    if not shop or not shop.enabled or not Gangs.IsGang(job) then return false end
    if shop.ownerOnly ~= false then return owner == job end
    return Gangs.CanCapture(t, job)
end

function Gangs.Fmt(n)
    local x = math.floor((tonumber(n) or 0) + 0.5)
    local s = tostring(math.abs(x)):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
    return (x < 0 and '-' or '') .. s
end

-- "12:05" / "1:02:30"
function Gangs.Clock(sec)
    sec = math.max(0, math.floor(sec or 0))
    local h, m, s = sec // 3600, (sec % 3600) // 60, sec % 60
    if h > 0 then return ('%d:%02d:%02d'):format(h, m, s) end
    return ('%d:%02d'):format(m, s)
end
