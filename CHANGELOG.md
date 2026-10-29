# Changelog

## 1.0.0

First release. **Requires fks-core 2.1.2+**, ox_lib and oxmysql (VORP or RSG).

- **Territories:** a gang member fires one shot inside an area to start the capture: fks-core progress bar, armed
  enemy waves and a global warning. The capture is cancelled if the player dies, leaves or disconnects. The law
  cleans owned territories back to neutral. Each gang has its own map colour (`Config.Gangs`); unowned territories
  can be hidden (`Config.Map.showNeutral`).
- **Shops:** an NPC in each territory buys items only from the gang that owns it.
- **Hideouts:** buy a door, knock to be let in (members of the gang job walk straight in), a map blip only for the
  gang. Place a shared stash (default 1000 space) and a crafting bench with **G**.
- **Gang ledger** (wide fks-core panel): hire with an invite, fire (online or offline), custom ranks with
  permissions (level 4 = every power), gang money with history, hand the hideout to another member
  (`Config.Hideouts.allowTransfer`).
- **Crafting:** lockpick and dynamite recipes, choose the amount, see what you have and what is missing.
- **Reputation:** points for kills in territories, captures and contracts; tiers with perks (faster crafting,
  better shop prices, better contract pay).
- **Contracts:** hitman for hire (with a detection bar), supply run (`/spawnwagon`, other gangs can steal the cargo)
  and an organised heist (guards + lockpicked chest, minigame replaceable by export). 15 minute cooldown per gang,
  optional police alert, pay to the ledger or to the player (`Config.Missions.payTo`). A small box at the top
  centre shows the timer.
- **Admin:** `/managehideouts` lists every hideout to give it to a player, put it back on sale, delete it or go there.
- English and Portuguese locales. The server console warns when fks-core is missing and when a new version is out.
