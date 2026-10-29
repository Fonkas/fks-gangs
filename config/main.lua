Config = Config or {}

-- Server console: "up to date" / "OUTDATED" compared with the version in fxmanifest.lua on GitHub,
-- and a warning (with the download link) when fks-core (required) is not running
Config.VersionCheck = {
    enabled  = true,
    repo     = 'Fonkas/fks-gangs',      -- GitHub "user/repository"
    branch   = 'main',
    interval = 12,                      -- check again every X hours (0 = only on start)
    coreUrl  = 'https://github.com/Fonkas/fks-core',
}

Config.Debug = false                -- true: prints captures / purchases in the server console

-- Language: 'en' | 'pt' (files in locales/; missing keys fall back to English)
Config.Locale = 'en'

-- Framework: 'auto' | 'rsg' | 'vorp'
Config.Framework = 'auto'
-- RSG only: money account used as "gold" (rsg-core has no gold account by default; set nil to disable gold on RSG)
Config.RSGGoldAccount = 'gold'
-- Inventory: 'auto' | 'ox_inventory' | 'rsg-inventory' | 'vorp_inventory'
Config.Inventory = 'auto'
-- Admin groups (VORP groups / RSG permissions) allowed to use the admin commands
Config.AdminGroups = { 'admin', 'superadmin' }

---------------------------------------------------------------------------
-- Gangs
-- Every gang is a JOB. The key is the job name (exactly as in your framework).
--   label     = name shown in notifications
--   blipStyle = colour of the territory on the map while this gang owns it - every gang its own
--               (colour list at the end of this file: some colours also show a small ball / icon in the centre)
--   recipes   = what this gang can craft at its bench (config/gang.lua, Config.Recipes). nil = Config.Crafting.defaultRecipes
---------------------------------------------------------------------------
Config.Gangs = {
    gang1 = { label = 'Gang 1', blipStyle = 693035517, recipes = { 'lockpick', 'dynamite' } },   -- red (circle only)
    -- gang2 = { label = 'Gang 2', blipStyle = -1282792512 },  -- yellow
    -- gang3 = { label = 'Gang 3', blipStyle = 2098831270 },   -- white
    -- gang4 = { label = 'Gang 4', blipStyle = -1702907713 },  -- pink
    -- gang5 = { label = 'Gang 5', blipStyle = -700928964 },   -- gray
}

---------------------------------------------------------------------------
-- Law: can capture a territory that has an owner (Config.Territories[].police = false turns it off for one
-- territory) but NEVER has access to the shop. When the law wins, the territory goes back to neutral and the
-- player who started it gets a reward.
---------------------------------------------------------------------------
Config.Police = {
    enabled    = true,
    jobs       = { 'police' },
    label      = 'The Law',
    blipStyle  = 1673015813,            -- white (colour shown while the law is capturing)
    reward     = { min = 250, max = 350 },  -- cash for cleaning a territory (min = 0, max = 0 = no reward)
    noCooldown = true,                  -- the law is not affected by the capture cooldown
}

---------------------------------------------------------------------------
-- Capture rules (defaults for every territory - a territory can override any of these)
--
-- A capture is tied to the player who fired the shot: it is cancelled the moment that player dies,
-- leaves the area or disconnects.
---------------------------------------------------------------------------
Config.Capture = {
    duration      = 1,       -- minutes to capture a territory
    cooldown      = 30,       -- minutes before the same gang can start another capture (after a capture ends or is cancelled)
    cooldownScope = 'gang',   -- 'gang'      = the gang cannot capture ANY territory during the cooldown
                              -- 'territory' = only that territory is locked (for every gang)
    alertDelay    = 7,        -- seconds after the shot before every player online is warned (0 = right away)
    announceEnd   = true,     -- notification to every player online when a territory is captured / cleaned
    progressLabel = nil,      -- text of the progress bar (nil = locale 'progress_label')
}

