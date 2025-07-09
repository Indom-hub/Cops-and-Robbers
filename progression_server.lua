-- progression_server.lua
-- Enhanced Experience and Leveling System for Cops and Robbers
-- Handles all progression-related server logic including XP, levels, perks, and rewards

-- =========================
-- Global Variables
-- =========================
local playerPerks = {} -- Store active perks for each player
local playerChallenges = {} -- Store challenge progress for each player
local activeSeasonalEvent = nil -- Current seasonal event
local prestigeData = {} -- Store prestige information

-- =========================
-- Utility Functions
-- =========================


-- Calculate total XP required to reach a specific level
local function CalculateTotalXPForLevel(targetLevel, role)
    if not Config.LevelingSystemEnabled then return 0 end
    
    local totalXP = 0
    for level = 1, math.min(targetLevel - 1, Config.MaxLevel - 1) do
        local xpForNext = (Config.XPTable and Config.XPTable[level]) or 1000
        totalXP = totalXP + xpForNext
    end
    return totalXP
end

-- Calculate XP needed for next level
local function CalculateXPForNextLevel(currentLevel, role)
    if not Config.LevelingSystemEnabled or currentLevel >= Config.MaxLevel then 
        return 0 
    end
    
    return (Config.XPTable and Config.XPTable[currentLevel]) or 1000
end

-- =========================
-- Enhanced Level Calculation
-- =========================

function CalculateLevel(xp, role)
    if not Config.LevelingSystemEnabled then return 1 end
    
    local currentLevel = 1
    local cumulativeXp = 0
    
    -- Apply prestige XP multiplier if applicable
    local playerId = source
    if playerId and prestigeData[playerId] and prestigeData[playerId].level > 0 then
        local prestigeReward = Config.PrestigeSystem.prestigeRewards[prestigeData[playerId].level]
        if prestigeReward and prestigeReward.xpMultiplier then
            xp = math.floor(xp * prestigeReward.xpMultiplier)
        end
    end
    
    -- Iterate through XP table to find current level
    for level = 1, (Config.MaxLevel or 50) - 1 do
        local xpForNext = (Config.XPTable and Config.XPTable[level]) or 1000
        cumulativeXp = cumulativeXp + xpForNext
        if xp >= cumulativeXp then
            currentLevel = level + 1
        else
            break
        end
    end
    
    return math.min(currentLevel, Config.MaxLevel)
end

-- =========================
-- Enhanced ApplyPerks Function
-- =========================

function ApplyPerks(playerId, level, role)
    if not Config.LevelingSystemEnabled then return end
    
    local pIdNum = tonumber(playerId)
    if not pIdNum then return end
    
    -- Initialize player perks if not exists
    if not playerPerks[pIdNum] then
        playerPerks[pIdNum] = {}
    end
    
    -- Clear existing perks
    playerPerks[pIdNum] = {}
    
    -- Apply all perks up to current level
    local unlocks = Config.LevelUnlocks[role]
    if not unlocks then return end
    
    for unlockLevel = 1, level do
        local levelUnlocks = unlocks[unlockLevel]
        if levelUnlocks then
            for _, unlock in ipairs(levelUnlocks) do
                if unlock.type == "passive_perk" then
                    playerPerks[pIdNum][unlock.perkId] = unlock.value
                    Log(string.format("Applied perk %s to player %s (value: %s)", unlock.perkId, pIdNum, tostring(unlock.value)), "info", "CNR_PROGRESSION")
                end
            end
        end
    end
    
    -- Apply prestige perks
    if prestigeData[pIdNum] and prestigeData[pIdNum].level > 0 then
        local prestigeReward = Config.PrestigeSystem.prestigeRewards[prestigeData[pIdNum].level]
        if prestigeReward then
            playerPerks[pIdNum]["prestige_xp_multiplier"] = prestigeReward.xpMultiplier
            playerPerks[pIdNum]["prestige_title"] = prestigeReward.title
        end
    end
    
    Log(string.format("Applied perks for player %s (Level %d, Role %s)", pIdNum, level, role), "info", "CNR_PROGRESSION")
end

-- =========================
-- Enhanced AddXP Function
-- =========================

