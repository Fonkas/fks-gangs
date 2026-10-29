-- Client helpers: native prompts, blips, models.
Prompts, Blips = {}, {}

local function Var(text) return CreateVarString(10, 'LITERAL_STRING', text) end

function Prompts.Group()
    return GetRandomIntInRange(0, 0xffffff)
end

function Prompts.Make(group, key, text, hold)
    local p = PromptRegisterBegin()
    PromptSetControlAction(p, key)
    PromptSetText(p, Var(text))
    PromptSetEnabled(p, false)
    PromptSetVisible(p, false)
    -- hold = true (default time) or the time in ms
    if hold then PromptSetHoldMode(p, type(hold) == 'number' and hold or true) else PromptSetStandardMode(p, true) end
    PromptSetGroup(p, group, 0)
    PromptRegisterEnd(p)
    return p
end

function Prompts.Text(p, text) PromptSetText(p, Var(text)) end

function Prompts.Show(p, on)
    PromptSetVisible(p, on)
    PromptSetEnabled(p, on)
end

function Prompts.Active(group, label)
    PromptSetActiveGroupThisFrame(group, Var(label))
end

function Prompts.Done(p, hold)
    if hold then return PromptHasHoldModeCompleted(p) end
    return PromptHasStandardModeCompleted(p)
end

---------------------------------------------------------------------------
-- Blips
---------------------------------------------------------------------------
function Blips.Color(blip, modifier)
    if modifier then Citizen.InvokeNative(0x662D364ABF16DE2F, blip, joaat(modifier)) end  -- BlipAddModifier
end

-- area blip: its style is its colour (list at the end of config/main.lua)
-- what shows in the centre of the area depends on the style only (list at the end of config/main.lua)
function Blips.Radius(coords, radius, style, name)
    local blip = Citizen.InvokeNative(0x45F13B7E0A15C880, style, coords.x, coords.y, coords.z, radius + 0.0) -- BlipAddForRadius
    if name then Citizen.InvokeNative(0x9CB1A1623062F402, blip, name) end                                -- SetBlipName
    return blip
end

function Blips.Point(coords, sprite, name, modifier)
    local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, coords.x, coords.y, coords.z)  -- BlipAddForCoords
    SetBlipSprite(blip, type(sprite) == 'string' and joaat(sprite) or sprite, true)
    Citizen.InvokeNative(0x9CB1A1623062F402, blip, name)                                         -- SetBlipName
    Blips.Color(blip, modifier)
    return blip
end

function Blips.Remove(blip)
    if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
end

---------------------------------------------------------------------------
-- Models / peds
---------------------------------------------------------------------------
function LoadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < t do Wait(10) end
    return HasModelLoaded(hash) and hash or nil
end

-- RedM peds are invisible until they wear an outfit: give them a random one and wait until it has streamed in
function PedOutfit(ped)
    Citizen.InvokeNative(0x283978A15512B2FE, ped, true)                              -- SetRandomOutfitVariation
    local t = GetGameTimer() + 3000
    while not Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped) and GetGameTimer() < t do  -- IsPedReadyToRender
        Wait(10)
    end
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)    -- UpdatePedVariation
    SetEntityVisible(ped, true)
end

function SpawnNpc(model, c)
    local hash = LoadModel(model)
    if not hash then return nil end
    local ped = CreatePed(hash, c.x, c.y, c.z, c.w or 0.0, false, false, false, false)
    PedOutfit(ped)
    PlaceEntityOnGroundProperly(ped)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    SetModelAsNoLongerNeeded(hash)
    return ped
end

-- the `close` action has one handler per script: every file adds its own through OnUIClose
local closeCbs = {}
function OnUIClose(cb) closeCbs[#closeCbs + 1] = cb end
UI.On('close', function(d)
    for _, cb in ipairs(closeCbs) do cb(d) end
end)

function MyJob()
    return (Bridge.GetJob() or {}).name
end

function CanAct()
    local ped = PlayerPedId()
    return not IsEntityDead(ped) and not IsPedOnMount(ped) and not IsPedInAnyVehicle(ped, false) and not UI.IsOpen()
end
