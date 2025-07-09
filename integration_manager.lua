-- integration_manager.lua
-- Integration manager for seamless transition to refactored systems
-- Version: 1.2.0

-- Ensure all required modules are loaded
local requiredModules = {
    "Constants", "Validation", "DataManager", "SecureInventory", 
    "SecureTransactions", "PlayerManager", "PerformanceOptimizer"
}

for _, moduleName in ipairs(requiredModules) do
    if not _G[moduleName] then
        error(string.format("Required module %s is not loaded", moduleName))
    end
end

-- Initialize IntegrationManager module
IntegrationManager = IntegrationManager or {}

-- Integration status tracking
local integrationStatus = {
    initialized = false,
    modulesLoaded = {},
    migrationComplete = false,
    startTime = 0
}

-- Legacy compatibility layer
local legacyFunctions = {}

-- ====================================================================
-- INITIALIZATION SYSTEM
-- ====================================================================

--- Initialize all refactored systems in the correct order
function IntegrationManager.Initialize()
    integrationStatus.startTime = GetGameTimer()
    
    print("[CNR_INTEGRATION] Starting system initialization...")
    
    -- Initialize core systems first
    local initOrder = {
        {name = "Constants", module = Constants, required = true},
        {name = "Validation", module = Validation, required = true},
        {name = "DataManager", module = DataManager, required = true},
        {name = "SecureInventory", module = SecureInventory, required = true},
        {name = "SecureTransactions", module = SecureTransactions, required = true},
        {name = "PlayerManager", module = PlayerManager, required = true},
        {name = "PerformanceOptimizer", module = PerformanceOptimizer, required = false}
    }
    
    for _, system in ipairs(initOrder) do
        local success = IntegrationManager.InitializeSystem(system.name, system.module, system.required)
        integrationStatus.modulesLoaded[system.name] = success
        
        if system.required and not success then
            error(string.format("Failed to initialize required system: %s", system.name))
        end
    end
    
    -- Set up legacy compatibility
    IntegrationManager.SetupLegacyCompatibility()
    
    -- Perform data migration if needed
    IntegrationManager.PerformDataMigration()
    
    -- Start monitoring systems
    IntegrationManager.StartMonitoring()
    
    integrationStatus.initialized = true
    local initTime = GetGameTimer() - integrationStatus.startTime
    
    print(string.format("[CNR_INTEGRATION] System initialization completed in %dms", initTime))
    
    -- Log initialization status
    IntegrationManager.LogInitializationStatus()
end

--- Initialize a specific system with error handling
--- @param systemName string Name of the system
--- @param systemModule table System module
--- @param required boolean Whether the system is required
--- @return boolean Success status
function IntegrationManager.InitializeSystem(systemName, systemModule, required)
    print(string.format("[CNR_INTEGRATION] Initializing %s...", systemName))
    
    local success, error = pcall(function()
        if systemModule and systemModule.Initialize then
            systemModule.Initialize()
        end
    end)
    
    if success then
        print(string.format("[CNR_INTEGRATION] ✅ %s initialized successfully", systemName))
        return true
    else
        local logLevel = required and "error" or "warn"
        print(string.format("[CNR_INTEGRATION] ❌ Failed to initialize %s: %s", systemName, tostring(error)))
        return false
    end
end

-- ====================================================================
-- LEGACY COMPATIBILITY LAYER
-- ====================================================================

--- Set up compatibility functions for existing code
function IntegrationManager.SetupLegacyCompatibility()
    print("[CNR_INTEGRATION] Setting up legacy compatibility layer...")
    
    -- Store original functions if they exist
    legacyFunctions.AddItemToPlayerInventory = AddItemToPlayerInventory
    legacyFunctions.RemoveItemFromPlayerInventory = RemoveItemFromPlayerInventory
    legacyFunctions.AddPlayerMoney = AddPlayerMoney
    legacyFunctions.RemovePlayerMoney = RemovePlayerMoney
    
    -- Replace with secure versions
    AddItemToPlayerInventory = function(playerId, itemId, quantity, itemDetails)
        local success, message = SecureInventory.AddItem(playerId, itemId, quantity, "legacy_add")
        return success, message
    end
    
    RemoveItemFromPlayerInventory = function(playerId, itemId, quantity)
        local success, message = SecureInventory.RemoveItem(playerId, itemId, quantity, "legacy_remove")
        return success, message
    end
    
    AddPlayerMoney = function(playerId, amount)
        local success, message = SecureTransactions.AddMoney(playerId, amount, "legacy_add")
        return success
    end
    
    RemovePlayerMoney = function(playerId, amount)
        local success, message = SecureTransactions.RemoveMoney(playerId, amount, "legacy_remove")
        return success
    end
    
    -- Enhanced MarkPlayerForInventorySave compatibility
    MarkPlayerForInventorySave = function(playerId)
        DataManager.MarkPlayerForSave(playerId)
    end
    
    print("[CNR_INTEGRATION] ✅ Legacy compatibility layer established")
