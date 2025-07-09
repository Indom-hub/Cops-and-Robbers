-- player_manager.lua
-- Refactored player data management system with improved security and performance
-- Version: 1.2.0

-- Ensure required modules are loaded
if not Constants then
    error("Constants must be loaded before player_manager.lua")
end

if not Validation then
    error("Validation must be loaded before player_manager.lua")
end

if not DataManager then
    error("DataManager must be loaded before player_manager.lua")
end

-- Initialize PlayerManager module
PlayerManager = PlayerManager or {}

-- Player data cache (replaces global playersData)
local playerDataCache = {}
local playerLoadingStates = {}

-- Statistics
local playerStats = {
    totalLoads = 0,
    totalSaves = 0,
    failedLoads = 0,
    failedSaves = 0,
    averageLoadTime = 0,
    averageSaveTime = 0
}

-- ====================================================================
-- UTILITY FUNCTIONS
-- ====================================================================

--- Log player management operations
--- @param playerId number Player ID
--- @param operation string Operation type
--- @param message string Log message
--- @param level string Log level
local function LogPlayerManager(playerId, operation, message, level)
    level = level or Constants.LOG_LEVELS.INFO
    local playerName = GetPlayerName(playerId) or "Unknown"
    
    if level == Constants.LOG_LEVELS.ERROR or level == Constants.LOG_LEVELS.WARN then
        print(string.format("[CNR_PLAYER_MANAGER] [%s] Player %s (%d) - %s: %s", 
            string.upper(level), playerName, playerId, operation, message))
    end
end

--- Get player license identifier safely
--- @param playerId number Player ID
--- @return string, boolean License identifier and success status
local function GetPlayerLicenseSafe(playerId)
    local identifiers = GetPlayerIdentifiers(playerId)
    if not identifiers then
        return nil, false
    end
    
    for _, identifier in ipairs(identifiers) do
        if string.find(identifier, "license:") then
            return identifier, true
        end
    end
    
    return nil, false
end

--- Create default player data structure
--- @param playerId number Player ID
--- @return table Default player data
local function CreateDefaultPlayerData(playerId)
    local playerPed = GetPlayerPed(tostring(playerId))
    local initialCoords = vector3(0, 0, 70) -- Default spawn location
    
    if playerPed and playerPed ~= 0 then
        local coords = GetEntityCoords(playerPed)
        if coords then
            initialCoords = coords
        end
    end
    
    return {
        -- Basic player information
        playerId = playerId,
        license = GetPlayerLicenseSafe(playerId),
        name = GetPlayerName(playerId) or "Unknown",
        
        -- Game state
        role = Constants.ROLES.CITIZEN,
        level = 1,
        xp = 0,
        money = Constants.PLAYER_LIMITS.DEFAULT_STARTING_MONEY,
        
        -- Position and world state
        lastKnownPosition = initialCoords,
        
        -- Systems
        inventory = {},
        
        -- Timestamps
        firstJoined = os.time(),
        lastSeen = os.time(),
        
        -- Flags
        isDataLoaded = false,
        
        -- Statistics
        totalPlayTime = 0,
        sessionsPlayed = 1,
        
        -- Version for data migration
        dataVersion = "1.2.0"
    }
end

--- Validate player data structure
--- @param playerData table Player data to validate
--- @return boolean, table Success status and validation issues
local function ValidatePlayerDataStructure(playerData)
    local issues = {}
    
    if not playerData or type(playerData) ~= "table" then
        table.insert(issues, "Player data is not a table")
        return false, issues
    end
    
    -- Check required fields
    local requiredFields = {
        "playerId", "role", "level", "xp", "money", "inventory"
    }
    
    for _, field in ipairs(requiredFields) do
        if playerData[field] == nil then
            table.insert(issues, string.format("Missing required field: %s", field))
        end
    end
    
    -- Validate field types and ranges
    if playerData.level and (type(playerData.level) ~= "number" or playerData.level < 1 or playerData.level > Constants.PLAYER_LIMITS.MAX_PLAYER_LEVEL) then
        table.insert(issues, "Invalid level value")
    end
    
    if playerData.money and (type(playerData.money) ~= "number" or playerData.money < 0) then
        table.insert(issues, "Invalid money value")
    end
    
    if playerData.xp and (type(playerData.xp) ~= "number" or playerData.xp < 0) then
        table.insert(issues, "Invalid XP value")
    end
    
    if playerData.inventory and type(playerData.inventory) ~= "table" then
        table.insert(issues, "Inventory is not a table")
    end
    
    return #issues == 0, issues
