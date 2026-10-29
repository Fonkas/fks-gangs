-- fks-gangs · Copyright (C) 2026 FKS · Licensed under the GNU GPL v3 or later (see LICENSE)
fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

name 'fks-gangs'
author 'FKS'
description 'Gang territories (capture + shop), hideouts with a gang ledger, crafting, reputation and contracts for RedM (VORP / RSG)'
version '1.0.0'
license 'GPL-3.0-or-later'
fks_core_version '2.1.2' -- minimum fks-core version (VORP / RSG bridge, shared UI, notifications, progress bar)

shared_scripts {
    '@ox_lib/init.lua',
    '@fks-core/import.lua',
    'config/main.lua',
    'config/territories.lua',
    'config/hideouts.lua',
    'config/gang.lua',
    'config/missions.lua',
    'locales/*.lua',
    'shared/locale.lua',
    'shared/utils.lua',
}

client_scripts {
    'client/utils.lua',
    'client/enemies.lua',
    'client/territories.lua',
    'client/shop.lua',
    'client/hideouts.lua',
    'client/gang.lua',
    'client/crafting.lua',
    'client/missions.lua',
    'client/admin.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/version.lua',
    'server/db.lua',
    'server/framework.lua',
    'server/reputation.lua',
    'server/territories.lua',
    'server/shop.lua',
    'server/gang.lua',
    'server/hideouts.lua',
    'server/crafting.lua',
    'server/missions.lua',
    'server/admin.lua',
}

-- + fks-core 2.1.2+ (required: VORP / RSG bridge, shared UI, notifications) - https://github.com/Fonkas/fks-core
--   not listed below so that, when it is missing, the server console shows the download link (server/version.lua)
-- + a framework (rsg-core or vorp_core) and an inventory (ox_inventory, rsg-inventory or vorp_inventory)
dependencies {
    'ox_lib',
    'oxmysql',
}