end

-- ====================================================================
-- DATA MIGRATION SYSTEM
-- ====================================================================

--- Perform data migration from old format to new format
function IntegrationManager.PerformDataMigration()
    print("[CNR_INTEGRATION] Starting data migration...")
    
    -- Check if migration is needed
    local migrationNeeded = IntegrationManager.CheckMigrationNeeded()
    
    if not migrationNeeded then
        print("[CNR_INTEGRATION] No data migration needed")
        integrationStatus.migrationComplete = true
        return
    end
    
    -- Perform migration
    local success, error = pcall(function()
        IntegrationManager.MigratePlayerData()
        IntegrationManager.MigrateSystemData()
    end)
    
    if success then
        print("[CNR_INTEGRATION] ✅ Data migration completed successfully")
        integrationStatus.migrationComplete = true
    else
        print(string.format("[CNR_INTEGRATION] ❌ Data migration failed: %s", tostring(error)))
    end
end

--- Check if data migration is needed
--- @return boolean Whether migration is needed
function IntegrationManager.CheckMigrationNeeded()
    -- Check for old format files
    local oldFormatFiles = {
        "bans.json",
        "purchase_history.json"
    }
    
    for _, filename in ipairs(oldFormatFiles) do
        local fileData = LoadResourceFile(GetCurrentResourceName(), filename)
        if fileData then
            local success, data = pcall(json.decode, fileData)
            if success and data and not data.version then
                return true -- Old format detected
            end
        end
    end
    
    return false
end

--- Migrate player data files
function IntegrationManager.MigratePlayerData()
    print("[CNR_INTEGRATION] Migrating player data...")
    
    -- This would scan the player_data directory and migrate files
    -- For now, we'll rely on PlayerManager's built-in migration
    print("[CNR_INTEGRATION] Player data migration handled by PlayerManager")
end

--- Migrate system data files
function IntegrationManager.MigrateSystemData()
    print("[CNR_INTEGRATION] Migrating system data...")
    
    -- Migrate bans.json
    local success, bansData = DataManager.LoadSystemData("bans")
    if success and bansData then
        if not bansData.version then
            bansData.version = "1.2.0"
            bansData.migrated = os.time()
            DataManager.SaveSystemData("bans", bansData)
            print("[CNR_INTEGRATION] Migrated bans.json")
        end
    end
    
    -- Migrate purchase_history.json
    local success, purchaseData = DataManager.LoadSystemData("purchases")
    if success and purchaseData then
        if not purchaseData.version then
            purchaseData.version = "1.2.0"
            purchaseData.migrated = os.time()
            DataManager.SaveSystemData("purchases", purchaseData)
            print("[CNR_INTEGRATION] Migrated purchase_history.json")
        end
    end
end

-- ====================================================================
-- MONITORING AND HEALTH CHECKS
-- ====================================================================

--- Start monitoring systems
function IntegrationManager.StartMonitoring()
    print("[CNR_INTEGRATION] Starting system monitoring...")
    
    -- Create monitoring loop using PerformanceOptimizer
    if PerformanceOptimizer then
        PerformanceOptimizer.CreateOptimizedLoop(function()
            IntegrationManager.PerformHealthCheck()
        end, 60000, 120000, 3) -- 1 minute base interval, medium priority
        
        PerformanceOptimizer.CreateOptimizedLoop(function()
            IntegrationManager.LogSystemStats()
        end, 300000, 600000, 5) -- 5 minute base interval, low priority
    end
end

