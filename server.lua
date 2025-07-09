-- server.lua
-- Version: 1.2.0

-- Configuration shortcuts (Config must be loaded before Log if Log uses it)
-- However, config.lua is a shared_script, so Config global should be available.
-- For safety, ensure Log definition handles potential nil Config if script order changes.
local Config = Config -- Keep this near the top as Log depends on it.



function shallowcopy(original)
    local copy = {}
    for k, v in pairs(original) do
        copy[k] = v
    end
    return copy
end

function tablelength(T)
    if not T or type(T) ~= "table" then return 0 end
    local count = 0
    for _ in pairs(T) do count = count + 1 end
    return count
end



function MinimizeInventoryForSync(richInventory)
    if not richInventory then return {} end
    local minimalInv = {}
    for itemId, itemData in pairs(richInventory) do
        if itemData and itemData.count then
            minimalInv[itemId] = { count = itemData.count }
        end
    end
    return minimalInv
end

-- Safe table assignment wrapper for player IDs
local function SafeSetByPlayerId(tbl, playerId, value)
    if tbl and playerId and type(playerId) == "number" and playerId > 0 then
        tbl[playerId] = value
    end
end
local function SafeRemoveByPlayerId(tbl, playerId)
    if tbl and playerId and type(playerId) == "number" and playerId > 0 then
        tbl[playerId] = nil
    end
end
local function SafeGetByPlayerId(tbl, playerId)
    if tbl and playerId and type(playerId) == "number" and playerId > 0 then
        return tbl[playerId]
    end
    return nil
end


-- Forward declarations for functions defined later
local MarkPlayerForInventorySave
local SavePlayerDataImmediate

-- Global state tables
local playersData = {}
local copsOnDuty = {}
local robbersActive = {}
local jail = {}
local wantedPlayers = {}
local activeCooldowns = {}
local purchaseHistory = {}
local bannedPlayers = {}
local k9Engagements = {}
local activeBounties = {}
local playerDeployedSpikeStripsCount = {} -- For extra_spike_strips perk
local activeSpikeStrips = {} -- To manage strip IDs and removal: {stripId = {copId = src, location = ...}}
local nextSpikeStripId = 1

-- ====================================================================
-- Get Player Role Handler
-- ====================================================================
RegisterNetEvent('cnr:getPlayerRole')
AddEventHandler('cnr:getPlayerRole', function()
    local source = source
    local role = "civilian" -- Default role
    
    if playersData[source] and playersData[source].role then
        role = playersData[source].role
    elseif copsOnDuty[source] then
        role = "cop"
    elseif robbersActive[source] then
        role = "robber"
    end
    
    TriggerClientEvent('cnr:returnPlayerRole', source, role)
end)

-- ====================================================================
-- Bounty System
-- ====================================================================

-- Function to get a list of active bounties
function GetActiveBounties()
    local currentTime = os.time()
    local bounties = {}
    
    -- Filter out expired bounties
    for playerId, bounty in pairs(activeBounties) do
        if bounty.expireTime > currentTime then
            table.insert(bounties, {
                id = playerId,
                name = bounty.name,
                wantedLevel = bounty.wantedLevel,
                reward = bounty.amount,
                timeLeft = math.floor((bounty.expireTime - currentTime) / 60) -- minutes
            })
        else
            -- Remove expired bounty
            activeBounties[playerId] = nil
        end
    end
    
    return bounties
end

-- Check if a player has a wanted level sufficient for a bounty
function CheckPlayerWantedLevel(playerId)
    if not wantedPlayers[playerId] then return 0 end
    
    local wantedData = wantedPlayers[playerId]
    if not wantedData.wantedLevel then return 0 end
    
    -- Get the current wanted stars
    local stars = 0
    
    for i, level in ipairs(Config.WantedSettings.levels) do
        if wantedData.wantedLevel >= level.threshold then
            stars = level.stars
        end
    end
    
    return stars
end

-- Place a bounty on a player
function PlaceBounty(targetId)
    -- Check if player exists
    if not playersData[targetId] then
        return false, "Player does not exist."
    end
    
    -- Check if player is a robber
    if not robbersActive[targetId] then
        return false, "Bounties can only be placed on robbers."
    end
    
    -- Check if player has minimum wanted level
    local wantedLevel = CheckPlayerWantedLevel(targetId)
    if wantedLevel < Config.BountySettings.wantedLevelThreshold then
        return false, "Target must have at least " .. Config.BountySettings.wantedLevelThreshold .. " wanted stars."
    end
    
    -- Check if player already has an active bounty
    if activeBounties[targetId] then
        local timeLeft = math.floor((activeBounties[targetId].expireTime - os.time()) / 60)
        if timeLeft > 0 then
            return false, "Player already has an active bounty for " .. timeLeft .. " more minutes."
        end
    end
    
    -- Calculate bounty amount based on wanted level
    local bountyAmount = Config.BountySettings.baseAmount + 
                         (wantedLevel - Config.BountySettings.wantedLevelThreshold) * 
                         Config.BountySettings.baseAmount * Config.BountySettings.multiplier
    
    -- Cap at maximum amount
    bountyAmount = math.min(bountyAmount, Config.BountySettings.maxAmount)
    bountyAmount = math.floor(bountyAmount)
    
    -- Store the bounty
    local expireTime = os.time() + (Config.BountySettings.duration * 60)
    
    activeBounties[targetId] = {
        amount = bountyAmount,
        wantedLevel = wantedLevel,
        placedTime = os.time(),
        expireTime = expireTime,
        name = GetPlayerName(targetId)
    }
    
    -- Notify all cops about the bounty
    for cop, _ in pairs(copsOnDuty) do
        TriggerClientEvent('cnr:notification', cop, "A $" .. bountyAmount .. " bounty has been placed on " .. GetPlayerName(targetId) .. "!")
    end
    
    -- Notify the target
    TriggerClientEvent('cnr:notification', targetId, "A $" .. bountyAmount .. " bounty has been placed on you!", "warning")
    
    return true, "Bounty of $" .. bountyAmount .. " placed on " .. GetPlayerName(targetId)
end

-- Claim a bounty when a cop arrests a player with a bounty
function ClaimBounty(copId, targetId)
    if not activeBounties[targetId] then
        return false, "No active bounty found on this player."
    end
    
    local bountyAmount = activeBounties[targetId].amount
    
    -- Pay the cop
    AddPlayerMoney(copId, bountyAmount)
    
    -- Add XP to the cop
    AddPlayerXP(copId, bountyAmount / 100) -- 1 XP per $100 of bounty
    
    -- Notify the cop
    TriggerClientEvent('cnr:notification', copId, "You claimed a $" .. bountyAmount .. " bounty on " .. GetPlayerName(targetId) .. "!")
    
    -- Remove the bounty
    activeBounties[targetId] = nil
    
    return true, "Bounty of $" .. bountyAmount .. " claimed successfully."
end

-- Register server event to get bounty list
RegisterNetEvent('cnr:requestBountyList')
AddEventHandler('cnr:requestBountyList', function()
    local source = source
    local bounties = GetActiveBounties()
    TriggerClientEvent('cnr:receiveBountyList', source, bounties)
end)

-- Automatically check for placing bounties on players with high wanted levels
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(60000) -- Check every minute
        
        for playerId, wantedData in pairs(wantedPlayers) do
            -- If player is not already bountied and meets threshold
            if playersData[playerId] and robbersActive[playerId] and not activeBounties[playerId] then
                local wantedLevel = CheckPlayerWantedLevel(playerId)
                
                -- Automatically place a bounty if wanted level is high enough
                if wantedLevel >= 4 then -- Auto-bounty for 4+ stars
                    PlaceBounty(playerId)
                end
            end
        end
    end
end)

-- ====================================================================
-- Contraband Dealers Implementation
-- ====================================================================

-- Register NUI callback for accessing contraband dealer
RegisterNetEvent('cnr:accessContrabandDealer')
AddEventHandler('cnr:accessContrabandDealer', function()
    local source = source
    local pData = GetCnrPlayerData(source)
    
    if not pData then
        TriggerClientEvent('cnr:showNotification', source, "~r~Player data not found.")
        return
    end
    
    -- Check if player is a robber
    if pData.role ~= "robber" then
        TriggerClientEvent('cnr:showNotification', source, "~r~Only robbers can access contraband dealers.")
        return
    end
    
    -- Get contraband items (high-end weapons and tools)
    local contrabandItems = {
        "weapon_compactrifle",
        "weapon_bullpuprifle", 
        "weapon_advancedrifle",
        "weapon_specialcarbine",
        "weapon_machinegun",
        "weapon_combatmg_mk2",
        "weapon_minigun",
        "weapon_grenade",
        "weapon_rpg",
        "weapon_grenadelauncher",
        "weapon_hominglauncher",
        "weapon_firework",
        "weapon_railgun",
        "weapon_autoshotgun",
        "weapon_bullpupshotgun",
        "weapon_dbshotgun",
        "weapon_musket",
        "weapon_heavysniper",
        "weapon_heavysniper_mk2",
        "weapon_marksmanrifle",
        "weapon_marksmanrifle_mk2",
        "ammo_smg",
        "ammo_rifle",
        "ammo_sniper",
        "ammo_explosive",
        "ammo_minigun",
        "lockpick",
        "adv_lockpick",
        "hacking_device",
        "drill",
        "thermite",
        "c4",
        "mask",
        "heavy_armor"
    }
    
    -- Send to client to open contraband store
    TriggerClientEvent('cnr:openContrabandStoreUI', source, contrabandItems)
end)

-- OLD: Table to store last report times for specific crimes per player (no longer used)
-- local clientReportCooldowns = {} -- DISABLED - replaced by server-side detection
local activeSubdues = {} -- Tracks active subdue attempts: activeSubdues[robberId] = { copId = copId, expiryTimer = timer }

-- Forward declaration for functions that might be called before definition due to event handlers
local GetPlayerLevelAndXP, AddXP, SetPlayerRole, IsPlayerCop, IsPlayerRobber, SavePlayerData, LoadPlayerData, CheckAndPlaceBounty, UpdatePlayerWantedLevel, ReduceWantedLevel, SendToJail

-- SafeGetPlayerName is provided by safe_utils.lua (loaded before this script)


-- Function to load bans from bans.json
local function LoadBans()
    local banFile = LoadResourceFile(GetCurrentResourceName(), "bans.json")
    if banFile then
        local success, loaded = pcall(json.decode, banFile)
        if success and type(loaded) == "table" then
            for identifier, banInfo in pairs(loaded) do
                if not bannedPlayers[identifier] then -- Merge, Config.BannedPlayers can take precedence or be defaults
                    bannedPlayers[identifier] = banInfo
                end
            end
            Log("Loaded " .. tablelength(loaded) .. " bans from bans.json", "info", "CNR_SERVER")
        else
            Log("Failed to decode bans.json: " .. tostring(loaded), "error", "CNR_SERVER")
        end
    else
        Log("bans.json not found. Only using bans from Config.BannedPlayers.", "info", "CNR_SERVER")
    end
end

local function SaveBans()
    local success = SaveResourceFile(GetCurrentResourceName(), "bans.json", json.encode(bannedPlayers), -1)
    if success then
        Log("Saved bans to bans.json", "info", "CNR_SERVER")
    else
        Log("Failed to save bans.json", "error", "CNR_SERVER")
    end
end

-- Function to load purchase history from purchase_history.json
local function LoadPurchaseHistory()
    local historyFile = LoadResourceFile(GetCurrentResourceName(), "purchase_history.json")
    if historyFile then
        local success, loaded = pcall(json.decode, historyFile)
        if success and type(loaded) == "table" then
            purchaseHistory = loaded
            Log("Loaded purchase history from purchase_history.json. Count: " .. tablelength(purchaseHistory), "info", "CNR_SERVER")
        else
            Log("Failed to decode purchase_history.json: " .. tostring(loaded), "error", "CNR_SERVER")
            purchaseHistory = {} -- Start fresh if file is corrupt
        end
    else
        Log("purchase_history.json not found. Initializing empty history.", "info", "CNR_SERVER")
        purchaseHistory = {}
    end
end

local function SavePurchaseHistory()
    if not Config.DynamicEconomy or not Config.DynamicEconomy.enabled then return end -- Only save if enabled
    local success = SaveResourceFile(GetCurrentResourceName(), "purchase_history.json", json.encode(purchaseHistory), -1)
    if success then
        Log("Saved purchase history to purchase_history.json", "info", "CNR_SERVER")
    else
        Log("Failed to save purchase_history.json", "error", "CNR_SERVER")
    end
end

-- =================================================================================================
-- HELPER FUNCTIONS
-- =================================================================================================

-- Helper function to get a player's license identifier
local function GetPlayerLicense(playerId)
    local identifiers = GetPlayerIdentifiers(tostring(playerId))
    if identifiers then
        for _, identifier in ipairs(identifiers) do
            if string.match(identifier, "^license:") then
                return identifier
            end
        end
    end
    return nil
end

local function GetCnrPlayerData(playerId)
    return playersData[tonumber(playerId)]
end

-- Global access function for other server scripts
_G.GetCnrPlayerData = GetCnrPlayerData

local function GetPlayerMoney(playerId)
    local pId = tonumber(playerId)
    local pData = playersData[pId]
    if pData and pData.money then
        return pData.money
    end
    return 0
end

-- Function to add money to a player
local function AddPlayerMoney(playerId, amount, type)
    type = type or 'cash' -- Assuming 'cash' is the primary type. Add handling for 'bank' if needed.
    local pId = tonumber(playerId)
    if not pId or pId <= 0 then
        Log(string.format("AddPlayerMoney: Invalid player ID %s.", tostring(playerId)), "error", "CNR_SERVER")
        return false
    end

    local pData = playersData[pId]
    if pData then
        if type == 'cash' then
            pData.money = (pData.money or 0) + amount
            Log(string.format("Added %d to player %s's %s account. New balance: %d", amount, playerId, type, pData.money), "info", "CNR_SERVER")
            -- Send a notification to the client
            SafeTriggerClientEvent('chat:addMessage', pId, { args = {"^2Money", string.format("You received $%d.", amount)} })
            local pDataForBasicInfo = shallowcopy(pData)
            pDataForBasicInfo.inventory = nil
            SafeTriggerClientEvent('cnr:updatePlayerData', pId, pDataForBasicInfo)
            -- Inventory is not changed by this function, so no need to send cnr:syncInventory
            return true
        else
            Log(string.format("AddPlayerMoney: Unsupported account type '%s' for player %s.", type, playerId), "warn", "CNR_SERVER")
            return false
        end
    else
        Log(string.format("AddPlayerMoney: Player data not found for %s.", playerId), "error", "CNR_SERVER")
        return false
    end
end

-- Export AddPlayerMoney for potential use by other resources (if needed)
_G.AddPlayerMoney = AddPlayerMoney

-- Function to add XP to a player
local function AddPlayerXP(playerId, amount)
    local pId = tonumber(playerId)
    if not pId or pId <= 0 then
        Log(string.format("AddPlayerXP: Invalid player ID %s.", tostring(playerId)), "error", "CNR_SERVER")
        return false
    end

    local pData = playersData[pId]
    if pData then
        -- Add XP
        pData.xp = (pData.xp or 0) + amount
        
        -- Check if player leveled up
        local oldLevel = pData.level or 1
        -- Use a simple level calculation formula if CalculatePlayerLevel is not defined
        local newLevel = math.floor(math.sqrt(pData.xp / 100)) + 1
        pData.level = newLevel
        
        -- Send XP notification to client
        SafeTriggerClientEvent('cnr:xpGained', pId, amount)
        
        -- Send level up notification if needed
        if newLevel > oldLevel then
            SafeTriggerClientEvent('cnr:levelUp', pId, newLevel)
        end
        
        -- Update client with new player data
        local pDataForBasicInfo = shallowcopy(pData)
        pDataForBasicInfo.inventory = nil
        SafeTriggerClientEvent('cnr:updatePlayerData', pId, pDataForBasicInfo)
        
        return true
    else
        Log(string.format("AddPlayerXP: Player data not found for %s.", pId), "error", "CNR_SERVER")
        return false
    end
end

-- Export AddPlayerXP for potential use by other resources
_G.AddPlayerXP = AddPlayerXP

local function RemovePlayerMoney(playerId, amount, type)
    type = type or 'cash'
    local pId = tonumber(playerId)
    if not pId or pId <= 0 then
        Log(string.format("RemovePlayerMoney: Invalid player ID %s.", tostring(playerId)), "error", "CNR_SERVER")
        return false
    end

    local pData = playersData[pId]
    if pData then
        if type == 'cash' then
            if (pData.money or 0) >= amount then
                pData.money = pData.money - amount
                Log(string.format("Removed %d from player %s's %s account. New balance: %d", amount, playerId, type, pData.money), "info", "CNR_SERVER")
                local pDataForBasicInfo = shallowcopy(pData)
                pDataForBasicInfo.inventory = nil
                SafeTriggerClientEvent('cnr:updatePlayerData', pId, pDataForBasicInfo)
                -- Inventory is not changed by this function, so no need to send cnr:syncInventory
                return true
            else
                -- Notify the client about insufficient funds
                SafeTriggerClientEvent('chat:addMessage', pId, { args = {"^1Error", "You don't have enough money."} })
                return false
            end
        else
            Log(string.format("RemovePlayerMoney: Unsupported account type '%s' for player %s.", type, playerId), "warn", "CNR_SERVER")
            return false
        end
    else
        Log(string.format("RemovePlayerMoney: Player data not found for %s.", playerId), "error", "CNR_SERVER")
        return false
    end
end

local function IsAdmin(playerId)
    local src = tonumber(playerId) -- Ensure it is a number for GetPlayerIdentifiers
    if not src then return false end

    local identifiers = GetPlayerIdentifiers(tostring(src))
    if not identifiers then return false end

    if not Config or type(Config.Admins) ~= "table" then
        Log("IsAdmin Check: Config.Admins is not loaded or not a table.", "error", "CNR_SERVER")
        return false -- Should not happen if Config.lua is correct
    end

    for _, identifier in ipairs(identifiers) do
        if Config.Admins[identifier] then
            Log("IsAdmin Check: Player " .. src .. " with identifier " .. identifier .. " IS an admin.", "info", "CNR_SERVER")
            return true
        end
    end
    Log("IsAdmin Check: Player " .. src .. " is NOT an admin.", "info", "CNR_SERVER")
    return false
end

local function GetPlayerRole(playerId)
    local pData = GetCnrPlayerData(playerId)
    if pData then return pData.role end
    return "citizen"
end

local function CalculateDynamicPrice(itemId, basePrice)
    -- Ensure basePrice is a number
    basePrice = tonumber(basePrice) or 0

    if not Config.DynamicEconomy or not Config.DynamicEconomy.enabled then
        return basePrice
    end

    local currentTime = os.time()
    local timeframe = Config.DynamicEconomy.popularityTimeframe or (3 * 60 * 60) -- Default 3 hours
    local recentPurchases = 0

    for _, purchase in ipairs(purchaseHistory) do
        if purchase.itemId == itemId and (currentTime - purchase.timestamp) <= timeframe then
            recentPurchases = recentPurchases + (purchase.quantity or 1)
        end
    end

    local price = basePrice
    if recentPurchases > (Config.DynamicEconomy.popularityThresholdHigh or 10) then
        price = math.floor(basePrice * (Config.DynamicEconomy.priceIncreaseFactor or 1.2))
        Log(string.format("DynamicPrice: Item %s popular (%d purchases), price increased to %d from %d", itemId, recentPurchases, price, basePrice), "info", "CNR_SERVER")
    elseif recentPurchases < (Config.DynamicEconomy.popularityThresholdLow or 2) then
        price = math.floor(basePrice * (Config.DynamicEconomy.priceDecreaseFactor or 0.8))
        Log(string.format("DynamicPrice: Item %s unpopular (%d purchases), price decreased to %d from %d", itemId, recentPurchases, price, basePrice), "info", "CNR_SERVER")
    else
        Log(string.format("DynamicPrice: Item %s normal popularity (%d purchases), price remains %d", itemId, recentPurchases, price), "info", "CNR_SERVER")
    end
    return price
end

-- =================================================================================================
-- PLAYER DATA MANAGEMENT (XP, LEVELS, SAVING/LOADING)
-- =================================================================================================

-- Simple (or placeholder) inventory interaction functions
-- In a full system, these would likely call exports from inventory_server.lua


-- OLD INVENTORY FUNCTIONS REMOVED - Using enhanced versions with save marking below

-- Ensure InitializePlayerInventory is defined (even if simple)
function InitializePlayerInventory(pData, playerId)
    if not pData then
        Log("InitializePlayerInventory: pData is nil for playerId " .. (playerId or "unknown"), "error", "CNR_SERVER")
        return
    end
    pData.inventory = pData.inventory or {}
    -- Log("InitializePlayerInventory: Ensured inventory table exists for player " .. (playerId or "unknown"), "info")
