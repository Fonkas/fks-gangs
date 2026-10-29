---------------------------------------------------------------------------
-- Jobs (hire / fire / promote). fks-core has no "set job" yet, so it is done here for VORP / RSG,
-- online (through the framework) and offline (straight in its database).
---------------------------------------------------------------------------
Framework = {}

-- server id of the character `cid` when online
function Framework.Online(cid)
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local P = Bridge.GetPlayer(src)
        if P and P.cid == cid then return src, P end
    end
end

local function JobLabel(job)
    local g = Config.Gangs[job]
    if g then return g.label end
    local rsg = Bridge.RSG()
    local j = rsg and rsg.Shared and rsg.Shared.Jobs and rsg.Shared.Jobs[job]
    return j and j.label or job
end

-- ok, error text
function Framework.SetJob(src, job, grade)
    grade = math.floor(tonumber(grade) or 0)
    local rsg, vorp = Bridge.RSG(), Bridge.VORP()
    if rsg then
        local P = rsg.Functions.GetPlayer(src)
        if not P then return false end
        local ok, res = pcall(P.Functions.SetJob, job, grade)
        if not ok or res == false then
            print(('^1[fks-gangs] rsg-core could not set job "%s" grade %d - add it to rsg-core/shared/jobs.lua^0'):format(job, grade))
            return false, _L('job_missing', job, grade)
        end
    elseif vorp then
        local user = vorp.getUser(src)
        local char = user and user.getUsedCharacter
        if not char then return false end
        local ok = pcall(function()
            char.setJob(job, true)
            char.setJobGrade(grade, true)
            char.setJobLabel(JobLabel(job), true)
        end)
        if not ok then return false end
    else
        return false
    end
    TriggerClientEvent('fks-gangs:client:jobChanged', src)
    return true
end

-- offline character: written in the framework's table (applied on their next login)
function Framework.SetJobOffline(cid, job, grade)
    grade = math.floor(tonumber(grade) or 0)
    if Bridge.Framework() == 'vorp' then
        MySQL.update('UPDATE characters SET job = ?, jobgrade = ?, joblabel = ? WHERE charidentifier = ?',
            { job, grade, JobLabel(job), tonumber(cid) or cid })
    elseif Bridge.Framework() == 'rsg' then
        local rsg = Bridge.RSG()
        local j = rsg and rsg.Shared.Jobs and rsg.Shared.Jobs[job] or {}
        local g = j.grades and (j.grades[tostring(grade)] or j.grades[grade]) or {}
        local data = {
            name = job, label = j.label or job, payment = g.payment or 0, onduty = j.defaultDuty ~= false,
            type = j.type, isboss = g.isboss == true, grade = { name = g.name or tostring(grade), level = grade },
        }
        MySQL.update('UPDATE players SET job = ? WHERE citizenid = ?', { json.encode(data), cid })
    end
end

-- online or offline
function Framework.SetJobAny(cid, job, grade)
    local src = Framework.Online(cid)
    if src then return Framework.SetJob(src, job, grade) end
    Framework.SetJobOffline(cid, job, grade)
    return true
end