end

--- Fix player data issues
--- @param playerData table Player data to fix
--- @param playerId number Player ID
--- @return table Fixed player data
local function FixPlayerDataIssues(playerData, playerId)
    -- Ensure basic structure
    if not playerData or type(playerData) ~= "table" then
        LogPlayerManager(playerId, "fix_data", "Creating new data structure due to corruption")
        return CreateDefaultPlayerData(playerId)
    end
    
    -- Fix missing or invalid fields
    playerData.playerId = playerData.playerId or playerId
    playerData.role = playerData.role or Constants.ROLES.CITIZEN
    playerData.level = math.max(1, math.min(playerData.level or 1, Constants.PLAYER_LIMITS.MAX_PLAYER_LEVEL))
    playerData.xp = math.max(0, playerData.xp or 0)
    playerData.money = math.max(0, playerData.money or Constants.PLAYER_LIMITS.DEFAULT_STARTING_MONEY)
    playerData.inventory = playerData.inventory or {}
    playerData.lastSeen = os.time()
    playerData.dataVersion = "1.2.0"
    
    -- Validate inventory integrity
    if SecureInventory then
        SecureInventory.FixInventoryIntegrity(playerId)
    end
    
    return playerData
end

-- ====================================================================
-- CORE PLAYER DATA FUNCTIONS
-- ====================================================================

--- Load player data with comprehensive validation and error handling
--- @param playerId number Player ID
--- @return boolean, string Success status and error message
function PlayerManager.LoadPlayerData(playerId)
    local startTime = GetGameTimer()
    
    -- Validate player
    local validPlayer, playerError = Validation.ValidatePlayer(playerId)
    if not validPlayer then
        return false, playerError
    end
    
    -- Check if already loading
    if playerLoadingStates[playerId] then
        LogPlayerManager(playerId, "load", "Data already loading, skipping duplicate request")
        return false, "Data already loading"
    end
    
    playerLoadingStates[playerId] = true
    
    -- Attempt to load from DataManager
    local success, playerData = DataManager.LoadPlayerData(playerId)
    
    if success then
        -- Validate loaded data
        local validData, issues = ValidatePlayerDataStructure(playerData)
        if not validData then
            LogPlayerManager(playerId, "load", 
                string.format("Data validation failed: %s", table.concat(issues, ", ")), 
                Constants.LOG_LEVELS.WARN)
            playerData = FixPlayerDataIssues(playerData, playerId)
        end
    else
        -- Create new player data
        LogPlayerManager(playerId, "load", "Creating new player data (first time or load failed)")
        playerData = CreateDefaultPlayerData(playerId)
    end
    
    -- Apply any necessary data migrations
    playerData = PlayerManager.MigratePlayerData(playerData, playerId)
    
    -- Cache the data
    playerDataCache[playerId] = playerData
    playerData.isDataLoaded = true
    
    -- Update statistics
    playerStats.totalLoads = playerStats.totalLoads + 1
    if not success then
        playerStats.failedLoads = playerStats.failedLoads + 1
    end
    
    local loadTime = GetGameTimer() - startTime
    playerStats.averageLoadTime = (playerStats.averageLoadTime + loadTime) / 2
    
    playerLoadingStates[playerId] = nil
    
    LogPlayerManager(playerId, "load", 
        string.format("Data loaded successfully (took %dms)", loadTime))
    
    return true, nil
end

