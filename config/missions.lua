---------------------------------------------------------------------------
-- Contracts (missions) - started from the gang ledger, tab "Contracts", by members whose rank has the
-- "missions" permission. One contract at a time per player.
--
--   payTo       = where the money of a contract goes: 'ledger' (the gang's money) | 'player' (the player's pocket)
--                 (a gang without a hideout always gets it in the pocket)
--   cooldown    = minutes before the same gang can take the same contract again (counts from the start)
--   policeAlert = every player with a police job (Config.Police.jobs) is warned when a contract starts
--                 (each contract can override it with its own policeAlert = true / false)
--   rep         = reputation the gang gets (nil = Config.Reputation.points.mission)
---------------------------------------------------------------------------
Config.Missions = {
    enabled     = true,
    payTo       = 'ledger',
    cooldown    = 15,
    policeAlert = true,
    alertBlip   = 60,          -- seconds the police see a blip around the place (0 = no blip)
    alertRadius = 120.0,
    gpsRoute    = true,        -- GPS route to the place
    -- map areas: plain styles only (no icon in the middle). Others like -308585968 (herd) or 953018525 (bounty eye) add one
    areaStyles  = {            -- circle-only styles (see the colour list at the end of config/main.lua)
        target = 693035517,    -- hitman area, supply buyer
        danger = 693035517,    -- heist, police alert
    },
    sprites     = {            -- map icons (sprite name or hash)
        police   = 'blip_ambient_sheriff',
        delivery = 'blip_post_office',
    },

    ---------------------------------------------------------------------------
    -- 1. Hitman: a target is somewhere around one of the places. Kill them without being spotted.
    --    The detection meter (top right) fills while the target can see / hear you: crouch, stay behind
    --    them and do not run. Spotted = the target runs away and the contract fails (failOnSpotted).
    ---------------------------------------------------------------------------
    assassin = {
        enabled   = true,
        label     = 'Hitman for hire',
        desc      = 'Someone wants a man gone. Get close without being seen and finish him quietly.',
        icon      = 'spur',
        reward    = 50,
        rep       = 10,
        timeLimit = 30,                 -- minutes
        locations = {
            vector4(-5207.35, -2110.3, 12.67, 228.21),
            vector4(-2575.69, -1409.86, 145.81, 218.57),
            vector4(-1016.07, 1687.62, 242.92, 189.56),
            vector4(1599.27, 1460.25, 145.39, 281.86),
        },
        models    = { 'A_M_M_ValCriminals_01', 'A_M_M_RkrFancyTravellers_01', 'A_M_M_ValTownfolk_01' },
        scenarios = { 'WORLD_HUMAN_SMOKE', 'WORLD_HUMAN_DRINKING', 'WORLD_HUMAN_WRITE_NOTEBOOK', 'WORLD_HUMAN_COFFEE_DRINK' },
        areaRadius = 60.0,              -- the map shows an area this big (not the exact spot)
        failOnSpotted = true,
        stealth = {
            sight      = 22.0,          -- metres the target can see you standing / walking
            sightCrouch = 9.0,          -- ... crouched
            hearing    = 3.0,           -- metres where he hears you (not crouched)
            runBonus   = 10.0,          -- extra metres when you run
            fill       = 35.0,          -- % per second at point blank (less the further you are)
            drain      = 15.0,          -- % per second while he cannot see you
        },
    },

    ---------------------------------------------------------------------------
    -- 2. Supply run: outside the hideout use /spawnwagon, then take the wagon to the destination in time.
    --    Players of other gangs can steal it: climbing on the wagon shows "Steal" (hold E) and from then
    --    on the thief sees the destination and gets the reward if they deliver it.
    ---------------------------------------------------------------------------
    supply = {
        enabled     = true,
        label       = 'Supply run',
        desc        = 'A wagon full of supplies has to reach the buyer. Other gangs would love to have it.',
        icon        = 'wagon',
        reward      = 100,
        rep         = 10,
        command     = 'spawnwagon',
        spawnWithin = 10,               -- minutes to use the command after taking the contract
        timeLimit   = 30,               -- minutes to deliver (counts from the moment the wagon appears)
        model       = 'wagon05x',
        stealTime   = 5,                -- seconds holding E to steal it
        deliverRadius = 10.0,
        destinations = {
            vector3(2512.98, 2273.46, 176.69),
            vector3(1890.36, -752.03, 41.71),
            vector3(-1423.53, -2313.71, 42.99),
            vector3(-4180.33, -3409.57, 37.08),
        },
    },

    ---------------------------------------------------------------------------
    -- 3. Organized heist: armed men guard a chest. They open fire as soon as you get close (triggerRadius).
    --    The chest needs a lockpick (lockpick.item) - the minigame can be replaced, see README (SetLockpickMinigame).
    ---------------------------------------------------------------------------
    heist = {
        enabled   = true,
        label     = 'Organized heist',
        desc      = 'A guarded chest full of gold. Bring guns, bring friends, bring a lockpick.',
        icon      = 'box',
        reward    = 200,
        items     = { { item = 'barraouro', amount = 10 } },
        rep       = 15,
        timeLimit = 30,
        triggerRadius = 35.0,
        chestModel = 'p_strongbox_muddy_01x',
        enemies = {
            models   = { 'G_M_M_UniBanditos_01', 'G_M_M_UniBrontegang_01', 'G_M_M_UniDuster_01' },
            weapons  = { 'WEAPON_REPEATER_CARBINE', 'WEAPON_REVOLVER_SCHOFIELD', 'WEAPON_RIFLE_VARMINT' },
            accuracy = 40,
            health   = 200,
        },
        areas = {
            {
                chest = vector3(-3844.15, -3009.28, -6.88),
                enemies = {
                    vector4(-3847.89, -3020.25, -6.98, 289.11),
                    vector4(-3842.97, -3027.12, -7.23, 275.38),
                    vector4(-3833.91, -3013.49, -7.32, 159.75),
                    vector4(-3836.47, -3000.72, -6.76, 193.39),
                    vector4(-3845.35, -2999.15, -6.89, 217.65),
                },
            },
            {
                chest = vector3(-1893.73, 1330.7, 200.09),
                enemies = {
                    vector4(-1893.09, 1335.65, 200.09, 137.23),
                    vector4(-1891.55, 1339.94, 200.63, 223.73),
                    vector4(-1877.74, 1336.63, 201.33, 115.76),
                    vector4(-1888.33, 1343.24, 201.17, 181.01),
                    vector4(-1890.04, 1324.94, 199.65, 150.61),
                },
            },
        },
        lockpick = {
            item        = 'lockpick',
            consume     = true,         -- the lockpick is used up when the chest opens
            breakChance = 50,           -- % chance the lockpick breaks when the minigame fails
            -- default minigame (fks-core falling letters); another script can replace it (README)
            minigame    = { duration = 8000, fallTime = 2200, spawnEvery = 800, spawnEveryEnd = 550, letters = 'WASDQE' },
        },
    },
}
