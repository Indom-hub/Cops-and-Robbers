-- data_manager.lua
-- Improved data persistence system with batching, error handling, and backup support
-- Version: 1.2.0

-- Ensure Constants are loaded
if not Constants then
    error("Constants must be loaded before data_manager.lua")
end

-- Initialize DataManager module
DataManager = DataManager or {}

-- Internal state
local pendingSaves = {}
local saveQueue = {}
local isProcessingSaves = false
local lastSaveTime = 0
local backupSchedule = {}

-- Performance monitoring
local saveStats = {
    totalSaves = 0,
    failedSaves = 0,
    averageSaveTime = 0,
    lastSaveTime = 0
}

-- ====================================================================
-- UTILITY FUNCTIONS
-- ====================================================================

--- Generate a unique filename for player data
--- @param playerId number Player ID
--- @return string Filename
local function GetPlayerDataFilename(playerId)
    return string.format("%s/player_%d%s", Constants.FILES.PLAYER_DATA_DIR, playerId, Constants.FILES.JSON_EXT)
end

--- Generate backup filename with timestamp
--- @param originalFilename string Original filename
--- @return string Backup filename
local function GetBackupFilename(originalFilename)
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local baseName = originalFilename:gsub(Constants.FILES.JSON_EXT .. "$", "")
    return string.format("%s/%s_%s%s", Constants.FILES.BACKUP_DIR, baseName, timestamp, Constants.FILES.BACKUP_EXT)
end

--- Log data manager operations
--- @param message string Log message
--- @param level string Log level
local function LogDataManager(message, level)
    level = level or Constants.LOG_LEVELS.INFO
    if level == Constants.LOG_LEVELS.ERROR or level == Constants.LOG_LEVELS.WARN then
        print(string.format("[CNR_DATA_MANAGER] [%s] %s", string.upper(level), message))
    end
end

--- Validate JSON data before saving
--- @param data table Data to validate
--- @return boolean, string Success status and error message
local function ValidateJsonData(data)
    if not data or type(data) ~= "table" then
        return false, "Data must be a table"
    end
    
    -- Check for circular references (basic check)
    local function checkCircular(tbl, seen)
        seen = seen or {}
        if seen[tbl] then
            return false
        end
        seen[tbl] = true
        
        for k, v in pairs(tbl) do
            if type(v) == "table" then
                if not checkCircular(v, seen) then
                    return false
                end
            end
        end
        
        seen[tbl] = nil
        return true
    end
    
    if not checkCircular(data) then
        return false, "Circular reference detected in data"
    end
    
    return true, nil
end

--- Safely encode JSON with error handling
--- @param data table Data to encode
--- @return boolean, string Success status and JSON string or error message
local function SafeJsonEncode(data)
    local valid, error = ValidateJsonData(data)
    if not valid then
        return false, error
    end
    
    local success, result = pcall(json.encode, data)
    if not success then
        return false, "JSON encoding failed: " .. tostring(result)
    end
    
    return true, result
end

--- Safely decode JSON with error handling
--- @param jsonString string JSON string to decode
--- @return boolean, table Success status and decoded data or error message
local function SafeJsonDecode(jsonString)
    if not jsonString or type(jsonString) ~= "string" or #jsonString == 0 then
        return false, "Invalid JSON string"
    end
    
    local success, result = pcall(json.decode, jsonString)
    if not success then
        return false, "JSON decoding failed: " .. tostring(result)
    end
    
    if type(result) ~= "table" then
        return false, "Decoded JSON is not a table"
    end
    
    return true, result
end

-- ====================================================================
-- BACKUP SYSTEM
-- ====================================================================