function AddXP(playerId, amount, type, reason)
    local pIdNum = tonumber(playerId)
    if not pIdNum then return end
    
    local pData = GetCnrPlayerData(pIdNum)
    if not pData then return end
    
    -- Validate role type
    if type and pData.role ~= type and type ~= "general" then return end
    
    -- Apply seasonal event multiplier
    if activeSeasonalEvent and activeSeasonalEvent.effects then
        local effects = activeSeasonalEvent.effects
        if effects.role == "all" or effects.role == pData.role then
            amount = math.floor(amount * (effects.xpMultiplier or 1.0))
        end
    end
    
    -- Apply prestige multiplier
    if prestigeData[pIdNum] and prestigeData[pIdNum].level > 0 then
        local prestigeReward = Config.PrestigeSystem.prestigeRewards[prestigeData[pIdNum].level]
        if prestigeReward and prestigeReward.xpMultiplier then
            amount = math.floor(amount * prestigeReward.xpMultiplier)
        end
    end
    
    -- Apply perk multipliers
    if playerPerks[pIdNum] then
        if playerPerks[pIdNum]["arrest_bonus"] and reason and string.find(reason, "arrest") then
            amount = math.floor(amount * playerPerks[pIdNum]["arrest_bonus"])
        elseif playerPerks[pIdNum]["master_thief"] and reason and string.find(reason, "heist") then
            amount = math.floor(amount * playerPerks[pIdNum]["master_thief"])
        end
    end
    
    -- Add XP
    local oldXP = pData.xp or 0
    pData.xp = oldXP + amount
    
    -- Calculate level change
    local oldLevel = pData.level or 1
    local newLevel = CalculateLevel(pData.xp, pData.role)
    
    -- Handle level up
    if newLevel > oldLevel then
        pData.level = newLevel
        HandleLevelUp(pIdNum, oldLevel, newLevel, pData.role)
        ApplyPerks(pIdNum, newLevel, pData.role)
    end
    
    -- Update challenges
    UpdateChallengeProgress(pIdNum, reason, 1)
    
    -- Notify client
    SafeTriggerClientEvent('cnr:xpGained', pIdNum, amount, reason)
    
    Log(string.format("Player %s gained %d XP (Reason: %s, Total: %d, Level: %d)", 
        pIdNum, amount, reason or "unknown", pData.xp, pData.level), "info", "CNR_PROGRESSION")
end

-- =========================
-- Level Up Handler
-- =========================

function HandleLevelUp(playerId, oldLevel, newLevel, role)
    local pIdNum = tonumber(playerId)
    if not pIdNum then return end
    
    local pData = GetCnrPlayerData(pIdNum)
    if not pData then return end
    
    -- Process all level unlocks between old and new level
    local unlocks = Config.LevelUnlocks[role]
    if unlocks then
        for level = oldLevel + 1, newLevel do
            local levelUnlocks = unlocks[level]
            if levelUnlocks then
                for _, unlock in ipairs(levelUnlocks) do
                    ProcessLevelUnlock(pIdNum, unlock, level)
                end
            end
        end
    end
    
    -- Send level up notification
    SafeTriggerClientEvent('cnr:levelUp', pIdNum, newLevel, pData.xp)
    SafeTriggerClientEvent('chat:addMessage', pIdNum, { 
        args = {"^2🎉 LEVEL UP!", string.format("Congratulations! You've reached Level %d!", newLevel)} 
    })
    
    -- Play level up sound and effects
    SafeTriggerClientEvent('cnr:playLevelUpEffects', pIdNum, newLevel)
    
    Log(string.format("Player %s leveled up from %d to %d (Role: %s)", pIdNum, oldLevel, newLevel, role), "info", "CNR_PROGRESSION")
end

-- =========================
-- Process Level Unlocks
-- =========================

function ProcessLevelUnlock(playerId, unlock, level)
    local pIdNum = tonumber(playerId)
    if not pIdNum then return end
    
    local pData = GetCnrPlayerData(pIdNum)
    if not pData then return end
    
    if unlock.type == "cash_reward" then
        pData.money = (pData.money or 0) + unlock.amount
        SafeTriggerClientEvent('chat:addMessage', pIdNum, { 
            args = {"^2💰 REWARD", unlock.message} 
        })
        
    elseif unlock.type == "item_access" then
        SafeTriggerClientEvent('chat:addMessage', pIdNum, { 
            args = {"^3🔓 UNLOCK", unlock.message} 
        })
        
    elseif unlock.type == "vehicle_access" then
        SafeTriggerClientEvent('chat:addMessage', pIdNum, { 
            args = {"^4🚗 VEHICLE", unlock.message} 
        })
        
    elseif unlock.type == "ability" then
        SafeTriggerClientEvent('chat:addMessage', pIdNum, { 
            args = {"^5⚡ ABILITY", unlock.message} 
        })
        SafeTriggerClientEvent('cnr:unlockAbility', pIdNum, unlock.abilityId, unlock.name)
        
    elseif unlock.type == "passive_perk" then
        SafeTriggerClientEvent('chat:addMessage', pIdNum, { 
            args = {"^6🌟 PERK", unlock.message} 
        })
    end
    
    -- Send unlock notification to UI
    SafeTriggerClientEvent('cnr:showUnlockNotification', pIdNum, unlock, level)
    
    Log(string.format("Processed unlock for player %s: %s (Level %d)", pIdNum, unlock.type, level), "info", "CNR_PROGRESSION")
end

-- =========================
-- Prestige System
-- =========================