end

LoadPlayerData = function(playerId)
    -- Log(string.format("LoadPlayerData: Called for player ID %s.", playerId), "info")
    local pIdNum = tonumber(playerId)
    if not pIdNum or pIdNum <= 0 then
        Log(string.format("LoadPlayerData: Invalid player ID %s", tostring(playerId)), "error", "CNR_SERVER")
        return
    end

    -- Check if player is still online
    if not GetPlayerName(pIdNum) then
        Log(string.format("LoadPlayerData: Player %s is not online", pIdNum), "warn", "CNR_SERVER")
        return
    end

    -- Log(string.format("LoadPlayerData: Attempting to get license for player %s.", pIdNum), "info")
    local license = GetPlayerLicense(pIdNum) -- Use helper to get license

    local filename = nil
    if license then
        filename = "player_data/" .. license:gsub(":", "") .. ".json"
    else
        Log(string.format("LoadPlayerData: CRITICAL - Could not find license for player %s (Name: %s) even after playerConnecting. Attempting PID fallback (pid_%s.json), but this may lead to data inconsistencies or load failures if server IDs are not static.", pIdNum, GetPlayerName(pIdNum) or "N/A", pIdNum), "error", "CNR_SERVER")
        -- The playerConnecting handler should ideally prevent this state for legitimate players.
        -- If this occurs, it might be due to:
        -- 1. A non-player entity somehow triggering this (e.g., faulty admin command or event).
        -- 2. An issue with identifier loading that even retries couldn't solve.
        -- 3. The player disconnected very rapidly after connecting, before identifiers were fully processed by all systems.
        filename = "player_data/pid_" .. pIdNum .. ".json"
    end

    -- Log(string.format("LoadPlayerData: Using filename %s for player %s.", filename, pIdNum), "info")
    -- Log(string.format("LoadPlayerData: Attempting to load data from file %s for player %s.", filename, pIdNum), "info")
    local fileData = LoadResourceFile(GetCurrentResourceName(), filename)
    local loadedMoney = 0 -- Default money if not in save file or new player

    if fileData then
        -- Log(string.format("LoadPlayerData: File %s found for player %s. Attempting to decode JSON.", filename, pIdNum), "info")
        local success, data = pcall(json.decode, fileData)
        if success and type(data) == "table" then
            playersData[pIdNum] = data
            loadedMoney = data.money or 0 -- Load money from file if exists
            Log("Loaded player data for " .. pIdNum .. " from " .. filename .. ". Level: " .. (data.level or 0) .. ", Role: " .. (data.role or "citizen") .. ", Money: " .. loadedMoney, "info", "CNR_SERVER")
        else
            Log("Failed to decode player data for " .. pIdNum .. " from " .. filename .. ". Using defaults. Error: " .. tostring(data), "error", "CNR_SERVER")
            playersData[pIdNum] = nil -- Force default initialization
        end
    else
        Log("No save file found for " .. pIdNum .. " at " .. filename .. ". Initializing default data.", "info", "CNR_SERVER")
        playersData[pIdNum] = nil -- Force default initialization
    end

if not playersData[pIdNum] then
        -- Log(string.format("LoadPlayerData: Initializing new default data structure for player %s.", pIdNum), "info")
        local playerPed = GetPlayerPed(tostring(pIdNum))
        local initialCoords = (playerPed and playerPed ~= 0) and GetEntityCoords(playerPed) or vector3(0,0,70) -- Fallback coords

        playersData[pIdNum] = {
            xp = 0, level = 1, role = "citizen",
            lastKnownPosition = initialCoords, -- Use current coords or a default spawn
            perks = {}, armorModifier = 1.0, bountyCooldownUntil = 0,
            money = Config.DefaultStartMoney or 5000, -- Use a config value for starting money
            inventory = {
                -- Give some default items to all new players
                ["armor"] = { count = 1, name = "Body Armor", category = "Armor" },
                ["weapon_pistol"] = { count = 1, name = "Pistol", category = "Weapons" },
                ["ammo_pistol"] = { count = 50, name = "Pistol Ammo", category = "Ammunition" }
            }
        }
        Log("Initialized default data for player " .. pIdNum .. ". Money: " .. playersData[pIdNum].money .. ", Default inventory added.", "info", "CNR_SERVER")
    else
        -- Ensure money is set if loaded from file, otherwise use default (already handled by loadedMoney init)
        playersData[pIdNum].money = playersData[pIdNum].money or Config.DefaultStartMoney or 5000
    end

    -- NEW PLACEMENT FOR isDataLoaded
    if playersData[pIdNum] then
        playersData[pIdNum].isDataLoaded = true
        Log("LoadPlayerData: Player data structure populated and isDataLoaded set to true for " .. pIdNum .. ".", "info", "CNR_SERVER") -- Combined log
    else
        Log("LoadPlayerData: CRITICAL - playersData[pIdNum] is nil AFTER data load/init attempt for " .. pIdNum .. ". Cannot set isDataLoaded or proceed.", "error", "CNR_SERVER")
        return -- Cannot proceed if playersData[pIdNum] is still nil here
    end

    -- Now call functions that might rely on isDataLoaded or a fully ready player object
    SetPlayerRole(pIdNum, playersData[pIdNum].role, true)
    ApplyPerks(pIdNum, playersData[pIdNum].level, playersData[pIdNum].role)

    -- Log(string.format("LoadPlayerData: About to call InitializePlayerInventory for player %s.", pIdNum), "info")
    if playersData[pIdNum] then -- Re-check pData as ApplyPerks or SetPlayerRole might have side effects (though unlikely to nil it)
        InitializePlayerInventory(playersData[pIdNum], pIdNum)
    else
        Log("LoadPlayerData: CRITICAL - playersData[pIdNum] became nil before InitializePlayerInventory for " .. pIdNum, "error", "CNR_SERVER")
    end

local pDataForLoad = shallowcopy(playersData[pIdNum])
    pDataForLoad.inventory = nil
    SafeTriggerClientEvent('cnr:updatePlayerData', pIdNum, pDataForLoad)
    
    -- Send config items first so client can properly reconstruct inventory
    if Config and Config.Items and type(Config.Items) == "table" then
        SafeTriggerClientEvent('cnr:receiveConfigItems', pIdNum, Config.Items)
        Log(string.format("Sent Config.Items to player %s during load", pIdNum), "info", "CNR_SERVER")
    end
    
    SafeTriggerClientEvent('cnr:syncInventory', pIdNum, MinimizeInventoryForSync(playersData[pIdNum].inventory))
    SafeTriggerClientEvent('cnr:wantedLevelSync', pIdNum, wantedPlayers[pIdNum] or { wantedLevel = 0, stars = 0 })

    -- Check for persisted jail data
    local pData = playersData[pIdNum] -- Re-fetch or use existing, ensure it's the most current
    if pData and pData.jailData and pData.jailData.originalDuration and pData.jailData.jailedTimestamp then
        -- Calculate how much time should be remaining based on the original sentence and total time elapsed.
        -- This correctly accounts for time passed while the player was offline (if the server was running).
        local totalTimeElapsedSinceJailing = os.time() - pData.jailData.jailedTimestamp
        local calculatedRemainingTime = math.max(0, pData.jailData.originalDuration - totalTimeElapsedSinceJailing)

        Log(string.format("Player %s jail check: OriginalDuration=%s, JailedTimestamp=%s, CurrentTime=%s, TotalElapsed=%s, CalculatedRemaining=%s, SavedRemaining=%s",
            pIdNum,
            tostring(pData.jailData.originalDuration),
            tostring(pData.jailData.jailedTimestamp),
            tostring(os.time()),
            tostring(totalTimeElapsedSinceJailing),
            tostring(calculatedRemainingTime),
            tostring(pData.jailData.remainingTime) -- For comparison logging
        ), "info", "CNR_SERVER")

        if calculatedRemainingTime > 0 then
            jail[pIdNum] = {
                startTime = os.time(), -- Current login time becomes the new reference for this session's server-side tick
                duration = pData.jailData.originalDuration, -- Always use the original full duration
                remainingTime = calculatedRemainingTime, -- The actual time left to serve
                arrestingOfficer = pData.jailData.jailedByOfficer or "System (Rejoin)"
            }
            SafeTriggerClientEvent('cnr:sendToJail', pIdNum, calculatedRemainingTime, Config.PrisonLocation)
            Log(string.format("Player %s re-jailed upon loading data. Calculated Remaining: %ds", pIdNum, calculatedRemainingTime), "info", "CNR_SERVER")
            SafeTriggerClientEvent('chat:addMessage', pIdNum, { args = {"^1Jail", string.format("You are still jailed. Time remaining: %d seconds.", calculatedRemainingTime)} })
        else
            Log(string.format("Player %s jail time expired while offline or on load. Original Duration: %ds, Total Elapsed: %ds", pIdNum, pData.jailData.originalDuration, totalTimeElapsedSinceJailing), "info", "CNR_SERVER")
            pData.jailData = nil -- Clear expired jail data
        end
    elseif pData and pData.jailData then -- If jailData exists but is incomplete (e.g., missing originalDuration or jailedTimestamp) or remainingTime was already <=0
        Log(string.format("Player %s had incomplete or already expired jailData. Clearing. Data: %s", pIdNum, json.encode(pData.jailData)), "warn", "CNR_SERVER")
        pData.jailData = nil -- Clean up old/completed/invalid jail data
    end
    -- Original position of isDataLoaded setting is now removed.
end

SavePlayerData = function(playerId)
    local pIdNum = tonumber(playerId)
    local pData = GetCnrPlayerData(pIdNum)
    if not pData then
        Log("SavePlayerData: No data for player " .. pIdNum, "warn", "CNR_SERVER")
        return
    end

    local license = GetPlayerLicense(pIdNum) -- Use helper

    if not license then
        Log("SavePlayerData: Could not find license for player " .. pIdNum .. ". Using numeric ID as fallback filename. Data might not persist correctly across sessions if ID changes.", "warn", "CNR_SERVER")
        license = "pid_" .. pIdNum -- Fallback, not ideal for persistence if server IDs are not static
    end

local filename = "player_data/" .. license:gsub(":", "") .. ".json"
    -- Ensure lastKnownPosition is updated before saving
    local playerPed = GetPlayerPed(tostring(pIdNum))
    if playerPed and playerPed ~= 0 and GetEntityCoords(playerPed) then
        pData.lastKnownPosition = GetEntityCoords(playerPed)
    end
    local success = SaveResourceFile(GetCurrentResourceName(), filename, json.encode(pData), -1)
    if success then
        Log("Saved player data for " .. pIdNum .. " to " .. filename .. ".", "info", "CNR_SERVER")
    else
        Log("Failed to save player data for " .. pIdNum .. " to " .. filename .. ".", "error", "CNR_SERVER")
    end
end

