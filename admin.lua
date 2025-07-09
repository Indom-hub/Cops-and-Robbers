-- admin.lua
-- Cops & Robbers FiveM Game Mode - Admin Script
-- Version: 1.1 | Date: 2025-02-11
-- This file contains admin commands and ban management for the game mode.

-- Admin identifiers are now managed in config.lua (Config.Admins)

-- Ban management is handled by server.lua via events.

-----------------------------------------------------------
-- Helper Functions
-----------------------------------------------------------


-- Helper function to log admin commands (replaces TriggerServerEvent calls)
local function LogAdminCommand(source, rawCommand)
    print(string.format("[CNR_ADMIN_LOG] %s (ID: %s) executed: %s", SafeGetPlayerName(source), source, rawCommand))
end

-- Helper function to check if a player ID is valid (i.e. currently connected)
local function IsValidPlayer(targetId)
    targetId = tonumber(targetId)
    if not targetId then return false end

    for _, playerId in ipairs(GetPlayers()) do
        if tonumber(playerId) == targetId then
            return true
        end
    end
    return false
end

-----------------------------------------------------------
-- Admin Commands
-----------------------------------------------------------

-- Kick command
RegisterCommand("kick", function(source, args, rawCommand)
    if not IsPlayerAdmin(source) then
        TriggerClientEvent('chat:addMessage', source, { args = { "^1System", "You do not have permission to use this command." } })
        return
    end

    local targetIdStr = args[1]
    local targetId = tonumber(targetIdStr)

    if targetId and IsValidPlayer(targetId) then
        -- Log admin command (direct server-side logging)
        print(string.format("[CNR_ADMIN_LOG] %s (ID: %s) executed: %s", SafeGetPlayerName(source), source, rawCommand))
        DropPlayer(tostring(targetId), "You have been kicked by an admin.")
        TriggerClientEvent('chat:addMessage', -1, { args = { "^1Admin", "Player " .. SafeGetPlayerName(targetId) .. " has been kicked." } })
    else
        TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Invalid player ID: " .. (targetIdStr or "nil") } })
    end
end, false)