---------------------------------------------------------------------------
-- Armed enemies that attack during a capture (spawned around the player who fired the shot).
-- A territory can have its own `enemies = { ... }` table to change any of these, or `enemies = false`.
---------------------------------------------------------------------------
Config.Enemies = {
    enabled   = true,
    models    = { 'G_M_M_UniBanditos_01', 'G_M_M_UniBrontegang_01', 'G_M_M_UniDuster_01' },
    weapons   = { 'WEAPON_REVOLVER_SCHOFIELD', 'WEAPON_REPEATER_CARBINE', 'WEAPON_REVOLVER_CATTLEMAN' },
    interval  = { min = 15, max = 45 },  -- seconds between waves (the first wave comes right after the shot)
    perWave   = { min = 1, max = 3 },    -- enemies per wave
    max       = 4,                       -- enemies alive at the same time
    accuracy  = 35,                      -- 0-100
    health    = 200,                     -- ped health (game default ~ 150-200)
    blip      = false,                   -- red blip on every enemy
    blipStyle = 953018525,               -- style of that blip (red bounty target)
    minDistance = 25.0,                  -- random spawn: at least this far from the player (when the territory has no spawnPoints)
    maxDistance = 60.0,                  -- random spawn: at most this far from the player
    sellerSafe  = 10.0,                  -- never spawn this close to the shop NPC
}

---------------------------------------------------------------------------
-- Map (territory blips)
--   visible   = show the territories on the map
--   visibleTo = 'all' (every player) | 'gangs' (only gang members and the law)
--   showNeutral = false: a territory with no owner is not on the map (like cap-territory); it shows with the
--                 colour of its gang once captured (and blinks while someone is capturing it)
--   baseStyle = colour of a territory with no owner (when showNeutral = true)
--   blink     = while a territory is being captured it alternates between its colour and the colour of
--               the side capturing it
---------------------------------------------------------------------------
Config.Map = {
    visible    = true,
    visibleTo  = 'all',
    showNeutral = false,
    baseStyle  = 693035517,          -- red
    blink      = true,
    blinkEvery = 1000,               -- ms between colour swaps
    showName   = false,              -- also an icon with the territory name in the middle of the area
    nameSprite = -392465725,         -- icon of that blip (hash or sprite name)
}

---------------------------------------------------------------------------
-- Keys (RedM control hashes)
---------------------------------------------------------------------------
Config.Keys = {
    interact = 0xCEFD9220,   -- E   hideout door / leave
    shop     = 0x760A9C6F,   -- G   talk to the shop NPC
    knock    = 0x760A9C6F,   -- G   knock at a hideout door / open the door from inside
    place    = 0x760A9C6F,   -- G   confirm where the stash / crafting bench goes
    cancel   = 0x156F7119,   -- BACKSPACE  cancel the placement
    rotate   = 0xDEB34313,   -- RIGHT ARROW  rotate while placing (LEFT ARROW 0xA65EBAB4 the other way)
    rotateBack = 0xA65EBAB4,
}

-- Item pictures in the shops. nil = taken from the inventory in use (vorp_inventory / rsg-inventory / ox_inventory).
-- Or your own folder, {name} = item name, e.g. 'nui://my_images/{name}.png'
Config.ItemImagePath = nil

Config.InteractDistance = 2.0   -- distance to the shop NPC / hideout door for the prompts to show
Config.NpcDistance = 60.0       -- distance at which the shop NPCs spawn

---------------------------------------------------------------------------
-- Territory colours (blipStyle / baseStyle). The colour IS the style of the area blip, and the style also decides
-- what shows in the middle of the area (the game draws it; it cannot be removed):
--   CIRCLE ONLY   693035517 (red)   - tested
--                 2098831270 (white, "no name") - not tested
--   SMALL BALL    1673015813 / -1559907306 (white) · -1282792512 / 2033377404 / 1247852480 / 227551412 (yellow)
--   ICON + NAME   red: 953018525 / 455691738 (bounty target), 662885764 / -1595050198 (lawman), -839369609 / 831283580 (enemy)
--                 yellow: -308585968 / 408396114 (destination x), -214162151 (straggler)
--                 white: -325639900 (pickup), -1749618580 (companion), 168093330 (destination), 486881925 (hat)
--                 gray: -678244495 (destination), -700928964 (herd), -89429847 / 422991367 (companion) · pink: -1702907713 (enemy)
---------------------------------------------------------------------------