function HandlePrestige(playerId)
    local pIdNum = tonumber(playerId)
    if not pIdNum then return false end
    
    if not Config.PrestigeSystem.enabled then
        return false, "Prestige system is disabled"
    end
    
    local pData = GetCnrPlayerData(pIdNum)
    if not pData then return false, "Player data not found" end
    
    -- Check if player meets prestige requirements
    if pData.level < Config.PrestigeSystem.levelRequiredForPrestige then
        return false, string.format("Must reach level %d to prestige", Config.PrestigeSystem.levelRequiredForPrestige)
    end
    
    -- Initialize prestige data if not exists
    if not prestigeData[pIdNum] then
        prestigeData[pIdNum] = { level = 0 }
    end
    
    -- Check max prestige
    if prestigeData[pIdNum].level >= Config.PrestigeSystem.maxPrestige then
        return false, "Maximum prestige level reached"
    end
    
    -- Perform prestige
    local newPrestigeLevel = prestigeData[pIdNum].level + 1
    local prestigeReward = Config.PrestigeSystem.prestigeRewards[newPrestigeLevel]
    
    if prestigeReward then
        -- Reset player level and XP
        pData.level = 1
        pData.xp = 0
        
        -- Increase prestige level
        prestigeData[pIdNum].level = newPrestigeLevel
        prestigeData[pIdNum].title = prestigeReward.title
        
        -- Give prestige rewards
        pData.money = (pData.money or 0) + prestigeReward.cash
        
        -- Reapply perks
        ApplyPerks(pIdNum, 1, pData.role)
        
        -- Notify player
        SafeTriggerClientEvent('cnr:prestigeComplete', pIdNum, newPrestigeLevel, prestigeReward)
        SafeTriggerClientEvent('chat:addMessage', pIdNum, { 
            args = {"^6🌟 PRESTIGE", string.format("Congratulations! You are now %s (Prestige %d)!", prestigeReward.title, newPrestigeLevel)} 
        })
        
        Log(string.format("Player %s prestiged to level %d (%s)", pIdNum, newPrestigeLevel, prestigeReward.title), "info", "CNR_PROGRESSION")
        return true, "Prestige successful"
    end
    
    return false, "Prestige reward not configured"
end

-- =========================
-- Challenge System
-- =========================

function InitializeChallenges(playerId)
    local pIdNum = tonumber(playerId)
    if not pIdNum then return end
    
    if not Config.ChallengeSystem.enabled then return end
    
    playerChallenges[pIdNum] = {
        daily = {},
        weekly = {},
        lastReset = os.time()
    }
    
    -- Initialize daily challenges
    local pData = GetCnrPlayerData(pIdNum)
    if pData and pData.role then
        local dailyChallenges = Config.ChallengeSystem.dailyChallenges[pData.role]
        if dailyChallenges then
            for _, challenge in ipairs(dailyChallenges) do
                playerChallenges[pIdNum].daily[challenge.id] = {
                    progress = 0,
                    target = challenge.target,
                    completed = false,
                    xpReward = challenge.xpReward,
                    cashReward = challenge.cashReward
                }
            end
        end
    end
    
    Log(string.format("Initialized challenges for player %s", pIdNum), "info", "CNR_PROGRESSION")
end

function UpdateChallengeProgress(playerId, action, amount)
    local pIdNum = tonumber(playerId)
    if not pIdNum or not Config.ChallengeSystem.enabled then return end
    
    if not playerChallenges[pIdNum] then
        InitializeChallenges(pIdNum)
    end
    
    local challenges = playerChallenges[pIdNum]
    if not challenges then return end
    
    -- Update daily challenges
    for challengeId, challengeData in pairs(challenges.daily) do
        if not challengeData.completed then
            local shouldUpdate = false
            
            -- Check if action matches challenge type
            if challengeId == "daily_heists" and (action == "heist" or action == "bank_heist") then
                shouldUpdate = true
            elseif challengeId == "daily_arrests" and action == "arrest" then
                shouldUpdate = true
            elseif challengeId == "daily_escapes" and action == "escape" then
                shouldUpdate = true
            elseif challengeId == "daily_lockpicks" and action == "lockpick" then
                shouldUpdate = true
            elseif challengeId == "daily_tickets" and action == "ticket" then
                shouldUpdate = true
            end
            
            if shouldUpdate then
                challengeData.progress = challengeData.progress + amount
                
                -- Check if challenge is completed
                if challengeData.progress >= challengeData.target then
                    challengeData.completed = true
                    CompleteChallengeReward(pIdNum, challengeId, challengeData)
                end
                
                -- Notify client of progress update
                SafeTriggerClientEvent('cnr:updateChallengeProgress', pIdNum, challengeId, challengeData)
            end
        end
    end
end