--- Create backup of a file
--- @param filename string Original filename
--- @return boolean Success status
local function CreateBackup(filename)
    local fileData = LoadResourceFile(GetCurrentResourceName(), filename)
    if not fileData then
        return false -- File doesn't exist, no backup needed
    end
    
    local backupFilename = GetBackupFilename(filename)
    local success = SaveResourceFile(GetCurrentResourceName(), backupFilename, fileData, -1)
    
    if success then
        LogDataManager(string.format("Created backup: %s -> %s", filename, backupFilename))
        
        -- Clean old backups
        CleanOldBackups(filename)
    else
        LogDataManager(string.format("Failed to create backup for %s", filename), Constants.LOG_LEVELS.ERROR)
    end
    
    return success
end

--- Clean old backup files to prevent disk space issues
--- @param originalFilename string Original filename
function CleanOldBackups(originalFilename)
    -- This is a simplified version - in a real implementation,
    -- you would scan the backup directory and remove old files
    -- For now, we'll just log the intent
    LogDataManager(string.format("Cleaning old backups for %s", originalFilename))
end

--- Schedule automatic backups
--- @param filename string Filename to backup
--- @param intervalHours number Backup interval in hours
function DataManager.ScheduleBackup(filename, intervalHours)
    intervalHours = intervalHours or Constants.FILES.BACKUP_INTERVAL_HOURS
    
    backupSchedule[filename] = {
        interval = intervalHours * Constants.TIME_MS.HOUR,
        lastBackup = 0
    }
end

--- Process scheduled backups
local function ProcessScheduledBackups()
    local currentTime = GetGameTimer()
    
    for filename, schedule in pairs(backupSchedule) do
        if currentTime - schedule.lastBackup >= schedule.interval then
            if CreateBackup(filename) then
                schedule.lastBackup = currentTime
            end
        end
    end
end

-- ====================================================================
-- CORE SAVE/LOAD FUNCTIONS
-- ====================================================================

--- Save data to file with error handling and backup
--- @param filename string Filename to save to
--- @param data table Data to save
--- @param createBackup boolean Whether to create backup before saving
--- @return boolean, string Success status and error message
function DataManager.SaveToFile(filename, data, createBackup)
    local startTime = GetGameTimer()
    
    -- Validate input
    if not filename or type(filename) ~= "string" then
        return false, "Invalid filename"
    end
    
    local valid, jsonData = SafeJsonEncode(data)
    if not valid then
        LogDataManager(string.format("Failed to encode data for %s: %s", filename, jsonData), Constants.LOG_LEVELS.ERROR)
        return false, jsonData
    end
    
    -- Create backup if requested
    if createBackup then
        CreateBackup(filename)
    end
    
    -- Save the file
    local success = SaveResourceFile(GetCurrentResourceName(), filename, jsonData, -1)
    
    -- Update statistics
    local saveTime = GetGameTimer() - startTime
    saveStats.totalSaves = saveStats.totalSaves + 1
    saveStats.lastSaveTime = saveTime
    saveStats.averageSaveTime = (saveStats.averageSaveTime + saveTime) / 2
    
    if success then
        LogDataManager(string.format("Saved %s (took %dms)", filename, saveTime))
        return true, nil
    else
        saveStats.failedSaves = saveStats.failedSaves + 1
        LogDataManager(string.format("Failed to save %s", filename), Constants.LOG_LEVELS.ERROR)
        return false, "File save operation failed"
    end
end

--- Load data from file with error handling
--- @param filename string Filename to load from
--- @return boolean, table Success status and loaded data or error message
function DataManager.LoadFromFile(filename)
    if not filename or type(filename) ~= "string" then
        return false, "Invalid filename"
    end
    
    local fileData = LoadResourceFile(GetCurrentResourceName(), filename)
    if not fileData then
        return false, "File not found or empty"
    end
    
    local valid, data = SafeJsonDecode(fileData)
    if not valid then
        LogDataManager(string.format("Failed to decode %s: %s", filename, data), Constants.LOG_LEVELS.ERROR)
        return false, data
    end
    
    LogDataManager(string.format("Loaded %s", filename))
    return true, data
end

-- ====================================================================
-- BATCHED SAVE SYSTEM
-- ====================================================================

