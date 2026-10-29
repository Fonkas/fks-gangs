---------------------------------------------------------------------------
-- Gang hideouts (client): door markers, prompts (buy / enter / knock / leave / open the door),
-- the admin creation form and the trip in and out of the interior.
---------------------------------------------------------------------------
if not Config.Hideouts.enabled then return end

local C = Config.Hideouts
local KVP = 'fks-gangs:inside'

-- what the other client files need: the hideout we are in and its stash / bench (client/gang.lua)
Hideout = { id = nil, interior = nil, props = {} }
local list = {}          -- what the server sent (with access flags for this player)
local insideId           -- hideout id while inside
local insideInterior     -- interior key while inside
local knock              -- { name, untilT } pending knock (while inside)
local blips = {}
local busy = false

local function Notify(msg, kind)
    Bridge.Notify({ title = _L('hideout'), description = msg, type = kind or 'inform' })
end

local function Price(n, cur)
    if cur == 'gold' then return ('%s %s'):format(Gangs.Fmt(n), _L('gold')) end
    return '$' .. Gangs.Fmt(n)
end

-- shells of the moonshine shacks
CreateThread(function()
    for _, imap in ipairs(Config.InteriorImaps) do RequestImap(joaat(imap)) end
end)

---------------------------------------------------------------------------
-- Prompts
---------------------------------------------------------------------------
local door = Prompts.Group()
local pBuy = Prompts.Make(door, Config.Keys.interact, _L('buy'), true)
local pEnter = Prompts.Make(door, Config.Keys.interact, _L('enter'), false)
local pKnock = Prompts.Make(door, Config.Keys.knock, _L('knock'), false)

local room = Prompts.Group()
local pLeave = Prompts.Make(room, Config.Keys.interact, _L('leave'), true)
local pOpen = Prompts.Make(room, Config.Keys.knock, _L('open_door'), false)

---------------------------------------------------------------------------
-- Blips
---------------------------------------------------------------------------
local function ClearBlips()
    for _, b in ipairs(blips) do Blips.Remove(b) end
    blips = {}
end

