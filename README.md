# fks-gangs

Gang territories, hideouts with a gang ledger, crafting, reputation and contracts for RedM (VORP / RSG).
Every screen and notification is drawn by **fks-core**.

## Installation

```cfg
ensure ox_lib
ensure oxmysql
ensure vorp_core        # or rsg-core
ensure vorp_inventory   # or rsg-inventory / ox_inventory
ensure fks-core         # 2.1.2 or newer
ensure fks-gangs
```

The database tables are created on start (`fks_gang_territories`, `fks_gang_hideouts`, `fks_gang_members`,
`fks_gang_ledger`, `fks_gang_reputation`).
The items used (`sunrise_moonshine`, ..., `lockpick`, `dynamite`, `barraferro`, `rubberr`, `polvora`, `barraouro`)
must exist in your inventory.

**RSG:** hiring sets the job of the new member to the gang job with the grade of their rank (0-4), so every gang
job needs the grades 0 to 4 in `rsg-core/shared/jobs.lua` (or set `Config.Ranks.setGrade = false`).

## Gangs

A gang is a **job**. Add every gang job to `Config.Gangs` (`config/main.lua`) with its label and map colour.
The law (`Config.Police.jobs`, default `police`) can capture territories too, but never uses the shops:
when the law wins, the territory goes back to neutral.

## Territories (`config/territories.lua`)

- Copy a block to add a territory: center, radius, which gangs can capture it, enemy spawn points, shop NPC and items.
- A member of an allowed gang goes inside the area and **fires one shot** -> the capture starts: that player gets
  the fks-core progress bar (with the percentage), armed enemies come in waves (`Config.Enemies`) and a few seconds
  later every player online is warned.
- The capture belongs to whoever fired: if they die, leave the area or disconnect, it is cancelled.
- Only one capture at a time per territory; cooldown per gang (or per territory) after a capture ends or is cancelled.
- The law cleans territories that have an owner (back to neutral) and gets a cash reward.
- Map: the colour of an area is its blip style (list at the end of `config/main.lua`). Neutral = red; owned = the
  gang's colour; while being captured it alternates with the capturing side's colour.
  `Config.Map.visible` / `visibleTo = 'all' | 'gangs'`.
- The buyer NPC is seen by everyone (`npcForAll = true`); only the owning gang can sell (`npcForAll = false` hides him from the others).
- Shop prices: `priceMode = 'random'` (rolled between min and max on every restart) or `'fixed'` (`price`).

Admin: `/territoryreset <id>` removes the owner and the cooldown.

## Hideouts (`config/hideouts.lua`)

- `/createganghideout` (admin), standing where the door should be: name, gang it is for (or any gang), price,
  cash / gold, interior.
- A marker shows on the ground. With `requireGang` only a gang can buy it, and each gang owns one hideout.
- The map blip (`ownedSprite = 1481032477`, with the hideout name) is only shown to the players with the gang's job.
  Anyone who finds the door still sees the marker and can **Knock** - the people inside are warned and can open.
- Owner, hired members (and everyone with the gang job, with `memberAccess`): **Enter**.
- Every hideout uses the Lemoyne moonshine interior (it floats in the sky) in its own instance (routing bucket),
  like another dimension: the door can be anywhere on the map. The player is held frozen behind a black screen
  until the interior has loaded.
- Stuck inside (crash, restart)? `/hideoutexit` takes the player back to the door (or `fallbackExit`).
- `/deleteganghideout` and `/resetganghideout` (admin) act on the nearest hideout.
- `/managehideouts` (admin): every hideout with its owner, gang, members and money - go to its door, give it to an
  online player (a member of its gang keeps the gang, anyone else starts a new one), put it back on sale or delete it.
- `allowTransfer = true`: the owner can hand the hideout over to a member of the gang (ledger, tab Hideout).

> `moonshine_interiors` is not needed (fks-gangs loads the shacks itself). If you keep it with
> `Config.UseTeleports = true`, its "Door" prompt shows inside the hideout too and takes the player to the shack
> outside - set it to `false` or remove it.

## Gang ledger (`config/gang.lua`)

The book inside the hideout (`Config.Interiors[].points.ledger`). Tabs:

