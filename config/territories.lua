---------------------------------------------------------------------------
-- Territories - copy a whole { ... } block to add as many as you want.
--
-- How a capture works:
--   1. A player whose job is in `jobs` (or the law, see Config.Police) goes inside the area.
--   2. They fire ONE shot (in the air is fine) -> the capture starts, a progress bar shows for that player
--      and armed enemies start to come (Config.Enemies). A few seconds later every player online is warned.
--   3. If that player dies, leaves the area or disconnects, the capture is cancelled (and the cooldown starts).
--   4. Only one capture at a time per territory.
--   5. When the bar reaches 100% the territory belongs to that gang (the law makes it neutral again).
--   6. The owning gang can sell the items of `shop.items` to the shop NPC of the territory.
--
-- Any key of Config.Capture (duration, cooldown, cooldownScope, alertDelay, announceEnd) can be set inside a
-- territory to override it for that territory only.
---------------------------------------------------------------------------

Config.Territories = {
    {
        id     = 'test_territory',                       -- unique id (saved in the database - do not change it later)
        label  = 'Test Territory',                       -- name used in notifications
        coords = vector3(-5740.59, -4519.87, -8.21),     -- center of the area
        radius = 100.0,                                  -- size of the area (metres from the center)

        jobs   = { 'gang1' },                            -- gangs (jobs from Config.Gangs) that can capture it
        police = true,                                   -- the law can capture it (to clean it); false = not here

        -- map: nil = use Config.Map. Override per territory, e.g. map = { visible = false } or map = { visibleTo = 'gangs' }
        -- map = { visible = true, visibleTo = 'all' },

        -- where the armed enemies appear (picked at random). Empty / missing = random spots around the player.
        spawnPoints = {
            -- vector3(x, y, z),
        },
        -- enemies = { max = 6, perWave = { min = 2, max = 4 } },   -- per-territory override of Config.Enemies (false = none)

        shop = {
            enabled = true,
            label   = 'Moonshine Buyer',                 -- title of the shop window
            npc     = {
                model  = 'u_m_m_valbartender_01',        -- ped model of the buyer
                coords = vector4(-5755.11, -4518.49, -7.2, 287.53),
            },
            ownerOnly = true,                            -- true: only the gang that owns the territory can sell
                                                         -- false: any gang of `jobs` can sell (the law never can)
            npcForAll = true,                            -- true: everyone sees the NPC (the others are told he only deals with the owner)
                                                         -- false: the NPC only exists for players who can sell to him

            -- price mode:
            --   'random' = a price between min and max is rolled ONCE every server restart
            --   'fixed'  = always `price` (or min when `price` is missing)
            priceMode = 'random',

            account    = 'cash',                         -- what the buyer pays with: 'cash' | 'gold'
            maxPerSale = 0,                              -- max units of one item per sale (0 = no limit)

            items = {
                { item = 'sunrise_moonshine',  min = 50,  max = 100, price = 75  },
                { item = 'tropical_moonshine', min = 70,  max = 120, price = 95  },
                { item = 'berry_moonshine',    min = 30,  max = 50,  price = 40  },
                { item = 'wild_moonshine',     min = 100, max = 150, price = 125 },
                -- { item = 'item_name', label = 'Optional label', min = 10, max = 20, price = 15,
                --   desc = 'Optional line shown on the item page', image = 'nui://my_resource/img/item.png' },
                -- (the picture comes from your inventory by default - see Config.ItemImagePath in config/main.lua)
            },
        },
    },

    -- {
    --     id     = 'another_territory',
    --     label  = 'Another Territory',
    --     coords = vector3(0.0, 0.0, 0.0),
    --     radius = 80.0,
    --     jobs   = { 'gang1', 'gang2' },
    --     police = true,
    --     spawnPoints = { vector3(0.0, 0.0, 0.0), vector3(0.0, 0.0, 0.0) },
    --     shop = {
    --         enabled = true,
    --         label = 'Buyer',
    --         npc = { model = 'u_m_m_valbartender_01', coords = vector4(0.0, 0.0, 0.0, 0.0) },
    --         ownerOnly = true,
    --         npcForAll = false,
    --         priceMode = 'fixed',
    --         account = 'cash',
    --         maxPerSale = 0,
    --         items = {
    --             { item = 'sunrise_moonshine', min = 50, max = 100, price = 80 },
    --         },
    --     },
    -- },
}
