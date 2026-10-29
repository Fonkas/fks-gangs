---------------------------------------------------------------------------
-- Gang hideouts
--
-- Admins create them in game with /createganghideout (standing where the door should be):
-- name, gang (job) it is for, price, currency (cash / gold) and the interior. A marker shows on the ground
-- and it can be bought. After that:
--   * the owner and the members get "Enter" (and the ledger inside to run the gang - config/gang.lua)
--   * everyone else gets "Knock" - whoever is inside is warned and can open the door for them
--
-- Every hideout is its own instance (routing bucket), so several hideouts can use the same interior.
---------------------------------------------------------------------------

Config.Hideouts = {
    enabled       = true,
    createCommand = 'createganghideout',   -- admin: create a hideout where you stand
    deleteCommand = 'deleteganghideout',   -- admin: delete the nearest hideout (within 5 m)
    resetCommand  = 'resetganghideout',    -- admin: remove the owner of the nearest hideout (it goes back on sale)
    manageCommand = 'managehideouts',      -- admin: menu with every hideout (owner, give to a player, reset, delete, go there)

    maxPerPlayer  = 1,          -- hideouts one character can own
    requireGang   = true,       -- only players whose job is a gang (Config.Gangs) can buy one, and each gang owns
                                -- at most one hideout (hiring sets the job of the new member to that gang)
    memberAccess  = true,       -- everyone with the gang's job can enter (false = only the members hired in the ledger)
    allowTransfer = true,       -- the owner can hand the hideout over to a member of the gang (ledger, tab Hideout)
    knockTimeout  = 60,         -- seconds the people inside have to open the door after a knock
    bucketOffset  = 7000,       -- routing bucket of a hideout = bucketOffset + hideout id

    -- stuck inside an interior (crash, resource restart...): this command takes the player out
    stuckCommand  = 'hideoutexit',
    fallbackExit  = vector4(1514.6, 438.11, 89.93, 0.0),  -- used when the hideout the player came from is unknown

    marker = {                  -- marker on the ground at the door
        enabled  = true,
        type     = 0x94FDAE17,  -- cylinder
        scale    = vector3(1.2, 1.2, 0.4),
        forSale  = { 230, 180, 60, 120 },   -- r, g, b, alpha while it is on sale
        owned    = { 180, 40, 40, 120 },    -- r, g, b, alpha after it is bought
        distance = 25.0,        -- only drawn this close
    },

    blip = {
        forSale       = true,          -- map blip on hideouts that are on sale (everyone sees it)
        forSaleSprite = -392465725,
        owned         = true,          -- map blip with the hideout name, only for the players with its gang's job
        ownedSprite   = 1481032477,    -- (anyone who finds the door still sees the marker and can knock)
    },

    -- props placed by the gang from the ledger ("Place the stash" / "Place the crafting bench")
    props = {
        stash = 'p_chest01x',
        craft = 'p_workbench01x',
    },
}

