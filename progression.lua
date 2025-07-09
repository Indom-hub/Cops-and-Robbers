-- progression.lua
-- Consolidated progression system (server and client)
-- Version: 1.2.0
-- Consolidated from: progression_server.lua, progression_client.lua

if IsDuplicityVersion() then
    -- ====================================================================
    -- SERVER-SIDE PROGRESSION SYSTEM
    -- ====================================================================
    
    -- Progression tracking
    local playerProgression = {}
    local dailyChallenges = {}
    local weeklyChallenges = {}
    
    --- Calculate XP required for next level
    --- @param currentLevel number Current player level
    --- @return number XP required for next level
    local function CalculateXPForNextLevel(currentLevel)
        return math.floor(100 * (currentLevel * 1.5))
    end
    
    --- Award XP to player
    --- @param playerId number Player ID
    --- @param amount number XP amount
    --- @param reason string Reason for XP award
    function AwardXP(playerId, amount, reason)
        local playerData = GetCnrPlayerData(playerId)
        if not playerData then return end
        
        local oldLevel = playerData.level or 1
        local oldXP = playerData.xp or 0
        
        -- Add XP
        playerData.xp = oldXP + amount
        
        -- Check for level up
        local xpRequired = CalculateXPForNextLevel(oldLevel)
        while playerData.xp >= xpRequired do
            playerData.xp = playerData.xp - xpRequired
            playerData.level = (playerData.level or 1) + 1
            
            -- Trigger level up event
            TriggerClientEvent('cnr:levelUp', playerId, playerData.level, oldLevel)
            
            -- Award level up rewards
            AwardLevelUpRewards(playerId, playerData.level)
            
            xpRequired = CalculateXPForNextLevel(playerData.level)
            oldLevel = playerData.level
        end
        
        -- Save player data
        if DataManager then
            DataManager.MarkPlayerForSave(playerId)
        end
        
        -- Notify client of XP gain
        TriggerClientEvent('cnr:xpGained', playerId, amount, reason, playerData.xp, playerData.level)
        
        print(string.format("[CNR_PROGRESSION] Player %d gained %d XP (%s) - Level: %d, XP: %d", 
            playerId, amount, reason or "unknown", playerData.level, playerData.xp))
    end
    
    --- Award level up rewards
    --- @param playerId number Player ID
    --- @param newLevel number New level
    function AwardLevelUpRewards(playerId, newLevel)
        local playerData = GetCnrPlayerData(playerId)
        if not playerData then return end
        
        -- Award money based on level
        local moneyReward = newLevel * 500
        playerData.money = (playerData.money or 0) + moneyReward
        
        -- Award special items at certain levels
        if newLevel == 5 then
            -- Award basic equipment
            if SecureInventory then
                SecureInventory.AddItem(playerId, "pistol", 1, "level_reward")
                SecureInventory.AddItem(playerId, "pistol_ammo", 50, "level_reward")
            end
        elseif newLevel == 10 then
            -- Award advanced equipment
            if SecureInventory then
                SecureInventory.AddItem(playerId, "armor", 1, "level_reward")
            end
        elseif newLevel == 25 then
            -- Award special vehicle access
            -- This would be handled by the vehicle system
        end
        
        print(string.format("[CNR_PROGRESSION] Player %d reached level %d - Awarded $%d", 
            playerId, newLevel, moneyReward))
    end
    
    --- Get player progression data
    --- @param playerId number Player ID
    --- @return table Progression data
    function GetPlayerProgression(playerId)
        local playerData = GetCnrPlayerData(playerId)
        if not playerData then return nil end
        
        local currentLevel = playerData.level or 1
        local currentXP = playerData.xp or 0
        local xpForNext = CalculateXPForNextLevel(currentLevel)
        
        return {
            level = currentLevel,
            xp = currentXP,
            xpForNext = xpForNext,
            xpProgress = (currentXP / xpForNext) * 100,
            totalXP = (playerData.totalXP or 0) + currentXP
        }
    end
    
    --- Initialize daily challenges
    function InitializeDailyChallenges()
        dailyChallenges = {
            {
                id = "arrests_daily",
                name = "Make 5 arrests",
                description = "Arrest 5 criminals as a police officer",
                target = 5,
                reward = 200,
                type = "arrests"
            },
            {
                id = "heists_daily", 
                name = "Complete 3 heists",
                description = "Successfully complete 3 bank heists",
                target = 3,
                reward = 300,
                type = "heists"
            },
            {
                id = "survival_daily",
                name = "Survive 10 minutes with 4+ wanted level",
                description = "Maintain a wanted level of 4 or higher for 10 minutes",
                target = 600, -- seconds
                reward = 250,
                type = "survival"
            }
        }
    end
    
    --- Initialize weekly challenges
    function InitializeWeeklyChallenges()
        weeklyChallenges = {
            {
                id = "master_criminal",
                name = "Master Criminal",
                description = "Complete 20 heists in one week",
                target = 20,
                reward = 1000,
                type = "heists"
            },
            {
                id = "law_enforcer",
                name = "Law Enforcer", 
                description = "Make 50 arrests in one week",
                target = 50,
                reward = 1200,
                type = "arrests"
            }
        }
    end
    
    --- Update challenge progress
    --- @param playerId number Player ID
    --- @param challengeType string Challenge type
    --- @param amount number Progress amount
    function UpdateChallengeProgress(playerId, challengeType, amount)
        local playerData = GetCnrPlayerData(playerId)
        if not playerData then return end
        
        if not playerData.challenges then
            playerData.challenges = {
                daily = {},
                weekly = {}
            }
        end
        
        -- Update daily challenges
        for _, challenge in ipairs(dailyChallenges) do
            if challenge.type == challengeType then
                local progress = playerData.challenges.daily[challenge.id] or 0
                progress = progress + amount
                playerData.challenges.daily[challenge.id] = progress
                
                -- Check if challenge completed
                if progress >= challenge.target then
                    AwardXP(playerId, challenge.reward, "Daily Challenge: " .. challenge.name)
                    TriggerClientEvent('cnr:challengeCompleted', playerId, challenge, "daily")
                end
            end
        end
        
        -- Update weekly challenges
        for _, challenge in ipairs(weeklyChallenges) do
            if challenge.type == challengeType then
                local progress = playerData.challenges.weekly[challenge.id] or 0
                progress = progress + amount
                playerData.challenges.weekly[challenge.id] = progress
                
                -- Check if challenge completed
                if progress >= challenge.target then
                    AwardXP(playerId, challenge.reward, "Weekly Challenge: " .. challenge.name)
                    TriggerClientEvent('cnr:challengeCompleted', playerId, challenge, "weekly")
                end
            end
        end
        
        -- Save player data
        if DataManager then
            DataManager.MarkPlayerForSave(playerId)
        end
    end
    
    -- ====================================================================
    -- SERVER EVENT HANDLERS
    -- ====================================================================
    
    RegisterNetEvent('cnr:getProgression')
    AddEventHandler('cnr:getProgression', function()
        local source = source
        local progression = GetPlayerProgression(source)
        TriggerClientEvent('cnr:receiveProgression', source, progression)
    end)
    
    RegisterNetEvent('cnr:getChallenges')
    AddEventHandler('cnr:getChallenges', function()
        local source = source
        local playerData = GetCnrPlayerData(source)
        
        local challengeData = {
            daily = dailyChallenges,
            weekly = weeklyChallenges,
            progress = playerData and playerData.challenges or { daily = {}, weekly = {} }
        }
        
        TriggerClientEvent('cnr:receiveChallenges', source, challengeData)
    end)
    
    -- Initialize challenges on resource start
    InitializeDailyChallenges()
    InitializeWeeklyChallenges()
    
    -- Reset daily challenges every day
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(24 * 60 * 60 * 1000) -- 24 hours
            
            -- Reset daily challenge progress for all players
            for playerId, data in pairs(playersData or {}) do
                if data.challenges and data.challenges.daily then
                    data.challenges.daily = {}
                end
            end
            
            print("[CNR_PROGRESSION] Daily challenges reset")
        end
    end)
    
    -- Reset weekly challenges every week
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(7 * 24 * 60 * 60 * 1000) -- 7 days
            
            -- Reset weekly challenge progress for all players
            for playerId, data in pairs(playersData or {}) do
                if data.challenges and data.challenges.weekly then
                    data.challenges.weekly = {}
                end
            end
            
            print("[CNR_PROGRESSION] Weekly challenges reset")
        end
    end)
    
