-- Tables are created automatically on start (no SQL import needed).

DB = { ready = false }

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `fks_gang_territories` (
            `id`             VARCHAR(60) NOT NULL,
            `owner`          VARCHAR(60) NULL,
            `captured_at`    INT(11) NULL,
            `cooldown_until` INT(11) NOT NULL DEFAULT 0,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `fks_gang_hideouts` (
            `id`          INT(11) NOT NULL AUTO_INCREMENT,
            `name`        VARCHAR(60) NOT NULL,
            `coords`      VARCHAR(120) NOT NULL,
            `interior`    VARCHAR(60) NOT NULL,
            `price`       INT(11) NOT NULL DEFAULT 0,
            `currency`    ENUM('cash','gold') NOT NULL DEFAULT 'cash',
            `owner`       VARCHAR(60) NULL,
            `owner_name`  VARCHAR(80) NULL,
            `gang`        VARCHAR(60) NULL,
            `meta`        LONGTEXT NULL,
            `bought_at`   INT(11) NULL,
            `created_at`  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `idx_owner` (`owner`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `fks_gang_members` (
            `cid`        VARCHAR(60) NOT NULL,
            `hideout_id` INT(11) NOT NULL,
            `name`       VARCHAR(80) NOT NULL,
            `rank_id`    INT(11) NOT NULL,
            `joined_at`  INT(11) NOT NULL,
            PRIMARY KEY (`cid`),
            KEY `idx_hideout` (`hideout_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `fks_gang_ledger` (
            `id`         INT(11) NOT NULL AUTO_INCREMENT,
            `hideout_id` INT(11) NOT NULL,
            `name`       VARCHAR(80) NOT NULL,
            `amount`     INT(11) NOT NULL,
            `reason`     VARCHAR(40) NOT NULL,
            `at`         INT(11) NOT NULL,
            PRIMARY KEY (`id`),
            KEY `idx_hideout` (`hideout_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `fks_gang_reputation` (
            `gang`       VARCHAR(60) NOT NULL,
            `points`     INT(11) NOT NULL DEFAULT 0,
            `kills`      INT(11) NOT NULL DEFAULT 0,
            `captures`   INT(11) NOT NULL DEFAULT 0,
            `missions`   INT(11) NOT NULL DEFAULT 0,
            `decayed_at` INT(11) NOT NULL DEFAULT 0,
            PRIMARY KEY (`gang`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    DB.ready = true
end)

function DB.Wait()
    while not DB.ready do Wait(100) end
end

---------------------------------------------------------------------------
-- Territories
---------------------------------------------------------------------------
function DB.LoadTerritories()
    DB.Wait()
    return MySQL.query.await('SELECT * FROM fks_gang_territories') or {}
end

function DB.SaveTerritory(id, owner, capturedAt, cooldownUntil)
    MySQL.insert([[
        INSERT INTO fks_gang_territories (id, owner, captured_at, cooldown_until) VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE owner = VALUES(owner), captured_at = VALUES(captured_at), cooldown_until = VALUES(cooldown_until)
    ]], { id, owner, capturedAt, cooldownUntil or 0 })
end

---------------------------------------------------------------------------
-- Hideouts
---------------------------------------------------------------------------
function DB.LoadHideouts()
    DB.Wait()
    return MySQL.query.await('SELECT * FROM fks_gang_hideouts') or {}
end

function DB.CreateHideout(name, coords, interior, price, currency)
    return MySQL.insert.await('INSERT INTO fks_gang_hideouts (name, coords, interior, price, currency) VALUES (?, ?, ?, ?, ?)',
        { name, coords, interior, price, currency })
end

function DB.DeleteHideout(id)
    MySQL.update('DELETE FROM fks_gang_hideouts WHERE id = ?', { id })
end

-- owner = nil puts it back on sale
function DB.SetHideoutOwner(id, owner, ownerName, gang)
    MySQL.update('UPDATE fks_gang_hideouts SET owner = ?, owner_name = ?, gang = ?, bought_at = ? WHERE id = ?',
        { owner, ownerName, gang, owner and os.time() or nil, id })
end

function DB.SaveHideoutMeta(id, meta)
    MySQL.update('UPDATE fks_gang_hideouts SET meta = ? WHERE id = ?', { json.encode(meta), id })
end

---------------------------------------------------------------------------
-- Gang members / ledger history
---------------------------------------------------------------------------
function DB.LoadMembers()
    DB.Wait()
    return MySQL.query.await('SELECT * FROM fks_gang_members') or {}
end

function DB.SaveMember(m, hideoutId)
    MySQL.insert([[
        INSERT INTO fks_gang_members (cid, hideout_id, name, rank_id, joined_at) VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE hideout_id = VALUES(hideout_id), name = VALUES(name), rank_id = VALUES(rank_id)
    ]], { m.cid, hideoutId, m.name, m.rank, m.joined })
end

function DB.DeleteMember(cid)
    MySQL.update('DELETE FROM fks_gang_members WHERE cid = ?', { cid })
end

function DB.DeleteMembers(hideoutId)
    MySQL.update('DELETE FROM fks_gang_members WHERE hideout_id = ?', { hideoutId })
    MySQL.update('DELETE FROM fks_gang_ledger WHERE hideout_id = ?', { hideoutId })
end

function DB.LedgerLog(hideoutId, name, amount, reason)
    MySQL.insert('INSERT INTO fks_gang_ledger (hideout_id, name, amount, reason, at) VALUES (?, ?, ?, ?, ?)',
        { hideoutId, name, amount, reason, os.time() })
end

function DB.LedgerHistory(hideoutId, limit)
    return MySQL.query.await('SELECT name, amount, reason, at FROM fks_gang_ledger WHERE hideout_id = ? ORDER BY id DESC LIMIT ?',
        { hideoutId, limit }) or {}
end

---------------------------------------------------------------------------
-- Reputation
---------------------------------------------------------------------------
function DB.LoadReputation()
    DB.Wait()
    return MySQL.query.await('SELECT * FROM fks_gang_reputation') or {}
end

function DB.SaveReputation(gang, r)
    MySQL.insert([[
        INSERT INTO fks_gang_reputation (gang, points, kills, captures, missions, decayed_at) VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE points = VALUES(points), kills = VALUES(kills), captures = VALUES(captures),
            missions = VALUES(missions), decayed_at = VALUES(decayed_at)
    ]], { gang, r.points, r.kills, r.captures, r.missions, r.decayedAt or 0 })
end