function CompleteChallengeReward(playerId, challengeId, challengeData)
    local pIdNum = tonumber(playerId)
    if not pIdNum then return end
    
    local pData = GetCnrPlayerData(pIdNum)
    if not pData then return end
    
    -- Give rewards
    if challengeData.xpReward > 0 then
        AddXP(pIdNum, challengeData.xpReward, "general", "challenge_completion")
    end
    
    if challengeData.cashReward > 0 then
        pData.money = (pData.money or 0) + challengeData.cashReward
    end
    
    -- Notify player
    SafeTriggerClientEvent('cnr:challengeCompleted', pIdNum, challengeId, challengeData)
    SafeTriggerClientEvent('chat:addMessage', pIdNum, { 
        args = {"^3🏆 CHALLENGE", string.format("Challenge completed! +%d XP, +$%d", challengeData.xpReward, challengeData.cashReward)} 
    })
    
    Log(string.format("Player %s completed challenge %s", pIdNum, challengeId), "info", "CNR_PROGRESSION")
end

-- =========================
-- Seasonal Events
-- =========================

function StartSeasonalEvent(eventName)
    if not Config.SeasonalEvents.enabled then return false end
    
    for _, event in ipairs(Config.SeasonalEvents.events) do
        if event.name == eventName then
            activeSeasonalEvent = {
                name = event.name,
                description = event.description,
                effects = event.effects,
                endTime = os.time() + event.duration
            }
            
            -- Notify all players
            TriggerClientEvent('cnr:seasonalEventStarted', -1, activeSeasonalEvent)
            TriggerClientEvent('chat:addMessage', -1, { 
                args = {"^5🎉 EVENT", string.format("Seasonal Event Started: %s - %s", event.name, event.description)} 
            })
            
            Log(string.format("Started seasonal event: %s", eventName), "info", "CNR_PROGRESSION")
            return true
        end
    end
    
    return false
end

function CheckSeasonalEventExpiry()
    if activeSeasonalEvent and os.time() >= activeSeasonalEvent.endTime then
        TriggerClientEvent('cnr:seasonalEventEnded', -1, activeSeasonalEvent.name)
        TriggerClientEvent('chat:addMessage', -1, { 
            args = {"^5📅 EVENT", string.format("Seasonal Event Ended: %s", activeSeasonalEvent.name)} 
        })
        
        Log(string.format("Ended seasonal event: %s", activeSeasonalEvent.name), "info", "CNR_PROGRESSION")
        activeSeasonalEvent = nil
    end
end

-- =========================
-- Utility Functions for Other Scripts
-- =========================

-- Get player perk value
function GetPlayerPerk(playerId, perkId)
    local pIdNum = tonumber(playerId)
    if not pIdNum or not playerPerks[pIdNum] then return nil end
    return playerPerks[pIdNum][perkId]
end

-- Check if player has ability
function HasPlayerAbility(playerId, abilityId)
    local pIdNum = tonumber(playerId)
    if not pIdNum then return false end
    
    local pData = GetCnrPlayerData(pIdNum)
    if not pData then return false end
    
    local unlocks = Config.LevelUnlocks[pData.role]
    if not unlocks then return false end
    
    for level = 1, pData.level do
        local levelUnlocks = unlocks[level]
        if levelUnlocks then
            for _, unlock in ipairs(levelUnlocks) do
                if unlock.type == "ability" and unlock.abilityId == abilityId then
                    return true
                end
            end
        end
    end
    
    return false
end

-- Get player prestige info
function GetPlayerPrestige(playerId)
    local pIdNum = tonumber(playerId)
    if not pIdNum then return nil end
    return prestigeData[pIdNum]
end

-- =========================
-- Event Handlers
-- =========================

-- Player connecting
AddEventHandler('playerConnecting', function()
    local playerId = source
    InitializeChallenges(playerId)
end)

-- Player dropping
AddEventHandler('playerDropped', function()
    local playerId = source
    local pIdNum = tonumber(playerId)
    
    if pIdNum then
        playerPerks[pIdNum] = nil
        playerChallenges[pIdNum] = nil
        -- Note: prestigeData is kept for when player reconnects
    end
end)

-- Periodic checks
CreateThread(function()
    while true do
        Wait(60000) -- Check every minute
        CheckSeasonalEventExpiry()
    end
end)

-- =========================
-- Exports
-- =========================

-- Export functions for use by other scripts
exports('AddXP', AddXP)
exports('GetPlayerPerk', GetPlayerPerk)
exports('HasPlayerAbility', HasPlayerAbility)
exports('HandlePrestige', HandlePrestige)
exports('GetPlayerPrestige', GetPlayerPrestige)
exports('StartSeasonalEvent', StartSeasonalEvent)
exports('UpdateChallengeProgress', UpdateChallengeProgress)

Log("Enhanced Progression System loaded successfully", "info", "CNR_PROGRESSION")