- **Overview** - reputation tier, points, kills / territories / contracts and the perks of the gang.
- **Members** - hire (the player has to be next to you and accept; their job becomes the gang job), change rank, fire
  (online or offline; they get `Config.Ranks.firedJob`).
- **Ranks** - rename, create (up to `max`), delete, level 0-4 and permissions. **Level 4 = every power**: giving a
  level 4 rank to someone gives them the same powers as the owner. Lower levels never manage equal or higher ranks.
- **Money** - deposit / withdraw (`Config.Ledger.account`) and the last movements.
- **Contracts** - the missions (below).
- **Hideout** - place the **stash** (`Config.Stash.size`, default 1000) and the **crafting bench**: the ledger closes,
  a see-through prop follows you, **G** places it, arrows rotate, BACKSPACE cancels.

**Crafting** (`Config.Recipes`, which gang makes what: `Config.Gangs[job].recipes`): a card per recipe; on the recipe
page the amount updates the ingredients needed vs. what you have, and **Check my bag** reads your inventory again.
The ingredients are taken at the end of the progress bar.

**Reputation** (`Config.Reputation`): + kills of other players inside territories, + captures, + contracts; loses
`decay.amount` every `decay.everyHours`. Tiers give perks: faster crafting, +10% in the territory shops, +10% contract pay.

## Contracts (`config/missions.lua`)

Taken in the ledger, one at a time per player, `cooldown` (15 min) per gang + contract, optional police alert
(`policeAlert`, with a blip for `alertBlip` seconds). `payTo = 'ledger' | 'player'`.

1. **Hitman for hire** - a target somewhere in an area around one of 4 places. A detection meter (side card) fills
   while he can see / hear you: crouch, stay behind him, do not run. Spotted = he runs and the contract fails.
2. **Supply run** - outside the hideout use `/spawnwagon` and take the wagon to the buyer in 30 min. A player of
   another gang who climbs on it can hold **E** to steal it: they get the destination and the reward.
3. **Organized heist** - armed guards open fire when you get close; pick the lock of the chest (needs `lockpick`)
   for 10x `barraouro` + $200.

Another lockpick minigame (client):

```lua
exports['fks-gangs']:SetLockpickMinigame(function()
    return exports['my-lockpick']:Start()   -- true = opened, false = failed
end)
```

(or `Config.LockpickMinigame = function() ... end` in any shared config file). Default: fks-core falling letters.

## For developers

Server exports: `GetTerritoryOwner(id)`, `IsTerritoryBeingCaptured(id)`, `GetShopPrice(id, item)`,
`GetHideout(id)`, `GetPlayerHideout(src)`, `GetPlayerGangHideout(src)`, `GetGangLedger(hideoutId)`,
`AddGangLedger(hideoutId, amount, reason)`, `GetReputation(gang)`, `AddReputation(gang, points)`, `GetActiveMission(src)`.
Client export: `SetLockpickMinigame(fn)`.
Server events: `fks-gangs:captureStarted (id, side, src)`, `fks-gangs:territoryCaptured (id, owner, side)`,
`fks-gangs:captureFailed (id, side)`, `fks-gangs:itemSold (src, id, item, amount, total)`, `fks-gangs:hideoutBought (src, id)`,
`fks-gangs:crafted (src, item, amount)`, `fks-gangs:missionStarted / missionDone / missionFailed (src, id, ...)`,
`fks-gangs:reputationChanged (gang, points, kind, added)`.

## Credits

- Interface: drawn by [fks-core](https://github.com/Fonkas/fks-core) (fonts and their licenses live there).
- Built for the RedM community. Thanks to the Overextended (ox_lib, oxmysql), VORP and RSG teams.

---

## Contributing

Issues and pull requests are welcome. Please keep new texts in `locales/` (English is the base language) and test on
both VORP and RSG (the framework bridge lives in [fks-core](https://github.com/Fonkas/fks-core)).

---

## License

Copyright (C) 2026 FKS

This program is free software: you can redistribute it and/or modify it under the terms of the
**GNU General Public License** as published by the Free Software Foundation, either **version 3** of the License, or
(at your option) any later version. It is distributed in the hope that it will be useful, but **WITHOUT ANY WARRANTY**.
See [LICENSE](LICENSE) for the full text.