--- Perform health check on all systems
function IntegrationManager.PerformHealthCheck()
    local issues = {}
    
    -- Check each system
    for systemName, loaded in pairs(integrationStatus.modulesLoaded) do
        if not loaded then
            table.insert(issues, string.format("%s not loaded", systemName))
        end
    end
    
    -- Check data integrity
    if DataManager then
        local stats = DataManager.GetStats()
        if stats.failedSaves > 0 then
            table.insert(issues, string.format("DataManager has %d failed saves", stats.failedSaves))
        end
    end
    
    -- Check performance
    if PerformanceOptimizer then
        local metrics = PerformanceOptimizer.GetMetrics()
        if metrics.memoryUsage > Constants.PERFORMANCE.MEMORY_WARNING_THRESHOLD_MB * 1024 then
            table.insert(issues, string.format("High memory usage: %.1fMB", metrics.memoryUsage / 1024))
        end
    end
    
    -- Log issues if any
    if #issues > 0 then
        print(string.format("[CNR_INTEGRATION] Health check found %d issues:", #issues))
        for _, issue in ipairs(issues) do
            print(string.format("[CNR_INTEGRATION] - %s", issue))
        end
    end
end

--- Log comprehensive system statistics
function IntegrationManager.LogSystemStats()
    print("[CNR_INTEGRATION] === SYSTEM STATISTICS ===")
    
    -- Integration status
    print(string.format("[CNR_INTEGRATION] Initialized: %s, Migration: %s", 
        tostring(integrationStatus.initialized), 
        tostring(integrationStatus.migrationComplete)))
    
    -- Module status
    for systemName, loaded in pairs(integrationStatus.modulesLoaded) do
        print(string.format("[CNR_INTEGRATION] %s: %s", systemName, loaded and "✅" or "❌"))
    end
    
    -- System-specific stats
    if DataManager then DataManager.LogStats() end
    if SecureInventory then SecureInventory.LogStats() end
    if SecureTransactions then SecureTransactions.LogStats() end
    if PlayerManager then PlayerManager.LogStats() end
    if PerformanceOptimizer then PerformanceOptimizer.LogStats() end
    
    print("[CNR_INTEGRATION] === END STATISTICS ===")
end

--- Log initialization status
function IntegrationManager.LogInitializationStatus()
    print("[CNR_INTEGRATION] === INITIALIZATION SUMMARY ===")
    
    local totalSystems = 0
    local loadedSystems = 0
    
    for systemName, loaded in pairs(integrationStatus.modulesLoaded) do
        totalSystems = totalSystems + 1
        if loaded then loadedSystems = loadedSystems + 1 end
        
        print(string.format("[CNR_INTEGRATION] %s: %s", 
            systemName, loaded and "✅ LOADED" or "❌ FAILED"))
    end
    
    print(string.format("[CNR_INTEGRATION] Systems: %d/%d loaded", loadedSystems, totalSystems))
    print(string.format("[CNR_INTEGRATION] Migration: %s", 
        integrationStatus.migrationComplete and "✅ COMPLETE" or "❌ PENDING"))
    print(string.format("[CNR_INTEGRATION] Status: %s", 
        integrationStatus.initialized and "✅ READY" or "❌ NOT READY"))
    
    print("[CNR_INTEGRATION] === END SUMMARY ===")
end

-- ====================================================================
-- UTILITY FUNCTIONS
-- ====================================================================

--- Get integration status
--- @return table Integration status information
function IntegrationManager.GetStatus()
    return {
        initialized = integrationStatus.initialized,
        migrationComplete = integrationStatus.migrationComplete,
        modulesLoaded = integrationStatus.modulesLoaded,
        uptime = GetGameTimer() - integrationStatus.startTime
    }
end

--- Check if all systems are ready
--- @return boolean Whether all systems are ready
function IntegrationManager.IsReady()
    if not integrationStatus.initialized then return false end
    if not integrationStatus.migrationComplete then return false end
    
    for _, loaded in pairs(integrationStatus.modulesLoaded) do
        if not loaded then return false end
    end
    
    return true
end

-- ====================================================================
-- CLEANUP AND SHUTDOWN
-- ====================================================================

--- Cleanup all systems on resource stop
function IntegrationManager.Cleanup()
    print("[CNR_INTEGRATION] Starting system cleanup...")
    
    -- Cleanup systems in reverse order
    local cleanupOrder = {
        "PerformanceOptimizer", "PlayerManager", "SecureTransactions",
        "SecureInventory", "DataManager", "Validation"
    }
    
    for _, systemName in ipairs(cleanupOrder) do
        local system = _G[systemName]
        if system and system.Cleanup then
            local success, error = pcall(system.Cleanup)
            if success then
                print(string.format("[CNR_INTEGRATION] ✅ %s cleaned up", systemName))
            else
                print(string.format("[CNR_INTEGRATION] ❌ %s cleanup failed: %s", systemName, tostring(error)))
            end
        end
    end
    
    print("[CNR_INTEGRATION] System cleanup completed")
end

-- ====================================================================
-- RESOURCE EVENT HANDLERS
-- ====================================================================

--- Handle resource start
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        -- Small delay to ensure all scripts are loaded
        Citizen.SetTimeout(1000, function()
            IntegrationManager.Initialize()
        end)
    end
end)

--- Handle resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        IntegrationManager.Cleanup()
    end
end)

-- IntegrationManager module is now available globally