--- Save player data with validation and error handling
--- @param playerId number Player ID
--- @param immediate boolean Whether to save immediately or queue
--- @return boolean, string Success status and error message
function PlayerManager.SavePlayerData(playerId, immediate)
    local startTime = GetGameTimer()
    immediate = immediate or false
    
    -- Validate player
    local validPlayer, playerError = Validation.ValidatePlayer(playerId)
    if not validPlayer then
        return false, playerError
    end
    
    -- Get player data from cache
    local playerData = playerDataCache[playerId]
    if not playerData then
        return false, "No player data to save"
    end
    
    -- Update last seen timestamp
    playerData.lastSeen = os.time()
    
    -- Update position if player is online
    local playerPed = GetPlayerPed(tostring(playerId))
    if playerPed and playerPed ~= 0 then
        local coords = GetEntityCoords(playerPed)
        if coords then
            playerData.lastKnownPosition = coords
        end
    end
    
    -- Validate data before saving
    local validData, issues = ValidatePlayerDataStructure(playerData)
    if not validData then
        LogPlayerManager(playerId, "save", 
            string.format("Data validation failed before save: %s", table.concat(issues, ", ")), 
            Constants.LOG_LEVELS.ERROR)
        return false, "Data validation failed"
    end
    
    -- Save using DataManager
    local success, error = DataManager.SavePlayerData(playerId, playerData, immediate)
    
    -- Update statistics
    playerStats.totalSaves = playerStats.totalSaves + 1
    if not success then
        playerStats.failedSaves = playerStats.failedSaves + 1
    end
    
    local saveTime = GetGameTimer() - startTime
    playerStats.averageSaveTime = (playerStats.averageSaveTime + saveTime) / 2
    
    if success then
        LogPlayerManager(playerId, "save", 
            string.format("Data saved successfully (took %dms, immediate: %s)", 
                saveTime, tostring(immediate)))
    else
        LogPlayerManager(playerId, "save", 
            string.format("Save failed: %s", error), 
            Constants.LOG_LEVELS.ERROR)
    end
    
    return success, error
end

--- Get player data from cache with validation
--- @param playerId number Player ID
--- @return table, boolean Player data and success status
function PlayerManager.GetPlayerData(playerId)
    -- Validate player
    local validPlayer, playerError = Validation.ValidatePlayer(playerId)
    if not validPlayer then
        return nil, false
    end
    
    local playerData = playerDataCache[playerId]
    if not playerData then
        LogPlayerManager(playerId, "get_data", "No cached data found", Constants.LOG_LEVELS.WARN)
        return nil, false
    end
    
    if not playerData.isDataLoaded then
        LogPlayerManager(playerId, "get_data", "Data not fully loaded", Constants.LOG_LEVELS.WARN)
        return nil, false
    end
    
    return playerData, true
end

--- Set player data in cache with validation
--- @param playerId number Player ID
--- @param playerData table Player data to set
--- @return boolean Success status
function PlayerManager.SetPlayerData(playerId, playerData)
    -- Validate player
    local validPlayer, playerError = Validation.ValidatePlayer(playerId)
    if not validPlayer then
        return false
    end
    
    -- Validate data structure
    local validData, issues = ValidatePlayerDataStructure(playerData)
    if not validData then
        LogPlayerManager(playerId, "set_data", 
            string.format("Invalid data structure: %s", table.concat(issues, ", ")), 
            Constants.LOG_LEVELS.ERROR)
        return false
    end
    
    playerDataCache[playerId] = playerData
    DataManager.MarkPlayerForSave(playerId)
    
    return true
end

-- ====================================================================
-- DATA MIGRATION SYSTEM
-- ====================================================================

--- Migrate player data to current version
--- @param playerData table Player data to migrate
--- @param playerId number Player ID
--- @return table Migrated player data
function PlayerManager.MigratePlayerData(playerData, playerId)
    local currentVersion = "1.2.0"
    local dataVersion = playerData.dataVersion or "1.0.0"
    
    if dataVersion == currentVersion then
        return playerData -- No migration needed
    end
    
    LogPlayerManager(playerId, "migrate", 
        string.format("Migrating data from version %s to %s", dataVersion, currentVersion))
    
    -- Migration logic for different versions
    if dataVersion == "1.0.0" or dataVersion == "1.1.0" then
        -- Add new fields introduced in 1.2.0
        playerData.dataVersion = currentVersion
        playerData.totalPlayTime = playerData.totalPlayTime or 0
        playerData.sessionsPlayed = playerData.sessionsPlayed or 1
        
        -- Ensure inventory structure is correct
        if not playerData.inventory or type(playerData.inventory) ~= "table" then
            playerData.inventory = {}
        end
        
        -- Fix any legacy role names
        if playerData.role == "civilian" then
            playerData.role = Constants.ROLES.CITIZEN
        end
    end
    
    LogPlayerManager(playerId, "migrate", "Data migration completed successfully")
    return playerData
end

-- ====================================================================
-- PLAYER LIFECYCLE MANAGEMENT
-- ====================================================================

