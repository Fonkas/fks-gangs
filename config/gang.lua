---------------------------------------------------------------------------
-- The gang ledger (the book inside the hideout - Config.Interiors[].points.ledger)
--
-- Whoever bought the hideout runs the gang from it: hire / fire players, ranks, the gang's money,
-- where the stash and the crafting bench go, the reputation and the contracts (config/missions.lua).
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Ranks
--   level 0-4 = power of the rank. Level 4 (bossLevel) can do EVERYTHING in the ledger: giving a level 4 rank
--   to another player gives them the same powers as the owner. Lower levels only do what their
--   permissions allow, and can never hire / promote / fire someone of their own level or higher.
--   The gang can rename these, create more and change their permissions in the ledger.
--
--   setGrade = true: the job grade of a member follows the level of their rank (hire / promote).
--   RSG: the gang job must exist in rsg-core/shared/jobs.lua with the grades 0 to 4.
---------------------------------------------------------------------------
Config.Ranks = {
    bossLevel = 4,
    setGrade  = true,
    max       = 10,              -- ranks a gang can have
    firedJob  = 'unemployed',    -- job given to a fired member (grade 0)

    -- permissions shown in the ledger (labels in the locales: perm_<name>)
    permissions = { 'deposit', 'withdraw', 'hire', 'fire', 'ranks', 'stash', 'craft', 'missions', 'place' },

    -- ranks of a new gang (the last one is given to whoever buys the hideout)
    default = {
        { name = 'Recruit',    level = 0, perms = { 'deposit', 'missions' } },
        { name = 'Member',     level = 1, perms = { 'deposit', 'missions', 'stash', 'craft' } },
        { name = 'Enforcer',   level = 2, perms = { 'deposit', 'missions', 'stash', 'craft', 'hire' } },
        { name = 'Lieutenant', level = 3, perms = { 'deposit', 'withdraw', 'missions', 'stash', 'craft', 'hire', 'fire' } },
        { name = 'Boss',       level = 4, perms = {} },   -- level 4 = everything
    },
}

---------------------------------------------------------------------------
-- Gang ledger (money of the gang)
---------------------------------------------------------------------------
Config.Ledger = {
    account    = 'cash',   -- what goes in and out: 'cash' | 'gold'
    history    = 25,       -- last movements shown in the ledger
    hireRange  = 10.0,     -- the player to hire has to be this close (inside the hideout)
}

---------------------------------------------------------------------------
-- Gang stash (placed by the gang from the ledger)
--   size: vorp_inventory = number of items it holds · ox_inventory / rsg-inventory = weight in kg
---------------------------------------------------------------------------
Config.Stash = {
    size  = 1000,
    slots = 100,           -- ox_inventory / rsg-inventory: slots of the grid
}

---------------------------------------------------------------------------
-- Crafting (bench placed by the gang from the ledger)
--   Every recipe: label (nil = item label), amount made per craft, time in seconds per craft,
--   ingredients = { { item, amount } }
--   Which recipes a gang can make: Config.Gangs[job].recipes = { 'lockpick', ... } in config/main.lua,
--   else Config.Crafting.defaultRecipes.
--   The reputation can make crafting faster (Config.Reputation tiers -> craftTime).
---------------------------------------------------------------------------
Config.Crafting = {
    maxAmount      = 25,    -- most crafts in one go
    defaultRecipes = { 'lockpick', 'dynamite' },
    anim = { dict = 'mech_inventory@crafting@fallbacks', clip = 'full_craft_and_stow', flag = 17 },
}

Config.Recipes = {
    lockpick = {
        amount = 1,
        time   = 8,
        ingredients = {
            { item = 'barraferro', amount = 2 },
        },
    },
    dynamite = {
        amount = 1,
        time   = 15,
        ingredients = {
            { item = 'rubberr', amount = 2 },
            { item = 'polvora', amount = 2 },
        },
    },
    -- my_item = { label = 'My item', amount = 2, time = 10, ingredients = { { item = 'wood', amount = 3 } } },
}

---------------------------------------------------------------------------
-- Reputation: every gang (job) has its own. It goes up with:
--   kill     = a player of another gang (or no gang) killed by a member inside a territory
--   capture  = a territory captured
--   mission  = a contract done (each mission can give its own amount - config/missions.lua)
-- and goes down with time (decay) - a gang has to keep it up.
-- Higher tiers give perks to the whole gang:
--   craftTime    = multiplier of the crafting time (0.8 = 20% faster)
--   shopBonus    = more money when selling in the territory shops (0.10 = +10%)
--   missionBonus = more money from contracts (0.10 = +10%)
---------------------------------------------------------------------------
Config.Reputation = {
    enabled = true,
    points  = { kill = 2, capture = 25, mission = 10 },
    killCooldown = 300,     -- seconds: the same killer / victim pair only counts once in this time (no farming)

    decay = { enabled = true, amount = 10, everyHours = 24 },   -- loses `amount` every `everyHours` (never below 0)

    tiers = {
        { label = 'Unknown',   min = 0 },
        { label = 'Known',     min = 100,  perks = { craftTime = 0.9 } },
        { label = 'Respected', min = 250,  perks = { craftTime = 0.8, shopBonus = 0.10 } },
        { label = 'Feared',    min = 500,  perks = { craftTime = 0.7, shopBonus = 0.10, missionBonus = 0.10 } },
        { label = 'Legendary', min = 1000, perks = { craftTime = 0.5, shopBonus = 0.10, missionBonus = 0.10 } },
    },
}