SetPlayerRole = function(playerId, role, skipNotify)
    local pIdNum = tonumber(playerId)
    if not pIdNum or pIdNum <= 0 then
        Log(string.format("SetPlayerRole: Invalid player ID %s", tostring(playerId)), "error", "CNR_SERVER")
        return
    end

    -- Check if player is still online
    if not GetPlayerName(pIdNum) then
        Log(string.format("SetPlayerRole: Player %s is not online", pIdNum), "warn", "CNR_SERVER")
        return
    end

    local playerName = GetPlayerName(pIdNum) or "Unknown"
    -- Log(string.format("SetPlayerRole DEBUG: Attempting to set role for pIdNum: %s, playerName: %s, to newRole: %s. Current role in playersData: %s", pIdNum, playerName, role, (playersData[pIdNum] and playersData[pIdNum].role or "nil_or_no_pData")), "info")

    local pData = playersData[pIdNum] -- Get pData directly
    if not pData or not pData.isDataLoaded then -- Check both for robustness
        Log(string.format("SetPlayerRole: Attempted to set role for %s (Name: %s) but data not loaded/ready. Role: %s. pData exists: %s, isDataLoaded: %s. This should have been caught by the caller.", pIdNum, playerName, role, tostring(pData ~= nil), tostring(pData and pData.isDataLoaded)), "warn", "CNR_SERVER")
        -- Do NOT trigger 'cnr:roleSelected' here, as the caller handles it.
        SafeTriggerClientEvent('chat:addMessage', pIdNum, { args = {"^1Error", "Role change failed: Player data integrity issue."} })
        return
    end

    -- Log(string.format("SetPlayerRole DEBUG: Before role update. pIdNum: %s, current playersData[pIdNum].role: %s, new role to set: %s", pIdNum, (playersData[pIdNum] and playersData[pIdNum].role or "nil_or_no_pData"), role), "info")
    pData.role = role
    -- Log(string.format("SetPlayerRole DEBUG: After role update. pIdNum: %s, playersData[pIdNum].role is now: %s", pIdNum, playersData[pIdNum].role), "info")
    -- player.Functions.SetMetaData("role", role) -- Example placeholder

    if role == "cop" then
        SafeSetByPlayerId(copsOnDuty, pIdNum, true)
        SafeRemoveByPlayerId(robbersActive, pIdNum)
        
        -- Clear wanted level when switching to cop (cops can't be wanted)
        if wantedPlayers[pIdNum] and wantedPlayers[pIdNum].wantedLevel > 0 then
            wantedPlayers[pIdNum] = { wantedLevel = 0, stars = 0, lastCrimeTime = 0, crimesCommitted = {} }
            SafeTriggerClientEvent('cnr:wantedLevelSync', pIdNum, wantedPlayers[pIdNum])
            SafeTriggerClientEvent('cops_and_robbers:updateWantedDisplay', pIdNum, 0, 0)
            SafeTriggerClientEvent('cnr:hideWantedNotification', pIdNum)
            Log(string.format("Cleared wanted level for player %s who switched to cop role", pIdNum), "info", "CNR_SERVER")
            
            -- Notify all cops that this player is no longer wanted
            for copId, _ in pairs(copsOnDuty) do
                if GetPlayerName(copId) ~= nil then
                    SafeTriggerClientEvent('cnr:updatePoliceBlip', copId, pIdNum, nil, 0, false)
                end
            end
        end
        
        -- player.Functions.SetJob("leo", 0) -- Placeholder for framework integration
        SafeTriggerClientEvent('cnr:setPlayerRole', pIdNum, "cop")
        if not skipNotify then SafeTriggerClientEvent('chat:addMessage', pIdNum, { args = {"^3Role", "You are now a Cop."} }) end
        Log("Player " .. pIdNum .. " (" .. playerName .. ") set to Cop role.", "info", "CNR_SERVER")
        SafeTriggerClientEvent('cops_and_robbers:bountyListUpdate', pIdNum, activeBounties)
    elseif role == "robber" then
        SafeSetByPlayerId(robbersActive, pIdNum, true)
        SafeRemoveByPlayerId(copsOnDuty, pIdNum)
        -- player.Functions.SetJob("unemployed", 0) -- Placeholder for framework integration
        SafeTriggerClientEvent('cnr:setPlayerRole', pIdNum, "robber")
        if not skipNotify then SafeTriggerClientEvent('chat:addMessage', pIdNum, { args = {"^3Role", "You are now a Robber."} }) end
        Log("Player " .. pIdNum .. " (" .. playerName .. ") set to Robber role.", "info", "CNR_SERVER")
    else
        SafeRemoveByPlayerId(copsOnDuty, pIdNum)
        SafeRemoveByPlayerId(robbersActive, pIdNum)
        -- player.Functions.SetJob("unemployed", 0) -- Placeholder for framework integration
        SafeTriggerClientEvent('cnr:setPlayerRole', pIdNum, "citizen")
        if not skipNotify then SafeTriggerClientEvent('chat:addMessage', pIdNum, { args = {"^3Role", "You are now a Citizen."} }) end
        Log("Player " .. pIdNum .. " (" .. playerName .. ") set to Citizen role.", "info", "CNR_SERVER")
    end
    ApplyPerks(pIdNum, playersData[pIdNum].level, role) -- Re-apply/update perks based on new role
    -- Log(string.format("SetPlayerRole DEBUG: Before TriggerClientEvent cnr:updatePlayerData. pIdNum: %s, Data being sent: %s", pIdNum, json.encode(playersData[pIdNum])), "info")
    local pDataForBasicInfo = shallowcopy(playersData[pIdNum])
    pDataForBasicInfo.inventory = nil
    SafeTriggerClientEvent('cnr:updatePlayerData', pIdNum, pDataForBasicInfo)
    
    -- Send config items first so client can properly reconstruct inventory
    if Config and Config.Items and type(Config.Items) == "table" then
        SafeTriggerClientEvent('cnr:receiveConfigItems', pIdNum, Config.Items)
    end
    
    SafeTriggerClientEvent('cnr:syncInventory', pIdNum, MinimizeInventoryForSync(playersData[pIdNum].inventory))
end

IsPlayerCop = function(playerId) return GetPlayerRole(playerId) == "cop" end
IsPlayerRobber = function(playerId) return GetPlayerRole(playerId) == "robber" end

local function CalculateLevel(xp, role)
    if not Config.LevelingSystemEnabled then return 1 end -- Return level 1 if system disabled
    local currentLevel = 1
    local cumulativeXp = 0

    -- Iterate up to Config.MaxLevel - 1 because XPTable defines XP to reach NEXT level
    for level = 1, (Config.MaxLevel or 10) - 1 do
        local xpForNext = (Config.XPTable and Config.XPTable[level]) or 999999
        cumulativeXp = cumulativeXp + xpForNext
        if xp >= cumulativeXp then
            currentLevel = level + 1
        else
            break -- Stop if player does not have enough XP for this level
        end
    end
    -- Ensure level does not exceed MaxLevel
    return math.min(currentLevel, (Config.MaxLevel or 10))
end

-- Enhanced AddXP function that integrates with the new progression system
AddXP = function(playerId, amount, type, reason)
    local pIdNum = tonumber(playerId)
    if not pIdNum or pIdNum <= 0 then
        Log("AddXP: Invalid player ID " .. tostring(playerId), "error", "CNR_SERVER")
        return
    end

    local pData = GetCnrPlayerData(pIdNum)
    if not pData then
        Log("AddXP: Player " .. (pIdNum or "unknown") .. " data not init.", "error", "CNR_SERVER")
        return
    end
    
    -- Check if progression system is available and use it
    if exports['cops-and-robbers'] and exports['cops-and-robbers'].AddXP then
        exports['cops-and-robbers'].AddXP(pIdNum, amount, type, reason)
        return
    end
    
    -- Fallback to original system if progression system is not available
    if type and pData.role ~= type and type ~= "general" then return end

    pData.xp = pData.xp + amount
    local oldLevel = pData.level
    local newLevel = CalculateLevel(pData.xp, pData.role)

    if newLevel > oldLevel then
        pData.level = newLevel
        SafeTriggerClientEvent('chat:addMessage', pIdNum, { args = {"^2Level Up!", string.format("Congratulations! You've reached Level %d!", newLevel)} })
        SafeTriggerClientEvent('cnr:levelUp', pIdNum, newLevel, pData.xp)
        Log(string.format("Player %s leveled up to %d (XP: %d, Role: %s)", pIdNum, newLevel, pData.xp, pData.role), "info", "CNR_SERVER")
        ApplyPerks(pIdNum, newLevel, pData.role)
    else
        SafeTriggerClientEvent('cnr:xpGained', pIdNum, amount, pData.xp)
        Log(string.format("Player %s gained %d XP (Total: %d, Role: %s)", pIdNum, amount, pData.xp, pData.role), "info", "CNR_SERVER")
    end
    
    -- Update XP bar display
    local xpForNextLevel = CalculateXpForNextLevel(newLevel, pData.role)
    SafeTriggerClientEvent('updateXPBar', pIdNum, pData.xp, newLevel, xpForNextLevel, amount)
    
    local pDataForBasicInfo = shallowcopy(pData)
    pDataForBasicInfo.inventory = nil
    SafeTriggerClientEvent('cnr:updatePlayerData', pIdNum, pDataForBasicInfo)
    
    -- Send config items first so client can properly reconstruct inventory
    if Config and Config.Items and type(Config.Items) == "table" then
        SafeTriggerClientEvent('cnr:receiveConfigItems', pIdNum, Config.Items)
    end
    
    SafeTriggerClientEvent('cnr:syncInventory', pIdNum, MinimizeInventoryForSync(pData.inventory))
end

ApplyPerks = function(playerId, level, role)
    local pIdNum = tonumber(playerId)
    if not pIdNum or pIdNum <= 0 then
        Log("ApplyPerks: Invalid player ID " .. tostring(playerId), "error", "CNR_SERVER")
        return
    end

    local pData = GetCnrPlayerData(pIdNum)
    if not pData then
        return
    end
    pData.perks = {} -- Reset perks
    pData.extraSpikeStrips = 0 -- Reset specific perk values
    pData.contrabandCollectionModifier = 1.0 -- Reset specific perk values
    pData.armorModifier = 1.0 -- Ensure armorModifier is also reset

    local unlocks = {}
    if role and Config.LevelUnlocks and Config.LevelUnlocks[role] then
        unlocks = Config.LevelUnlocks[role]
    else
        Log(string.format("ApplyPerks: No level unlocks defined for role '%s'. Player %s will have no role-specific level perks.", tostring(role), pIdNum), "info", "CNR_SERVER")
        -- No need to immediately return, as pData.perks (now empty) and other perk-related values need to be synced.
    end

    for levelKey, levelUnlocksTable in pairs(unlocks) do
        if level >= levelKey then
            if type(levelUnlocksTable) == "table" then -- Ensure levelUnlocksTable is a table
                for _, perkDetail in ipairs(levelUnlocksTable) do
                    if type(perkDetail) == "table" then -- Ensure perkDetail is a table
                        -- Only try to set pData.perks if it's actually a perk and perkId is valid
                        if perkDetail.type == "passive_perk" and perkDetail.perkId then
                            pData.perks[perkDetail.perkId] = true
                            Log(string.format("Player %s unlocked perk: %s at level %d", pIdNum, perkDetail.perkId, levelKey), "info", "CNR_SERVER")
                        -- else
                            -- Log for non-passive_perk types if needed for debugging, e.g.:
                            -- if perkDetail.type ~= "passive_perk" then
                            --     Log(string.format("ApplyPerks: Skipping non-passive_perk type '%s' for player %s at level %d.", tostring(perkDetail.type), pIdNum, levelKey))
                            -- end
                        end

                        -- Handle specific perk values (existing logic, ensure perkDetail.type matches and perkId is valid)
                        if perkDetail.type == "passive_perk" and perkDetail.perkId then
                            if perkDetail.perkId == "increased_armor_durability" and role == "cop" then
                                pData.armorModifier = perkDetail.value or Config.PerkEffects.IncreasedArmorDurabilityModifier or 1.25
                                Log(string.format("Player %s granted increased_armor_durability (modifier: %s).", pIdNum, pData.armorModifier), "info", "CNR_SERVER")
                            elseif perkDetail.perkId == "extra_spike_strips" and role == "cop" then
                                pData.extraSpikeStrips = perkDetail.value or 1
                                Log(string.format("Player %s granted extra_spike_strips (value: %d).", pIdNum, pData.extraSpikeStrips), "info", "CNR_SERVER")
                            elseif perkDetail.perkId == "faster_contraband_collection" and role == "robber" then
                                 pData.contrabandCollectionModifier = perkDetail.value or 0.8
                                 Log(string.format("Player %s granted faster_contraband_collection (modifier: %s).", pIdNum, pData.contrabandCollectionModifier), "info", "CNR_SERVER")
                            end
                        end
                    else
                        Log(string.format("ApplyPerks: perkDetail at levelKey %s for role %s is not a table. Skipping.", levelKey, role), "warn", "CNR_SERVER")
                    end
                end
            else
                 Log(string.format("ApplyPerks: levelUnlocksTable at levelKey %s for role %s is not a table. Skipping.", levelKey, role), "warn", "CNR_SERVER")
            end
        end
    end
    local pDataForBasicInfo = shallowcopy(pData)
    pDataForBasicInfo.inventory = nil
    SafeTriggerClientEvent('cnr:updatePlayerData', pIdNum, pDataForBasicInfo)
    
    -- Send config items first so client can properly reconstruct inventory
    if Config and Config.Items and type(Config.Items) == "table" then
        SafeTriggerClientEvent('cnr:receiveConfigItems', pIdNum, Config.Items)
    end
    
    SafeTriggerClientEvent('cnr:syncInventory', pIdNum, MinimizeInventoryForSync(pData.inventory))
end


-- =================================================================================================
-- BOUNTY SYSTEM
-- =================================================================================================
function CheckAndPlaceBounty(playerId)
    local pIdNum = tonumber(playerId)
    if not Config.BountySettings.enabled then return end
    local wantedData = wantedPlayers[pIdNum]
    local pData = GetCnrPlayerData(pIdNum)
    if not wantedData or not pData then
        return
    end

    if wantedData.stars >= Config.BountySettings.wantedLevelThreshold and
       not activeBounties[pIdNum] and (pData.bountyCooldownUntil or 0) < os.time() then
        local bountyAmount = Config.BountySettings.baseAmount
        local targetName = SafeGetPlayerName(pIdNum) or "Unknown Target"
        local durationMinutes = Config.BountySettings.durationMinutes
        if durationMinutes and activeBounties and pIdNum then
            activeBounties[pIdNum] = { name = targetName, amount = bountyAmount, issueTimestamp = os.time(), lastIncreasedTimestamp = os.time(), expiresAt = os.time() + (durationMinutes * 60) }
            Log(string.format("Bounty of $%d placed on %s (ID: %d) for reaching %d stars.", bountyAmount, targetName, pIdNum, wantedData.stars), "info", "CNR_SERVER")
            TriggerClientEvent('cops_and_robbers:bountyListUpdate', -1, activeBounties)
            TriggerClientEvent('chat:addMessage', -1, { args = {"^1[BOUNTY PLACED]", string.format("A bounty of $%d has been placed on %s!", bountyAmount, targetName)} })
        end
    end
end

CreateThread(function() -- Bounty Increase & Expiry Loop
    while true do Wait(60000)
        if not Config.BountySettings.enabled then goto continue_bounty_loop end
        local bountyUpdatedThisCycle = false
        local currentTime = os.time()
        for playerIdStr, bountyData in pairs(activeBounties) do
            local playerId = tonumber(playerIdStr)
            -- local player = GetPlayerFromServerId(playerId) -- Not needed if player is offline, bounty can still tick or expire
            local pData = GetCnrPlayerData(playerId)
            local wantedData = wantedPlayers[playerId]
            local isPlayerOnline = GetPlayerName(tostring(playerId)) ~= nil -- Check if player is online

            if isPlayerOnline and pData and wantedData and wantedData.stars >= Config.BountySettings.wantedLevelThreshold and currentTime < bountyData.expiresAt then
                if bountyData.amount < Config.BountySettings.maxBounty then
                    bountyData.amount = math.min(bountyData.amount + Config.BountySettings.increasePerMinute, Config.BountySettings.maxBounty)
                    bountyData.lastIncreasedTimestamp = currentTime
                    Log(string.format("Bounty for %s (ID: %d) increased to $%d.", bountyData.name, playerId, bountyData.amount), "info", "CNR_SERVER")
                    bountyUpdatedThisCycle = true
                end
            elseif currentTime >= bountyData.expiresAt or (isPlayerOnline and pData and wantedData and wantedData.stars < Config.BountySettings.wantedLevelThreshold) then
                local bountyAmount = bountyData.amount or 0
                local bountyName = bountyData.name or "Unknown"
                local starCount = (wantedData and wantedData.stars) or "N/A"
                Log(string.format("Bounty of $%d expired/removed for %s (ID: %s). Player online: %s, Stars: %s", bountyAmount, bountyName, tostring(playerId), tostring(isPlayerOnline), tostring(starCount)), "info", "CNR_SERVER")
                if activeBounties and playerId then
                    activeBounties[playerId] = nil
                end
                if pData then
                    local cooldownMinutes = Config.BountySettings.cooldownMinutes
                    if cooldownMinutes then
                        pData.bountyCooldownUntil = currentTime + (cooldownMinutes * 60)
                    end
                    if isPlayerOnline then SavePlayerData(playerId) end
                end
                bountyUpdatedThisCycle = true
            end
        end
        if bountyUpdatedThisCycle then TriggerClientEvent('cops_and_robbers:bountyListUpdate', -1, activeBounties) end
        ::continue_bounty_loop::
    end
end)

-- Handle bounty list request
RegisterNetEvent('cnr:requestBountyList')
AddEventHandler('cnr:requestBountyList', function()
    local source = source
    -- Send the list of all active bounties to the player who requested it
    local bountyList = {}
    
    -- If there are no active bounties, return an empty list
    if not next(activeBounties) then
        TriggerClientEvent('cnr:receiveBountyList', source, {})
        return
    end
    
    -- Convert the activeBounties table to an array format for the UI
    for playerId, bountyData in pairs(activeBounties) do
        table.insert(bountyList, {
            id = playerId,
            name = bountyData.name,
            amount = bountyData.amount,
            expiresAt = bountyData.expiresAt
        })
    end
    
    -- Sort bounties by amount (highest first)
    table.sort(bountyList, function(a, b) return a.amount > b.amount end)
    
    -- Send the formatted bounty list to the client
    TriggerClientEvent('cnr:receiveBountyList', source, bountyList)
end)

-- =================================================================================================
-- WANTED SYSTEM
-- =================================================================================================
UpdatePlayerWantedLevel = function(playerId, crimeKey, officerId)
    local pIdNum = tonumber(playerId)
    if not pIdNum or pIdNum <= 0 then
        Log("UpdatePlayerWantedLevel: Invalid player ID " .. tostring(playerId), "error", "CNR_SERVER")
        return
    end

    if GetPlayerName(pIdNum) == nil or not IsPlayerRobber(pIdNum) then return end -- Check player online using GetPlayerName

    local crimeConfig = Config.WantedSettings.crimes[crimeKey]
    if not crimeConfig then
        Log("UpdatePlayerWantedLevel: Unknown crimeKey: " .. crimeKey, "error", "CNR_SERVER")
        return
    end

    if not wantedPlayers[pIdNum] then wantedPlayers[pIdNum] = { wantedLevel = 0, stars = 0, lastCrimeTime = 0, crimesCommitted = {} } end
    local currentWanted = wantedPlayers[pIdNum]

    -- Use crimeConfig.points if defined, otherwise Config.WantedSettings.baseIncreasePoints
    local pointsToAdd = (type(crimeConfig) == "table" and crimeConfig.wantedPoints) or (type(crimeConfig) == "number" and crimeConfig) or Config.WantedSettings.baseIncreasePoints or 1
    local maxConfiguredWantedLevel = 0
    if Config.WantedSettings and Config.WantedSettings.levels and #Config.WantedSettings.levels > 0 then
        maxConfiguredWantedLevel = Config.WantedSettings.levels[#Config.WantedSettings.levels].threshold + 10 -- A bit above the highest threshold
    else
        maxConfiguredWantedLevel = 200 -- Fallback max wanted points if config is malformed
    end

    currentWanted.wantedLevel = math.min(currentWanted.wantedLevel + pointsToAdd, maxConfiguredWantedLevel)
    currentWanted.lastCrimeTime = os.time()
    if not currentWanted.crimesCommitted[crimeKey] then currentWanted.crimesCommitted[crimeKey] = 0 end
    currentWanted.crimesCommitted[crimeKey] = currentWanted.crimesCommitted[crimeKey] + 1

    local newStars = 0
    if Config.WantedSettings and Config.WantedSettings.levels then
        for i = #Config.WantedSettings.levels, 1, -1 do
            if currentWanted.wantedLevel >= Config.WantedSettings.levels[i].threshold then
                newStars = Config.WantedSettings.levels[i].stars
                break
            end
        end
    end

currentWanted.stars = newStars
    -- Reduced logging: Only log on significant changes to reduce spam
    if newStars ~= (currentWanted.previousStars or 0) then
        Log(string.format("Player %s committed crime '%s'. Points: %s. Wanted Lvl: %d, Stars: %d", pIdNum, crimeKey, pointsToAdd, currentWanted.wantedLevel, newStars), "info", "CNR_SERVER")
        currentWanted.previousStars = newStars
    end

SafeTriggerClientEvent('cnr:wantedLevelSync', pIdNum, currentWanted) -- Syncs wantedLevel points and stars
    -- The [CNR_SERVER_DEBUG] print previously here is now covered by the TRACE print above.
    SafeTriggerClientEvent('cops_and_robbers:updateWantedDisplay', pIdNum, newStars, currentWanted.wantedLevel) -- Explicitly update client UI

    -- Send UI notification instead of chat message
    local uiLabel = ""
    for _, levelData in ipairs(Config.WantedSettings.levels or {}) do
        if levelData.stars == newStars then
            uiLabel = levelData.uiLabel
            break
        end
    end
    if uiLabel == "" then
        uiLabel = "Wanted: " .. string.rep("★", newStars) .. string.rep("☆", 5 - newStars)
    end

    SafeTriggerClientEvent('cnr:showWantedNotification', pIdNum, newStars, currentWanted.wantedLevel, uiLabel)

    local crimeDescription = (type(crimeConfig) == "table" and crimeConfig.description) or crimeKey:gsub("_"," "):gsub("%a", string.upper, 1)
    local robberPlayerName = GetPlayerName(pIdNum) or "Unknown Suspect"
    local robberPed = GetPlayerPed(pIdNum) -- Get ped once
    local robberCoords = robberPed and GetEntityCoords(robberPed) or nil

    if newStars > 0 and robberCoords then -- Only proceed if player has stars and valid coordinates
        -- NPC Police Response Logic (now explicitly server-triggered and configurable)
        if Config.WantedSettings.enableNPCResponse then
            if robberCoords then -- Ensure robberCoords is not nil before logging its components
                Log(string.format("UpdatePlayerWantedLevel: NPC Response ENABLED. Triggering cops_and_robbers:wantedLevelResponseUpdate for player %s (%d stars) at Coords: X:%.2f, Y:%.2f, Z:%.2f", pIdNum, newStars, robberCoords.x, robberCoords.y, robberCoords.z), "info", "CNR_SERVER")
            else
                Log(string.format("UpdatePlayerWantedLevel: NPC Response ENABLED for player %s (%d stars), but robberCoords are nil. Event will still be triggered.", pIdNum, newStars), "warn", "CNR_SERVER")
            end
            SafeTriggerClientEvent('cops_and_robbers:wantedLevelResponseUpdate', pIdNum, pIdNum, newStars, currentWanted.wantedLevel, robberCoords)
        else
            Log(string.format("UpdatePlayerWantedLevel: NPC Response DISABLED via Config.WantedSettings.enableNPCResponse for player %s (%d stars). Not triggering event.", pIdNum, newStars), "info", "CNR_SERVER")
        end

        -- Alert Human Cops (existing logic)
        for copId, _ in pairs(copsOnDuty) do
            if GetPlayerName(copId) ~= nil then -- Check cop is online
                SafeTriggerClientEvent('chat:addMessage', copId, { args = {"^5Police Alert", string.format("Suspect %s (%s) is %d-star wanted for %s.", robberPlayerName, pIdNum, newStars, crimeDescription)} })
                SafeTriggerClientEvent('cnr:updatePoliceBlip', copId, pIdNum, robberCoords, newStars, true)
            end
        end
    end

    if type(crimeConfig) == "table" and crimeConfig.xpForRobber and crimeConfig.xpForRobber > 0 then
        AddXP(pIdNum, crimeConfig.xpForRobber, "robber")
    end
    CheckAndPlaceBounty(pIdNum)
end

ReduceWantedLevel = function(playerId, amount)
    local pIdNum = tonumber(playerId)
    if not pIdNum or pIdNum <= 0 then
        Log("ReduceWantedLevel: Invalid player ID " .. tostring(playerId), "error", "CNR_SERVER")
        return
    end

    if wantedPlayers[pIdNum] then
        wantedPlayers[pIdNum].wantedLevel = math.max(0, wantedPlayers[pIdNum].wantedLevel - amount)
        local newStars = 0
        if Config.WantedSettings and Config.WantedSettings.levels then
            for i = #Config.WantedSettings.levels, 1, -1 do
                if wantedPlayers[pIdNum].wantedLevel >= Config.WantedSettings.levels[i].threshold then
                    newStars = Config.WantedSettings.levels[i].stars
                    break
                end
            end
        end
        wantedPlayers[pIdNum].stars = newStars
        SafeTriggerClientEvent('cnr:wantedLevelSync', pIdNum, wantedPlayers[pIdNum])
        SafeTriggerClientEvent('cops_and_robbers:updateWantedDisplay', pIdNum, newStars, wantedPlayers[pIdNum].wantedLevel)
        Log(string.format("Reduced wanted for %s. New Lvl: %d, Stars: %d", pIdNum, wantedPlayers[pIdNum].wantedLevel, newStars), "info", "CNR_SERVER")
        if wantedPlayers[pIdNum].wantedLevel == 0 then
            SafeTriggerClientEvent('cnr:hideWantedNotification', pIdNum)
            SafeTriggerClientEvent('chat:addMessage', pIdNum, { args = {"^2Wanted", "You are no longer wanted."} })
            for copId, _ in pairs(copsOnDuty) do
                if GetPlayerName(copId) ~= nil then -- Check cop is online
                    SafeTriggerClientEvent('cnr:updatePoliceBlip', copId, pIdNum, nil, 0, false)
                end
            end
        end
        if newStars < Config.BountySettings.wantedLevelThreshold and activeBounties[pIdNum] then
             -- Bounty expiry due to wanted level drop is handled by the bounty loop
        end
    end
end

CreateThread(function() -- Wanted level decay with cop sight detection
    while true do Wait(Config.WantedSettings.decayIntervalMs or 30000)
        local currentTime = os.time()
        for playerIdStr, data in pairs(wantedPlayers) do 
            local playerId = tonumber(playerIdStr)
            -- Only apply decay to online robbers
            if GetPlayerName(playerId) ~= nil and IsPlayerRobber(playerId) then
                if data.wantedLevel > 0 and (currentTime - data.lastCrimeTime) > (Config.WantedSettings.noCrimeCooldownMs / 1000) then
                    -- Check if any cops are nearby (cop sight detection)
                    local playerPed = GetPlayerPed(playerId)
                    local canDecay = true
                    
                    if playerPed and playerPed > 0 and DoesEntityExist(playerPed) then
                        local playerCoords = GetEntityCoords(playerPed)
                        local copSightDistance = Config.WantedSettings.copSightDistance or 50.0
                        
                        -- Check distance to all online cops
                        for copId, _ in pairs(copsOnDuty) do
                            if GetPlayerName(copId) ~= nil then -- Cop is online
                                local copPed = GetPlayerPed(copId)
                                if copPed and copPed > 0 and DoesEntityExist(copPed) then
                                    local copCoords = GetEntityCoords(copPed)
                                    local distance = #(playerCoords - copCoords)
                                    
                                    if distance <= copSightDistance then
                                        canDecay = false
                                        -- Update last cop sight time
                                        data.lastCopSightTime = currentTime
                                        break
                                    end
                                end
                            end
                        end
                        
                        -- Check cop sight cooldown
                        if canDecay and data.lastCopSightTime then
                            local timeSinceLastSight = currentTime - data.lastCopSightTime
                            if timeSinceLastSight < (Config.WantedSettings.copSightCooldownMs / 1000) then
                                canDecay = false
                            end
                        end
                    end
                    
                    if canDecay then
                        ReduceWantedLevel(playerId, Config.WantedSettings.decayRatePoints)
                    end
                end
            elseif GetPlayerName(playerId) == nil then
                -- Player is offline, keep their wanted level but don't decay it
                -- This preserves wanted levels across disconnections
            elseif not IsPlayerRobber(playerId) then
                -- Player switched to cop, clear their wanted level immediately
                wantedPlayers[playerIdStr] = nil
                Log(string.format("Cleared wanted level for player %s who switched from robber to cop", playerId), "info", "CNR_SERVER")
            end
        end
    end
end)

-- Server-side crime detection for robbers only
local playerSpeedingData = {} -- Track speeding state per player
local playerVehicleData = {} -- Track vehicle damage and collisions

CreateThread(function()
    while true do
        Wait(1000) -- Check every second
        
        for playerId, _ in pairs(robbersActive) do
            if GetPlayerName(playerId) ~= nil then -- Player is online
                local playerPed = GetPlayerPed(playerId)
                if playerPed and playerPed > 0 and DoesEntityExist(playerPed) then
                    local vehicle = GetVehiclePedIsIn(playerPed, false)
                    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
                        local speed = GetEntitySpeed(vehicle) * 2.236936 -- Convert m/s to mph
                        local currentTime = os.time()
                        local vehicleClass = GetVehicleClass(vehicle)
                        
                        -- Exclude aircraft (planes/helicopters) and boats from speeding detection
                        local isAircraft = (vehicleClass == 15 or vehicleClass == 16) -- Helicopters and planes
                        local isBoat = (vehicleClass == 14) -- Boats
                        local speedLimit = Config.SpeedLimitMph or 60.0
                        
                        -- Initialize player data if not exists
                        if not playerSpeedingData[playerId] then
                            playerSpeedingData[playerId] = {
                                isCurrentlySpeeding = false,
                                speedingStartTime = 0,
                                lastSpeedingViolation = 0
                            }
                        end
                        
                        if not playerVehicleData[playerId] then
                            playerVehicleData[playerId] = {
                                lastVehicle = vehicle,
                                lastVehicleHealth = GetVehicleEngineHealth(vehicle),
                                lastCollisionCheck = currentTime
                            }
                        end
                        
                        local speedData = playerSpeedingData[playerId]
                        local vehicleData = playerVehicleData[playerId]
                        
                        -- Check for speeding (increase wanted level) only for ground vehicles
                        if not isAircraft and not isBoat and speed > speedLimit then
                            if not speedData.isCurrentlySpeeding then
                                -- Player just started speeding, start the timer
                                speedData.speedingStartTime = currentTime
                                speedData.isCurrentlySpeeding = true
                            elseif (currentTime - speedData.speedingStartTime) > 5 and (currentTime - speedData.lastSpeedingViolation) > 10 then
                                -- Player has been speeding for more than 5 seconds and cooldown period has passed
                                speedData.lastSpeedingViolation = currentTime
                                UpdatePlayerWantedLevel(playerId, "speeding")
                                Log(string.format("Player %s caught speeding at %.1f mph (limit: %.1f mph)", playerId, speed, speedLimit), "info", "CNR_SERVER")
                            end
                        else
                            -- Player is no longer speeding or in exempt vehicle
                            speedData.isCurrentlySpeeding = false
                            speedData.speedingStartTime = 0
                        end
                        
                        -- Check for vehicle damage (potential hit and run)
                        if vehicleData.lastVehicle == vehicle then
                            local currentHealth = GetVehicleEngineHealth(vehicle)
                            if currentHealth < vehicleData.lastVehicleHealth - 50 and speed > 20 then -- Significant damage while moving
                                if (currentTime - vehicleData.lastCollisionCheck) > 3 then -- Cooldown to prevent spam
                                    vehicleData.lastCollisionCheck = currentTime
                                    UpdatePlayerWantedLevel(playerId, "hit_and_run")
                                    Log(string.format("Player %s involved in hit and run (vehicle damage detected)", playerId), "info", "CNR_SERVER")
                                end
                            end
                            vehicleData.lastVehicleHealth = currentHealth
                        else
                            -- Player switched vehicles, update tracking
                            vehicleData.lastVehicle = vehicle
                            vehicleData.lastVehicleHealth = GetVehicleEngineHealth(vehicle)
                        end
                    else
                        -- Player not in vehicle, reset speeding state
                        if playerSpeedingData[playerId] then
                            playerSpeedingData[playerId].isCurrentlySpeeding = false
                            playerSpeedingData[playerId].speedingStartTime = 0
                        end
                    end
                end
            end
        end
    end
end)

-- Server-side weapon discharge detection for robbers
RegisterNetEvent('cnr:weaponFired')
AddEventHandler('cnr:weaponFired', function(weaponHash, coords)
    local src = source
    if not IsPlayerRobber(src) then return end -- Only apply to robbers
    
    -- Check if player is in a safe zone or other restricted area
    local playerPed = GetPlayerPed(src)
    if not playerPed or playerPed <= 0 then return end
    
    -- Add wanted level for weapons discharge
    UpdatePlayerWantedLevel(src, "weapons_discharge")
    Log(string.format("Player %s fired weapon (Hash: %s) - wanted level increased", src, weaponHash), "info", "CNR_SERVER")
end)

-- Server-side restricted area monitoring for robbers
local playerRestrictedAreaData = {} -- Track which areas players have entered

CreateThread(function()
    while true do
        Wait(2000) -- Check every 2 seconds
        
        if Config.RestrictedAreas and #Config.RestrictedAreas > 0 then
            for playerId, _ in pairs(robbersActive) do
                if GetPlayerName(playerId) ~= nil then -- Player is online
                    local playerPed = GetPlayerPed(playerId)
                    if playerPed and playerPed > 0 and DoesEntityExist(playerPed) then
                        local playerCoords = GetEntityCoords(playerPed)
                        
                        -- Initialize player restricted area data if not exists
                        if not playerRestrictedAreaData[playerId] then
                            playerRestrictedAreaData[playerId] = {}
                        end
                        
                        for _, area in ipairs(Config.RestrictedAreas) do
                            local distance = #(playerCoords - area.center)
                            local areaKey = area.name or "unknown"
                            
                            if distance <= area.radius then
                                -- Player is in restricted area
                                if not playerRestrictedAreaData[playerId][areaKey] then
                                    -- First time entering this area
                                    playerRestrictedAreaData[playerId][areaKey] = true
                                    
                                    -- Check if this area applies to robbers (ifNotRobber = false or nil)
                                    if not area.ifNotRobber then
                                        -- Show warning message
                                        if area.message then
                                            SafeTriggerClientEvent('chat:addMessage', playerId, { 
                                                args = {"^3Restricted Area", area.message} 
                                            })
                                        end
                                        
                                        -- Add wanted points if configured
                                        if area.wantedPoints and area.wantedPoints > 0 then
                                            UpdatePlayerWantedLevel(playerId, "restricted_area_entry")
                                            Log(string.format("Player %s entered restricted area: %s - wanted level increased", playerId, areaKey), "info", "CNR_SERVER")
                                        end
                                    end
                                end
                            else
                                -- Player left the area
                                if playerRestrictedAreaData[playerId][areaKey] then
                                    playerRestrictedAreaData[playerId][areaKey] = nil
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- Server-side assault and murder detection for robbers
RegisterNetEvent('cnr:playerDamaged')
AddEventHandler('cnr:playerDamaged', function(targetPlayerId, damage, weaponHash, isFatal)
    local src = source
    if not IsPlayerRobber(src) then return end -- Only apply to robbers
    if src == targetPlayerId then return end -- Don't count self-damage
    
    local targetData = GetCnrPlayerData(targetPlayerId)
    if not targetData then return end
    
    if isFatal then
        -- Murder
        if targetData.role == "cop" then
            UpdatePlayerWantedLevel(src, "murder_cop")
            Log(string.format("Player %s murdered cop %s - high wanted level increase", src, targetPlayerId), "warn", "CNR_SERVER")
        else
            UpdatePlayerWantedLevel(src, "murder_civilian")
            Log(string.format("Player %s murdered civilian %s - wanted level increased", src, targetPlayerId), "info", "CNR_SERVER")
        end
    else
        -- Assault
        if targetData.role == "cop" then
            UpdatePlayerWantedLevel(src, "assault_cop")
            Log(string.format("Player %s assaulted cop %s - wanted level increased", src, targetPlayerId), "info", "CNR_SERVER")
        else
            UpdatePlayerWantedLevel(src, "assault_civilian")
            Log(string.format("Player %s assaulted civilian %s - wanted level increased", src, targetPlayerId), "info", "CNR_SERVER")
        end
    end
end)

-- Test command for wanted system (admin only)
RegisterCommand('testwanted', function(source, args, rawCommand)
    local src = source
    if src == 0 then return end -- Console command not supported
    
    local pData = GetCnrPlayerData(src)
    if not pData or not pData.isAdmin then
        SafeTriggerClientEvent('chat:addMessage', src, { args = {"^1Error", "You don't have permission to use this command."} })
        return
    end
    
    if not args[1] then
        SafeTriggerClientEvent('chat:addMessage', src, { args = {"^3Usage", "/testwanted <crime_key> - Test wanted level system"} })
        return
    end
    
    local crimeKey = args[1]
    if not Config.WantedSettings.crimes[crimeKey] then
        SafeTriggerClientEvent('chat:addMessage', src, { args = {"^1Error", "Invalid crime key. Check config.lua for valid crimes."} })
        return
    end
    
    if not IsPlayerRobber(src) then
        SafeTriggerClientEvent('chat:addMessage', src, { args = {"^1Error", "You must be a robber to test the wanted system."} })
        return
    end
    
    UpdatePlayerWantedLevel(src, crimeKey)
    SafeTriggerClientEvent('chat:addMessage', src, { args = {"^2Test", "Wanted level updated for crime: " .. crimeKey} })
end, false)

-- Command for cops to report crimes they witness
RegisterCommand('reportcrime', function(source, args, rawCommand)
    local src = source
    if src == 0 then return end -- Console command not supported
    
    if not IsPlayerCop(src) then
        SafeTriggerClientEvent('chat:addMessage', src, { args = {"^1Error", "Only cops can report crimes."} })
        return
    end
    
    if not args[1] or not args[2] then
        SafeTriggerClientEvent('chat:addMessage', src, { args = {"^3Usage", "/reportcrime <player_id> <crime_key>"} })
        SafeTriggerClientEvent('chat:addMessage', src, { args = {"^3Examples", "/reportcrime 5 speeding, /reportcrime 12 weapons_discharge"} })
        return
    end
    
    local targetId = tonumber(args[1])
    local crimeKey = args[2]
    
    if not targetId or targetId <= 0 then
        SafeTriggerClientEvent('chat:addMessage', src, { args = {"^1Error", "Invalid player ID."} })
        return
    end
    
    if not GetPlayerName(targetId) then
        SafeTriggerClientEvent('chat:addMessage', src, { args = {"^1Error", "Player not found or offline."} })
        return
    end
    
    if not IsPlayerRobber(targetId) then
        SafeTriggerClientEvent('chat:addMessage', src, { args = {"^1Error", "Target player is not a robber."} })
        return
    end
    
    if not Config.WantedSettings.crimes[crimeKey] then
        SafeTriggerClientEvent('chat:addMessage', src, { args = {"^1Error", "Invalid crime key. Available crimes: speeding, weapons_discharge, assault_civilian, etc."} })
        return
    end
    
    -- Report the crime
    UpdatePlayerWantedLevel(targetId, crimeKey)
    
    local copName = GetPlayerName(src) or "Unknown Officer"
    local targetName = GetPlayerName(targetId) or "Unknown"
    
    SafeTriggerClientEvent('chat:addMessage', src, { args = {"^2Crime Reported", string.format("You reported %s (ID: %d) for %s", targetName, targetId, crimeKey)} })
    SafeTriggerClientEvent('chat:addMessage', targetId, { args = {"^1Crime Reported", string.format("Officer %s reported you for %s", copName, crimeKey)} })
    
    Log(string.format("Officer %s (ID: %d) reported %s (ID: %d) for crime: %s", copName, src, targetName, targetId, crimeKey), "info", "CNR_SERVER")
end, false)

-- =================================================================================================
-- JAIL SYSTEM
-- =================================================================================================

-- Helper function to calculate jail term based on wanted stars
local function CalculateJailTermFromStars(stars)
    local minPunishment = 60 -- Default minimum
    local maxPunishment = 120 -- Default maximum

    if Config.WantedSettings and Config.WantedSettings.levels then
        for _, levelData in ipairs(Config.WantedSettings.levels) do
            if levelData.stars == stars then
                minPunishment = levelData.minPunishment or minPunishment
                maxPunishment = levelData.maxPunishment or maxPunishment
                break
            end
        end
    else
        Log("CalculateJailTermFromStars: Config.WantedSettings.levels not found. Using default punishments.", "warn", "CNR_SERVER")
    end

    if maxPunishment < minPunishment then -- Sanity check
        maxPunishment = minPunishment
        Log("CalculateJailTermFromStars: maxPunishment was less than minPunishment. Adjusted. Stars: " .. stars, "warn", "CNR_SERVER")
    end

    return math.random(minPunishment, maxPunishment)
end

SendToJail = function(playerId, durationSeconds, arrestingOfficerId, arrestOptions)
    local pIdNum = tonumber(playerId)
    if not pIdNum or pIdNum <= 0 then
        Log("SendToJail: Invalid player ID " .. tostring(playerId), "error", "CNR_SERVER")
        return
    end

    if GetPlayerName(pIdNum) == nil then return end -- Check player online
    local jailedPlayerName = GetPlayerName(pIdNum) or "Unknown Suspect"
    arrestOptions = arrestOptions or {} -- Ensure options table exists

    -- Store original wanted data before resetting (for accurate XP calculation)
    local originalWantedData = {}
    if wantedPlayers[pIdNum] then
        originalWantedData.stars = wantedPlayers[pIdNum].stars or 0
        -- Copy other fields if needed for complex XP rules later
    else
        originalWantedData.stars = 0
    end

    local finalDurationSeconds = durationSeconds
    if not finalDurationSeconds or finalDurationSeconds <= 0 then
        finalDurationSeconds = CalculateJailTermFromStars(originalWantedData.stars)
        Log(string.format("SendToJail: Calculated jail term for player %s (%d stars) as %d seconds.", pIdNum, originalWantedData.stars, finalDurationSeconds), "info", "CNR_SERVER")
    end

    jail[pIdNum] = { startTime = os.time(), duration = finalDurationSeconds, remainingTime = finalDurationSeconds, arrestingOfficer = arrestingOfficerId }
    wantedPlayers[pIdNum] = { wantedLevel = 0, stars = 0, lastCrimeTime = 0, crimesCommitted = {} } -- Reset wanted
    SafeTriggerClientEvent('cnr:wantedLevelSync', pIdNum, wantedPlayers[pIdNum])
    SafeTriggerClientEvent('cnr:sendToJail', pIdNum, finalDurationSeconds, Config.PrisonLocation)
    SafeTriggerClientEvent('chat:addMessage', pIdNum, { args = {"^1Jail", string.format("You have been jailed for %d seconds.", finalDurationSeconds)} })
    Log(string.format("Player %s jailed for %ds. Officer: %s. Options: %s", pIdNum, finalDurationSeconds, arrestingOfficerId or "N/A", json.encode(arrestOptions)), "info", "CNR_SERVER")

    -- Persist jail information in player data
    local pData = GetCnrPlayerData(pIdNum)
    if pData then
        pData.jailData = {
            remainingTime = finalDurationSeconds,
            originalDuration = finalDurationSeconds,
            jailedByOfficer = arrestingOfficerId,
            jailedTimestamp = os.time()
        }
        -- Mark for save, or SavePlayerDataImmediate if critical, though playerDropped will also save.
        -- For now, let standard save mechanisms handle it unless issues arise.
        MarkPlayerForInventorySave(pIdNum) -- This function name is a bit misleading but marks generic pData save
    end

    local arrestingOfficerName = (arrestingOfficerId and GetPlayerName(arrestingOfficerId)) or "System"
    for copId, _ in pairs(copsOnDuty) do
        if GetPlayerName(copId) ~= nil then -- Check cop is online
            SafeTriggerClientEvent('chat:addMessage', copId, { args = {"^5Police Info", string.format("Suspect %s jailed by %s.", jailedPlayerName, arrestingOfficerName)} })
            SafeTriggerClientEvent('cnr:updatePoliceBlip', copId, pIdNum, nil, 0, false)
        end
    end

    if arrestingOfficerId and IsPlayerCop(arrestingOfficerId) then
        local officerIdNum = tonumber(arrestingOfficerId)
        if not officerIdNum or officerIdNum <= 0 then
            Log("SendToJail: Invalid arresting officer ID " .. tostring(arrestingOfficerId), "warn", "CNR_SERVER")
            return
        end

        local arrestXP = 0

        -- Use originalWantedData.stars for XP calculation
        if originalWantedData.stars >= 4 then arrestXP = Config.XPActionsCop.successful_arrest_high_wanted or 40
        elseif originalWantedData.stars >= 2 then arrestXP = Config.XPActionsCop.successful_arrest_medium_wanted or 25
        else arrestXP = Config.XPActionsCop.successful_arrest_low_wanted or 15 end

        AddXP(officerIdNum, arrestXP, "cop")
        SafeTriggerClientEvent('chat:addMessage', officerIdNum, { args = {"^2XP", string.format("Gained %d XP for arrest.", arrestXP)} })

        -- K9 Assist Bonus (existing logic, now using arrestOptions)
        local engagement = k9Engagements[pIdNum] -- pIdNum is the robber
        -- arrestOptions.isK9Assist would be set by K9 logic if it calls SendToJail
        if (engagement and engagement.copId == officerIdNum and (os.time() - engagement.time < (Config.K9AssistWindowSeconds or 30))) or arrestOptions.isK9Assist then
            local k9BonusXP = Config.XPActionsCop.k9_assist_arrest or 10 -- Corrected XP value
            AddXP(officerIdNum, k9BonusXP, "cop")
            SafeTriggerClientEvent('chat:addMessage', officerIdNum, { args = {"^2XP", string.format("+%d XP K9 Assist!", k9BonusXP)} })
            Log(string.format("Cop %s K9 assist XP %d for robber %s.", officerIdNum, k9BonusXP, pIdNum), "info", "CNR_SERVER")
            k9Engagements[pIdNum] = nil -- Clear engagement after awarding
        end

        -- Subdue Arrest Bonus (New Logic)
        if arrestOptions.isSubdueArrest and not arrestOptions.isK9Assist then -- Avoid double bonus if K9 was also involved somehow in subdue
            local subdueBonusXP = Config.XPActionsCop.subdue_arrest_bonus or 10
            AddXP(officerIdNum, subdueBonusXP, "cop")
            SafeTriggerClientEvent('chat:addMessage', officerIdNum, { args = {"^2XP", string.format("+%d XP for Subdue Arrest!", subdueBonusXP)} })
            Log(string.format("Cop %s Subdue Arrest XP %d for robber %s.", officerIdNum, subdueBonusXP, pIdNum), "info", "CNR_SERVER")
        end
        if Config.BountySettings.enabled and Config.BountySettings.claimMethod == "arrest" and activeBounties[pIdNum] then
            local bountyInfo = activeBounties[pIdNum]
            local bountyAmt = bountyInfo.amount
            AddPlayerMoney(officerIdNum, bountyAmt)
            Log(string.format("Cop %s claimed $%d bounty on %s.", officerIdNum, bountyAmt, bountyInfo.name), "info", "CNR_SERVER")
            local officerNameForBounty = GetPlayerName(officerIdNum) or "An officer"
            TriggerClientEvent('chat:addMessage', -1, { args = {"^1[BOUNTY CLAIMED]", string.format("%s claimed $%d bounty on %s!", officerNameForBounty, bountyAmt, bountyInfo.name)} })
            activeBounties[pIdNum] = nil
            local robberPData = GetCnrPlayerData(pIdNum)
            if robberPData then
                robberPData.bountyCooldownUntil = os.time() + (Config.BountySettings.cooldownMinutes*60)
                if GetPlayerName(pIdNum) then
                    SavePlayerData(pIdNum)
                end
            end
            TriggerClientEvent('cops_and_robbers:bountyListUpdate', -1, activeBounties)
        end
    end
end

ForceReleasePlayerFromJail = function(playerId, reason)
    local pIdNum = tonumber(playerId)
    if not pIdNum or pIdNum <= 0 then
        Log(string.format("ForceReleasePlayerFromJail: Invalid player ID '%s'.", tostring(playerId)), "error", "CNR_SERVER")
        return false
    end

    reason = reason or "Released by server"
    local playerIsOnline = GetPlayerName(pIdNum) ~= nil

    -- Log the attempt
    Log(string.format("Attempting to release player %s from jail. Reason: %s. Online: %s", pIdNum, reason, tostring(playerIsOnline)), "info", "CNR_SERVER")

    -- Clear live jail data from the `jail` table
    if jail[pIdNum] then
        jail[pIdNum] = nil
        Log(string.format("Player %s removed from live jail tracking.", pIdNum), "info", "CNR_SERVER")
    else
        Log(string.format("Player %s was not in live jail tracking. Proceeding to check persisted data.", pIdNum), "info", "CNR_SERVER")
    end

    -- Clear persisted jail data from `playersData`
    local pData = GetCnrPlayerData(pIdNum)
    if pData and pData.jailData then
        pData.jailData = nil
        Log(string.format("Cleared persisted jail data for player %s.", pIdNum), "info", "CNR_SERVER")
        -- Mark for save. If player is online, normal save mechanisms will pick it up.
        -- If offline, this save might only happen if SavePlayerData can handle it or on next login.
        MarkPlayerForInventorySave(pIdNum) -- This marks pData for saving
    else
        Log(string.format("No persisted jail data found for player %s to clear.", pIdNum), "info", "CNR_SERVER")
    end

    if playerIsOnline then
        SafeTriggerClientEvent('cnr:releaseFromJail', pIdNum)
        SafeTriggerClientEvent('chat:addMessage', pIdNum, { args = {"^2Jail", "You have been released. (" .. reason .. ")"} })
        Log(string.format("Player %s (online) released. Client notified.", pIdNum), "info", "CNR_SERVER")
    else
        -- If player is offline, their data (now without jailData) will be saved by MarkPlayerForInventorySave
        -- if the periodic saver picks them up or if SavePlayerData is called by another process for offline players.
        -- Otherwise, it's saved on their next disconnect (if they were online briefly) or handled by LoadPlayerData on next join.
        Log(string.format("Player %s (offline) jail data cleared. They will be free on next login.", pIdNum), "info", "CNR_SERVER")
        -- Persist the updated data immediately so they won't be jailed again on reconnect
        local saveSuccess = SavePlayerDataImmediate(pIdNum, "unjail_offline")
        if not saveSuccess then
            Log(string.format("Failed to save data for player %s after unjailing. Retrying...", pIdNum), "error", "CNR_SERVER")
            saveSuccess = SavePlayerDataImmediate(pIdNum, "unjail_offline")
            if not saveSuccess then
                Log(string.format("Retry failed: Could not save data for player %s after unjailing. Manual intervention may be required.", pIdNum), "error", "CNR_SERVER")
            end
        end
    end
    return true
end

CreateThread(function() -- Jail time update loop
    while true do Wait(1000)
        -- Iterate over a copy of keys if modifying the table, though here we are just checking values.
        for playerIdKey, jailInstanceData in pairs(jail) do
            local pIdNum = tonumber(playerIdKey) -- Ensure we use the key from pairs()

            if pIdNum and pIdNum > 0 then
                if GetPlayerName(pIdNum) ~= nil then -- Check player online
                    jailInstanceData.remainingTime = jailInstanceData.remainingTime - 1
                    if jailInstanceData.remainingTime <= 0 then
                        ForceReleasePlayerFromJail(pIdNum, "Sentence served")
                    elseif jailInstanceData.remainingTime > 0 and jailInstanceData.remainingTime % 60 == 0 then
                        SafeTriggerClientEvent('chat:addMessage', pIdNum, { args = {"^3Jail Info", string.format("Jail time remaining: %d sec.", jailInstanceData.remainingTime)} })
                    end
                else
                    -- Player is in the 'jail' table but is offline.
                    -- This could happen if playerDropped didn't clean them up fully from 'jail' table,
                    -- or if they were added to 'jail' while offline (which shouldn't happen with current logic).
                    -- LoadPlayerData should handle their actual status on rejoin based on persisted pData.jailData.
                    -- So, we can remove them from the live 'jail' table here to keep it clean.
                    Log(string.format("Player %s found in 'jail' table but is offline. Removing from live tracking. Persisted data will determine status on rejoin.", pIdNum), "warn", "CNR_SERVER")
                    jail[pIdNum] = nil
                end
            else
                 Log(string.format("Invalid player ID key '%s' found in jail table.", tostring(playerIdKey)), "error", "CNR_SERVER")
                 jail[playerIdKey] = nil -- Remove invalid entry
            end
        end
    end
end)
-- (Removed duplicate cnr:playerSpawned handler. See consolidated handler below.)

RegisterNetEvent('cnr:selectRole')
AddEventHandler('cnr:selectRole', function(selectedRole)
    local src = source
    local pIdNum = tonumber(src)
    local pData = GetCnrPlayerData(pIdNum)

    -- Check if player data is loaded
    if not pData or not pData.isDataLoaded then
        Log(string.format("cnr:selectRole: Player data not ready for %s. pData exists: %s, isDataLoaded: %s", pIdNum, tostring(pData ~= nil), tostring(pData and pData.isDataLoaded or false)), "warn", "CNR_SERVER")
        TriggerClientEvent('cnr:roleSelected', src, false, "Player data is not ready. Please wait a moment and try again.")
        return
    end    -- No need for the old `if not pData then` check as the above condition covers it.

    if selectedRole ~= "cop" and selectedRole ~= "robber" and selectedRole ~= "civilian" then
        TriggerClientEvent('cnr:roleSelected', src, false, "Invalid role selected.")
        return
    end

    -- Handle civilian role (no special spawn handling needed)
    if selectedRole == "civilian" then
        SetPlayerRole(pIdNum, nil) -- Clear role
        TriggerClientEvent('cnr:roleSelected', src, true, "You are now a civilian.")
        return
    end

    -- Set role server-side
    SetPlayerRole(pIdNum, selectedRole)
    -- Teleport to spawn and set ped model (client will handle visuals, but send spawn info)
    local spawnLocation = nil
    local spawnHeading = 0.0

    if selectedRole == "cop" and Config.SpawnPoints and Config.SpawnPoints.cop then
        spawnLocation = Config.SpawnPoints.cop
        spawnHeading = 270.0 -- Facing west (common for Mission Row PD)
    elseif selectedRole == "robber" and Config.SpawnPoints and Config.SpawnPoints.robber then
        spawnLocation = Config.SpawnPoints.robber
        spawnHeading = 180.0 -- Facing south
    end

    if spawnLocation then
        TriggerClientEvent('cnr:spawnPlayerAt', src, spawnLocation, spawnHeading, selectedRole)
        Log(string.format("Player %s spawned as %s at %s", GetPlayerName(src), selectedRole, tostring(spawnLocation)), "info", "CNR_SERVER")
    else
        Log(string.format("No spawn point found for role %s for player %s", selectedRole, src), "warn", "CNR_SERVER")
        TriggerClientEvent('cnr:roleSelected', src, false, "No spawn point configured for this role.")
        return
    end
    -- Confirm to client
    TriggerClientEvent('cnr:roleSelected', src, true, "Role selected successfully.")
end)

-- Helper function to safely send NUI messages
function SafeSendNUIMessage(playerId, message)
    if not message or type(message) ~= 'table' then
        print('[CNR_SERVER_ERROR] Invalid NUI message format:', message)
        return false
    end
    
    if not message.action or type(message.action) ~= 'string' or message.action == '' then
        print('[CNR_SERVER_ERROR] NUI message missing or invalid action:', json.encode(message))
        return false
    end
    
    TriggerClientEvent('cnr:sendNUIMessage', playerId, message)
    return true
end

-- Helper function to get proper image path for items
function GetItemImagePath(configItem)
    -- If item has a specific image, use it
    if configItem.image and configItem.image ~= "" then
        return configItem.image
    end
    
    -- Generate image path based on category and itemId
    local category = configItem.category or "misc"
    local itemId = configItem.itemId or "default"
    
    -- Set default images based on category
    if category:lower() == "weapons" then
        return "img/items/" .. itemId .. ".png"
    elseif category:lower() == "ammo" then
        return "img/items/ammo.png"
    elseif category:lower() == "armor" then
        return "img/items/armor.png"
    elseif category:lower() == "tools" then
        return "img/items/tool.png"
    elseif category:lower() == "medical" then
        return "img/items/medical.png"
    else
        return "img/items/default.png"
    end
end

RegisterNetEvent('cops_and_robbers:getItemList')
AddEventHandler('cops_and_robbers:getItemList', function(storeType, vendorItemIds, storeName) -- Renamed itemList to vendorItemIds for clarity
    local src = source
    local pData = GetCnrPlayerData(src)

    if not storeName then
        print('[CNR_SERVER_ERROR] Store name missing in getItemList event from', src)
        return
    end

    -- Server-side role-based store access validation
    local playerRole = pData and pData.role or "citizen"
    local hasAccess = false
    
    if storeName == "Cop Store" then
        hasAccess = (playerRole == "cop")
    elseif storeName == "Gang Supplier" or storeName == "Black Market Dealer" then
        hasAccess = (playerRole == "robber")
    else
        -- General stores accessible to all roles
        hasAccess = true
    end
    
    if not hasAccess then
        print(string.format('[CNR_SERVER_SECURITY] Player %s (role: %s) attempted unauthorized access to %s', src, playerRole, storeName))
        TriggerClientEvent('cops_and_robbers:sendItemList', src, storeName, {}) -- Send empty list
        return
    end

    -- The vendorItemIds from client (originating from Config.NPCVendors[storeName].items) is a list of strings.
    -- We need to transform this into a list of full item objects using Config.Items.
    if not vendorItemIds or type(vendorItemIds) ~= 'table' then
        print('[CNR_SERVER_ERROR] Item ID list missing or not a table for store', storeName, 'from', src)
        TriggerClientEvent('cops_and_robbers:sendItemList', src, storeName, {}) -- Send empty list on error
        return
    end

    local fullItemDetailsList = {}
    if Config.Items and type(Config.Items) == 'table' then
        for _, itemIdFromVendor in ipairs(vendorItemIds) do
            local foundItem = nil
            for _, configItem in ipairs(Config.Items) do
                if configItem.itemId == itemIdFromVendor then
                    -- Create a new table for the item to send, ensuring all necessary fields are present
                    foundItem = {
                        itemId = configItem.itemId or itemIdFromVendor, -- Ensure itemId is always present
                        name = configItem.name or configItem.itemId or itemIdFromVendor,
                        basePrice = configItem.basePrice or 100, -- Default price if missing
                        price = configItem.basePrice or 100, -- Explicitly add 'price' for NUI if it uses that
                        category = configItem.category or "misc",
                        forCop = configItem.forCop,
                        minLevelCop = configItem.minLevelCop or 1,
                        minLevelRobber = configItem.minLevelRobber or 1,
                        icon = configItem.icon or "📦", -- Default icon
                        image = GetItemImagePath(configItem), -- Use helper function for proper image path
                        description = configItem.description or ""
                    }
                    -- Apply dynamic pricing if enabled
                    if Config.DynamicEconomy and Config.DynamicEconomy.enabled then
                        foundItem.price = CalculateDynamicPrice(foundItem.itemId, foundItem.basePrice)
                        -- If NUI also needs basePrice separately, keep it, otherwise price is now dynamic price
                    end
                    table.insert(fullItemDetailsList, foundItem)
                    break -- Found the item in Config.Items, move to next itemIdFromVendor
                end
            end
            if not foundItem then
                print(string.format("[CNR_SERVER_WARN] Item ID '%s' specified for vendor '%s' not found in Config.Items. Skipping.", itemIdFromVendor, storeName))
            end
        end
    else
        print("[CNR_SERVER_ERROR] Config.Items is not defined or not a table. Cannot populate item details.")
        TriggerClientEvent('cops_and_robbers:sendItemList', src, storeName, {}) -- Send empty list
        return
    end    -- Include player level, role, and cash information for UI to check restrictions and display
    local playerInfo = {
        level = 1, -- Will be calculated from XP below
        role = pData and pData.role or "citizen",
        cash = pData and (pData.cash or pData.money) or 0
    }
    
    -- Always calculate level from XP to ensure accuracy
    if pData and pData.xp then
        local calculatedLevel = CalculateLevel(pData.xp, pData.role)
        playerInfo.level = calculatedLevel
        
        -- Update stored level if different (with debug logging)
        if pData.level ~= calculatedLevel then
            print(string.format("[CNR_LEVEL_DEBUG] Level correction for player %s: stored=%d, calculated=%d from XP=%d", 
                src, pData.level or 1, calculatedLevel, pData.xp))
            pData.level = calculatedLevel
        end
    elseif pData and pData.level then
        -- If no XP data, use stored level
        playerInfo.level = pData.level
    end
    
    -- Debug log for level display issues
    print(string.format("[CNR_LEVEL_DEBUG] Sending level to store UI for player %s: level=%d, XP=%d", 
        src, playerInfo.level, pData and pData.xp or 0))
    
    -- Send the constructed list of full item details to the client
    TriggerClientEvent('cops_and_robbers:sendItemList', src, storeName, fullItemDetailsList, playerInfo)
end)

RegisterNetEvent('cops_and_robbers:getPlayerInventory')
AddEventHandler('cops_and_robbers:getPlayerInventory', function()
    local src = source
    local pData = GetCnrPlayerData(src)

    if not pData or not pData.inventory then
        print(string.format("[CNR_CRITICAL_LOG] [ERROR] Player data or inventory not found for src %s in getPlayerInventory.", src))
        TriggerClientEvent('cops_and_robbers:sendPlayerInventory', src, {}) -- Send empty table if no inventory
        return
    end

    local processedInventoryForNui = {}
    -- No need to check Config.Items here on server for this specific NUI message,
    -- as NUI will do the lookup. Server just provides IDs and counts from player's actual inventory.

    local inventoryCount = 0
    for itemId, invItemData in pairs(pData.inventory) do
        inventoryCount = inventoryCount + 1
        -- invItemData is now { count = X, name = "Item Name", category = "Category", itemId = "itemId" }
        if invItemData and invItemData.count and invItemData.count > 0 then
            table.insert(processedInventoryForNui, {
                itemId = itemId, -- Or invItemData.itemId, they should be the same
                count = invItemData.count
            })
        end
    end

    TriggerClientEvent('cops_and_robbers:sendPlayerInventory', src, processedInventoryForNui)
end)

-- =====================================
--           HEIST FUNCTIONALITY
-- =====================================

-- Handle heist initiation requests from clients
RegisterServerEvent('cnr:initiateHeist')
AddEventHandler('cnr:initiateHeist', function(heistType)
    local playerId = source
    local playerData = GetCnrPlayerData(playerId)
    
    if not playerData then
        TriggerClientEvent('cnr:notifyPlayer', playerId, "~r~Error: Cannot start heist - player data not found.")
        return
    end
    
    if playerData.role ~= 'robber' then
        TriggerClientEvent('cnr:notifyPlayer', playerId, "~r~Only robbers can initiate heists.")
        return
    end
    
    -- Check for cooldown
    local currentTime = os.time()
    if playerData.lastHeistTime and (currentTime - playerData.lastHeistTime) < Config.HeistCooldown then
        local remainingTime = math.ceil((playerData.lastHeistTime + Config.HeistCooldown - currentTime) / 60)
        TriggerClientEvent('cnr:notifyPlayer', playerId, "~r~Heist cooldown active. Try again in " .. remainingTime .. " minutes.")
        return
    end
    
    -- Check if heist type is valid
    if not heistType or (heistType ~= "bank" and heistType ~= "jewelry" and heistType ~= "store") then
        TriggerClientEvent('cnr:notifyPlayer', playerId, "~r~Invalid heist type.")
        return
    end
    
    -- Set cooldown for player
    playerData.lastHeistTime = currentTime
    
    -- Determine heist details based on type
    local heistDuration = 0
    local rewardBase = 0
    local heistName = ""
    
    if heistType == "bank" then
        heistDuration = 180  -- 3 minutes
        rewardBase = 15000   -- Base reward $15,000
        heistName = "Bank Heist"
    elseif heistType == "jewelry" then
        heistDuration = 120  -- 2 minutes
        rewardBase = 10000   -- Base reward $10,000
        heistName = "Jewelry Store Robbery"
    elseif heistType == "store" then
        heistDuration = 60   -- 1 minute
        rewardBase = 5000    -- Base reward $5,000
        heistName = "Store Robbery"    end
      -- Alert all cops about the heist
    for _, targetPlayerId in ipairs(GetPlayers()) do
        local targetId = tonumber(targetPlayerId)
        
        -- Check if targetId is valid before proceeding
        if targetId and targetId > 0 then
            local targetData = GetCnrPlayerData(targetId)
            
            if targetData and targetData.role == 'cop' then
                local playerPed = GetPlayerPed(playerId)
                if playerPed and playerPed > 0 then
                    local playerCoords = GetEntityCoords(playerPed)
                    if playerCoords then
                        local coordsTable = {
                            x = playerCoords.x,
                            y = playerCoords.y,
                            z = playerCoords.z
                        }
                        TriggerClientEvent('cnr:heistAlert', targetId, heistType, coordsTable)
                    else
                        local defaultCoords = {x = 0, y = 0, z = 0}
                        TriggerClientEvent('cnr:heistAlert', targetId, heistType, defaultCoords)
                    end
                else
                    local defaultCoords = {x = 0, y = 0, z = 0}
                    TriggerClientEvent('cnr:heistAlert', targetId, heistType, defaultCoords)
                end
            end
        end
    end
    
    -- Start the heist for the player
    TriggerClientEvent('cnr:startHeistTimer', playerId, heistDuration, heistName)
    
    -- Set a timer to complete the heist
    SetTimeout(heistDuration * 1000, function()
        local playerStillConnected = GetPlayerPing(playerId) > 0
        
        if playerStillConnected then
            -- Calculate final reward based on player level and add randomness
            local levelMultiplier = 1.0 + (playerData.level * 0.05)  -- 5% more per level
            local randomVariation = math.random(80, 120) / 100  -- 0.8 to 1.2 multiplier
            local finalReward = math.floor(rewardBase * levelMultiplier * randomVariation)
            
            -- Award the player
            if AddPlayerMoney(playerId, finalReward) then
                -- Update heist statistics
                if not playerData.stats then playerData.stats = {} end
                if not playerData.stats.heists then playerData.stats.heists = 0 end
                playerData.stats.heists = playerData.stats.heists + 1
                      -- Award XP for the heist
                local xpReward = 0
                if heistType == "bank" then xpReward = 500
                elseif heistType == "jewelry" then xpReward = 300
                elseif heistType == "store" then xpReward = 150
                end
                
                -- Add XP if the function exists
                if _G.AddPlayerXP then
                    _G.AddPlayerXP(playerId, xpReward)
                else
                    -- Fallback if global function doesn't exist
                    if playerData.xp then
                        playerData.xp = playerData.xp + xpReward
                    end
                end
                
                -- Notify the player
                TriggerClientEvent('cnr:notifyPlayer', playerId, "~g~Heist completed! Earned $" .. finalReward)
                TriggerClientEvent('cnr:heistCompleted', playerId, finalReward, xpReward)
            else
                TriggerClientEvent('cnr:notifyPlayer', playerId, "~r~Error processing heist reward. Contact an admin.")
            end
        end
    end)
end)

-- OLD HANDLERS REMOVED - Using enhanced versions below with inventory saving

-- =================================================================================================
-- ROBUST INVENTORY SAVING SYSTEM
-- =================================================================================================

-- Table to track players who need inventory save
local playersSavePending = {}

-- Function to mark player for inventory save
local function MarkPlayerForInventorySave(playerId)
    local pIdNum = tonumber(playerId)
    if pIdNum and pIdNum > 0 then
        playersSavePending[pIdNum] = true
    end
end

-- Function to save player data immediately (used for critical saves)
local function SavePlayerDataImmediate(playerId, reason)
    reason = reason or "manual"
    local pIdNum = tonumber(playerId)
    if not pIdNum or pIdNum <= 0 then return false end

    local pData = GetCnrPlayerData(pIdNum)
    if not pData then return false end

    local success = SavePlayerData(pIdNum)
    if success then
        playersSavePending[pIdNum] = nil -- Clear pending save flag
        Log(string.format("Immediate save completed for player %s (reason: %s)", pIdNum, reason), "info", "CNR_SERVER")
        return true
    else
        Log(string.format("Failed immediate save for player %s (reason: %s)", pIdNum, reason), "error", "CNR_SERVER")
        return false
    end
end

-- Periodic save system - saves all pending players every 30 seconds
CreateThread(function()
    while true do
        Wait(30000) -- 30 seconds

        -- Save all players who have pending saves
        for playerId, needsSave in pairs(playersSavePending) do
            if needsSave and GetPlayerName(playerId) then
                SavePlayerDataImmediate(playerId, "periodic")
            end
        end

        -- Clean up offline players from pending saves
        for playerId, _ in pairs(playersSavePending) do
            if not GetPlayerName(playerId) then
                playersSavePending[playerId] = nil
            end
        end
    end
end)

-- REFACTORED: Player connection handler using new PlayerManager system
AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
    local src = source
    Log(string.format("Player connecting: %s (ID: %s)", name, src), "info", "CNR_SERVER")

    -- Check for bans using improved validation
    local identifiers = GetPlayerIdentifiers(src)
    if identifiers then
        for _, identifier in ipairs(identifiers) do
            if bannedPlayers[identifier] then
                local banInfo = bannedPlayers[identifier]
                local banMessage = string.format("You are banned from this server. Reason: %s", 
                    banInfo.reason or "No reason provided")
                setKickReason(banMessage)
                Log(string.format("Blocked banned player %s (%s) - Reason: %s", 
                    name, identifier, banInfo.reason or "No reason"), "warn", "CNR_SERVER")
                return
            end
        end
    end

    -- Send Config.Items to player after connection is established
    Citizen.CreateThread(function()
        Citizen.Wait(Constants.TIME_MS.SECOND * 2) -- Wait for player to fully connect
        if Config and Config.Items then
            TriggerClientEvent(Constants.EVENTS.SERVER_TO_CLIENT.RECEIVE_CONFIG_ITEMS, src, Config.Items)
            Log(string.format("Sent Config.Items to connecting player %s", src), "info", "CNR_SERVER")
        end
    end)
end)

-- REFACTORED: Player disconnection handler using new PlayerManager system
AddEventHandler('playerDropped', function(reason)
    local src = source
    local playerName = GetPlayerName(src) or "Unknown"

    Log(string.format("Player %s (ID: %s) disconnected. Reason: %s", playerName, src, reason), "info", "CNR_SERVER")

    -- Use PlayerManager for proper cleanup and saving
    PlayerManager.OnPlayerDisconnected(src, reason)

    -- Clean up legacy global tracking tables (for compatibility)
    if playersSavePending then playersSavePending[src] = nil end
    if playersData then playersData[src] = nil end
    if copsOnDuty then copsOnDuty[src] = nil end
    if robbersActive then robbersActive[src] = nil end
    if wantedPlayers then wantedPlayers[src] = nil end
    if jail then jail[src] = nil end
    if activeBounties then activeBounties[src] = nil end
    if playerSpeedingData then playerSpeedingData[src] = nil end
    if playerVehicleData then playerVehicleData[src] = nil end
    if playerRestrictedAreaData then playerRestrictedAreaData[src] = nil end
    if k9Engagements then k9Engagements[src] = nil end
    if playerDeployedSpikeStripsCount then playerDeployedSpikeStripsCount[src] = nil end
    
    -- Clean up any active spike strips deployed by this player
    if activeSpikeStrips then
        for stripId, stripData in pairs(activeSpikeStrips) do
            if stripData.copId == src then
                activeSpikeStrips[stripId] = nil
            end
        end
    end
end)

-- Enhanced buy/sell operations with immediate inventory saves
-- REFACTORED: Secure buy item handler using new validation and transaction systems
RegisterNetEvent('cops_and_robbers:buyItem')
AddEventHandler('cops_and_robbers:buyItem', function(itemId, quantity)
    local src = source
    
    -- Validate network event with rate limiting and input validation
    local validEvent, eventError = Validation.ValidateNetworkEvent(src, "buyItem", {itemId = itemId, quantity = quantity})
    if not validEvent then
        TriggerClientEvent('cnr:sendNUIMessage', src, {
            action = 'buyResult',
            success = false,
            message = Constants.ERROR_MESSAGES.VALIDATION_FAILED
        })
        return
    end
    
    -- Process purchase using secure transaction system with comprehensive validation
    local success, message, transactionResult = SecureTransactions.ProcessPurchase(src, itemId, quantity)
    
    -- Send standardized response to NUI
    TriggerClientEvent('cnr:sendNUIMessage', src, {
        action = 'buyResult',
        success = success,
        message = message
    })
    
    if success and transactionResult then
        -- Update player cash in NUI with validated balance
        TriggerClientEvent('cnr:sendNUIMessage', src, {
            action = 'updateMoney',
            cash = transactionResult.newBalance
        })
        
        -- Refresh sell list for updated inventory
        TriggerClientEvent('cops_and_robbers:refreshSellListIfNeeded', src)
        
        -- Note: Inventory updates and saves are handled automatically by SecureInventory and DataManager
        -- No need for immediate saves as the new system uses batched, efficient saving
    end
end)

-- REFACTORED: Secure sell item handler using new validation and transaction systems
RegisterNetEvent('cops_and_robbers:sellItem')
AddEventHandler('cops_and_robbers:sellItem', function(itemId, quantity)
    local src = source
    
    -- Validate network event with rate limiting and input validation
    local validEvent, eventError = Validation.ValidateNetworkEvent(src, "sellItem", {itemId = itemId, quantity = quantity})
    if not validEvent then
        TriggerClientEvent('cnr:sendNUIMessage', src, {
            action = 'sellResult',
            success = false,
            message = Constants.ERROR_MESSAGES.VALIDATION_FAILED
        })
        return
    end
    
    -- Process sale using secure transaction system with comprehensive validation
    local success, message, transactionResult = SecureTransactions.ProcessSale(src, itemId, quantity)
    
    -- Send standardized response to NUI
    TriggerClientEvent('cnr:sendNUIMessage', src, {
        action = 'sellResult',
        success = success,
        message = message
    })
    
    if success and transactionResult then
        -- Update player cash in NUI with validated balance
        TriggerClientEvent('cnr:sendNUIMessage', src, {
            action = 'updateMoney',
            cash = transactionResult.newBalance
        })
        
        -- Refresh sell list for updated inventory
        TriggerClientEvent('cops_and_robbers:refreshSellListIfNeeded', src)
        
        -- Note: Inventory updates and saves are handled automatically by SecureInventory and DataManager
        -- No need for immediate saves as the new system uses batched, efficient saving
    end
end)

-- Enhanced respawn system with inventory restoration
RegisterNetEvent('cnr:playerRespawned')
AddEventHandler('cnr:playerRespawned', function()
    local src = source
    Log(string.format("Player %s respawned, restoring inventory", src), "info", "CNR_SERVER")

    -- Reload and sync player inventory
    local pData = GetCnrPlayerData(src)
    if pData and pData.inventory then
        -- Send config items first so client can properly reconstruct inventory
        if Config and Config.Items and type(Config.Items) == "table" then
            SafeTriggerClientEvent('cnr:receiveConfigItems', src, Config.Items)
        end
        
        -- Send fresh inventory sync
        SafeTriggerClientEvent('cnr:syncInventory', src, MinimizeInventoryForSync(pData.inventory))
        Log(string.format("Restored inventory for respawned player %s with %d items", src, tablelength(pData.inventory or {})), "info", "CNR_SERVER")
    else
        Log(string.format("No inventory to restore for player %s", src), "warn", "CNR_SERVER")
    end
end)

-- REFACTORED: Player spawn handler using new PlayerManager system
RegisterNetEvent('cnr:playerSpawned')
AddEventHandler('cnr:playerSpawned', function()
    local src = source
    Log(string.format("Player %s spawned, initializing with PlayerManager", src), "info", "CNR_SERVER")

    -- Use PlayerManager for proper initialization
    PlayerManager.OnPlayerConnected(src)

    -- Ensure data sync after a brief delay for client readiness
    Citizen.SetTimeout(Constants.TIME_MS.SECOND * 2, function()
        -- Validate player is still online
        if not GetPlayerName(src) then return end
        
        -- Sync player data to client using PlayerManager
        PlayerManager.SyncPlayerDataToClient(src)
        
        Log(string.format("Player %s initialization and sync completed", src), "info", "CNR_SERVER")
    end)
end)

-- Enhanced AddItemToPlayerInventory with save marking
function AddItemToPlayerInventory(playerId, itemId, quantity, itemDetails)
    local pData = GetCnrPlayerData(playerId)
    if not pData then return false, "Player data not found" end

    pData.inventory = pData.inventory or {}

    if not itemDetails or not itemDetails.name or not itemDetails.category then
        local foundConfigItem = nil
        for _, cfgItem in ipairs(Config.Items) do
            if cfgItem.itemId == itemId then
                foundConfigItem = cfgItem
                break
            end
        end
        if not foundConfigItem then
            Log(string.format("AddItemToPlayerInventory: CRITICAL - Item details not found in Config.Items for itemId '%s' and not passed correctly. Cannot add to inventory for player %s.", itemId, playerId), "error", "CNR_SERVER")
            return false, "Item configuration not found"
        end
        itemDetails = foundConfigItem
    end

    local currentCount = 0
    if pData.inventory[itemId] and pData.inventory[itemId].count then
        currentCount = pData.inventory[itemId].count
    end

    local newCount = currentCount + quantity

    pData.inventory[itemId] = {
        count = newCount,
        name = itemDetails.name,
        category = itemDetails.category,
        itemId = itemId
    }

    -- Mark for save
    MarkPlayerForInventorySave(playerId)

    local pDataForBasicInfo = shallowcopy(pData)
    pDataForBasicInfo.inventory = nil
    TriggerClientEvent('cnr:updatePlayerData', playerId, pDataForBasicInfo)
    TriggerClientEvent('cnr:syncInventory', playerId, MinimizeInventoryForSync(pData.inventory)) -- Send MINIMAL inventory separately
    Log(string.format("Added/updated %d of %s to player %s inventory. New count: %d. Name: %s, Category: %s", quantity, itemId, playerId, newCount, itemDetails.name, itemDetails.category), "info", "CNR_SERVER")
    return true, "Item added/updated"
end

-- ==========================================================================
-- ENHANCED PROGRESSION SYSTEM INTEGRATION
-- ==========================================================================

-- Event handler for progression system requests
RegisterNetEvent('cnr:requestProgressionData')
AddEventHandler('cnr:requestProgressionData', function()
    local playerId = source
    local pData = GetCnrPlayerData(playerId)
    if not pData then return end
    
    -- Send current progression data to client
    local progressionData = {
        currentXP = pData.xp or 0,
        currentLevel = pData.level or 1,
        xpForNextLevel = CalculateXpForNextLevel(pData.level or 1, pData.role),
        prestigeInfo = pData.prestige or { level = 0, title = "Rookie" },
        role = pData.role
    }
    
    SafeTriggerClientEvent('cnr:progressionDataResponse', playerId, progressionData)
end)

-- Event handler for ability usage
RegisterNetEvent('cnr:useAbility')
AddEventHandler('cnr:useAbility', function(abilityId)
    local playerId = source
    local pData = GetCnrPlayerData(playerId)
    if not pData then return end
    
    -- Check if progression system export is available
    if exports['cops-and-robbers'] and exports['cops-and-robbers'].HasPlayerAbility then
        if exports['cops-and-robbers'].HasPlayerAbility(playerId, abilityId) then
            -- Trigger ability effect based on ability type
            TriggerAbilityEffect(playerId, abilityId)
        else
            SafeTriggerClientEvent('chat:addMessage', playerId, { 
                args = {"^1Error", "You don't have this ability unlocked!"} 
            })
        end
    end
end)

-- Event handler for prestige requests
RegisterNetEvent('cnr:requestPrestige')
AddEventHandler('cnr:requestPrestige', function()
    local playerId = source
    
    -- Check if progression system export is available
    if exports['cops-and-robbers'] and exports['cops-and-robbers'].HandlePrestige then
        local success, message = exports['cops-and-robbers'].HandlePrestige(playerId)
        if not success then
            SafeTriggerClientEvent('chat:addMessage', playerId, { 
                args = {"^1Prestige Error", message} 
            })
        end
    else
        SafeTriggerClientEvent('chat:addMessage', playerId, { 
            args = {"^1Error", "Prestige system is not available"} 
        })
    end
end)

-- Function to trigger ability effects
function TriggerAbilityEffect(playerId, abilityId)
    local pData = GetCnrPlayerData(playerId)
    if not pData then return end
    
    if abilityId == "smoke_bomb" then
        -- Create smoke effect around player
        SafeTriggerClientEvent('cnr:createSmokeEffect', playerId)
        SafeTriggerClientEvent('chat:addMessage', playerId, { 
            args = {"^3Ability", "Smoke bomb deployed!"} 
        })
        
    elseif abilityId == "adrenaline_rush" then
        -- Give temporary speed boost
        SafeTriggerClientEvent('cnr:applyAdrenalineRush', playerId)
        SafeTriggerClientEvent('chat:addMessage', playerId, { 
            args = {"^3Ability", "Adrenaline rush activated!"} 
        })
        
    elseif abilityId == "ghost_mode" then
        -- Temporary invisibility to security systems
        SafeTriggerClientEvent('cnr:activateGhostMode', playerId)
        SafeTriggerClientEvent('chat:addMessage', playerId, { 
            args = {"^3Ability", "Ghost mode activated!"} 
        })
        
    elseif abilityId == "master_escape" then
        -- Instantly reduce wanted level
        if pData.wantedLevel and pData.wantedLevel > 2 then
            pData.wantedLevel = math.max(0, pData.wantedLevel - 2)
            SafeTriggerClientEvent('cnr:updateWantedLevel', playerId, pData.wantedLevel)
            SafeTriggerClientEvent('chat:addMessage', playerId, { 
                args = {"^3Ability", "Master escape used! Wanted level reduced!"} 
            })
        end
        
    elseif abilityId == "backup_call" then
        -- Call for police backup
        SafeTriggerClientEvent('cnr:callBackup', playerId)
        SafeTriggerClientEvent('chat:addMessage', playerId, { 
            args = {"^3Ability", "Backup called!"} 
        })
        
    elseif abilityId == "tactical_scan" then
        -- Scan area for criminals
        SafeTriggerClientEvent('cnr:performTacticalScan', playerId)
        SafeTriggerClientEvent('chat:addMessage', playerId, { 
            args = {"^3Ability", "Tactical scan activated!"} 
        })
        
    elseif abilityId == "crowd_control" then
        -- Advanced crowd control
        SafeTriggerClientEvent('cnr:activateCrowdControl', playerId)
        SafeTriggerClientEvent('chat:addMessage', playerId, { 
            args = {"^3Ability", "Crowd control measures deployed!"} 
        })
        
    elseif abilityId == "detective_mode" then
        -- Enhanced investigation
        SafeTriggerClientEvent('cnr:activateDetectiveMode', playerId)
        SafeTriggerClientEvent('chat:addMessage', playerId, { 
            args = {"^3Ability", "Detective mode activated!"} 
        })
    end
end

-- Enhanced XP reward functions with progression system integration
function RewardArrestXP(playerId, suspectWantedLevel)
    local xpAmount = 0
    local reason = ""
    
    if suspectWantedLevel >= 4 then
        xpAmount = Config.XPActionsCop.successful_arrest_high_wanted or 50
        reason = "high_wanted_arrest"
    elseif suspectWantedLevel >= 2 then
        xpAmount = Config.XPActionsCop.successful_arrest_medium_wanted or 35
        reason = "medium_wanted_arrest"
    else
        xpAmount = Config.XPActionsCop.successful_arrest_low_wanted or 20
        reason = "low_wanted_arrest"
    end
    
    AddXP(playerId, xpAmount, "cop", reason)
    
    -- Update challenge progress
    if exports['cops-and-robbers'] and exports['cops-and-robbers'].UpdateChallengeProgress then
        exports['cops-and-robbers'].UpdateChallengeProgress(playerId, "arrest", 1)
    end
end

function RewardHeistXP(playerId, heistType, success)
    if not success then return end
    
    local xpAmount = 0
    local reason = ""
    
    if heistType == "bank_major" then
        xpAmount = Config.XPActionsRobber.successful_bank_heist_major or 100
        reason = "major_bank_heist"
    elseif heistType == "bank_minor" then
        xpAmount = Config.XPActionsRobber.successful_bank_heist_minor or 50
        reason = "minor_bank_heist"
    elseif heistType == "store_large" then
        xpAmount = Config.XPActionsRobber.successful_store_robbery_large or 35
        reason = "large_store_robbery"
    elseif heistType == "store_medium" then
        xpAmount = Config.XPActionsRobber.successful_store_robbery_medium or 25
        reason = "medium_store_robbery"
    else
        xpAmount = Config.XPActionsRobber.successful_store_robbery_small or 15
        reason = "small_store_robbery"
    end
    
    AddXP(playerId, xpAmount, "robber", reason)
    
    -- Update challenge progress
    if exports['cops-and-robbers'] and exports['cops-and-robbers'].UpdateChallengeProgress then
        exports['cops-and-robbers'].UpdateChallengeProgress(playerId, "heist", 1)
    end
end

function RewardEscapeXP(playerId, wantedLevel)
    local xpAmount = 0
    local reason = ""
    
    if wantedLevel >= 4 then
        xpAmount = Config.XPActionsRobber.escape_from_cops_high_wanted or 30
        reason = "high_wanted_escape"
    elseif wantedLevel >= 2 then
        xpAmount = Config.XPActionsRobber.escape_from_cops_medium_wanted or 20
        reason = "medium_wanted_escape"
    else
        xpAmount = 10
        reason = "low_wanted_escape"
    end
    
    AddXP(playerId, xpAmount, "robber", reason)
    
    -- Update challenge progress
    if exports['cops-and-robbers'] and exports['cops-and-robbers'].UpdateChallengeProgress then
        exports['cops-and-robbers'].UpdateChallengeProgress(playerId, "escape", 1)
    end
end

-- Admin command to start seasonal events
RegisterCommand('start_event', function(source, args, rawCommand)
    -- Debug check
    if not IsPlayerAdmin then
        print("[CNR_ERROR] IsPlayerAdmin function is not defined!")
        return
    end
    if source == 0 or IsPlayerAdmin(source) then
        local eventName = args[1]
        if eventName then
            if exports['cops-and-robbers'] and exports['cops-and-robbers'].StartSeasonalEvent then
                local success = exports['cops-and-robbers'].StartSeasonalEvent(eventName)
                if success then
                    print(string.format("[CNR_ADMIN] Started seasonal event: %s", eventName))
                else
                    print(string.format("[CNR_ADMIN] Failed to start seasonal event: %s", eventName))
                end
            end
        else
            print("[CNR_ADMIN] Usage: /start_event <event_name>")
        end
    end
end, false)

-- Admin command to give XP
RegisterCommand('give_xp', function(source, args, rawCommand)
    -- Debug check
    if not IsPlayerAdmin then
        print("[CNR_ERROR] IsPlayerAdmin function is not defined!")
        return
    end
    if source == 0 or IsPlayerAdmin(source) then
        local targetId = tonumber(args[1])
        local amount = tonumber(args[2])
        local reason = args[3] or "admin_grant"
        
        if targetId and amount then
            AddXP(targetId, amount, "general", reason)
            print(string.format("[CNR_ADMIN] Gave %d XP to player %d (Reason: %s)", amount, targetId, reason))
            
            if source ~= 0 then
                SafeTriggerClientEvent('chat:addMessage', source, { 
                    args = {"^2Admin", string.format("Gave %d XP to player %d", amount, targetId)} 
                })
            end
        else
            print("[CNR_ADMIN] Usage: /give_xp <player_id> <amount> [reason]")
        end
    end
end, false)

-- Admin command to set player level
RegisterCommand('set_level', function(source, args, rawCommand)
    -- Debug check
    if not IsPlayerAdmin then
        print("[CNR_ERROR] IsPlayerAdmin function is not defined!")
        return
    end
    if source == 0 or IsPlayerAdmin(source) then
        local targetId = tonumber(args[1])
        local level = tonumber(args[2])
        
        if targetId and level then
            local pData = GetCnrPlayerData(targetId)
            if pData then
                local totalXPNeeded = 0
                for i = 1, level - 1 do
                    totalXPNeeded = totalXPNeeded + (Config.XPTable[i] or 1000)
                end
                
                pData.xp = totalXPNeeded
                pData.level = level
                
                -- Apply perks for new level
                ApplyPerks(targetId, level, pData.role)
                
                -- Update client
                local pDataForBasicInfo = shallowcopy(pData)
                pDataForBasicInfo.inventory = nil
                SafeTriggerClientEvent('cnr:updatePlayerData', targetId, pDataForBasicInfo)
                
                print(string.format("[CNR_ADMIN] Set player %d to level %d", targetId, level))
                
                if source ~= 0 then
                    SafeTriggerClientEvent('chat:addMessage', source, { 
                        args = {"^2Admin", string.format("Set player %d to level %d", targetId, level)} 
                    })
                end
            end
        else
            print("[CNR_ADMIN] Usage: /set_level <player_id> <level>")
        end
    end
end, false)

Log("Enhanced Progression System integration loaded", "info", "CNR_SERVER")

function RemoveItemFromPlayerInventory(playerId, itemId, quantity)
    local pData = GetCnrPlayerData(playerId)
    if not pData or not pData.inventory or not pData.inventory[itemId] or pData.inventory[itemId].count < quantity then
        return false, "Item not found or insufficient quantity"
    end

    pData.inventory[itemId].count = pData.inventory[itemId].count - quantity

    if pData.inventory[itemId].count <= 0 then
        pData.inventory[itemId] = nil
    end

    -- Mark for save
    MarkPlayerForInventorySave(playerId)

    local pDataForBasicInfo = shallowcopy(pData)
    pDataForBasicInfo.inventory = nil
    TriggerClientEvent('cnr:updatePlayerData', playerId, pDataForBasicInfo)
    TriggerClientEvent('cnr:syncInventory', playerId, MinimizeInventoryForSync(pData.inventory)) -- Send MINIMAL inventory separately
    Log(string.format("Removed %d of %s from player %s inventory.", quantity, itemId, playerId), "info", "CNR_SERVER")
    return true, "Item removed"
end

-- Handle client request for Config.Items
RegisterServerEvent('cnr:requestConfigItems')
AddEventHandler('cnr:requestConfigItems', function()
    local source = source
    Log(string.format("Received Config.Items request from player %s", source), "info", "CNR_SERVER")

    -- Give some time for Config to be fully loaded if this is early in startup
    Citizen.Wait(100)

    if Config and Config.Items and type(Config.Items) == "table" then
        local itemCount = 0
        for _ in pairs(Config.Items) do itemCount = itemCount + 1 end
        TriggerClientEvent('cnr:receiveConfigItems', source, Config.Items)
        Log(string.format("Sent Config.Items to player %s (%d items)", source, itemCount), "info", "CNR_SERVER")
    else
        Log(string.format("Failed to send Config.Items to player %s - Config.Items not found or invalid. Config exists: %s, Config.Items type: %s", source, tostring(Config ~= nil), type(Config and Config.Items)), "error", "CNR_SERVER")
        -- Send empty table as fallback
        TriggerClientEvent('cnr:receiveConfigItems', source, {})
    end
end)

-- Handle speeding fine issuance
RegisterServerEvent('cnr:issueSpeedingFine')
RegisterNetEvent('cnr:issueSpeedingFine')
AddEventHandler('cnr:issueSpeedingFine', function(targetPlayerId, speed)
    local source = source
    local pData = GetCnrPlayerData(source)
    local targetData = GetCnrPlayerData(targetPlayerId)
    
    -- Validate cop issuing the fine
    if not pData or pData.role ~= "cop" then
        SafeTriggerClientEvent('cnr:showNotification', source, "~r~You must be a cop to issue fines!")
        return
    end
    
    -- Validate target player
    if not targetData then
        SafeTriggerClientEvent('cnr:showNotification', source, "~r~Target player not found!")
        return
    end
    
    -- Validate speed parameter
    if not speed or type(speed) ~= "number" or speed <= Config.SpeedLimitMph then
        SafeTriggerClientEvent('cnr:showNotification', source, "~r~Invalid speed data!")
        return
    end
    
    -- Calculate fine amount
    local fineAmount = Config.SpeedingFine or 250
    local excessSpeed = speed - Config.SpeedLimitMph
    
    -- Add bonus fine for excessive speeding (optional enhancement)
    if excessSpeed > 20 then
        fineAmount = fineAmount + math.floor(excessSpeed * 5) -- $5 per mph over 20mph excess
    end
    
    -- Deduct money from target player
    if targetData.money >= fineAmount then
        targetData.money = targetData.money - fineAmount
        pData.money = pData.money + math.floor(fineAmount * 0.5) -- Cop gets 50% commission
          -- Award XP to the cop
        local xpAmount = (Config.XPActionsCop and Config.XPActionsCop.speeding_fine_issued) or 8 -- Standardized to XPActionsCop
        AddXP(source, xpAmount, "cop") -- XP type should be "cop"
        
        -- Save both players' data
        SavePlayerData(source)
        SavePlayerData(targetPlayerId)
        
        -- Update both players' data
        local copDataForSync = shallowcopy(pData)
        copDataForSync.inventory = nil
        SafeTriggerClientEvent('cnr:updatePlayerData', source, copDataForSync)
        
        local targetDataForSync = shallowcopy(targetData)
        targetDataForSync.inventory = nil
        SafeTriggerClientEvent('cnr:updatePlayerData', targetPlayerId, targetDataForSync)
        
        -- Send notifications
        SafeTriggerClientEvent('cnr:showNotification', source, 
            string.format("~g~Speeding fine issued! $%d collected (~b~%d mph in %d mph zone~g~). You earned $%d commission.", 
                fineAmount, speed, Config.SpeedLimitMph, math.floor(fineAmount * 0.5)))
        
        SafeTriggerClientEvent('cnr:showNotification', targetPlayerId, 
            string.format("~r~You were fined $%d for speeding! (~o~%d mph in %d mph zone~r~)", 
                fineAmount, speed, Config.SpeedLimitMph))
        
        -- Log the fine for admin purposes
        Log(string.format("Speeding fine issued: Cop %s fined Player %s $%d for %d mph in %d mph zone", 
            source, targetPlayerId, fineAmount, speed, Config.SpeedLimitMph), "info", "CNR_SERVER")
    else
        SafeTriggerClientEvent('cnr:showNotification', source, 
            string.format("~o~Target player doesn't have enough money for the fine ($%d required, has $%d)", 
                fineAmount, targetData.money))
    end
end)

-- Handle admin status check for F2 keybind
RegisterServerEvent('cnr:checkAdminStatus')
RegisterNetEvent('cnr:checkAdminStatus')
AddEventHandler('cnr:checkAdminStatus', function()
    local source = source
    local pData = GetCnrPlayerData(source)
    
    if not pData then
        Log(string.format("Admin status check failed - no player data for %s", source), "warn", "CNR_SERVER")
        return
    end
    
    -- Check if player is admin (you can customize this check based on your admin system)
    local isAdmin = false
    
    -- Method 1: Check ace permissions
    if IsPlayerAceAllowed(source, "cnr.admin") then
        isAdmin = true
    end
    
    -- Method 2: Check if they have admin role in player data (if you store it there)
    if pData.isAdmin or pData.role == "admin" then
        isAdmin = true
    end
    
    -- Method 3: Check against admin list in config (if you have one)
    if Config.AdminPlayers then
        local identifier = GetPlayerIdentifier(source, 0) -- Steam ID
        for _, adminId in ipairs(Config.AdminPlayers) do
            if identifier == adminId then
                isAdmin = true
                break
            end
        end
    end
    
    if isAdmin then
        TriggerClientEvent('cnr:showAdminPanel', source)
        Log(string.format("Admin panel opened for player %s", source), "info", "CNR_SERVER")
    else
        -- Show robber menu if they're a robber, otherwise generic message
        if pData.role == "robber" then
            TriggerClientEvent('cnr:showRobberMenu', source)
        else
            SafeTriggerClientEvent('cnr:showNotification', source, "~r~No special menu available for your role.")
        end
    end
end)

-- Handle role selection request
RegisterServerEvent('cnr:requestRoleSelection')
RegisterNetEvent('cnr:requestRoleSelection')
AddEventHandler('cnr:requestRoleSelection', function()
    local source = source
    Log(string.format("Role selection requested by player %s", source), "info", "CNR_SERVER")
    
    -- Send role selection UI to client
    TriggerClientEvent('cnr:showRoleSelection', source)
end)

-- OLD CLIENT-SIDE CRIME REPORTING EVENT REMOVED
-- This has been replaced by server-side crime detection systems:
-- - cnr:weaponFired for weapon discharge detection
-- - cnr:playerDamaged for assault/murder detection
-- - Server-side threads for speeding, hit-and-run, and restricted area detection
-- - /reportcrime command for manual cop reporting

--[[
-- OLD: Register the crime reporting event (DISABLED)
RegisterNetEvent('cops_and_robbers:reportCrime')
AddEventHandler('cops_and_robbers:reportCrime', function(crimeType)
    local src = source
    if not src or src <= 0 then return end
    
    -- Verify the crime type is valid
    local crimeConfig = Config.WantedSettings.crimes[crimeType]
    if not crimeConfig then
        print("[CNR_SERVER_ERROR] Invalid crime type reported: " .. tostring(crimeType))
        return
    end
    
    -- Check if player is a robber
    if not IsPlayerRobber(src) then
        return
    end
    
    -- Check for spam (cooldown per crime type)
    local now = os.time()
    if not clientReportCooldowns[src] then clientReportCooldowns[src] = {} end
    
    local lastReportTime = clientReportCooldowns[src][crimeType] or 0
    local cooldownTime = 5 -- 5 seconds cooldown between same crime reports
    
    if now - lastReportTime < cooldownTime then
        -- Still on cooldown, ignore this report
        return
    end
    
    -- Update cooldown timestamp
    clientReportCooldowns[src][crimeType] = now
    
    -- Update wanted level for this crime
    UpdatePlayerWantedLevel(src, crimeType)
end)
--]]

-- =========================
--      Banking System
-- =========================

-- Banking data storage
local bankAccounts = {}
local playerLoans = {}
local playerInvestments = {}
local atmHackCooldowns = {}
local dailyWithdrawals = {}

-- Initialize player bank account
function InitializeBankAccount(playerLicense)
    if not bankAccounts[playerLicense] then
        bankAccounts[playerLicense] = {
            balance = Config.Banking.startingBalance,
            accountNumber = math.random(100000000, 999999999),
            openDate = os.time(),
            transactionHistory = {},
            dailyWithdrawal = 0,
            lastWithdrawalReset = os.date("%Y-%m-%d")
        }
        SaveBankingData()
    end
end

-- Get player bank account
function GetBankAccount(playerLicense)
    InitializeBankAccount(playerLicense)
    return bankAccounts[playerLicense]
end

-- Add transaction to history
function AddTransactionHistory(playerLicense, transaction)
    local account = GetBankAccount(playerLicense)
    table.insert(account.transactionHistory, {
        type = transaction.type,
        amount = transaction.amount,
        description = transaction.description,
        timestamp = os.time(),
        balance = account.balance
    })
    
    -- Keep only last 50 transactions
    if #account.transactionHistory > 50 then
        table.remove(account.transactionHistory, 1)
    end
end

-- Reset daily withdrawal limits
function ResetDailyWithdrawals()
    local today = os.date("%Y-%m-%d")
    for license, account in pairs(bankAccounts) do
        if account.lastWithdrawalReset ~= today then
            account.dailyWithdrawal = 0
            account.lastWithdrawalReset = today
        end
    end
end

-- Bank deposit
RegisterNetEvent('cnr:bankDeposit')
AddEventHandler('cnr:bankDeposit', function(amount)
    local src = source
    local playerLicense = GetPlayerLicense(src)
    if not playerLicense then return end
    
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        TriggerClientEvent('cnr:showNotification', src, 'Invalid amount', 'error')
        return
    end
    
    local playerMoney = GetPlayerMoney(src)
    if playerMoney < amount then
        TriggerClientEvent('cnr:showNotification', src, 'Insufficient cash', 'error')
        return
    end
    
    local account = GetBankAccount(playerLicense)
    
    -- Remove cash and add to bank
    RemovePlayerMoney(src, amount)
    account.balance = account.balance + amount
    
    AddTransactionHistory(playerLicense, {
        type = "deposit",
        amount = amount,
        description = "Cash deposit"
    })
    
    TriggerClientEvent('cnr:showNotification', src, 'Deposited $' .. amount, 'success')
    TriggerClientEvent('cnr:updateBankBalance', src, account.balance)
    SaveBankingData()
end)

-- Bank withdrawal
RegisterNetEvent('cnr:bankWithdraw')
AddEventHandler('cnr:bankWithdraw', function(amount)
    local src = source
    local playerLicense = GetPlayerLicense(src)
    if not playerLicense then return end
    
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        TriggerClientEvent('cnr:showNotification', src, 'Invalid amount', 'error')
        return
    end
    
    local account = GetBankAccount(playerLicense)
    ResetDailyWithdrawals()
    
    -- Check daily limit
    if account.dailyWithdrawal + amount > Config.Banking.dailyWithdrawalLimit then
        TriggerClientEvent('cnr:showNotification', src, 'Daily withdrawal limit exceeded', 'error')
        return
    end
    
    -- Check balance
    if account.balance < amount then
        TriggerClientEvent('cnr:showNotification', src, 'Insufficient bank balance', 'error')
        return
    end
    
    -- Process withdrawal
    account.balance = account.balance - amount
    account.dailyWithdrawal = account.dailyWithdrawal + amount
    AddPlayerMoney(src, amount)
    
    AddTransactionHistory(playerLicense, {
        type = "withdrawal",
        amount = amount,
        description = "ATM withdrawal"
    })
    
    TriggerClientEvent('cnr:showNotification', src, 'Withdrew $' .. amount, 'success')
    TriggerClientEvent('cnr:updateBankBalance', src, account.balance)
    SaveBankingData()
end)

-- Bank transfer
RegisterNetEvent('cnr:bankTransfer')
AddEventHandler('cnr:bankTransfer', function(targetId, amount)
    local src = source
    local playerLicense = GetPlayerLicense(src)
    local targetLicense = GetPlayerLicense(targetId)
    
    if not playerLicense or not targetLicense then
        TriggerClientEvent('cnr:showNotification', src, 'Invalid player', 'error')
        return
    end
    
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        TriggerClientEvent('cnr:showNotification', src, 'Invalid amount', 'error')
        return
    end
    
    local senderAccount = GetBankAccount(playerLicense)
    local receiverAccount = GetBankAccount(targetLicense)
    
    local totalCost = amount + Config.Banking.transferFee
    
    if senderAccount.balance < totalCost then
        TriggerClientEvent('cnr:showNotification', src, 'Insufficient funds (includes $' .. Config.Banking.transferFee .. ' fee)', 'error')
        return
    end
    
    -- Process transfer
    senderAccount.balance = senderAccount.balance - totalCost
    receiverAccount.balance = receiverAccount.balance + amount
    
    -- Add transaction history
    AddTransactionHistory(playerLicense, {
        type = "transfer_out",
        amount = totalCost,
        description = "Transfer to " .. GetPlayerName(targetId) .. " (+$" .. Config.Banking.transferFee .. " fee)"
    })
    
    AddTransactionHistory(targetLicense, {
        type = "transfer_in",
        amount = amount,
        description = "Transfer from " .. GetPlayerName(src)
    })
    
    TriggerClientEvent('cnr:showNotification', src, 'Transferred $' .. amount .. ' (Fee: $' .. Config.Banking.transferFee .. ')', 'success')
    TriggerClientEvent('cnr:showNotification', targetId, 'Received $' .. amount .. ' from ' .. GetPlayerName(src), 'success')
    
    TriggerClientEvent('cnr:updateBankBalance', src, senderAccount.balance)
    TriggerClientEvent('cnr:updateBankBalance', targetId, receiverAccount.balance)
    SaveBankingData()
end)

-- Loan system
RegisterNetEvent('cnr:requestLoan')
AddEventHandler('cnr:requestLoan', function(amount, duration)
    local src = source
    local playerLicense = GetPlayerLicense(src)
    if not playerLicense then return end
    
    local playerLevel = GetPlayerLevel(src)
    if playerLevel < Config.Banking.loanRequiredLevel then
        TriggerClientEvent('cnr:showNotification', src, 'Level ' .. Config.Banking.loanRequiredLevel .. ' required for loans', 'error')
        return
    end
    
    amount = tonumber(amount)
    duration = tonumber(duration) or 7 -- Default 7 days
    
    if not amount or amount <= 0 or amount > Config.Banking.maxLoanAmount then
        TriggerClientEvent('cnr:showNotification', src, 'Invalid loan amount', 'error')
        return
    end
    
    -- Check if player already has a loan
    if playerLoans[playerLicense] then
        TriggerClientEvent('cnr:showNotification', src, 'You already have an active loan', 'error')
        return
    end
    
    local account = GetBankAccount(playerLicense)
    local collateralRequired = math.floor(amount * Config.Banking.loanCollateralRate)
    
    if account.balance < collateralRequired then
        TriggerClientEvent('cnr:showNotification', src, 'Insufficient collateral ($' .. collateralRequired .. ' required)', 'error')
        return
    end
    
    -- Process loan
    account.balance = account.balance - collateralRequired + amount
    
    playerLoans[playerLicense] = {
        principal = amount,
        collateral = collateralRequired,
        dailyInterest = Config.Banking.loanInterestRate,
        startDate = os.time(),
        duration = duration * 24 * 3600, -- Convert days to seconds
        totalOwed = amount
    }
    
    AddTransactionHistory(playerLicense, {
        type = "loan",
        amount = amount,
        description = "Loan approved (Collateral: $" .. collateralRequired .. ")"
    })
    
    TriggerClientEvent('cnr:showNotification', src, 'Loan approved: $' .. amount, 'success')
    TriggerClientEvent('cnr:updateBankBalance', src, account.balance)
    SaveBankingData()
end)

-- Loan repayment
RegisterNetEvent('cnr:repayLoan')
AddEventHandler('cnr:repayLoan', function(amount)
    local src = source
    local playerLicense = GetPlayerLicense(src)
    if not playerLicense then return end
    
    local loan = playerLoans[playerLicense]
    if not loan then
        TriggerClientEvent('cnr:showNotification', src, 'No active loan', 'error')
        return
    end
    
    amount = tonumber(amount)
    if not amount or amount <= 0 then
        TriggerClientEvent('cnr:showNotification', src, 'Invalid amount', 'error')
        return
    end
    
    local account = GetBankAccount(playerLicense)
    if account.balance < amount then
        TriggerClientEvent('cnr:showNotification', src, 'Insufficient bank balance', 'error')
        return
    end
    
    -- Process repayment
    account.balance = account.balance - amount
    loan.totalOwed = loan.totalOwed - amount
    
    if loan.totalOwed <= 0 then
        -- Loan fully repaid, return collateral
        account.balance = account.balance + loan.collateral
        playerLoans[playerLicense] = nil
        
        TriggerClientEvent('cnr:showNotification', src, 'Loan fully repaid! Collateral returned.', 'success')
    else
        TriggerClientEvent('cnr:showNotification', src, 'Payment processed. Remaining: $' .. math.floor(loan.totalOwed), 'success')
    end
    
    AddTransactionHistory(playerLicense, {
        type = "loan_payment",
        amount = amount,
        description = "Loan repayment"
    })
    
    TriggerClientEvent('cnr:updateBankBalance', src, account.balance)
    SaveBankingData()
end)

-- Investment system
RegisterNetEvent('cnr:makeInvestment')
AddEventHandler('cnr:makeInvestment', function(investmentId, amount)
    local src = source
    local playerLicense = GetPlayerLicense(src)
    if not playerLicense then return end
    
    local investment = nil
    for _, inv in pairs(Config.Investments) do
        if inv.id == investmentId then
            investment = inv
            break
        end
    end
    
    if not investment then
        TriggerClientEvent('cnr:showNotification', src, 'Invalid investment', 'error')
        return
    end
    
    local playerLevel = GetPlayerLevel(src)
    if playerLevel < investment.requiredLevel then
        TriggerClientEvent('cnr:showNotification', src, 'Level ' .. investment.requiredLevel .. ' required', 'error')
        return
    end
    
    amount = tonumber(amount)
    if not amount or amount < investment.minInvestment then
        TriggerClientEvent('cnr:showNotification', src, 'Minimum investment: $' .. investment.minInvestment, 'error')
        return
    end
    
    local account = GetBankAccount(playerLicense)
    if account.balance < amount then
        TriggerClientEvent('cnr:showNotification', src, 'Insufficient bank balance', 'error')
        return
    end
    
    -- Process investment
    account.balance = account.balance - amount
    
    if not playerInvestments[playerLicense] then
        playerInvestments[playerLicense] = {}
    end
    
    table.insert(playerInvestments[playerLicense], {
        type = investmentId,
        amount = amount,
        startTime = os.time(),
        duration = investment.duration * 3600, -- Convert hours to seconds
        expectedReturn = investment.expectedReturn,
        riskLevel = investment.riskLevel
    })
    
    AddTransactionHistory(playerLicense, {
        type = "investment",
        amount = amount,
        description = "Investment: " .. investment.name
    })
    
    TriggerClientEvent('cnr:showNotification', src, 'Investment made: $' .. amount, 'success')
    TriggerClientEvent('cnr:updateBankBalance', src, account.balance)
    SaveBankingData()
end)

-- ATM Hacking (for robbers)
RegisterNetEvent('cnr:hackATM')
AddEventHandler('cnr:hackATM', function(atmId)
    local src = source
    local playerData = playerDataCache[src]
    
    if not playerData or playerData.role ~= "robber" then
        TriggerClientEvent('cnr:showNotification', src, 'Access denied', 'error')
        return
    end
    
    local playerLicense = GetPlayerLicense(src)
    local now = GetGameTimer()
    
    -- Check cooldown
    if atmHackCooldowns[atmId] and now - atmHackCooldowns[atmId] < Config.Banking.atmHackCooldown then
        TriggerClientEvent('cnr:showNotification', src, 'ATM recently compromised', 'error')
        return
    end
    
    -- Start hacking process
    TriggerClientEvent('cnr:startATMHack', src, atmId, Config.Banking.atmHackTime)
    
    -- Set cooldown
    atmHackCooldowns[atmId] = now
    
    -- Award money after hack time
    SetTimeout(Config.Banking.atmHackTime, function()
        local reward = math.random(Config.Banking.atmHackReward[1], Config.Banking.atmHackReward[2])
        AddPlayerMoney(src, reward)
        
        -- Add wanted level
        UpdatePlayerWantedLevel(src, "atm_hack")
        
        TriggerClientEvent('cnr:showNotification', src, 'ATM hacked! Gained $' .. reward, 'success')
        
        -- Alert nearby cops
        local playerCoords = GetEntityCoords(GetPlayerPed(src))
        for _, playerId in pairs(GetPlayers()) do
            local targetData = playerDataCache[tonumber(playerId)]
            if targetData and targetData.role == "cop" then
                TriggerClientEvent('cnr:policeAlert', playerId, {
                    type = "ATM Hack",
                    location = playerCoords,
                    suspect = GetPlayerName(src)
                })
            end
        end
    end)
end)

-- Get bank balance
RegisterNetEvent('cnr:getBankBalance')
AddEventHandler('cnr:getBankBalance', function()
    local src = source
    local playerLicense = GetPlayerLicense(src)
    if not playerLicense then return end
    
    local account = GetBankAccount(playerLicense)
    TriggerClientEvent('cnr:updateBankBalance', src, account.balance)
end)

-- Get transaction history
RegisterNetEvent('cnr:getTransactionHistory')
AddEventHandler('cnr:getTransactionHistory', function()
    local src = source
    local playerLicense = GetPlayerLicense(src)
    if not playerLicense then return end
    
    local account = GetBankAccount(playerLicense)
    TriggerClientEvent('cnr:updateTransactionHistory', src, account.transactionHistory)
end)

-- Banking interest and loan processing (runs every hour)
function ProcessBankingInterest()
    local now = os.time()
    
    for license, account in pairs(bankAccounts) do
        -- Process savings interest
        if account.balance >= Config.Banking.interestMinBalance then
            local interest = math.floor(account.balance * Config.Banking.interestRate)
            account.balance = account.balance + interest
            
            if interest > 0 then
                AddTransactionHistory(license, {
                    type = "interest",
                    amount = interest,
                    description = "Daily interest earned"
                })
            end
        end
    end
    
    -- Process loan interest
    for license, loan in pairs(playerLoans) do
        local interest = math.floor(loan.totalOwed * loan.dailyInterest)
        loan.totalOwed = loan.totalOwed + interest
        
        -- Check if loan is overdue
        if now - loan.startDate > loan.duration then
            -- Loan overdue, additional penalty
            local penalty = math.floor(loan.totalOwed * 0.1) -- 10% penalty
            loan.totalOwed = loan.totalOwed + penalty
        end
    end
    
    -- Process investments
    for license, investments in pairs(playerInvestments) do
        for i = #investments, 1, -1 do
            local investment = investments[i]
            if now - investment.startTime >= investment.duration then
                -- Investment matured
                local account = GetBankAccount(license)
                
                -- Calculate return based on risk
                local returnMultiplier = investment.expectedReturn
                if investment.riskLevel == "high" then
                    -- High risk: 70% chance of expected return, 30% chance of loss
                    if math.random() < 0.7 then
                        returnMultiplier = returnMultiplier * (0.8 + math.random() * 0.4) -- 80-120% of expected
                    else
                        returnMultiplier = -0.2 - math.random() * 0.3 -- 20-50% loss
                    end
                elseif investment.riskLevel == "medium" then
                    -- Medium risk: 85% chance of expected return
                    if math.random() < 0.85 then
                        returnMultiplier = returnMultiplier * (0.9 + math.random() * 0.2) -- 90-110% of expected
                    else
                        returnMultiplier = -0.1 - math.random() * 0.1 -- 10-20% loss
                    end
                else
                    -- Low risk: guaranteed return with small variance
                    returnMultiplier = returnMultiplier * (0.95 + math.random() * 0.1) -- 95-105% of expected
                end
                
                local returnAmount = math.floor(investment.amount * (1 + returnMultiplier))
                account.balance = account.balance + returnAmount
                
                local profit = returnAmount - investment.amount
                AddTransactionHistory(license, {
                    type = "investment_return",
                    amount = returnAmount,
                    description = "Investment return (" .. (profit >= 0 and "+" or "") .. "$" .. profit .. ")"
                })
                
                -- Remove completed investment
                table.remove(investments, i)
            end
        end
    end
    
    SaveBankingData()
end

-- Banking data persistence
function SaveBankingData()
    local data = {
        accounts = bankAccounts,
        loans = playerLoans,
        investments = playerInvestments
    }
    SaveResourceFile(GetCurrentResourceName(), "banking_data.json", json.encode(data, {indent = true}), -1)
end

function LoadBankingData()
    local file = LoadResourceFile(GetCurrentResourceName(), "banking_data.json")
    if file then
        local data = json.decode(file)
        if data then
            bankAccounts = data.accounts or {}
            playerLoans = data.loans or {}
            playerInvestments = data.investments or {}
        end
    end
end

-- Initialize banking system on resource start
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        LoadBankingData()
        
        -- Start banking interest processing timer (every hour)
        SetTimeout(3600000, function()
            ProcessBankingInterest()
        end)
    end
end)

-- Initialize bank account when player joins
AddEventHandler('playerJoining', function()
    local src = source
    local playerLicense = GetPlayerLicense(src)
    if playerLicense then
        InitializeBankAccount(playerLicense)
    end
end)

-- =========================
--    Enhanced Heist System
-- =========================

-- Enhanced heist data storage
local activeHeists = {}
local heistCooldowns = {}
local heistCrews = {}
local playerCrewRoles = {}
local heistPlanningRooms = {}

-- Initialize heist crew
function CreateHeistCrew(leaderId, heistId)
    local crewId = "crew_" .. leaderId .. "_" .. os.time()
    
    heistCrews[crewId] = {
        id = crewId,
        leader = leaderId,
        heistId = heistId,
        members = {leaderId},
        roles = {[leaderId] = "mastermind"},
        status = "recruiting",
        equipment = {},
        planningComplete = false,
        startTime = nil
    }
    
    playerCrewRoles[leaderId] = crewId
    return crewId
end

-- Join heist crew
RegisterNetEvent('cnr:joinHeistCrew')
AddEventHandler('cnr:joinHeistCrew', function(crewId, role)
    local src = source
    local playerData = playerDataCache[src]
    
    if not playerData or playerData.role ~= "robber" then
        TriggerClientEvent('cnr:showNotification', src, 'Only robbers can join heist crews', 'error')
        return
    end
    
    local crew = heistCrews[crewId]
    if not crew then
        TriggerClientEvent('cnr:showNotification', src, 'Crew not found', 'error')
        return
    end
    
    -- Check if player already in a crew
    if playerCrewRoles[src] then
        TriggerClientEvent('cnr:showNotification', src, 'You are already in a crew', 'error')
        return
    end
    
    -- Check role requirements
    local roleConfig = nil
    for _, r in pairs(Config.CrewRoles) do
        if r.id == role then
            roleConfig = r
            break
        end
    end
    
    if not roleConfig then
        TriggerClientEvent('cnr:showNotification', src, 'Invalid role', 'error')
        return
    end
    
    local playerLevel = GetPlayerLevel(src)
    if playerLevel < roleConfig.requiredLevel then
        TriggerClientEvent('cnr:showNotification', src, 'Level ' .. roleConfig.requiredLevel .. ' required for ' .. roleConfig.name, 'error')
        return
    end
    
    -- Add to crew
    table.insert(crew.members, src)
    crew.roles[src] = role
    playerCrewRoles[src] = crewId
    
    -- Notify crew members
    for _, memberId in pairs(crew.members) do
        TriggerClientEvent('cnr:showNotification', memberId, GetPlayerName(src) .. ' joined as ' .. roleConfig.name, 'success')
        TriggerClientEvent('cnr:updateCrewInfo', memberId, crew)
    end
end)

-- Leave heist crew
RegisterNetEvent('cnr:leaveHeistCrew')
AddEventHandler('cnr:leaveHeistCrew', function()
    local src = source
    local crewId = playerCrewRoles[src]
    
    if not crewId then
        TriggerClientEvent('cnr:showNotification', src, 'You are not in a crew', 'error')
        return
    end
    
    local crew = heistCrews[crewId]
    if not crew then return end
    
    -- Remove from crew
    for i, memberId in pairs(crew.members) do
        if memberId == src then
            table.remove(crew.members, i)
            break
        end
    end
    
    crew.roles[src] = nil
    playerCrewRoles[src] = nil
    
    -- If leader left, disband crew
    if crew.leader == src then
        for _, memberId in pairs(crew.members) do
            playerCrewRoles[memberId] = nil
            TriggerClientEvent('cnr:showNotification', memberId, 'Crew disbanded - leader left', 'error')
        end
        heistCrews[crewId] = nil
    else
        -- Notify remaining members
        for _, memberId in pairs(crew.members) do
            TriggerClientEvent('cnr:showNotification', memberId, GetPlayerName(src) .. ' left the crew', 'info')
            TriggerClientEvent('cnr:updateCrewInfo', memberId, crew)
        end
    end
end)

-- Start heist planning
RegisterNetEvent('cnr:startHeistPlanning')
AddEventHandler('cnr:startHeistPlanning', function(heistId)
    local src = source
    local playerData = playerDataCache[src]
    
    if not playerData or playerData.role ~= "robber" then
        TriggerClientEvent('cnr:showNotification', src, 'Access denied', 'error')
        return
    end
    
    -- Find heist config
    local heistConfig = nil
    for _, heist in pairs(Config.EnhancedHeists) do
        if heist.id == heistId then
            heistConfig = heist
            break
        end
    end
    
    if not heistConfig then
        TriggerClientEvent('cnr:showNotification', src, 'Invalid heist', 'error')
        return
    end
    
    -- Check level requirement
    local playerLevel = GetPlayerLevel(src)
    if playerLevel < heistConfig.requiredLevel then
        TriggerClientEvent('cnr:showNotification', src, 'Level ' .. heistConfig.requiredLevel .. ' required', 'error')
        return
    end
    
    -- Check cooldown
    local now = os.time()
    if heistCooldowns[heistId] and now - heistCooldowns[heistId] < heistConfig.cooldown then
        local remaining = math.ceil((heistConfig.cooldown - (now - heistCooldowns[heistId])) / 60)
        TriggerClientEvent('cnr:showNotification', src, 'Heist on cooldown (' .. remaining .. ' minutes)', 'error')
        return
    end
    
    -- Create crew
    local crewId = CreateHeistCrew(src, heistId)
    
    TriggerClientEvent('cnr:showNotification', src, 'Heist planning started. Recruit your crew!', 'success')
    TriggerClientEvent('cnr:openHeistPlanning', src, heistConfig, crewId)
end)

-- Purchase heist equipment
RegisterNetEvent('cnr:purchaseHeistEquipment')
AddEventHandler('cnr:purchaseHeistEquipment', function(itemId, quantity)
    local src = source
    local crewId = playerCrewRoles[src]
    
    if not crewId then
        TriggerClientEvent('cnr:showNotification', src, 'You must be in a crew', 'error')
        return
    end
    
    local crew = heistCrews[crewId]
    if not crew or crew.leader ~= src then
        TriggerClientEvent('cnr:showNotification', src, 'Only crew leader can purchase equipment', 'error')
        return
    end
    
    -- Find equipment in heist equipment shop
    local equipment = nil
    for _, item in pairs(Config.HeistEquipment.items) do
        if item.id == itemId then
            equipment = item
            break
        end
    end
    
    if not equipment then
        TriggerClientEvent('cnr:showNotification', src, 'Invalid equipment', 'error')
        return
    end
    
    local playerLevel = GetPlayerLevel(src)
    if equipment.requiredLevel and playerLevel < equipment.requiredLevel then
        TriggerClientEvent('cnr:showNotification', src, 'Level ' .. equipment.requiredLevel .. ' required', 'error')
        return
    end
    
    quantity = quantity or 1
    local totalCost = equipment.price * quantity
    local playerMoney = GetPlayerMoney(src)
    
    if playerMoney < totalCost then
        TriggerClientEvent('cnr:showNotification', src, 'Insufficient funds', 'error')
        return
    end
    
    -- Purchase equipment
    RemovePlayerMoney(src, totalCost)
    
    if not crew.equipment[itemId] then
        crew.equipment[itemId] = 0
    end
    crew.equipment[itemId] = crew.equipment[itemId] + quantity
    
    TriggerClientEvent('cnr:showNotification', src, 'Purchased ' .. quantity .. 'x ' .. equipment.name, 'success')
    
    -- Update crew info for all members
    for _, memberId in pairs(crew.members) do
        TriggerClientEvent('cnr:updateCrewInfo', memberId, crew)
    end
end)

-- Start enhanced heist
RegisterNetEvent('cnr:startEnhancedHeist')
AddEventHandler('cnr:startEnhancedHeist', function()
    local src = source
    local crewId = playerCrewRoles[src]
    
    if not crewId then
        TriggerClientEvent('cnr:showNotification', src, 'You must be in a crew', 'error')
        return
    end
    
    local crew = heistCrews[crewId]
    if not crew or crew.leader ~= src then
        TriggerClientEvent('cnr:showNotification', src, 'Only crew leader can start heist', 'error')
        return
    end
    
    -- Find heist config
    local heistConfig = nil
    for _, heist in pairs(Config.EnhancedHeists) do
        if heist.id == crew.heistId then
            heistConfig = heist
            break
        end
    end
    
    if not heistConfig then
        TriggerClientEvent('cnr:showNotification', src, 'Heist configuration error', 'error')
        return
    end
    
    -- Check crew size
    if #crew.members < heistConfig.requiredCrew then
        TriggerClientEvent('cnr:showNotification', src, 'Need ' .. heistConfig.requiredCrew .. ' crew members', 'error')
        return
    end
    
    -- Check required equipment
    for _, requiredItem in pairs(heistConfig.equipment) do
        if not crew.equipment[requiredItem] or crew.equipment[requiredItem] < 1 then
            TriggerClientEvent('cnr:showNotification', src, 'Missing required equipment: ' .. requiredItem, 'error')
            return
        end
    end
    
    -- Check if enough cops online
    local copCount = 0
    for _, playerId in pairs(GetPlayers()) do
        local playerData = playerDataCache[tonumber(playerId)]
        if playerData and playerData.role == "cop" then
            copCount = copCount + 1
        end
    end
    
    local minCopsRequired = math.max(2, math.floor(heistConfig.requiredCrew / 2))
    if copCount < minCopsRequired then
        TriggerClientEvent('cnr:showNotification', src, 'Not enough police online (' .. minCopsRequired .. ' required)', 'error')
        return
    end
    
    -- Start heist
    crew.status = "active"
    crew.startTime = os.time()
    crew.currentStage = 1
    crew.stageStartTime = os.time()
    
    activeHeists[crewId] = {
        crew = crew,
        heistConfig = heistConfig,
        startTime = os.time(),
        currentStage = 1,
        completed = false,
        failed = false
    }
    
    -- Set cooldown
    heistCooldowns[crew.heistId] = os.time()
    
    -- Notify crew members
    for _, memberId in pairs(crew.members) do
        TriggerClientEvent('cnr:startHeistExecution', memberId, heistConfig, crew)
        TriggerClientEvent('cnr:showNotification', memberId, 'Heist started: ' .. heistConfig.name, 'success')
        
        -- Add wanted level
        UpdatePlayerWantedLevel(memberId, "heist_participation")
    end
    
    -- Alert police
    local heistLocation = heistConfig.location
    for _, playerId in pairs(GetPlayers()) do
        local playerData = playerDataCache[tonumber(playerId)]
        if playerData and playerData.role == "cop" then
            TriggerClientEvent('cnr:policeAlert', playerId, {
                type = "Major Heist",
                location = heistLocation,
                heistName = heistConfig.name,
                crewSize = #crew.members
            })
        end
    end
    
    -- Start heist stage timer
    ProcessHeistStages(crewId)
end)

-- Process heist stages
function ProcessHeistStages(crewId)
    local heist = activeHeists[crewId]
    if not heist or heist.completed or heist.failed then return end
    
    local crew = heist.crew
    local heistConfig = heist.heistConfig
    local currentStage = heistConfig.stages[heist.currentStage]
    
    if not currentStage then
        -- Heist completed
        CompleteHeist(crewId)
        return
    end
    
    -- Notify crew of current stage
    for _, memberId in pairs(crew.members) do
        TriggerClientEvent('cnr:updateHeistStage', memberId, {
            stage = heist.currentStage,
            description = currentStage.description,
            duration = currentStage.duration,
            timeRemaining = currentStage.duration
        })
    end
    
    -- Set timer for stage completion
    SetTimeout(currentStage.duration * 1000, function()
        if activeHeists[crewId] and not activeHeists[crewId].completed and not activeHeists[crewId].failed then
            -- Move to next stage
            activeHeists[crewId].currentStage = activeHeists[crewId].currentStage + 1
            ProcessHeistStages(crewId)
        end
    end)
end

-- Complete heist
function CompleteHeist(crewId)
    local heist = activeHeists[crewId]
    if not heist then return end
    
    local crew = heist.crew
    local heistConfig = heist.heistConfig
    
    heist.completed = true
    
    -- Calculate rewards
    local baseReward = math.random(heistConfig.minReward, heistConfig.maxReward)
    local crewBonus = 1.0
    
    -- Apply crew role bonuses
    for memberId, role in pairs(crew.roles) do
        for _, roleConfig in pairs(Config.CrewRoles) do
            if roleConfig.id == role and roleConfig.bonuses then
                if roleConfig.bonuses.crew_coordination then
                    crewBonus = crewBonus * roleConfig.bonuses.crew_coordination
                end
                break
            end
        end
    end
    
    local totalReward = math.floor(baseReward * crewBonus)
    local rewardPerMember = math.floor(totalReward / #crew.members)
    
    -- Distribute rewards
    for _, memberId in pairs(crew.members) do
        AddPlayerMoney(memberId, rewardPerMember)
        
        -- Award XP based on heist type
        local xpReward = 0
        if heistConfig.type == "major_bank" then
            xpReward = Config.XPActionsRobber.successful_bank_heist_major or 100
        elseif heistConfig.type == "small_bank" then
            xpReward = Config.XPActionsRobber.successful_bank_heist_minor or 50
        elseif heistConfig.type == "jewelry" then
            xpReward = Config.XPActionsRobber.successful_store_robbery_large or 35
        else
            xpReward = 75 -- Default for other heist types
        end
        
        AddXP(memberId, xpReward, "Enhanced heist completion")
        
        TriggerClientEvent('cnr:heistCompleted', memberId, {
            success = true,
            reward = rewardPerMember,
            xp = xpReward,
            heistName = heistConfig.name
        })
        
        TriggerClientEvent('cnr:showNotification', memberId, 'Heist completed! Reward: $' .. rewardPerMember, 'success')
    end
    
    -- Clean up
    CleanupHeist(crewId)
end

-- Fail heist
function FailHeist(crewId, reason)
    local heist = activeHeists[crewId]
    if not heist then return end
    
    local crew = heist.crew
    heist.failed = true
    
    -- Notify crew members
    for _, memberId in pairs(crew.members) do
        TriggerClientEvent('cnr:heistCompleted', memberId, {
            success = false,
            reason = reason,
            heistName = heist.heistConfig.name
        })
        
        TriggerClientEvent('cnr:showNotification', memberId, 'Heist failed: ' .. reason, 'error')
    end
    
    -- Clean up
    CleanupHeist(crewId)
end

-- Cleanup heist
function CleanupHeist(crewId)
    local heist = activeHeists[crewId]
    if not heist then return end
    
    local crew = heist.crew
    
    -- Remove crew roles
    for _, memberId in pairs(crew.members) do
        playerCrewRoles[memberId] = nil
    end
    
    -- Remove heist data
    activeHeists[crewId] = nil
    heistCrews[crewId] = nil
end

-- Heist member arrest (causes heist failure)
RegisterNetEvent('cnr:heistMemberArrested')
AddEventHandler('cnr:heistMemberArrested', function(arrestedPlayerId)
    local crewId = playerCrewRoles[arrestedPlayerId]
    if crewId and activeHeists[crewId] then
        FailHeist(crewId, "Crew member arrested")
    end
end)

-- Get player's crew info
RegisterNetEvent('cnr:getCrewInfo')
AddEventHandler('cnr:getCrewInfo', function()
    local src = source
    local crewId = playerCrewRoles[src]
    
    if crewId and heistCrews[crewId] then
        TriggerClientEvent('cnr:updateCrewInfo', src, heistCrews[crewId])
    else
        TriggerClientEvent('cnr:updateCrewInfo', src, nil)
    end
end)

-- Get available heists
RegisterNetEvent('cnr:getAvailableHeists')
AddEventHandler('cnr:getAvailableHeists', function()
    local src = source
    local playerLevel = GetPlayerLevel(src)
    local availableHeists = {}
    
    for _, heist in pairs(Config.EnhancedHeists) do
        if playerLevel >= heist.requiredLevel then
            local now = os.time()
            local onCooldown = heistCooldowns[heist.id] and now - heistCooldowns[heist.id] < heist.cooldown
            
            table.insert(availableHeists, {
                id = heist.id,
                name = heist.name,
                type = heist.type,
                difficulty = heist.difficulty,
                requiredCrew = heist.requiredCrew,
                minReward = heist.minReward,
                maxReward = heist.maxReward,
                duration = heist.duration,
                onCooldown = onCooldown,
                cooldownRemaining = onCooldown and math.ceil((heist.cooldown - (now - heistCooldowns[heist.id])) / 60) or 0
            })
        end
    end
    
    TriggerClientEvent('cnr:updateAvailableHeists', src, availableHeists)
end)