-- Ban command
RegisterCommand("ban", function(source, args, rawCommand)
    if not IsPlayerAdmin(source) then
        TriggerClientEvent('chat:addMessage', source, { args = { "^1System", "You do not have permission to use this command." } })
        return
    end

    local targetIdStr = args[1]
    local targetId = tonumber(targetIdStr)
    local reason = table.concat(args, " ", 2) -- Combine remaining args for reason

    if not reason or reason == "" then
        reason = "No reason provided."
    end
    
    if targetId and IsValidPlayer(targetId) then
        -- Log admin command (direct server-side logging)
        print(string.format("[CNR_ADMIN_LOG] %s (ID: %s) executed: %s", SafeGetPlayerName(source), source, rawCommand))
        
        -- Handle ban directly (since we're on server)
        local playerIdentifiers = SafeGetPlayerIdentifiers(targetId)
        if playerIdentifiers then
            -- Add to ban list (assuming there's a ban management system)
            TriggerEvent('cops_and_robbers:banPlayer', targetId, reason)
            TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Player " .. SafeGetPlayerName(targetId) .. " has been banned." } })
        else
            TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Failed to get player identifiers for ban." } })
        end
    else
        TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Invalid player ID: " .. (targetIdStr or "nil") } })
    end
end, false)

-- Set cash command
RegisterCommand("setcash", function(source, args, rawCommand)
    if not IsPlayerAdmin(source) then
        TriggerClientEvent('chat:addMessage', source, { args = { "^1System", "You do not have permission to use this command." } })
        return
    end

    local targetIdStr = args[1]
    local targetId = tonumber(targetIdStr)
    local amount = tonumber(args[2])    if targetId and IsValidPlayer(targetId) and amount then
        -- Log admin command (direct server-side logging)
        print(string.format("[CNR_ADMIN_LOG] %s (ID: %s) executed: %s", SafeGetPlayerName(source), source, rawCommand))
        
        -- Set cash directly (since we're already on server)
        local pData = GetCnrPlayerData(targetId)
        if pData then
            pData.cash = amount
            SaveCnrPlayerData(targetId, pData)
            TriggerClientEvent('cnr:updatePlayerData', targetId, pData.role, pData.cash, pData.xp, pData.level)
            TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Set cash for " .. SafeGetPlayerName(targetId) .. " to $" .. amount } })
        else
            TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Failed to find player data for ID: " .. targetId } })
        end
    else
        TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Invalid input. Usage: /setcash <playerId> <amount>" } })
    end
end, false)

-- Add cash command
RegisterCommand("addcash", function(source, args, rawCommand)
    if not IsPlayerAdmin(source) then
        TriggerClientEvent('chat:addMessage', source, { args = { "^1System", "You do not have permission to use this command." } })
        return
    end

    local targetIdStr = args[1]
    local targetId = tonumber(targetIdStr)
    local amount = tonumber(args[2])    if targetId and IsValidPlayer(targetId) and amount then
        -- Log admin command (direct server-side logging)
        print(string.format("[CNR_ADMIN_LOG] %s (ID: %s) executed: %s", SafeGetPlayerName(source), source, rawCommand))
        
        -- Add cash directly (since we're already on server)
        local pData = GetCnrPlayerData(targetId)
        if pData then
            pData.cash = (pData.cash or 0) + amount
            SaveCnrPlayerData(targetId, pData)
            TriggerClientEvent('cnr:updatePlayerData', targetId, pData.role, pData.cash, pData.xp, pData.level)
            TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Added $" .. amount .. " to " .. SafeGetPlayerName(targetId) } })
        else
            TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Failed to find player data for ID: " .. targetId } })
        end
    else
        TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Invalid input. Usage: /addcash <playerId> <amount>" } })
    end
end, false)

-- Remove cash command
RegisterCommand("removecash", function(source, args, rawCommand)
    if not IsPlayerAdmin(source) then
        TriggerClientEvent('chat:addMessage', source, { args = { "^1System", "You do not have permission to use this command." } })
        return
    end

    local targetIdStr = args[1]
    local targetId = tonumber(targetIdStr)
    local amount = tonumber(args[2])    if targetId and IsValidPlayer(targetId) and amount then
        -- Log admin command (direct server-side logging)
        print(string.format("[CNR_ADMIN_LOG] %s (ID: %s) executed: %s", SafeGetPlayerName(source), source, rawCommand))
        
        -- Remove cash directly (since we're already on server)
        local pData = GetCnrPlayerData(targetId)
        if pData then
            pData.cash = math.max(0, (pData.cash or 0) - amount)
            SaveCnrPlayerData(targetId, pData)
            TriggerClientEvent('cnr:updatePlayerData', targetId, pData.role, pData.cash, pData.xp, pData.level)
            TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Removed $" .. amount .. " from " .. SafeGetPlayerName(targetId) } })
        else
            TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Failed to find player data for ID: " .. targetId } })
        end
    else
        TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Invalid input. Usage: /removecash <playerId> <amount>" } })
    end
end, false)



-- Remove weapon command
RegisterCommand("removeweapon", function(source, args, rawCommand)
    if not IsPlayerAdmin(source) then
        TriggerClientEvent('chat:addMessage', source, { args = { "^1System", "You do not have permission to use this command." } })
        return
    end

    local targetIdStr = args[1]
    local targetId = tonumber(targetIdStr)
    local weaponName = args[2]    if targetId and IsValidPlayer(targetId) and weaponName then
        LogAdminCommand(source, rawCommand) -- Log before action
        TriggerEvent('cops_and_robbers:removeWeapon', targetId, weaponName) -- Changed to server event
        TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Removed weapon " .. weaponName .. " from " .. SafeGetPlayerName(targetId) } })
    else
        TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Invalid input. Usage: /removeweapon <playerId> <weaponName>" } })
    end
end, false)

-- Reassign team command
RegisterCommand("reassign", function(source, args, rawCommand)
    if not IsPlayerAdmin(source) then
        TriggerClientEvent('chat:addMessage', source, { args = { "^1System", "You do not have permission to use this command." } })
        return
    end
    
    local targetIdStr = args[1]
    local targetId = tonumber(targetIdStr)
    local newRole = args[2]   -- Should be "cop" or "robber"

    if targetId and IsValidPlayer(targetId) and (newRole == "cop" or newRole == "robber") then
        LogAdminCommand(source, rawCommand) -- Log before action
        TriggerEvent('cops_and_robbers:reassignRoleServer', targetId, newRole) -- Ensure server event handles all logic
        -- Client event 'cops_and_robbers:reassignRole' or 'cops_and_robbers:setRole' is triggered by server for target client
        TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Reassigned " .. SafeGetPlayerName(targetId) .. " to " .. newRole } })
    else
        TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Invalid input. Usage: /reassign <playerId> <cop|robber>" } })
    end
end, false)

-- Freeze command
RegisterCommand("freeze", function(source, args, rawCommand)
    if not IsPlayerAdmin(source) then
        TriggerClientEvent('chat:addMessage', source, { args = { "^1System", "You do not have permission to use this command." } })
        return
    end

    local targetIdStr = args[1]
    local targetId = tonumber(targetIdStr)    if targetId and IsValidPlayer(targetId) then
        LogAdminCommand(source, rawCommand) -- Log before action
        TriggerClientEvent('cops_and_robbers:toggleFreeze', targetId)
        TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Toggled freeze for " .. SafeGetPlayerName(targetId) } })
    else
        TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Invalid player ID: " .. (targetIdStr or "nil") } })
    end
end, false)

-- Teleport command
RegisterCommand("teleport", function(source, args, rawCommand)
    if not IsPlayerAdmin(source) then
        TriggerClientEvent('chat:addMessage', source, { args = { "^1System", "You do not have permission to use this command." } })
        return
    end

    local targetIdStr = args[1]
    local targetId = tonumber(targetIdStr)    if targetId and IsValidPlayer(targetId) then
        LogAdminCommand(source, rawCommand) -- Log before action
        TriggerClientEvent('cops_and_robbers:teleportToPlayer', source, targetId)
        TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Teleported to " .. SafeGetPlayerName(targetId) } })
    else
        TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Invalid player ID: " .. (targetIdStr or "nil") } })
    end
end, false)

-- =====================================
-- Scenario Trigger Commands
-- =====================================
RegisterCommand("triggerarmoredcar", function(source, args, rawCommand)
    if not IsPlayerAdmin(source) then
        TriggerClientEvent('chat:addMessage', source, { args = { "^1System", "You do not have permission to use this command." } })
        return
    end

    LogAdminCommand(source, rawCommand)
    TriggerEvent('cops_and_robbers:adminTriggerArmoredCar')
    TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Armored car event triggered." } })
end, false)

RegisterCommand("triggerbankheist", function(source, args, rawCommand)
    if not IsPlayerAdmin(source) then
        TriggerClientEvent('chat:addMessage', source, { args = { "^1System", "You do not have permission to use this command." } })
        return
    end

    local bankId = tonumber(args[1])
    if not bankId then
        TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Usage: /triggerbankheist <bankId>" } })
        return
    end
    
    LogAdminCommand(source, rawCommand)
    TriggerEvent('cops_and_robbers:adminTriggerBankHeist', bankId)
    TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Bank heist event triggered for bank ID: " .. bankId } })
end, false)

RegisterCommand("triggerstorerobbery", function(source, args, rawCommand)
    if not IsPlayerAdmin(source) then
        TriggerClientEvent('chat:addMessage', source, { args = { "^1System", "You do not have permission to use this command." } })
        return
    end

    local storeId = tonumber(args[1])
    if not storeId then
        TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Usage: /triggerstorerobbery <storeId>" } })
        return
    end
    
    LogAdminCommand(source, rawCommand)
    TriggerEvent('cops_and_robbers:adminTriggerStoreRobbery', storeId)
    TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Store robbery event triggered for store ID: " .. storeId } })
end, false)

RegisterCommand("triggerpoweroutage", function(source, args, rawCommand)
    if not IsPlayerAdmin(source) then
        TriggerClientEvent('chat:addMessage', source, { args = { "^1System", "You do not have permission to use this command." } })
        return
    end

    local gridId = tonumber(args[1])
    if not gridId then
        TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Usage: /triggerpoweroutage <gridId>" } })
        return
    end
    
    LogAdminCommand(source, rawCommand)
    TriggerEvent('cops_and_robbers:adminTriggerPowerOutage', gridId)
    TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Power outage event triggered for grid ID: " .. gridId } })
end, false)

-- Set level command
RegisterCommand("setlevel", function(source, args, rawCommand)
    if not IsPlayerAdmin(source) then
        TriggerClientEvent('chat:addMessage', source, { args = { "^1System", "You do not have permission to use this command." } })
        return
    end

    local targetId = tonumber(args[1])
    local newLevel = tonumber(args[2])

    if not targetId or not newLevel then
        TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Usage: /setlevel <playerId> <level>" } })
        return
    end

    if not IsValidPlayer(targetId) then
        TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Invalid player ID." } })
        return
    end
    
    if newLevel < 1 or newLevel > 100 then
        TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Level must be between 1 and 100." } })
        return
    end
    
    TriggerEvent('cops_and_robbers:logAdminCommand', SafeGetPlayerName(source), source, rawCommand)
    TriggerEvent('cops_and_robbers:adminSetLevel', targetId, newLevel)

    TriggerClientEvent('chat:addMessage', source, {
        args = { "^1Admin", string.format("Set level for %s to %d", SafeGetPlayerName(targetId), newLevel) }
    })
    TriggerClientEvent('chat:addMessage', targetId, {
        args = { "^1Admin", string.format("Admin set your level to %d", newLevel) }
    })
end, false)

-- Jail command
RegisterCommand("jail", function(source, args, rawCommand)
    if not IsPlayerAdmin(source) then
        TriggerClientEvent('chat:addMessage', source, { args = { "^1System", "You do not have permission to use this command." } })
        return
    end

    local targetIdStr = args[1]
    local durationStr = args[2]
    local reason = table.concat(args, " ", 3)

    local targetId = tonumber(targetIdStr)
    local durationSeconds = tonumber(durationStr)

    if not targetId or not IsValidPlayer(targetId) then
        TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Invalid or offline player ID: " .. (targetIdStr or "nil") } })
        return
    end

    if not durationSeconds or durationSeconds <= 0 then
        TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Invalid duration. Must be a positive number of seconds." } })
        return
    end

    reason = (reason and reason ~= "") and reason or "Jailed by Admin"

    -- Log admin command
    LogAdminCommand(source, rawCommand)

    -- Call the global SendToJail function from server.lua
    -- SendToJail = function(playerId, durationSeconds, arrestingOfficerId, arrestOptions)
    local adminName = SafeGetPlayerName(source)
    SendToJail(targetId, durationSeconds, adminName .. " (Admin)", {isAdminAction = true})

    TriggerClientEvent('chat:addMessage', -1, { args = { "^1Admin", string.format("Player %s (ID: %d) has been jailed by %s for %d seconds. Reason: %s", SafeGetPlayerName(targetId), targetId, adminName, durationSeconds, reason) } })
end, false)

-- Unjail command
RegisterCommand("unjail", function(source, args, rawCommand)
    if not IsPlayerAdmin(source) then
        TriggerClientEvent('chat:addMessage', source, { args = { "^1System", "You do not have permission to use this command." } })
        return
    end

    local targetIdStr = args[1]
    local reason = table.concat(args, " ", 2)
    local targetId = tonumber(targetIdStr)

    if not targetId then -- No need to check IsValidPlayer here, can unjail offline players by clearing their persisted data
        TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Invalid player ID: " .. (targetIdStr or "nil") } })
        return
    end

    local targetName = SafeGetPlayerName(targetId) -- Get name if online, otherwise will be "Unknown Player" or based on GetCnrPlayerData if enhanced
    local pData = GetCnrPlayerData(targetId)
    if not pData or not pData.jailData then
        if not jail[targetId] then -- Check live jail table too
             TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", string.format("Player %s (ID: %d) is not currently jailed.", targetName, targetId) } })
             return
        end
    end

    reason = (reason and reason ~= "") and reason or "Unjailed by Admin"

    LogAdminCommand(source, rawCommand)

    -- Call the global ForceReleasePlayerFromJail function from server.lua
    local success = ForceReleasePlayerFromJail(targetId, SafeGetPlayerName(source) .. " (Admin - Reason: " .. reason .. ")")

    if success then
        TriggerClientEvent('chat:addMessage', -1, { args = { "^1Admin", string.format("Player %s (ID: %d) has been unjailed by %s. Reason: %s", targetName, targetId, SafeGetPlayerName(source), reason) } })
    else
        TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", string.format("Failed to unjail player %s (ID: %d). Check server console.", targetName, targetId) } })
    end
end, false)

-- Checkjail command
RegisterCommand("checkjail", function(source, args, rawCommand)
    if not IsPlayerAdmin(source) then
        TriggerClientEvent('chat:addMessage', source, { args = { "^1System", "You do not have permission to use this command." } })
        return
    end

    local targetIdStr = args[1]
    local targetId = tonumber(targetIdStr)

    if not targetId then
        TriggerClientEvent('chat:addMessage', source, { args = { "^1Admin", "Invalid player ID: " .. (targetIdStr or "nil") } })
        return
    end

    local targetName = SafeGetPlayerName(targetId) -- Works if player is online

    -- Check live jail table first (for online players)
    if jail[targetId] and jail[targetId].remainingTime then
        TriggerClientEvent('chat:addMessage', source, { args = { "^3Jail Info", string.format("Player %s (ID: %d, Online) has %d seconds remaining.", targetName, targetId, jail[targetId].remainingTime) } })
        return
    end

    -- If not in live jail, check persisted data (for offline players or if not in live table for some reason)
    local pData = GetCnrPlayerData(targetId)
    if pData and pData.jailData and pData.jailData.originalDuration and pData.jailData.jailedTimestamp then
        local totalTimeElapsedSinceJailing = os.time() - pData.jailData.jailedTimestamp
        local calculatedRemainingTime = math.max(0, pData.jailData.originalDuration - totalTimeElapsedSinceJailing)

        if calculatedRemainingTime > 0 then
            TriggerClientEvent('chat:addMessage', source, { args = { "^3Jail Info", string.format("Player %s (ID: %d, Offline/Persisted) has approximately %d seconds remaining.", targetName, targetId, calculatedRemainingTime) } })
        else
            TriggerClientEvent('chat:addMessage', source, { args = { "^3Jail Info", string.format("Player %s (ID: %d, Offline/Persisted) should be released (jail time expired).", targetName, targetId) } })
        end
        return
    end

    TriggerClientEvent('chat:addMessage', source, { args = { "^3Jail Info", string.format("Player %s (ID: %d) is not found in jail records.", targetName, targetId) } })
end, false)