local function DrawBlips()
    ClearBlips()
    for _, h in ipairs(list) do
        -- on sale: everyone · owned: only the players of its gang (others only find the door by chance)
        if not h.owned and C.blip.forSale then
            blips[#blips + 1] = Blips.Point(h.coords, C.blip.forSaleSprite, _L('for_sale_blip', h.name))
        elseif h.owned and h.gangMember and C.blip.owned then
            blips[#blips + 1] = Blips.Point(h.coords, C.blip.ownedSprite, h.name)
        end
    end
end

---------------------------------------------------------------------------
-- Moving in and out
---------------------------------------------------------------------------
-- The player stays frozen behind a black screen until the ground (or the interior floor) under them has
-- loaded - the moonshine interiors float high in the sky, so landing before that means falling to death.
local function Teleport(c, interior)
    local ped = PlayerPedId()
    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(10) end

    local mount = GetMount(ped)
    if mount ~= 0 then TaskDismountAnimal(ped, 0, 0, 0, 0, 0) Wait(800) end
    FreezeEntityPosition(ped, true)
    SetEntityCoords(ped, c.x, c.y, c.z, false, false, false, false)
    SetEntityHeading(ped, c.w or 0.0)

    local t = GetGameTimer() + 8000
    while GetGameTimer() < t do
        RequestCollisionAtCoord(c.x, c.y, c.z)
        local ready = HasCollisionLoadedAroundEntity(ped)
        if ready and interior then
            local id = GetInteriorAtCoords(c.x, c.y, c.z)
            ready = id ~= 0 and IsInteriorReady(id)
        end
        if ready then break end
        Wait(100)
    end
    Wait(500)

    SetEntityCoords(ped, c.x, c.y, c.z, false, false, false, false)   -- again, now that the floor exists
    FreezeEntityPosition(ped, false)
    DoScreenFadeIn(800)
end

local function EnterInterior(id, key)
    local int = Config.Interiors[key]
    if not int then return end
    for _, imap in ipairs(Config.InteriorImaps) do RequestImap(joaat(imap)) end
    for _, set in ipairs(int.interior_sets or {}) do
        if not IsInteriorEntitySetActive(int.interior, set) then ActivateInteriorEntitySet(int.interior, set) end
    end
    insideId, insideInterior, knock = id, key, nil
    Hideout.id, Hideout.interior, Hideout.props = id, key, {}
    SetResourceKvp(KVP, tostring(id or 0))
    Teleport(int.inside, true)
    Hideout.props = lib.callback.await('fks-gangs:hideout:props', false) or {}
    TriggerEvent('fks-gangs:client:enteredHideout', id, key)
end

-- is the player standing in one of the interiors?
local function InAnInterior()
    local pos = GetEntityCoords(PlayerPedId())
    for _, int in pairs(Config.Interiors) do
        if #(pos - int.inside.xyz) < 60.0 then return true end
    end
    return false
end

local function Outside(coords)
    insideId, insideInterior, knock = nil, nil, nil
    Hideout.id, Hideout.interior, Hideout.props = nil, nil, {}
    TriggerEvent('fks-gangs:client:leftHideout')
    DeleteResourceKvp(KVP)
    if coords then Teleport(coords) end
end

-- let in by someone inside (the server already moved us into the instance)
RegisterNetEvent('fks-gangs:client:enterHideout', function(id, key)
    EnterInterior(id, key)
end)

RegisterNetEvent('fks-gangs:client:leaveHideout', function(coords)
    Outside(coords)
end)

RegisterNetEvent('fks-gangs:client:hideoutProps', function(id, props)
    if Hideout.id ~= id then return end
    Hideout.props = props or {}
    TriggerEvent('fks-gangs:client:propsChanged')
end)

RegisterNetEvent('fks-gangs:client:knock', function(name, timeout)
    if not insideId then return end
    knock = { name = name, untilT = GetGameTimer() + timeout * 1000 }
end)

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
local function Run(fn)
    if busy then return end
    busy = true
    CreateThread(function()
        fn()
        Wait(500)
        busy = false
    end)
end

local function Buy(h)
    Run(function()
        local ok = UI.Confirm({ title = _L('buy_title', h.name), text = _L('buy_text', Price(h.price, h.currency)), ok = _L('buy'), cancel = _L('cancel') })
        if not ok then return end
        local done, msg = lib.callback.await('fks-gangs:hideout:buy', false, h.id)
        Notify(msg or _L('error'), done and 'success' or 'error')
    end)
end

local function Enter(h)
    Run(function()
        local ok, res = lib.callback.await('fks-gangs:hideout:enter', false, h.id)
        if not ok then return Notify(res or _L('error'), 'error') end
        EnterInterior(h.id, res)
    end)
end

local function Leave()
    Run(function()
        local coords = lib.callback.await('fks-gangs:hideout:leave', false)
        if not coords then
            for _, h in ipairs(list) do if h.id == insideId then coords = h.coords end end
        end
        Outside(coords or C.fallbackExit)
    end)
end

local function LetIn()
    Run(function()
        local ok, msg = lib.callback.await('fks-gangs:hideout:letIn', false)
        knock = nil
        Notify(msg or _L('error'), ok and 'success' or 'error')
    end)
end

---------------------------------------------------------------------------
-- Admin: creation form (fks-core prompt)
---------------------------------------------------------------------------
RegisterNetEvent('fks-gangs:client:createHideout', function()
    local interiors = {}
    for key, int in pairs(Config.Interiors) do interiors[#interiors + 1] = { value = key, label = int.label or key } end
    table.sort(interiors, function(a, b) return a.label < b.label end)

    local gangs = { { value = '', label = _L('any_gang') } }
    for job, g in pairs(Config.Gangs) do gangs[#gangs + 1] = { value = job, label = g.label or job } end

    local fields = {
        { type = 'input', name = 'name', label = _L('gang_name'), max = 60, required = true },
        { type = 'select', name = 'gang', label = _L('hideout_gang'), value = '', options = gangs },
        { type = 'number', name = 'price', label = _L('price'), value = 1000, min = 0, max = 10000000, step = 1, quick = { 100, 1000, 10000 } },
        { type = 'select', name = 'currency', label = _L('currency'), value = 'cash',
          options = { { value = 'cash', label = _L('cash') }, { value = 'gold', label = _L('gold') } } },
    }
    -- only asked when there is more than one interior to choose from
    if #interiors > 1 then
        fields[#fields + 1] = { type = 'select', name = 'interior', label = _L('interior'), value = Config.DefaultInterior, options = interiors }
    end

    local v = UI.Prompt({ title = _L('create_title'), text = _L('create_text'), ok = _L('create'), cancel = _L('cancel'), fields = fields })
    if not v then return end
    v.interior = v.interior or Config.DefaultInterior
    local ok, msg = lib.callback.await('fks-gangs:hideout:create', false, v)
    Notify(msg or _L('error'), ok and 'success' or 'error')
end)

---------------------------------------------------------------------------
-- Sync
---------------------------------------------------------------------------
local function Load()
    local data, serverInside = lib.callback.await('fks-gangs:hideouts', false)
    list = data or {}
    DrawBlips()
    if serverInside and not insideId then
        -- resource restarted while inside
        for _, h in ipairs(list) do
            if h.id == serverInside then
                insideId, insideInterior = h.id, h.interior
                Hideout.id, Hideout.interior = h.id, h.interior
                Hideout.props = lib.callback.await('fks-gangs:hideout:props', false) or {}
                TriggerEvent('fks-gangs:client:enteredHideout', h.id, h.interior)
            end
        end
    end
end

RegisterNetEvent('fks-gangs:client:hideoutsChanged', function()
    if Bridge.IsLoggedIn() then Load() end
end)

Bridge.OnJobUpdate(Load)

-- hired / fired / promoted from a ledger (the framework may not tell us)
RegisterNetEvent('fks-gangs:client:jobChanged', function()
    SetTimeout(1000, function()
        Load()
        if Shop then Shop.Refresh() end
    end)
end)

-- out of an interior when the player is not really inside a hideout: to the door they came from, else fallbackExit
local function Rescue()
    local saved = GetResourceKvpString(KVP)
    local coords = lib.callback.await('fks-gangs:hideout:restore', false, saved)
    Outside(coords or C.fallbackExit)
end

Bridge.OnLoaded(function()
    Load()
    -- relog / crash inside a hideout
    if not insideId and (GetResourceKvpString(KVP) or InAnInterior()) then Rescue() end
end)

RegisterCommand(C.stuckCommand, function()
    if insideId then return Leave() end
    if InAnInterior() then Rescue() end
end, false)

---------------------------------------------------------------------------
-- Markers + prompts
---------------------------------------------------------------------------
local function DrawDoor(h)
    local m = C.marker
    local col = h.owned and m.owned or m.forSale
    Citizen.InvokeNative(0x2A32FAA57B937173, m.type, h.coords.x, h.coords.y, h.coords.z - 0.98, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        m.scale.x, m.scale.y, m.scale.z, col[1], col[2], col[3], col[4], false, false, 2, false, nil, nil, false) -- DrawMarker
end

CreateThread(function()
    while true do
        local wait = 750
        if Bridge.IsLoggedIn() then
            local pos = GetEntityCoords(PlayerPedId())

            if insideId then
                local int = Config.Interiors[insideInterior]
                if int and #(pos - int.inside.xyz) <= Config.InteractDistance then
                    wait = 0
                    local pending = knock and GetGameTimer() < knock.untilT
                    if not pending then knock = nil end
                    Prompts.Show(pLeave, true)
                    Prompts.Show(pOpen, pending == true)
                    if pending then Prompts.Text(pOpen, _L('open_door_for', knock.name)) end
                    Prompts.Active(room, _L('hideout'))
                    if Prompts.Done(pLeave, true) then Leave() end
                    if pending and Prompts.Done(pOpen) then LetIn() end
                elseif int then
                    wait = 250
                end
            else
                for _, h in ipairs(list) do
                    local d = #(pos - h.coords.xyz)
                    if d <= C.marker.distance then
                        wait = 0
                        if C.marker.enabled then DrawDoor(h) end
                        if d <= Config.InteractDistance and CanAct() then
                            Prompts.Show(pBuy, not h.owned)
                            Prompts.Show(pEnter, h.access == true)
                            Prompts.Show(pKnock, h.owned and not h.access)
                            if not h.owned then Prompts.Text(pBuy, _L('buy_for', Price(h.price, h.currency))) end
                            Prompts.Active(door, h.owned and _L('hideout_of', h.name) or _L('for_sale', h.name))
                            if not h.owned and Prompts.Done(pBuy, true) then Buy(h)
                            elseif h.access and Prompts.Done(pEnter) then Enter(h)
                            elseif h.owned and not h.access and Prompts.Done(pKnock) then
                                TriggerServerEvent('fks-gangs:hideout:knock', h.id)
                            end
                        end
                    end
                end
            end
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    ClearBlips()
    for _, p in ipairs({ pBuy, pEnter, pKnock, pLeave, pOpen }) do PromptDelete(p) end
end)