--- Handle player connection
--- @param playerId number Player ID
function PlayerManager.OnPlayerConnected(playerId)
    LogPlayerManager(playerId, "connect", "Player connected, initializing data")
    
    -- Load player data
    local success, error = PlayerManager.LoadPlayerData(playerId)
    if not success then
        LogPlayerManager(playerId, "connect", 
            string.format("Failed to load data: %s", error), 
            Constants.LOG_LEVELS.ERROR)
        return
    end
    
    -- Initialize player systems
    PlayerManager.InitializePlayerSystems(playerId)
    
    LogPlayerManager(playerId, "connect", "Player initialization completed")
end

--- Handle player disconnection
--- @param playerId number Player ID
--- @param reason string Disconnect reason
function PlayerManager.OnPlayerDisconnected(playerId, reason)
    LogPlayerManager(playerId, "disconnect", 
        string.format("Player disconnected (reason: %s), saving data", reason or "unknown"))
    
    -- Save player data immediately
    local success, error = PlayerManager.SavePlayerData(playerId, true)
    if not success then
        LogPlayerManager(playerId, "disconnect", 
            string.format("Failed to save data: %s", error), 
            Constants.LOG_LEVELS.ERROR)
    end
    
    -- Clean up player from cache and other systems
    PlayerManager.CleanupPlayer(playerId)
    
    LogPlayerManager(playerId, "disconnect", "Player cleanup completed")
end

--- Initialize player systems after data load
--- @param playerId number Player ID
function PlayerManager.InitializePlayerSystems(playerId)
    local playerData = playerDataCache[playerId]
    if not playerData then
        LogPlayerManager(playerId, "init_systems", "No player data available", Constants.LOG_LEVELS.ERROR)
        return
    end
    
    -- Set player role (this will trigger role-specific initialization)
    PlayerManager.SetPlayerRole(playerId, playerData.role, true)
    
    -- Apply level-based perks
    if ApplyPerks then
        ApplyPerks(playerId, playerData.level, playerData.role)
    end
    
    -- Initialize inventory
    if not playerData.inventory then
        playerData.inventory = {}
    end
    
    -- Sync data to client
    PlayerManager.SyncPlayerDataToClient(playerId)
    
    LogPlayerManager(playerId, "init_systems", "Player systems initialized")
end

--- Sync player data to client
--- @param playerId number Player ID
function PlayerManager.SyncPlayerDataToClient(playerId)
    local playerData = playerDataCache[playerId]
    if not playerData then return end
    
    -- Send minimized inventory for performance
    if SecureInventory then
        local success, inventory = SecureInventory.GetInventory(playerId)
        if success then
            TriggerClientEvent(Constants.EVENTS.SERVER_TO_CLIENT.SYNC_INVENTORY, playerId, 
                MinimizeInventoryForSync(inventory))
        end
    end
    
    -- Send other player data
    TriggerClientEvent(Constants.EVENTS.SERVER_TO_CLIENT.UPDATE_PLAYER_DATA, playerId, {
        role = playerData.role,
        level = playerData.level,
        xp = playerData.xp,
        money = playerData.money
    })
end

--- Clean up player data and references
--- @param playerId number Player ID
function PlayerManager.CleanupPlayer(playerId)
    -- Remove from cache
    playerDataCache[playerId] = nil
    playerLoadingStates[playerId] = nil
    
    -- Clean up other systems
    if Validation then
        Validation.CleanupPlayer(playerId)
    end
    
    if SecureInventory then
        SecureInventory.CleanupPlayer(playerId)
    end
    
    if SecureTransactions then
        SecureTransactions.CleanupPlayer(playerId)
    end
    
    LogPlayerManager(playerId, "cleanup", "Player cleanup completed")
end

-- ====================================================================
-- ROLE MANAGEMENT
-- ====================================================================