--- Add data to save queue for batched processing
--- @param filename string Filename to save to
--- @param data table Data to save
--- @param priority number Priority (higher = processed first)
function DataManager.QueueSave(filename, data, priority)
    priority = priority or 1
    
    -- Remove existing entry for same file to prevent duplicates
    for i = #saveQueue, 1, -1 do
        if saveQueue[i].filename == filename then
            table.remove(saveQueue, i)
        end
    end
    
    -- Add to queue
    table.insert(saveQueue, {
        filename = filename,
        data = data,
        priority = priority,
        timestamp = GetGameTimer()
    })
    
    -- Sort by priority (higher first)
    table.sort(saveQueue, function(a, b) return a.priority > b.priority end)
    
    LogDataManager(string.format("Queued save for %s (priority: %d, queue size: %d)", filename, priority, #saveQueue))
end

--- Process the save queue
local function ProcessSaveQueue()
    if isProcessingSaves or #saveQueue == 0 then
        return
    end
    
    isProcessingSaves = true
    local processed = 0
    local maxProcessPerCycle = Constants.DATABASE.BATCH_SIZE
    
    while #saveQueue > 0 and processed < maxProcessPerCycle do
        local saveItem = table.remove(saveQueue, 1)
        local success, error = DataManager.SaveToFile(saveItem.filename, saveItem.data, true)
        
        if not success then
            LogDataManager(string.format("Failed to save queued file %s: %s", saveItem.filename, error), Constants.LOG_LEVELS.ERROR)
        end
        
        processed = processed + 1
    end
    
    isProcessingSaves = false
    lastSaveTime = GetGameTimer()
    
    if processed > 0 then
        LogDataManager(string.format("Processed %d saves from queue (%d remaining)", processed, #saveQueue))
    end
end

-- ====================================================================
-- PLAYER DATA MANAGEMENT
-- ====================================================================

--- Save player data with validation and queuing
--- @param playerId number Player ID
--- @param playerData table Player data to save
--- @param immediate boolean Whether to save immediately or queue
--- @return boolean, string Success status and error message
function DataManager.SavePlayerData(playerId, playerData, immediate)
    -- Validate player ID
    if not playerId or type(playerId) ~= "number" or playerId <= 0 then
        return false, "Invalid player ID"
    end
    
    -- Validate player data
    if not playerData or type(playerData) ~= "table" then
        return false, "Invalid player data"
    end
    
    -- Add metadata
    local dataToSave = {
        playerId = playerId,
        lastSaved = os.time(),
        version = "1.2.0",
        data = playerData
    }
    
    local filename = GetPlayerDataFilename(playerId)
    
    if immediate then
        return DataManager.SaveToFile(filename, dataToSave, true)
    else
        DataManager.QueueSave(filename, dataToSave, 2) -- Higher priority for player data
        return true, nil
    end
end

--- Load player data with validation
--- @param playerId number Player ID
--- @return boolean, table Success status and player data or error message
function DataManager.LoadPlayerData(playerId)
    if not playerId or type(playerId) ~= "number" or playerId <= 0 then
        return false, "Invalid player ID"
    end
    
    local filename = GetPlayerDataFilename(playerId)
    local success, fileData = DataManager.LoadFromFile(filename)
    
    if not success then
        return false, fileData
    end
    
    -- Validate file structure
    if not fileData.data then
        return false, "Invalid player data file structure"
    end
    
    -- Version compatibility check
    if fileData.version and fileData.version ~= "1.2.0" then
        LogDataManager(string.format("Player %d data version mismatch: %s", playerId, fileData.version), Constants.LOG_LEVELS.WARN)
        -- Could implement migration logic here
    end
    
    return true, fileData.data
end

--- Mark player data for saving (used by existing code)
--- @param playerId number Player ID
function DataManager.MarkPlayerForSave(playerId)
    if not pendingSaves[playerId] then
        pendingSaves[playerId] = GetGameTimer()
    end
end

--- Process pending player saves
local function ProcessPendingSaves()
    for playerId, queueTime in pairs(pendingSaves) do
        local playerData = GetCnrPlayerData(playerId)
        if playerData then
            DataManager.SavePlayerData(playerId, playerData, false)
        end
        pendingSaves[playerId] = nil
    end
end

-- ====================================================================
-- SYSTEM DATA MANAGEMENT
-- ====================================================================

--- Save system data (bans, purchase history, etc.)
--- @param dataType string Type of data (bans, purchases, banking)
--- @param data table Data to save
--- @return boolean, string Success status and error message
function DataManager.SaveSystemData(dataType, data)
    local filename
    
    if dataType == "bans" then
        filename = Constants.FILES.BANS_FILE
    elseif dataType == "purchases" then
        filename = Constants.FILES.PURCHASE_HISTORY_FILE
    elseif dataType == "banking" then
        filename = Constants.FILES.BANKING_DATA_FILE
    else
        return false, "Unknown data type: " .. tostring(dataType)
    end
    
    return DataManager.SaveToFile(filename, data, true)
end

--- Load system data
--- @param dataType string Type of data to load
--- @return boolean, table Success status and loaded data or error message
function DataManager.LoadSystemData(dataType)
    local filename
    
    if dataType == "bans" then
        filename = Constants.FILES.BANS_FILE
    elseif dataType == "purchases" then
        filename = Constants.FILES.PURCHASE_HISTORY_FILE
    elseif dataType == "banking" then
        filename = Constants.FILES.BANKING_DATA_FILE
    else
        return false, "Unknown data type: " .. tostring(dataType)
    end
    
    return DataManager.LoadFromFile(filename)
end

-- ====================================================================
-- MONITORING AND STATISTICS
-- ====================================================================

--- Get save statistics
--- @return table Save statistics
function DataManager.GetStats()
    return {
        totalSaves = saveStats.totalSaves,
        failedSaves = saveStats.failedSaves,
        successRate = saveStats.totalSaves > 0 and ((saveStats.totalSaves - saveStats.failedSaves) / saveStats.totalSaves * 100) or 0,
        averageSaveTime = saveStats.averageSaveTime,
        lastSaveTime = saveStats.lastSaveTime,
        queueSize = #saveQueue,
        pendingSaves = tablelength(pendingSaves)
    }
end

--- Log current statistics
function DataManager.LogStats()
    local stats = DataManager.GetStats()
    LogDataManager(string.format(
        "Stats - Total: %d, Failed: %d, Success Rate: %.1f%%, Avg Time: %.1fms, Queue: %d, Pending: %d",
        stats.totalSaves, stats.failedSaves, stats.successRate, 
        stats.averageSaveTime, stats.queueSize, stats.pendingSaves
    ))
end

-- ====================================================================
-- INITIALIZATION AND CLEANUP
-- ====================================================================

--- Initialize the data manager
function DataManager.Initialize()
    LogDataManager("Data Manager initialized")
    
    -- Schedule backups for important files
    DataManager.ScheduleBackup(Constants.FILES.BANS_FILE)
    DataManager.ScheduleBackup(Constants.FILES.PURCHASE_HISTORY_FILE)
    DataManager.ScheduleBackup(Constants.FILES.BANKING_DATA_FILE)
    
    -- Start processing threads
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(Constants.TIME_MS.SAVE_INTERVAL)
            ProcessSaveQueue()
            ProcessPendingSaves()
            ProcessScheduledBackups()
        end
    end)
    
    -- Statistics logging thread
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(10 * Constants.TIME_MS.MINUTE) -- Every 10 minutes
            DataManager.LogStats()
        end
    end)
end

--- Cleanup on resource stop
function DataManager.Cleanup()
    LogDataManager("Processing final saves before shutdown...")
    
    -- Process all pending saves immediately
    ProcessPendingSaves()
    
    -- Process entire save queue
    while #saveQueue > 0 do
        ProcessSaveQueue()
        Citizen.Wait(100)
    end
    
    LogDataManager("Data Manager cleanup completed")
end

-- Initialize when loaded
DataManager.Initialize()

-- DataManager module is now available globally