---------------------------------------------------------------------------
-- Interiors (the same moonshine shacks as moonshine_interiors).
--   inside        = where you appear when entering (also where the "Leave" prompt is)
--   interior      = interior id
--   interior_sets = entity sets turned on (pick the look:
--                   https://github.com/femga/rdr3_discoveries/blob/master/interiors/interior_sets/README.md)
--   points        = fixed spots inside: ledger = the book where the gang is run (config/gang.lua)
--                   (the stash and the crafting bench are placed by each gang wherever they want)
---------------------------------------------------------------------------
Config.Interiors = {
    lemoyne = {
        label = 'Moonshine Shack (Lemoyne)',
        inside = vector4(1785.01, -821.53, 191.01, 0.0),
        interior = 77313,
        interior_sets = {
            'mp006_mshine_band2', 'mp006_mshine_bar_benchAndFrame', 'mp006_mshine_dressing_3',
            'mp006_mshine_hidden_door_open', 'mp006_mshine_location2', 'mp006_mshine_pic_04',
            'mp006_mshine_shelfwall1', 'mp006_mshine_shelfwall2', 'mp006_mshine_Still_03',
            'mp006_mshine_still_hatch', 'mp006_mshine_theme_hunter',
        },
        points = {
            ledger = vector3(1788.95, -812.4, 192.59),
        },
    },
    -- The other moonshine shacks below work the same way, but only Lemoyne is tested: its interior floats high
    -- in the sky, so nothing of the normal world can be seen or reached from inside (same as syn_underground).
    -- cattail_pond = {
    --     label = 'Moonshine Shack (Cattail Pond)',
    --     inside = vector4(-1085.63, 714.14, 83.23, 0.0),
    --     interior = 77569,
    --     interior_sets = {
    --         'mp006_mshine_band2', 'mp006_mshine_bar_benchAndFrame', 'mp006_mshine_dressing_1',
    --         'mp006_mshine_hidden_door_open', 'mp006_mshine_location1', 'mp006_mshine_pic_09',
    --         'mp006_mshine_shelfwall1', 'mp006_mshine_shelfwall2', 'mp006_mshine_Still_02',
    --         'mp006_mshine_still_hatch', 'mp006_mshine_theme_goth',
    --     },
    --     points = {},
    -- },
    -- new_austin = {
    --     label = 'Moonshine Shack (New Austin)',
    --     inside = vector4(-2769.3, -3048.87, -9.7, 0.0),
    --     interior = 78337,
    --     interior_sets = {
    --         'mp006_mshine_band2', 'mp006_mshine_bar_benchAndFrame', 'mp006_mshine_dressing_1',
    --         'mp006_mshine_hidden_door_open', 'mp006_mshine_location1', 'mp006_mshine_pic_09',
    --         'mp006_mshine_shelfwall1', 'mp006_mshine_shelfwall2', 'mp006_mshine_Still_02',
    --         'mp006_mshine_still_hatch', 'mp006_mshine_theme_refined',
    --     },
    --     points = {},
    -- },
    -- hanover = {
    --     label = 'Moonshine Shack (New Hanover)',
    --     inside = vector4(1627.64, 822.9, 123.94, 0.0),
    --     interior = 78593,
    --     interior_sets = {
    --         'mp006_mshine_band2', 'mp006_mshine_bar_benchAndFrame', 'mp006_mshine_dressing_1',
    --         'mp006_mshine_hidden_door_open', 'mp006_mshine_location1', 'mp006_mshine_pic_09',
    --         'mp006_mshine_shelfwall1', 'mp006_mshine_shelfwall2', 'mp006_mshine_Still_02',
    --         'mp006_mshine_still_hatch', 'mp006_mshine_theme_floral',
    --     },
    --     points = {},
    -- },
    -- manzanita_post = {
    --     label = 'Moonshine Shack (Manzanita Post)',
    --     inside = vector4(-1861.7, -1722.17, 88.35, 0.0),
    --     interior = 77825,
    --     interior_sets = {
    --         'mp006_mshine_band2', 'mp006_mshine_bar_benchAndFrame', 'mp006_mshine_dressing_1',
    --         'mp006_mshine_hidden_door_open', 'mp006_mshine_location1', 'mp006_mshine_pic_09',
    --         'mp006_mshine_shelfwall1', 'mp006_mshine_shelfwall2', 'mp006_mshine_Still_03',
    --         'mp006_mshine_still_hatch', 'mp006_mshine_theme_hunter',
    --     },
    --     points = {},
    -- },
}

Config.DefaultInterior = 'lemoyne'   -- interior pre-selected in /createganghideout

-- shells of the moonshine shacks (loaded on start - no need for moonshine_interiors)
Config.InteriorImaps = {
    'MP006_A3SUPP_MOONSHINE01', 'MP006_A3SUPP_MOONSHINE01_PLUG',
    'MP006_A2SUPP_MOONSHINE02', 'MP006_A2SUPP_MOONSHINE02_PLUG',
    'MP006_A4SUPP_MOONSHINE03', 'MP006_A4SUPP_MOONSHINE03_PLUG',
    'MP006_A1SUPP_MOONSHINE04', 'MP006_A1SUPP_MOONSHINE04_PLUG',
    'MP006_A4SUPP_MOONSHINE05', 'MP006_A4SUPP_MOONSHINE05_PLUG',
}