--- Set player role with validation and system updates
--- @param playerId number Player ID
--- @param role string New role
--- @param skipNotify boolean Whether to skip notification
--- @return boolean Success status
function PlayerManager.SetPlayerRole(playerId, role, skipNotify)
    -- Validate player
    local validPlayer, playerError = Validation.ValidatePlayer(playerId)
    if not validPlayer then
        return false
    end
    
    -- Validate role
    local validRoles = {Constants.ROLES.COP, Constants.ROLES.ROBBER, Constants.ROLES.CITIZEN}
    local isValidRole = false
    for _, validRole in ipairs(validRoles) do
        if role == validRole then
            isValidRole = true
            break
        end
    end
    
    if not isValidRole then
        LogPlayerManager(playerId, "set_role", 
            string.format("Invalid role: %s", tostring(role)), 
            Constants.LOG_LEVELS.ERROR)
        return false
    end
    
    local playerData = playerDataCache[playerId]
    if not playerData then
        LogPlayerManager(playerId, "set_role", "No player data available", Constants.LOG_LEVELS.ERROR)
        return false
    end
    
    local oldRole = playerData.role
    playerData.role = role
    
    -- Update role-specific tracking (using existing global variables for compatibility)
    if copsOnDuty then
        copsOnDuty[playerId] = (role == Constants.ROLES.COP) or nil
    end
    
    if robbersActive then
        robbersActive[playerId] = (role == Constants.ROLES.ROBBER) or nil
    end
    
    -- Mark for save
    DataManager.MarkPlayerForSave(playerId)
    
    -- Notify player if not skipped
    if not skipNotify then
        TriggerClientEvent(Constants.EVENTS.SERVER_TO_CLIENT.SHOW_NOTIFICATION, playerId, 
            string.format("Role changed to %s", role), Constants.NOTIFICATION_TYPES.INFO)
    end
    
    LogPlayerManager(playerId, "set_role", 
        string.format("Role changed from %s to %s", oldRole, role))
    
    return true
end

-- ====================================================================
-- STATISTICS AND MONITORING
-- ====================================================================

--- Get player manager statistics
--- @return table Statistics
function PlayerManager.GetStats()
    return {
        totalLoads = playerStats.totalLoads,
        totalSaves = playerStats.totalSaves,
        failedLoads = playerStats.failedLoads,
        failedSaves = playerStats.failedSaves,
        loadSuccessRate = playerStats.totalLoads > 0 and 
            ((playerStats.totalLoads - playerStats.failedLoads) / playerStats.totalLoads * 100) or 0,
        saveSuccessRate = playerStats.totalSaves > 0 and 
            ((playerStats.totalSaves - playerStats.failedSaves) / playerStats.totalSaves * 100) or 0,
        averageLoadTime = playerStats.averageLoadTime,
        averageSaveTime = playerStats.averageSaveTime,
        cachedPlayers = tablelength(playerDataCache),
        loadingPlayers = tablelength(playerLoadingStates)
    }
end

--- Log player manager statistics
function PlayerManager.LogStats()
    local stats = PlayerManager.GetStats()
    print(string.format("[CNR_PLAYER_MANAGER] Stats - Loads: %d (%.1f%% success), Saves: %d (%.1f%% success), Avg Load: %.1fms, Avg Save: %.1fms, Cached: %d, Loading: %d",
        stats.totalLoads, stats.loadSuccessRate, stats.totalSaves, stats.saveSuccessRate,
        stats.averageLoadTime, stats.averageSaveTime, stats.cachedPlayers, stats.loadingPlayers))
end

-- ====================================================================
-- COMPATIBILITY FUNCTIONS
-- ====================================================================

--- Compatibility function for existing GetCnrPlayerData calls
--- @param playerId number Player ID
--- @return table Player data
function GetCnrPlayerData(playerId)
    local playerData, success = PlayerManager.GetPlayerData(playerId)
    return success and playerData or nil
end

--- Compatibility function for existing LoadPlayerData calls
--- @param playerId number Player ID
function LoadPlayerData(playerId)
    PlayerManager.LoadPlayerData(playerId)
end

--- Compatibility function for existing SavePlayerData calls
--- @param playerId number Player ID
function SavePlayerData(playerId)
    PlayerManager.SavePlayerData(playerId, false)
end

--- Compatibility function for immediate saves
--- @param playerId number Player ID
--- @param reason string Save reason
function SavePlayerDataImmediate(playerId, reason)
    PlayerManager.SavePlayerData(playerId, true)
end

--- Compatibility function for role setting
--- @param playerId number Player ID
--- @param role string Role to set
--- @param skipNotify boolean Skip notification
function SetPlayerRole(playerId, role, skipNotify)
    PlayerManager.SetPlayerRole(playerId, role, skipNotify)
end

-- ====================================================================
-- INITIALIZATION
-- ====================================================================

--- Initialize player manager
function PlayerManager.Initialize()
    print("[CNR_PLAYER_MANAGER] Player Manager initialized")
    
    -- Statistics logging thread
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(10 * Constants.TIME_MS.MINUTE)
            PlayerManager.LogStats()
        end
    end)
end

-- Initialize when loaded
PlayerManager.Initialize()

-- PlayerManager module is now available globally