else
    -- ====================================================================
    -- CLIENT-SIDE PROGRESSION SYSTEM
    -- ====================================================================
    
    -- Progression UI state
    local progressionMenuOpen = false
    local playerProgression = {}
    local playerChallenges = {}
    
    --- Open progression menu
    function OpenProgressionMenu()
        if progressionMenuOpen then return end
        
        progressionMenuOpen = true
        SetNuiFocus(true, true)
        
        -- Request data from server
        TriggerServerEvent('cnr:getProgression')
        TriggerServerEvent('cnr:getChallenges')
        
        SendNUIMessage({
            type = "showProgression",
            progression = playerProgression,
            challenges = playerChallenges
        })
    end
    
    --- Close progression menu
    function CloseProgressionMenu()
        if not progressionMenuOpen then return end
        
        progressionMenuOpen = false
        SetNuiFocus(false, false)
        
        SendNUIMessage({
            type = "hideProgression"
        })
    end
    
    --- Show XP gain notification
    --- @param amount number XP amount gained
    --- @param reason string Reason for XP gain
    function ShowXPGainNotification(amount, reason)
        SendNUIMessage({
            type = "showXPGain",
            amount = amount,
            reason = reason
        })
        
        -- Also show in chat
        TriggerEvent('chat:addMessage', {
            color = {0, 255, 0},
            multiline = true,
            args = {"XP", string.format("+%d XP (%s)", amount, reason)}
        })
    end
    
    --- Show level up notification
    --- @param newLevel number New level
    --- @param oldLevel number Previous level
    function ShowLevelUpNotification(newLevel, oldLevel)
        SendNUIMessage({
            type = "showLevelUp",
            newLevel = newLevel,
            oldLevel = oldLevel
        })
        
        -- Play level up sound
        PlaySoundFrontend(-1, "RANK_UP", "HUD_AWARDS", 1)
        
        -- Show in chat
        TriggerEvent('chat:addMessage', {
            color = {255, 215, 0},
            multiline = true,
            args = {"LEVEL UP", string.format("Congratulations! You reached level %d!", newLevel)}
        })
    end
    
    --- Show challenge completion notification
    --- @param challenge table Challenge data
    --- @param type string Challenge type (daily/weekly)
    function ShowChallengeCompletedNotification(challenge, type)
        SendNUIMessage({
            type = "showChallengeCompleted",
            challenge = challenge,
            challengeType = type
        })
        
        -- Play completion sound
        PlaySoundFrontend(-1, "CHALLENGE_UNLOCKED", "HUD_AWARDS", 1)
        
        -- Show in chat
        TriggerEvent('chat:addMessage', {
            color = {0, 255, 255},
            multiline = true,
            args = {"CHALLENGE", string.format("%s Challenge Completed: %s (+%d XP)", 
                string.upper(type), challenge.name, challenge.reward)}
        })
    end
    
    -- ====================================================================
    -- CLIENT EVENT HANDLERS
    -- ====================================================================
    
    RegisterNetEvent('cnr:receiveProgression')
    AddEventHandler('cnr:receiveProgression', function(progression)
        playerProgression = progression
        
        if progressionMenuOpen then
            SendNUIMessage({
                type = "updateProgression",
                progression = playerProgression
            })
        end
    end)
    
    RegisterNetEvent('cnr:receiveChallenges')
    AddEventHandler('cnr:receiveChallenges', function(challenges)
        playerChallenges = challenges
        
        if progressionMenuOpen then
            SendNUIMessage({
                type = "updateChallenges",
                challenges = playerChallenges
            })
        end
    end)
    
    RegisterNetEvent('cnr:xpGained')
    AddEventHandler('cnr:xpGained', function(amount, reason, currentXP, currentLevel)
        ShowXPGainNotification(amount, reason)
        
        -- Update local progression data
        if playerProgression then
            playerProgression.xp = currentXP
            playerProgression.level = currentLevel
        end
    end)
    
    RegisterNetEvent('cnr:levelUp')
    AddEventHandler('cnr:levelUp', function(newLevel, oldLevel)
        ShowLevelUpNotification(newLevel, oldLevel)
    end)
    
    RegisterNetEvent('cnr:challengeCompleted')
    AddEventHandler('cnr:challengeCompleted', function(challenge, type)
        ShowChallengeCompletedNotification(challenge, type)
    end)
    
    -- ====================================================================
    -- NUI CALLBACKS
    -- ====================================================================
    
    RegisterNUICallback('closeProgression', function(data, cb)
        CloseProgressionMenu()
        cb('ok')
    end)
    
    RegisterNUICallback('refreshProgression', function(data, cb)
        TriggerServerEvent('cnr:getProgression')
        TriggerServerEvent('cnr:getChallenges')
        cb('ok')
    end)
    
    -- ====================================================================
    -- CLIENT KEYBINDS
    -- ====================================================================
    
    -- Progression menu toggle keybind
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(0)
            
            if IsControlJustPressed(0, 199) then -- P key
                if progressionMenuOpen then
                    CloseProgressionMenu()
                else
                    OpenProgressionMenu()
                end
            end
        end
    end)
    
end