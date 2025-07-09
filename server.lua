-- server.lua
-- Version: 1.2.0
-- Consolidated server-side functionality

-- Configuration shortcuts (Config must be loaded before Log if Log uses it)
-- However, config.lua is a shared_script, so Config global should be available.
-- For safety, ensure Log definition handles potential nil Config if script order changes.
local Config = Config -- Keep this near the top as Log depends on it.

<<<<<<< Updated upstream
local function Log(message, level)
    level = level or "info"
    -- Only show critical errors and warnings to reduce spam
    if level == "error" or level == "warn" then
        print("[CNR_CRITICAL_LOG] [" .. string.upper(level) .. "] " .. message)
    end
end
=======
-- ====================================================================
-- VALIDATION SYSTEM (from validation.lua)
-- ====================================================================

-- Ensure Constants are loaded
if not Constants then
    error("Constants must be loaded before validation.lua")
end

-- Initialize Validation module
Validation = Validation or {}

-- Rate limiting storage
local rateLimits = {}
local playerEventCounts = {}

-- ====================================================================
-- VALIDATION UTILITY FUNCTIONS
-- ====================================================================

--- Safely convert value to number with bounds checking
--- @param value any The value to convert
--- @param min number Minimum allowed value
--- @param max number Maximum allowed value
--- @param default number Default value if conversion fails
--- @return number The validated number
local function SafeToNumber(value, min, max, default)
    local num = tonumber(value)
    if not num then return default end
    if min and num < min then return min end
    if max and num > max then return max end
    return num
end

--- Check if a string is valid and within length limits
--- @param str string The string to validate
--- @param maxLength number Maximum allowed length
--- @param allowEmpty boolean Whether empty strings are allowed
--- @return boolean, string Success status and error message
local function ValidateString(str, maxLength, allowEmpty)
    if not str then
        return false, "String is nil"
    end
    
    if type(str) ~= "string" then
        return false, "Value is not a string"
    end
    
    if not allowEmpty and #str == 0 then
        return false, "String cannot be empty"
    end
    
    if maxLength and #str > maxLength then
        return false, string.format("String too long (max: %d, got: %d)", maxLength, #str)
    end
    
    return true, nil
end

--- Log validation errors with context
--- @param playerId number Player ID for context
--- @param operation string The operation being validated
--- @param error string The validation error
local function LogValidationError(playerId, operation, error)
    local playerName = GetPlayerName(playerId) or "Unknown"
    print(string.format("[CNR_VALIDATION_ERROR] Player %s (%d) - %s: %s", 
        playerName, playerId, operation, error))
end

-- ====================================================================
-- RATE LIMITING SYSTEM
-- ====================================================================

--- Initialize rate limiting for a player
--- @param playerId number Player ID
local function InitializeRateLimit(playerId)
    if not rateLimits[playerId] then
        rateLimits[playerId] = {
            events = {},
            purchases = {},
            inventoryOps = {}
        }
    end
end

--- Check if player is rate limited for a specific action
--- @param playerId number Player ID
--- @param actionType string Type of action (events, purchases, inventoryOps)
--- @param maxCount number Maximum allowed actions
--- @param timeWindow number Time window in milliseconds
--- @return boolean Whether the action is allowed
function Validation.CheckRateLimit(playerId, actionType, maxCount, timeWindow)
    InitializeRateLimit(playerId)
    
    local currentTime = GetGameTimer()
    local playerLimits = rateLimits[playerId][actionType]
    
    -- Clean old entries
    for i = #playerLimits, 1, -1 do
        if currentTime - playerLimits[i] > timeWindow then
            table.remove(playerLimits, i)
        end
    end
    
    -- Check if limit exceeded
    if #playerLimits >= maxCount then
        LogValidationError(playerId, "RateLimit", 
            string.format("Exceeded %s limit: %d/%d in %dms", actionType, #playerLimits, maxCount, timeWindow))
        return false
    end
    
    -- Add current action
    table.insert(playerLimits, currentTime)
    return true
end

--- Clean up rate limiting data for disconnected player
--- @param playerId number Player ID
function Validation.CleanupRateLimit(playerId)
    rateLimits[playerId] = nil
    playerEventCounts[playerId] = nil
end

-- ====================================================================
-- PLAYER VALIDATION
-- ====================================================================

--- Validate player exists and is connected
--- @param playerId number Player ID to validate
--- @return boolean, string Success status and error message
function Validation.ValidatePlayer(playerId)
    if not playerId or type(playerId) ~= "number" then
        return false, "Invalid player ID type"
    end
    
    if playerId <= 0 then
        return false, "Invalid player ID value"
    end
    
    local playerName = GetPlayerName(playerId)
    if not playerName then
        return false, "Player not found or disconnected"
    end
    
    return true, nil
end

--- Validate player has required role
--- @param playerId number Player ID
--- @param requiredRole string Required role
--- @param playerData table Player data (optional, will fetch if not provided)
--- @return boolean, string Success status and error message
function Validation.ValidatePlayerRole(playerId, requiredRole, playerData)
    local valid, error = Validation.ValidatePlayer(playerId)
    if not valid then return false, error end
    
    if not playerData then
        playerData = GetCnrPlayerData(playerId)
    end
    
    if not playerData then
        return false, Constants.ERROR_MESSAGES.PLAYER_NOT_FOUND
    end
    
    if playerData.role ~= requiredRole then
        return false, string.format("Role '%s' required, player has '%s'", requiredRole, playerData.role or "none")
    end
    
    return true, nil
end

--- Validate player has required level
--- @param playerId number Player ID
--- @param requiredLevel number Required level
--- @param playerData table Player data (optional)
--- @return boolean, string Success status and error message
function Validation.ValidatePlayerLevel(playerId, requiredLevel, playerData)
    local valid, error = Validation.ValidatePlayer(playerId)
    if not valid then return false, error end
    
    if not playerData then
        playerData = GetCnrPlayerData(playerId)
    end
    
    if not playerData then
        return false, Constants.ERROR_MESSAGES.PLAYER_NOT_FOUND
    end
    
    local playerLevel = playerData.level or 1
    if playerLevel < requiredLevel then
        return false, string.format("Level %d required, player is level %d", requiredLevel, playerLevel)
    end
    
    return true, nil
end

-- ====================================================================
-- ITEM VALIDATION
-- ====================================================================

--- Validate item exists in configuration
--- @param itemId string Item ID to validate
--- @return boolean, table, string Success status, item config, and error message
function Validation.ValidateItem(itemId)
    local valid, error = ValidateString(itemId, Constants.VALIDATION.MAX_STRING_LENGTH, false)
    if not valid then
        return false, nil, "Invalid item ID: " .. error
    end
    
    if not Config or not Config.Items then
        return false, nil, "Item configuration not loaded"
    end
    
    local itemConfig = nil
    for _, item in ipairs(Config.Items) do
        if item.itemId == itemId then
            itemConfig = item
            break
        end
    end
    
    if not itemConfig then
        return false, nil, Constants.ERROR_MESSAGES.ITEM_NOT_FOUND
    end
    
    return true, itemConfig, nil
end

--- Validate item quantity
--- @param quantity any Quantity to validate
--- @return boolean, number, string Success status, validated quantity, and error message
function Validation.ValidateQuantity(quantity)
    local num = SafeToNumber(quantity, 
        Constants.VALIDATION.MIN_ITEM_QUANTITY, 
        Constants.VALIDATION.MAX_ITEM_QUANTITY, 
        nil)
    
    if not num then
        return false, 0, Constants.ERROR_MESSAGES.INVALID_QUANTITY
    end
    
    return true, num, nil
end

--- Validate player can afford item purchase
--- @param playerId number Player ID
--- @param itemConfig table Item configuration
--- @param quantity number Quantity to purchase
--- @param playerData table Player data (optional)
--- @return boolean, number, string Success status, total cost, and error message
function Validation.ValidateItemPurchase(playerId, itemConfig, quantity, playerData)
    if not playerData then
        playerData = GetCnrPlayerData(playerId)
    end
    
    if not playerData then
        return false, 0, Constants.ERROR_MESSAGES.PLAYER_NOT_FOUND
    end
    
    local totalCost = (itemConfig.basePrice or 0) * quantity
    
    -- Validate cost is reasonable
    if totalCost > Constants.VALIDATION.MAX_MONEY_TRANSACTION then
        return false, totalCost, "Transaction amount too large"
    end
    
    -- Check player funds
    local playerMoney = playerData.money or 0
    if playerMoney < totalCost then
        return false, totalCost, Constants.ERROR_MESSAGES.INSUFFICIENT_FUNDS
    end
    
    -- Check role restrictions
    if itemConfig.forCop and playerData.role ~= Constants.ROLES.COP then
        return false, totalCost, "Item restricted to police officers"
    end
    
    -- Check level requirements
    local requiredLevel = nil
    if playerData.role == Constants.ROLES.COP and itemConfig.minLevelCop then
        requiredLevel = itemConfig.minLevelCop
    elseif playerData.role == Constants.ROLES.ROBBER and itemConfig.minLevelRobber then
        requiredLevel = itemConfig.minLevelRobber
    end
    
    if requiredLevel then
        local playerLevel = playerData.level or 1
        if playerLevel < requiredLevel then
            return false, totalCost, string.format("Level %d required for this item", requiredLevel)
        end
    end
    
    return true, totalCost, nil
end

--- Validate player has item for sale
--- @param playerId number Player ID
--- @param itemId string Item ID
--- @param quantity number Quantity to sell
--- @param playerData table Player data (optional)
--- @return boolean, string Success status and error message
function Validation.ValidateItemSale(playerId, itemId, quantity, playerData)
    if not playerData then
        playerData = GetCnrPlayerData(playerId)
    end
    
    if not playerData or not playerData.inventory then
        return false, Constants.ERROR_MESSAGES.PLAYER_NOT_FOUND
    end
    
    local playerItem = playerData.inventory[itemId]
    if not playerItem or not playerItem.count then
        return false, Constants.ERROR_MESSAGES.INSUFFICIENT_ITEMS
    end
    
    if playerItem.count < quantity then
        return false, string.format("Insufficient items: have %d, need %d", playerItem.count, quantity)
    end
    
    return true, nil
end

-- ====================================================================
-- MONEY VALIDATION
-- ====================================================================

--- Validate money transaction
--- @param amount any Amount to validate
--- @param allowNegative boolean Whether negative amounts are allowed
--- @return boolean, number, string Success status, validated amount, and error message
function Validation.ValidateMoney(amount, allowNegative)
    local minAmount = allowNegative and -Constants.VALIDATION.MAX_MONEY_TRANSACTION or Constants.VALIDATION.MIN_MONEY_TRANSACTION
    local num = SafeToNumber(amount, minAmount, Constants.VALIDATION.MAX_MONEY_TRANSACTION, nil)
    
    if not num then
        return false, 0, "Invalid money amount"
    end
    
    return true, num, nil
end

--- Validate player has sufficient funds
--- @param playerId number Player ID
--- @param amount number Amount needed
--- @param playerData table Player data (optional)
--- @return boolean, string Success status and error message
function Validation.ValidatePlayerFunds(playerId, amount, playerData)
    if not playerData then
        playerData = GetCnrPlayerData(playerId)
    end
    
    if not playerData then
        return false, Constants.ERROR_MESSAGES.PLAYER_NOT_FOUND
    end
    
    local playerMoney = playerData.money or 0
    if playerMoney < amount then
        return false, string.format("Insufficient funds: have $%d, need $%d", playerMoney, amount)
    end
    
    return true, nil
end

-- ====================================================================
-- INVENTORY VALIDATION
-- ====================================================================

--- Validate inventory operation
--- @param playerId number Player ID
--- @param operation string Operation type
--- @return boolean, string Success status and error message
function Validation.ValidateInventoryOperation(playerId, operation)
    -- Rate limit inventory operations
    if not Validation.CheckRateLimit(playerId, "inventoryOps", 
        Constants.VALIDATION.MAX_INVENTORY_OPERATIONS_PER_SECOND, 
        Constants.TIME_MS.SECOND) then
        return false, Constants.ERROR_MESSAGES.RATE_LIMITED
    end
    
    local valid, error = Validation.ValidatePlayer(playerId)
    if not valid then return false, error end
    
    local validOperations = {"equip", "unequip", "use", "drop", "add", "remove"}
    local isValidOperation = false
    for _, validOp in ipairs(validOperations) do
        if operation == validOp then
            isValidOperation = true
            break
        end
    end
    
    if not isValidOperation then
        return false, "Invalid inventory operation: " .. tostring(operation)
    end
    
    return true, nil
end

--- Validate inventory has space for items
--- @param playerData table Player data
--- @param quantity number Quantity to add
--- @return boolean, string Success status and error message
function Validation.ValidateInventorySpace(playerData, quantity)
    if not playerData or not playerData.inventory then
        return false, Constants.ERROR_MESSAGES.PLAYER_NOT_FOUND
    end
    
    -- Calculate current inventory count
    local currentCount = 0
    for _, item in pairs(playerData.inventory) do
        currentCount = currentCount + (item.count or 0)
    end
    
    if (currentCount + quantity) > Constants.PLAYER_LIMITS.MAX_INVENTORY_SLOTS then
        return false, Constants.ERROR_MESSAGES.INVENTORY_FULL
    end
    
    return true, nil
end

-- ====================================================================
-- ADMIN VALIDATION
-- ====================================================================

--- Validate player has admin permissions
--- @param playerId number Player ID
--- @param requiredLevel number Required admin level (optional)
--- @return boolean, string Success status and error message
function Validation.ValidateAdminPermission(playerId, requiredLevel)
    local valid, error = Validation.ValidatePlayer(playerId)
    if not valid then return false, error end
    
    -- Use existing IsPlayerAdmin function
    if not IsPlayerAdmin(playerId) then
        return false, Constants.ERROR_MESSAGES.PERMISSION_DENIED
    end
    
    -- TODO: Implement admin levels if needed
    -- For now, just check if player is admin
    
    return true, nil
end

-- ====================================================================
-- EVENT VALIDATION
-- ====================================================================

--- Validate network event parameters
--- @param playerId number Player ID
--- @param eventName string Event name
--- @param params table Event parameters
--- @return boolean, string Success status and error message
function Validation.ValidateNetworkEvent(playerId, eventName, params)
    -- Rate limit general events
    if not Validation.CheckRateLimit(playerId, "events", 
        Constants.VALIDATION.MAX_EVENTS_PER_SECOND, 
        Constants.TIME_MS.SECOND) then
        return false, Constants.ERROR_MESSAGES.RATE_LIMITED
    end
    
    local valid, error = Validation.ValidatePlayer(playerId)
    if not valid then return false, error end
    
    local validError = ValidateString(eventName, Constants.VALIDATION.MAX_STRING_LENGTH, false)
    if not validError then
        return false, "Invalid event name"
    end
    
    if params and type(params) ~= "table" then
        return false, "Event parameters must be a table"
    end
    
    return true, nil
end

-- ====================================================================
-- VALIDATION CLEANUP FUNCTIONS
-- ====================================================================

--- Clean up validation data for disconnected player
--- @param playerId number Player ID
function Validation.CleanupPlayer(playerId)
    Validation.CleanupRateLimit(playerId)
end

--- Periodic cleanup of old rate limiting data
function Validation.PeriodicCleanup()
    local currentTime = GetGameTimer()
    local cleanupThreshold = 5 * Constants.TIME_MS.MINUTE -- 5 minutes
    
    for playerId, limits in pairs(rateLimits) do
        -- Check if player is still connected
        if not GetPlayerName(playerId) then
            rateLimits[playerId] = nil
        else
            -- Clean old entries for connected players
            for actionType, actions in pairs(limits) do
                for i = #actions, 1, -1 do
                    if currentTime - actions[i] > cleanupThreshold then
                        table.remove(actions, i)
                    end
                end
            end
        end
    end
end

-- Start periodic cleanup thread
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(Constants.TIME_MS.MINUTE) -- Run every minute
        Validation.PeriodicCleanup()
    end
end)

-- ====================================================================
-- DATA MANAGER SYSTEM (from data_manager.lua)
-- ====================================================================

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
-- DATA MANAGER UTILITY FUNCTIONS
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
-- DATA MANAGER INITIALIZATION AND CLEANUP
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

-- ====================================================================
-- SECURE TRANSACTIONS SYSTEM (from secure_transactions.lua)
-- ====================================================================

-- Initialize SecureTransactions module
SecureTransactions = SecureTransactions or {}

-- Transaction tracking
local activeTransactions = {}
local transactionHistory = {}

-- Statistics
local transactionStats = {
    totalTransactions = 0,
    successfulTransactions = 0,
    failedTransactions = 0,
    totalMoneyTransferred = 0,
    averageTransactionTime = 0
}

-- ====================================================================
-- TRANSACTION UTILITY FUNCTIONS
-- ====================================================================

--- Generate unique transaction ID
--- @return string Unique transaction ID
local function GenerateTransactionId()
    return string.format("txn_%d_%d", GetGameTimer(), math.random(100000, 999999))
end

--- Log transaction operations
--- @param playerId number Player ID
--- @param operation string Operation type
--- @param message string Log message
--- @param level string Log level
local function LogTransaction(playerId, operation, message, level)
    level = level or Constants.LOG_LEVELS.INFO
    local playerName = GetPlayerName(playerId) or "Unknown"
    
    if level == Constants.LOG_LEVELS.ERROR or level == Constants.LOG_LEVELS.WARN then
        print(string.format("[CNR_SECURE_TRANSACTIONS] [%s] Player %s (%d) - %s: %s", 
            string.upper(level), playerName, playerId, operation, message))
    end
end

--- Record transaction in history
--- @param transactionData table Transaction data
local function RecordTransaction(transactionData)
    table.insert(transactionHistory, transactionData)
    
    -- Keep only last 1000 transactions to prevent memory issues
    if #transactionHistory > 1000 then
        table.remove(transactionHistory, 1)
    end
end

-- ====================================================================
-- CORE TRANSACTION FUNCTIONS
-- ====================================================================

--- Process item purchase transaction
--- @param playerId number Player ID
--- @param itemId string Item ID
--- @param quantity number Quantity to purchase
--- @param storeType string Store type
--- @return boolean, string Success status and error message
function SecureTransactions.ProcessPurchase(playerId, itemId, quantity, storeType)
    local startTime = GetGameTimer()
    transactionStats.totalTransactions = transactionStats.totalTransactions + 1
    
    local transactionId = GenerateTransactionId()
    
    -- Validate inputs
    local valid, error = Validation.ValidatePlayer(playerId)
    if not valid then
        transactionStats.failedTransactions = transactionStats.failedTransactions + 1
        return false, error
    end
    
    local validItem, itemConfig, itemError = Validation.ValidateItem(itemId)
    if not validItem then
        transactionStats.failedTransactions = transactionStats.failedTransactions + 1
        return false, itemError
    end
    
    local validQuantity, validatedQuantity, quantityError = Validation.ValidateQuantity(quantity)
    if not validQuantity then
        transactionStats.failedTransactions = transactionStats.failedTransactions + 1
        return false, quantityError
    end
    
    -- Rate limit purchases
    if not Validation.CheckRateLimit(playerId, "purchases", 
        Constants.VALIDATION.MAX_PURCHASES_PER_MINUTE, 
        Constants.TIME_MS.MINUTE) then
        transactionStats.failedTransactions = transactionStats.failedTransactions + 1
        return false, Constants.ERROR_MESSAGES.RATE_LIMITED
    end
    
    -- Get player data
    local playerData = GetCnrPlayerData(playerId)
    if not playerData then
        transactionStats.failedTransactions = transactionStats.failedTransactions + 1
        return false, Constants.ERROR_MESSAGES.PLAYER_NOT_FOUND
    end
    
    -- Validate purchase
    local validPurchase, totalCost, purchaseError = Validation.ValidateItemPurchase(
        playerId, itemConfig, validatedQuantity, playerData)
    if not validPurchase then
        transactionStats.failedTransactions = transactionStats.failedTransactions + 1
        return false, purchaseError
    end
    
    -- Start transaction
    activeTransactions[transactionId] = {
        playerId = playerId,
        type = "purchase",
        itemId = itemId,
        quantity = validatedQuantity,
        cost = totalCost,
        startTime = startTime
    }
    
    -- Deduct money
    playerData.money = playerData.money - totalCost
    
    -- Add item to inventory
    local addSuccess, addError = SecureInventory.AddItem(playerId, itemId, validatedQuantity, "purchase")
    if not addSuccess then
        -- Rollback money deduction
        playerData.money = playerData.money + totalCost
        activeTransactions[transactionId] = nil
        transactionStats.failedTransactions = transactionStats.failedTransactions + 1
        return false, "Failed to add item to inventory: " .. addError
    end
    
    -- Complete transaction
    activeTransactions[transactionId] = nil
    transactionStats.successfulTransactions = transactionStats.successfulTransactions + 1
    transactionStats.totalMoneyTransferred = transactionStats.totalMoneyTransferred + totalCost
    
    -- Record transaction
    RecordTransaction({
        id = transactionId,
        playerId = playerId,
        type = "purchase",
        itemId = itemId,
        quantity = validatedQuantity,
        cost = totalCost,
        storeType = storeType,
        timestamp = os.time(),
        success = true
    })
    
    -- Save player data
    DataManager.MarkPlayerForSave(playerId)
    
    -- Update statistics
    local transactionTime = GetGameTimer() - startTime
    transactionStats.averageTransactionTime = (transactionStats.averageTransactionTime + transactionTime) / 2
    
    LogTransaction(playerId, "PURCHASE", 
        string.format("Purchased %d x %s for $%d", validatedQuantity, itemId, totalCost))
    
    return true, nil
end

--- Process item sale transaction
--- @param playerId number Player ID
--- @param itemId string Item ID
--- @param quantity number Quantity to sell
--- @return boolean, string Success status and error message
function SecureTransactions.ProcessSale(playerId, itemId, quantity)
    local startTime = GetGameTimer()
    transactionStats.totalTransactions = transactionStats.totalTransactions + 1
    
    local transactionId = GenerateTransactionId()
    
    -- Validate inputs
    local valid, error = Validation.ValidatePlayer(playerId)
    if not valid then
        transactionStats.failedTransactions = transactionStats.failedTransactions + 1
        return false, error
    end
    
    local validItem, itemConfig, itemError = Validation.ValidateItem(itemId)
    if not validItem then
        transactionStats.failedTransactions = transactionStats.failedTransactions + 1
        return false, itemError
    end
    
    local validQuantity, validatedQuantity, quantityError = Validation.ValidateQuantity(quantity)
    if not validQuantity then
        transactionStats.failedTransactions = transactionStats.failedTransactions + 1
        return false, quantityError
    end
    
    -- Get player data
    local playerData = GetCnrPlayerData(playerId)
    if not playerData then
        transactionStats.failedTransactions = transactionStats.failedTransactions + 1
        return false, Constants.ERROR_MESSAGES.PLAYER_NOT_FOUND
    end
    
    -- Validate sale
    local validSale, saleError = Validation.ValidateItemSale(playerId, itemId, validatedQuantity, playerData)
    if not validSale then
        transactionStats.failedTransactions = transactionStats.failedTransactions + 1
        return false, saleError
    end
    
    -- Calculate sale price (typically 50% of purchase price)
    local salePrice = math.floor((itemConfig.basePrice or 0) * validatedQuantity * 0.5)
    
    -- Start transaction
    activeTransactions[transactionId] = {
        playerId = playerId,
        type = "sale",
        itemId = itemId,
        quantity = validatedQuantity,
        price = salePrice,
        startTime = startTime
    }
    
    -- Remove item from inventory
    local removeSuccess, removeError = SecureInventory.RemoveItem(playerId, itemId, validatedQuantity, "sale")
    if not removeSuccess then
        activeTransactions[transactionId] = nil
        transactionStats.failedTransactions = transactionStats.failedTransactions + 1
        return false, "Failed to remove item from inventory: " .. removeError
    end
    
    -- Add money
    playerData.money = (playerData.money or 0) + salePrice
    
    -- Complete transaction
    activeTransactions[transactionId] = nil
    transactionStats.successfulTransactions = transactionStats.successfulTransactions + 1
    transactionStats.totalMoneyTransferred = transactionStats.totalMoneyTransferred + salePrice
    
    -- Record transaction
    RecordTransaction({
        id = transactionId,
        playerId = playerId,
        type = "sale",
        itemId = itemId,
        quantity = validatedQuantity,
        price = salePrice,
        timestamp = os.time(),
        success = true
    })
    
    -- Save player data
    DataManager.MarkPlayerForSave(playerId)
    
    -- Update statistics
    local transactionTime = GetGameTimer() - startTime
    transactionStats.averageTransactionTime = (transactionStats.averageTransactionTime + transactionTime) / 2
    
    LogTransaction(playerId, "SALE", 
        string.format("Sold %d x %s for $%d", validatedQuantity, itemId, salePrice))
    
    return true, nil
end

--- Transfer money between players
--- @param fromPlayerId number Source player ID
--- @param toPlayerId number Target player ID
--- @param amount number Amount to transfer
--- @param reason string Transfer reason
--- @return boolean, string Success status and error message
function SecureTransactions.TransferMoney(fromPlayerId, toPlayerId, amount, reason)
    local startTime = GetGameTimer()
    transactionStats.totalTransactions = transactionStats.totalTransactions + 1
    
    local transactionId = GenerateTransactionId()
    
    -- Validate inputs
    local validFrom, errorFrom = Validation.ValidatePlayer(fromPlayerId)
    if not validFrom then
        transactionStats.failedTransactions = transactionStats.failedTransactions + 1
        return false, errorFrom
    end
    
    local validTo, errorTo = Validation.ValidatePlayer(toPlayerId)
    if not validTo then
        transactionStats.failedTransactions = transactionStats.failedTransactions + 1
        return false, errorTo
    end
    
    local validAmount, validatedAmount, amountError = Validation.ValidateMoney(amount, false)
    if not validAmount then
        transactionStats.failedTransactions = transactionStats.failedTransactions + 1
        return false, amountError
    end
    
    -- Prevent self-transfer
    if fromPlayerId == toPlayerId then
        transactionStats.failedTransactions = transactionStats.failedTransactions + 1
        return false, "Cannot transfer money to yourself"
    end
    
    -- Get player data
    local fromPlayerData = GetCnrPlayerData(fromPlayerId)
    local toPlayerData = GetCnrPlayerData(toPlayerId)
    
    if not fromPlayerData or not toPlayerData then
        transactionStats.failedTransactions = transactionStats.failedTransactions + 1
        return false, Constants.ERROR_MESSAGES.PLAYER_NOT_FOUND
    end
    
    -- Validate sender has sufficient funds
    local validFunds, fundsError = Validation.ValidatePlayerFunds(fromPlayerId, validatedAmount, fromPlayerData)
    if not validFunds then
        transactionStats.failedTransactions = transactionStats.failedTransactions + 1
        return false, fundsError
    end
    
    -- Start transaction
    activeTransactions[transactionId] = {
        fromPlayerId = fromPlayerId,
        toPlayerId = toPlayerId,
        type = "transfer",
        amount = validatedAmount,
        reason = reason,
        startTime = startTime
    }
    
    -- Transfer money
    fromPlayerData.money = fromPlayerData.money - validatedAmount
    toPlayerData.money = (toPlayerData.money or 0) + validatedAmount
    
    -- Complete transaction
    activeTransactions[transactionId] = nil
    transactionStats.successfulTransactions = transactionStats.successfulTransactions + 1
    transactionStats.totalMoneyTransferred = transactionStats.totalMoneyTransferred + validatedAmount
    
    -- Record transaction
    RecordTransaction({
        id = transactionId,
        fromPlayerId = fromPlayerId,
        toPlayerId = toPlayerId,
        type = "transfer",
        amount = validatedAmount,
        reason = reason,
        timestamp = os.time(),
        success = true
    })
    
    -- Save both players' data
    DataManager.MarkPlayerForSave(fromPlayerId)
    DataManager.MarkPlayerForSave(toPlayerId)
    
    -- Update statistics
    local transactionTime = GetGameTimer() - startTime
    transactionStats.averageTransactionTime = (transactionStats.averageTransactionTime + transactionTime) / 2
    
    LogTransaction(fromPlayerId, "TRANSFER_OUT", 
        string.format("Transferred $%d to player %d (%s)", validatedAmount, toPlayerId, reason or "no reason"))
    LogTransaction(toPlayerId, "TRANSFER_IN", 
        string.format("Received $%d from player %d (%s)", validatedAmount, fromPlayerId, reason or "no reason"))
    
    return true, nil
end

--- Get transaction statistics
--- @return table Transaction statistics
function SecureTransactions.GetStats()
    return {
        totalTransactions = transactionStats.totalTransactions,
        successfulTransactions = transactionStats.successfulTransactions,
        failedTransactions = transactionStats.failedTransactions,
        successRate = transactionStats.totalTransactions > 0 and 
            (transactionStats.successfulTransactions / transactionStats.totalTransactions * 100) or 0,
        totalMoneyTransferred = transactionStats.totalMoneyTransferred,
        averageTransactionTime = transactionStats.averageTransactionTime,
        activeTransactions = tablelength(activeTransactions)
    }
end

--- Initialize secure transactions system
function SecureTransactions.Initialize()
    print("[CNR_SECURE_TRANSACTIONS] Secure Transactions System initialized")
    
    -- Statistics logging thread
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(15 * Constants.TIME_MS.MINUTE) -- Every 15 minutes
            local stats = SecureTransactions.GetStats()
            print(string.format("[CNR_SECURE_TRANSACTIONS] Stats - Total: %d, Success: %d, Failed: %d, Success Rate: %.1f%%, Money: $%d",
                stats.totalTransactions, stats.successfulTransactions, stats.failedTransactions, 
                stats.successRate, stats.totalMoneyTransferred))
        end
    end)
end

--- Cleanup transaction data for disconnected player
--- @param playerId number Player ID
function SecureTransactions.CleanupPlayer(playerId)
    -- Remove any active transactions for this player
    for transactionId, transaction in pairs(activeTransactions) do
        if transaction.playerId == playerId or transaction.fromPlayerId == playerId or transaction.toPlayerId == playerId then
            activeTransactions[transactionId] = nil
        end
    end
end

-- Initialize when loaded
SecureTransactions.Initialize()

-- ====================================================================
-- PLAYER MANAGER SYSTEM (from player_manager.lua)
-- ====================================================================

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
-- PLAYER MANAGER UTILITY FUNCTIONS
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
            TriggerClientEvent('cnr:syncInventory', playerId, 
                MinimizeInventoryForSync(inventory))
        end
    end
    
    -- Send other player data
    TriggerClientEvent('cnr:updatePlayerData', playerId, {
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
        TriggerClientEvent('cnr:showNotification', playerId, 
            string.format("Role changed to %s", role), "success")
    end
    
    LogPlayerManager(playerId, "set_role", 
        string.format("Role changed from %s to %s", oldRole, role))
    
    return true
end

--- Get player statistics
--- @return table Player manager statistics
function PlayerManager.GetStats()
    return {
        totalLoads = playerStats.totalLoads,
        totalSaves = playerStats.totalSaves,
        failedLoads = playerStats.failedLoads,
        failedSaves = playerStats.failedSaves,
        loadSuccessRate = playerStats.totalLoads > 0 and ((playerStats.totalLoads - playerStats.failedLoads) / playerStats.totalLoads * 100) or 0,
        saveSuccessRate = playerStats.totalSaves > 0 and ((playerStats.totalSaves - playerStats.failedSaves) / playerStats.totalSaves * 100) or 0,
        averageLoadTime = playerStats.averageLoadTime,
        averageSaveTime = playerStats.averageSaveTime,
        activePlayers = tablelength(playerDataCache),
        loadingPlayers = tablelength(playerLoadingStates)
    }
end

--- Log current statistics
function PlayerManager.LogStats()
    local stats = PlayerManager.GetStats()
    print(string.format("[CNR_PLAYER_MANAGER] Stats - Loads: %d (%.1f%% success), Saves: %d (%.1f%% success), Active: %d",
        stats.totalLoads, stats.loadSuccessRate, stats.totalSaves, stats.saveSuccessRate, stats.activePlayers))
end

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

-- Update the global GetCnrPlayerData function to use PlayerManager
function GetCnrPlayerData(playerId)
    local playerData, success = PlayerManager.GetPlayerData(playerId)
    return success and playerData or nil
end

-- ====================================================================
-- PERFORMANCE OPTIMIZER SYSTEM (from performance_optimizer.lua)
-- ====================================================================

-- Initialize PerformanceOptimizer module
PerformanceOptimizer = PerformanceOptimizer or {}

-- Performance monitoring data
local performanceMetrics = {
    frameTime = 0,
    memoryUsage = 0,
    activeThreads = 0,
    networkEvents = 0,
    lastUpdate = 0
}

-- Optimized loop management
local optimizedLoops = {}
local loopCounter = 0

-- Event batching system
local eventBatches = {}
local batchTimers = {}

-- ====================================================================
-- LOOP OPTIMIZATION SYSTEM
-- ====================================================================

--- Adjust loop interval based on performance metrics
--- @param loopData table Loop data structure
--- @param lastExecutionTime number Last execution time in milliseconds
local function AdjustLoopInterval(loopData, lastExecutionTime)
    -- If execution time is high, increase interval
    if lastExecutionTime > Constants.PERFORMANCE.MAX_EXECUTION_TIME_MS then
        loopData.currentInterval = math.min(loopData.currentInterval * 1.2, loopData.maxInterval)
    -- If execution time is low and we're not at base interval, decrease it
    elseif lastExecutionTime < Constants.PERFORMANCE.MAX_EXECUTION_TIME_MS * 0.5 and 
           loopData.currentInterval > loopData.baseInterval then
        loopData.currentInterval = math.max(loopData.currentInterval * 0.9, loopData.baseInterval)
    end
    
    -- Priority-based adjustments
    if loopData.priority <= 2 then
        -- High priority loops get preference
        loopData.currentInterval = math.max(loopData.currentInterval * 0.8, loopData.baseInterval)
    elseif loopData.priority >= 4 then
        -- Low priority loops get throttled more aggressively
        loopData.currentInterval = math.min(loopData.currentInterval * 1.5, loopData.maxInterval)
    end
end

--- Create an optimized loop that automatically adjusts its interval based on performance
--- @param callback function Function to execute
--- @param baseInterval number Base interval in milliseconds
--- @param maxInterval number Maximum interval in milliseconds
--- @param priority number Priority level (1-5, 1 being highest)
--- @return number Loop ID for management
function PerformanceOptimizer.CreateOptimizedLoop(callback, baseInterval, maxInterval, priority)
    loopCounter = loopCounter + 1
    priority = priority or 3
    maxInterval = maxInterval or baseInterval * 5
    
    local loopData = {
        id = loopCounter,
        callback = callback,
        baseInterval = baseInterval,
        maxInterval = maxInterval,
        currentInterval = baseInterval,
        priority = priority,
        lastExecution = 0,
        executionCount = 0,
        totalExecutionTime = 0,
        averageExecutionTime = 0,
        active = true
    }
    
    optimizedLoops[loopCounter] = loopData
    
    -- Start the loop thread
    Citizen.CreateThread(function()
        while loopData.active do
            local startTime = GetGameTimer()
            
            -- Execute callback with error handling
            local success, error = pcall(callback)
            if not success then
                print(string.format("[CNR_PERFORMANCE] Loop %d error: %s", loopData.id, tostring(error)))
            end
            
            -- Update performance metrics
            local executionTime = GetGameTimer() - startTime
            loopData.executionCount = loopData.executionCount + 1
            loopData.totalExecutionTime = loopData.totalExecutionTime + executionTime
            loopData.averageExecutionTime = loopData.totalExecutionTime / loopData.executionCount
            loopData.lastExecution = startTime
            
            -- Adjust interval based on performance
            AdjustLoopInterval(loopData, executionTime)
            
            Citizen.Wait(loopData.currentInterval)
        end
    end)
    
    print(string.format("[CNR_PERFORMANCE] Created optimized loop %d (base: %dms, max: %dms, priority: %d)", 
        loopCounter, baseInterval, maxInterval, priority))
    
    return loopCounter
end

--- Stop an optimized loop
--- @param loopId number Loop ID to stop
function PerformanceOptimizer.StopOptimizedLoop(loopId)
    if optimizedLoops[loopId] then
        optimizedLoops[loopId].active = false
        optimizedLoops[loopId] = nil
        print(string.format("[CNR_PERFORMANCE] Stopped optimized loop %d", loopId))
    end
end

-- ====================================================================
-- EVENT BATCHING SYSTEM
-- ====================================================================

--- Batch events to reduce network overhead
--- @param eventName string Event name
--- @param playerId number Player ID (or -1 for all players)
--- @param data any Event data
--- @param batchInterval number Batching interval in milliseconds
function PerformanceOptimizer.BatchEvent(eventName, playerId, data, batchInterval)
    batchInterval = batchInterval or 100 -- Default 100ms batching
    
    local batchKey = string.format("%s_%s", eventName, tostring(playerId))
    
    -- Initialize batch if it doesn't exist
    if not eventBatches[batchKey] then
        eventBatches[batchKey] = {
            eventName = eventName,
            playerId = playerId,
            data = {},
            count = 0
        }
    end
    
    -- Add data to batch
    table.insert(eventBatches[batchKey].data, data)
    eventBatches[batchKey].count = eventBatches[batchKey].count + 1
    
    -- Set timer if not already set
    if not batchTimers[batchKey] then
        batchTimers[batchKey] = Citizen.SetTimeout(batchInterval, function()
            PerformanceOptimizer.FlushEventBatch(batchKey)
        end)
    end
end

--- Flush a specific event batch
--- @param batchKey string Batch key
function PerformanceOptimizer.FlushEventBatch(batchKey)
    local batch = eventBatches[batchKey]
    if not batch or batch.count == 0 then
        return
    end
    
    -- Send batched event
    if batch.playerId == -1 then
        -- Send to all players
        TriggerClientEvent(batch.eventName, -1, batch.data)
    else
        -- Send to specific player
        TriggerClientEvent(batch.eventName, batch.playerId, batch.data)
    end
    
    -- Clean up
    eventBatches[batchKey] = nil
    batchTimers[batchKey] = nil
    
    print(string.format("[CNR_PERFORMANCE] Flushed batch %s with %d events", batchKey, batch.count))
end

--- Flush all event batches immediately
function PerformanceOptimizer.FlushAllBatches()
    for batchKey, _ in pairs(eventBatches) do
        PerformanceOptimizer.FlushEventBatch(batchKey)
    end
end

-- ====================================================================
-- MEMORY OPTIMIZATION
-- ====================================================================

--- Optimize table memory usage by removing nil values and compacting
--- @param tbl table Table to optimize
--- @return table Optimized table
function PerformanceOptimizer.OptimizeTable(tbl)
    if type(tbl) ~= "table" then
        return tbl
    end
    
    local optimized = {}
    for k, v in pairs(tbl) do
        if v ~= nil then
            if type(v) == "table" then
                optimized[k] = PerformanceOptimizer.OptimizeTable(v)
            else
                optimized[k] = v
            end
        end
    end
    
    return optimized
end

--- Clean up unused references and force garbage collection
function PerformanceOptimizer.CleanupMemory()
    -- Clean up optimized loops that are no longer active
    for loopId, loopData in pairs(optimizedLoops) do
        if not loopData.active then
            optimizedLoops[loopId] = nil
        end
    end
    
    -- Clean up old event batches
    local currentTime = GetGameTimer()
    for batchKey, timer in pairs(batchTimers) do
        if currentTime - timer > 5000 then -- 5 second timeout
            eventBatches[batchKey] = nil
            batchTimers[batchKey] = nil
        end
    end
    
    -- Force garbage collection
    collectgarbage("collect")
    
    print("[CNR_PERFORMANCE] Memory cleanup completed")
end

-- ====================================================================
-- PERFORMANCE MONITORING
-- ====================================================================

--- Update performance metrics
local function UpdatePerformanceMetrics()
    performanceMetrics.lastUpdate = GetGameTimer()
    performanceMetrics.activeThreads = tablelength(optimizedLoops)
    
    -- Calculate memory usage (approximation)
    local memBefore = collectgarbage("count")
    collectgarbage("collect")
    local memAfter = collectgarbage("count")
    performanceMetrics.memoryUsage = memAfter
    
    -- Restore memory state
    collectgarbage("restart")
end

--- Get current performance metrics
--- @return table Performance metrics
function PerformanceOptimizer.GetMetrics()
    UpdatePerformanceMetrics()
    return {
        frameTime = performanceMetrics.frameTime,
        memoryUsage = performanceMetrics.memoryUsage,
        activeThreads = performanceMetrics.activeThreads,
        networkEvents = performanceMetrics.networkEvents,
        lastUpdate = performanceMetrics.lastUpdate,
        optimizedLoops = tablelength(optimizedLoops),
        eventBatches = tablelength(eventBatches)
    }
end

--- Log performance statistics
function PerformanceOptimizer.LogStats()
    local metrics = PerformanceOptimizer.GetMetrics()
    print(string.format("[CNR_PERFORMANCE] Stats - Memory: %.1fKB, Threads: %d, Loops: %d, Batches: %d",
        metrics.memoryUsage, metrics.activeThreads, metrics.optimizedLoops, metrics.eventBatches))
    
    -- Log individual loop performance
    for loopId, loopData in pairs(optimizedLoops) do
        if loopData.executionCount > 0 then
            print(string.format("[CNR_PERFORMANCE] Loop %d - Avg: %.1fms, Count: %d, Interval: %dms",
                loopId, loopData.averageExecutionTime, loopData.executionCount, loopData.currentInterval))
        end
    end
end

--- Check for performance warnings
function PerformanceOptimizer.CheckPerformanceWarnings()
    local metrics = PerformanceOptimizer.GetMetrics()
    
    -- Memory warning
    if metrics.memoryUsage > Constants.PERFORMANCE.MEMORY_WARNING_THRESHOLD_MB * 1024 then
        print(string.format("[CNR_PERFORMANCE] WARNING: High memory usage: %.1fMB", 
            metrics.memoryUsage / 1024))
        PerformanceOptimizer.CleanupMemory()
    end
    
    -- Loop performance warnings
    for loopId, loopData in pairs(optimizedLoops) do
        if loopData.averageExecutionTime > Constants.PERFORMANCE.MAX_EXECUTION_TIME_MS then
            print(string.format("[CNR_PERFORMANCE] WARNING: Loop %d slow execution: %.1fms average",
                loopId, loopData.averageExecutionTime))
        end
    end
end

-- ====================================================================
-- OPTIMIZED REPLACEMENTS FOR COMMON PATTERNS
-- ====================================================================

--- Optimized player iteration with early exit and batching
--- @param callback function Function to call for each player
--- @param batchSize number Number of players to process per frame
function PerformanceOptimizer.ForEachPlayerOptimized(callback, batchSize)
    batchSize = batchSize or 10
    local players = GetPlayers()
    local currentBatch = 0
    
    Citizen.CreateThread(function()
        for i, playerId in ipairs(players) do
            -- Validate player is still online
            if GetPlayerName(playerId) then
                local success, error = pcall(callback, tonumber(playerId))
                if not success then
                    print(string.format("[CNR_PERFORMANCE] Player iteration error for %s: %s", 
                        playerId, tostring(error)))
                end
            end
            
            currentBatch = currentBatch + 1
            
            -- Yield every batchSize players to prevent frame drops
            if currentBatch >= batchSize then
                currentBatch = 0
                Citizen.Wait(0)
            end
        end
    end)
end

--- Optimized distance checking with caching
local distanceCache = {}
local distanceCacheTime = {}

function PerformanceOptimizer.GetDistanceCached(pos1, pos2, cacheTime)
    cacheTime = cacheTime or 1000 -- 1 second cache by default
    
    local cacheKey = string.format("%.1f_%.1f_%.1f_%.1f_%.1f_%.1f", 
        pos1.x, pos1.y, pos1.z, pos2.x, pos2.y, pos2.z)
    
    local currentTime = GetGameTimer()
    
    -- Check cache
    if distanceCache[cacheKey] and 
       distanceCacheTime[cacheKey] and 
       (currentTime - distanceCacheTime[cacheKey]) < cacheTime then
        return distanceCache[cacheKey]
    end
    
    -- Calculate distance
    local distance = #(pos1 - pos2)
    
    -- Cache result
    distanceCache[cacheKey] = distance
    distanceCacheTime[cacheKey] = currentTime
    
    return distance
end

--- Clean distance cache periodically
local function CleanDistanceCache()
    local currentTime = GetGameTimer()
    local cleanupThreshold = 5000 -- 5 seconds
    
    for cacheKey, cacheTime in pairs(distanceCacheTime) do
        if (currentTime - cacheTime) > cleanupThreshold then
            distanceCache[cacheKey] = nil
            distanceCacheTime[cacheKey] = nil
        end
    end
end

-- ====================================================================
-- PERFORMANCE OPTIMIZER INITIALIZATION AND CLEANUP
-- ====================================================================

--- Initialize performance optimizer
function PerformanceOptimizer.Initialize()
    print("[CNR_PERFORMANCE] Performance Optimizer initialized")
    
    -- Create monitoring loop
    PerformanceOptimizer.CreateOptimizedLoop(function()
        PerformanceOptimizer.CheckPerformanceWarnings()
    end, 30000, 60000, 4) -- Low priority, 30s base interval
    
    -- Create cleanup loop
    PerformanceOptimizer.CreateOptimizedLoop(function()
        PerformanceOptimizer.CleanupMemory()
        CleanDistanceCache()
    end, 60000, 120000, 5) -- Lowest priority, 1 minute base interval
    
    -- Create stats logging loop
    PerformanceOptimizer.CreateOptimizedLoop(function()
        PerformanceOptimizer.LogStats()
    end, 300000, 600000, 5) -- Lowest priority, 5 minute base interval
end

--- Cleanup on resource stop
function PerformanceOptimizer.Cleanup()
    print("[CNR_PERFORMANCE] Cleaning up performance optimizer...")
    
    -- Stop all optimized loops
    for loopId, _ in pairs(optimizedLoops) do
        PerformanceOptimizer.StopOptimizedLoop(loopId)
    end
    
    -- Flush all event batches
    PerformanceOptimizer.FlushAllBatches()
    
    -- Final memory cleanup
    PerformanceOptimizer.CleanupMemory()
    
    print("[CNR_PERFORMANCE] Performance optimizer cleanup completed")
end

-- Initialize when loaded
PerformanceOptimizer.Initialize()

-- ====================================================================
-- INTEGRATION MANAGER SYSTEM (from integration_manager.lua)
-- ====================================================================

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


>>>>>>> Stashed changes

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

-- Helper function to get player identifiers safely
local function GetSafePlayerIdentifiers(playerId)
    return GetPlayerIdentifiers(playerId)
end

-- Function to check if a player is an admin
function IsPlayerAdmin(playerId)
    local playerIdentifiers = GetSafePlayerIdentifiers(playerId)
    if not playerIdentifiers then return false end

    -- Ensure Config and Config.Admins are loaded and available
    if not Config or type(Config.Admins) ~= "table" then
        print("Error: Config.Admins is not loaded or not a table. Ensure config.lua defines it correctly.")
        return false
    end

    for _, identifier in ipairs(playerIdentifiers) do
        -- Check if the player's identifier exists as a key in the Config.Admins table
        if Config.Admins[identifier] then
            return true
        end
    end
    return false
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

-- Safe wrapper for TriggerClientEvent to prevent nil player ID errors
local function SafeTriggerClientEvent(eventName, playerId, ...)
    if playerId and type(playerId) == "number" and playerId > 0 and GetPlayerName(playerId) then
        TriggerClientEvent(eventName, playerId, ...)
        return true
    else
        Log(string.format("SafeTriggerClientEvent: Invalid or offline player ID %s for event %s", tostring(playerId), eventName), "warn")
        return false
    end
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
            Log("Loaded " .. tablelength(loaded) .. " bans from bans.json")
        else
            Log("Failed to decode bans.json: " .. tostring(loaded), "error")
        end
    else
        Log("bans.json not found. Only using bans from Config.BannedPlayers.")
    end
end

local function SaveBans()
    local success = SaveResourceFile(GetCurrentResourceName(), "bans.json", json.encode(bannedPlayers), -1)
    if success then
        Log("Saved bans to bans.json")
    else
        Log("Failed to save bans.json", "error")
    end
end

-- Function to load purchase history from purchase_history.json
local function LoadPurchaseHistory()
    local historyFile = LoadResourceFile(GetCurrentResourceName(), "purchase_history.json")
    if historyFile then
        local success, loaded = pcall(json.decode, historyFile)
        if success and type(loaded) == "table" then
            purchaseHistory = loaded
            Log("Loaded purchase history from purchase_history.json. Count: " .. tablelength(purchaseHistory))
        else
            Log("Failed to decode purchase_history.json: " .. tostring(loaded), "error")
            purchaseHistory = {} -- Start fresh if file is corrupt
        end
    else
        Log("purchase_history.json not found. Initializing empty history.")
        purchaseHistory = {}
    end
end

local function SavePurchaseHistory()
    if not Config.DynamicEconomy or not Config.DynamicEconomy.enabled then return end -- Only save if enabled
    local success = SaveResourceFile(GetCurrentResourceName(), "purchase_history.json", json.encode(purchaseHistory), -1)
    if success then
        Log("Saved purchase history to purchase_history.json")
    else
        Log("Failed to save purchase_history.json", "error")
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
        Log(string.format("AddPlayerMoney: Invalid player ID %s.", tostring(playerId)), "error")
        return false
    end

    local pData = playersData[pId]
    if pData then
        if type == 'cash' then
            pData.money = (pData.money or 0) + amount
            Log(string.format("Added %d to player %s's %s account. New balance: %d", amount, playerId, type, pData.money))
            -- Send a notification to the client
            SafeTriggerClientEvent('chat:addMessage', pId, { args = {"^2Money", string.format("You received $%d.", amount)} })
            local pDataForBasicInfo = shallowcopy(pData)
            pDataForBasicInfo.inventory = nil
            SafeTriggerClientEvent('cnr:updatePlayerData', pId, pDataForBasicInfo)
            -- Inventory is not changed by this function, so no need to send cnr:syncInventory
            return true
        else
            Log(string.format("AddPlayerMoney: Unsupported account type '%s' for player %s.", type, playerId), "warn")
            return false
        end
    else
        Log(string.format("AddPlayerMoney: Player data not found for %s.", playerId), "error")
        return false
    end
end

-- Export AddPlayerMoney for potential use by other resources (if needed)
_G.AddPlayerMoney = AddPlayerMoney

-- Function to add XP to a player
local function AddPlayerXP(playerId, amount)
    local pId = tonumber(playerId)
    if not pId or pId <= 0 then
        Log(string.format("AddPlayerXP: Invalid player ID %s.", tostring(playerId)), "error")
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
        Log(string.format("AddPlayerXP: Player data not found for %s.", pId), "error")
        return false
    end
end

-- Export AddPlayerXP for potential use by other resources
_G.AddPlayerXP = AddPlayerXP

local function RemovePlayerMoney(playerId, amount, type)
    type = type or 'cash'
    local pId = tonumber(playerId)
    if not pId or pId <= 0 then
        Log(string.format("RemovePlayerMoney: Invalid player ID %s.", tostring(playerId)), "error")
        return false
    end

    local pData = playersData[pId]
    if pData then
        if type == 'cash' then
            if (pData.money or 0) >= amount then
                pData.money = pData.money - amount
                Log(string.format("Removed %d from player %s's %s account. New balance: %d", amount, playerId, type, pData.money))
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
            Log(string.format("RemovePlayerMoney: Unsupported account type '%s' for player %s.", type, playerId), "warn")
            return false
        end
    else
        Log(string.format("RemovePlayerMoney: Player data not found for %s.", playerId), "error")
        return false
    end
end

local function IsAdmin(playerId)
    local src = tonumber(playerId) -- Ensure it is a number for GetPlayerIdentifiers
    if not src then return false end

    local identifiers = GetPlayerIdentifiers(tostring(src))
    if not identifiers then return false end

    if not Config or type(Config.Admins) ~= "table" then
        Log("IsAdmin Check: Config.Admins is not loaded or not a table.", "error")
        return false -- Should not happen if Config.lua is correct
    end

    for _, identifier in ipairs(identifiers) do
        if Config.Admins[identifier] then
            Log("IsAdmin Check: Player " .. src .. " with identifier " .. identifier .. " IS an admin.", "info")
            return true
        end
    end
    Log("IsAdmin Check: Player " .. src .. " is NOT an admin.", "info")
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
        Log(string.format("DynamicPrice: Item %s popular (%d purchases), price increased to %d from %d", itemId, recentPurchases, price, basePrice))
    elseif recentPurchases < (Config.DynamicEconomy.popularityThresholdLow or 2) then
        price = math.floor(basePrice * (Config.DynamicEconomy.priceDecreaseFactor or 0.8))
        Log(string.format("DynamicPrice: Item %s unpopular (%d purchases), price decreased to %d from %d", itemId, recentPurchases, price, basePrice))
    else
        Log(string.format("DynamicPrice: Item %s normal popularity (%d purchases), price remains %d", itemId, recentPurchases, price))
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
        Log("InitializePlayerInventory: pData is nil for playerId " .. (playerId or "unknown"), "error")
        return
    end
    pData.inventory = pData.inventory or {}
    -- Log("InitializePlayerInventory: Ensured inventory table exists for player " .. (playerId or "unknown"), "info")
end

LoadPlayerData = function(playerId)
    -- Log(string.format("LoadPlayerData: Called for player ID %s.", playerId), "info")
    local pIdNum = tonumber(playerId)
    if not pIdNum or pIdNum <= 0 then
        Log(string.format("LoadPlayerData: Invalid player ID %s", tostring(playerId)), "error")
        return
    end

    -- Check if player is still online
    if not GetPlayerName(pIdNum) then
        Log(string.format("LoadPlayerData: Player %s is not online", pIdNum), "warn")
        return
    end

    -- Log(string.format("LoadPlayerData: Attempting to get license for player %s.", pIdNum), "info")
    local license = GetPlayerLicense(pIdNum) -- Use helper to get license

    local filename = nil
    if license then
        filename = "player_data/" .. license:gsub(":", "") .. ".json"
    else
        Log(string.format("LoadPlayerData: CRITICAL - Could not find license for player %s (Name: %s) even after playerConnecting. Attempting PID fallback (pid_%s.json), but this may lead to data inconsistencies or load failures if server IDs are not static.", pIdNum, GetPlayerName(pIdNum) or "N/A", pIdNum), "error")
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
            Log("Loaded player data for " .. pIdNum .. " from " .. filename .. ". Level: " .. (data.level or 0) .. ", Role: " .. (data.role or "citizen") .. ", Money: " .. loadedMoney)
        else
            Log("Failed to decode player data for " .. pIdNum .. " from " .. filename .. ". Using defaults. Error: " .. tostring(data), "error")
            playersData[pIdNum] = nil -- Force default initialization
        end
    else
        Log("No save file found for " .. pIdNum .. " at " .. filename .. ". Initializing default data.")
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
        Log("Initialized default data for player " .. pIdNum .. ". Money: " .. playersData[pIdNum].money .. ", Default inventory added.")
    else
        -- Ensure money is set if loaded from file, otherwise use default (already handled by loadedMoney init)
        playersData[pIdNum].money = playersData[pIdNum].money or Config.DefaultStartMoney or 5000
    end

    -- NEW PLACEMENT FOR isDataLoaded
    if playersData[pIdNum] then
        playersData[pIdNum].isDataLoaded = true
        Log("LoadPlayerData: Player data structure populated and isDataLoaded set to true for " .. pIdNum .. ".") -- Combined log
    else
        Log("LoadPlayerData: CRITICAL - playersData[pIdNum] is nil AFTER data load/init attempt for " .. pIdNum .. ". Cannot set isDataLoaded or proceed.", "error")
        return -- Cannot proceed if playersData[pIdNum] is still nil here
    end

    -- Now call functions that might rely on isDataLoaded or a fully ready player object
    SetPlayerRole(pIdNum, playersData[pIdNum].role, true)
    ApplyPerks(pIdNum, playersData[pIdNum].level, playersData[pIdNum].role)

    -- Log(string.format("LoadPlayerData: About to call InitializePlayerInventory for player %s.", pIdNum), "info")
    if playersData[pIdNum] then -- Re-check pData as ApplyPerks or SetPlayerRole might have side effects (though unlikely to nil it)
        InitializePlayerInventory(playersData[pIdNum], pIdNum)
    else
        Log("LoadPlayerData: CRITICAL - playersData[pIdNum] became nil before InitializePlayerInventory for " .. pIdNum, "error")
    end

local pDataForLoad = shallowcopy(playersData[pIdNum])
    pDataForLoad.inventory = nil
    SafeTriggerClientEvent('cnr:updatePlayerData', pIdNum, pDataForLoad)
    
    -- Send config items first so client can properly reconstruct inventory
    if Config and Config.Items and type(Config.Items) == "table" then
        SafeTriggerClientEvent('cnr:receiveConfigItems', pIdNum, Config.Items)
        Log(string.format("Sent Config.Items to player %s during load", pIdNum), "info")
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
        ), "info")

        if calculatedRemainingTime > 0 then
            jail[pIdNum] = {
                startTime = os.time(), -- Current login time becomes the new reference for this session's server-side tick
                duration = pData.jailData.originalDuration, -- Always use the original full duration
                remainingTime = calculatedRemainingTime, -- The actual time left to serve
                arrestingOfficer = pData.jailData.jailedByOfficer or "System (Rejoin)"
            }
            SafeTriggerClientEvent('cnr:sendToJail', pIdNum, calculatedRemainingTime, Config.PrisonLocation)
            Log(string.format("Player %s re-jailed upon loading data. Calculated Remaining: %ds", pIdNum, calculatedRemainingTime), "info")
            SafeTriggerClientEvent('chat:addMessage', pIdNum, { args = {"^1Jail", string.format("You are still jailed. Time remaining: %d seconds.", calculatedRemainingTime)} })
        else
            Log(string.format("Player %s jail time expired while offline or on load. Original Duration: %ds, Total Elapsed: %ds", pIdNum, pData.jailData.originalDuration, totalTimeElapsedSinceJailing), "info")
            pData.jailData = nil -- Clear expired jail data
        end
    elseif pData and pData.jailData then -- If jailData exists but is incomplete (e.g., missing originalDuration or jailedTimestamp) or remainingTime was already <=0
        Log(string.format("Player %s had incomplete or already expired jailData. Clearing. Data: %s", pIdNum, json.encode(pData.jailData)), "warn")
        pData.jailData = nil -- Clean up old/completed/invalid jail data
    end
    -- Original position of isDataLoaded setting is now removed.
end

SavePlayerData = function(playerId)
    local pIdNum = tonumber(playerId)
    local pData = GetCnrPlayerData(pIdNum)
    if not pData then
        Log("SavePlayerData: No data for player " .. pIdNum, "warn")
        return
    end

    local license = GetPlayerLicense(pIdNum) -- Use helper

    if not license then
        Log("SavePlayerData: Could not find license for player " .. pIdNum .. ". Using numeric ID as fallback filename. Data might not persist correctly across sessions if ID changes.", "warn")
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
        Log("Saved player data for " .. pIdNum .. " to " .. filename .. ".")
    else
        Log("Failed to save player data for " .. pIdNum .. " to " .. filename .. ".", "error")
    end
end

SetPlayerRole = function(playerId, role, skipNotify)
    local pIdNum = tonumber(playerId)
    if not pIdNum or pIdNum <= 0 then
        Log(string.format("SetPlayerRole: Invalid player ID %s", tostring(playerId)), "error")
        return
    end

    -- Check if player is still online
    if not GetPlayerName(pIdNum) then
        Log(string.format("SetPlayerRole: Player %s is not online", pIdNum), "warn")
        return
    end

    local playerName = GetPlayerName(pIdNum) or "Unknown"
    -- Log(string.format("SetPlayerRole DEBUG: Attempting to set role for pIdNum: %s, playerName: %s, to newRole: %s. Current role in playersData: %s", pIdNum, playerName, role, (playersData[pIdNum] and playersData[pIdNum].role or "nil_or_no_pData")), "info")

    local pData = playersData[pIdNum] -- Get pData directly
    if not pData or not pData.isDataLoaded then -- Check both for robustness
        Log(string.format("SetPlayerRole: Attempted to set role for %s (Name: %s) but data not loaded/ready. Role: %s. pData exists: %s, isDataLoaded: %s. This should have been caught by the caller.", pIdNum, playerName, role, tostring(pData ~= nil), tostring(pData and pData.isDataLoaded)), "warn")
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
            Log(string.format("Cleared wanted level for player %s who switched to cop role", pIdNum), "info")
            
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
        Log("Player " .. pIdNum .. " (" .. playerName .. ") set to Cop role.")
        SafeTriggerClientEvent('cops_and_robbers:bountyListUpdate', pIdNum, activeBounties)
    elseif role == "robber" then
        SafeSetByPlayerId(robbersActive, pIdNum, true)
        SafeRemoveByPlayerId(copsOnDuty, pIdNum)
        -- player.Functions.SetJob("unemployed", 0) -- Placeholder for framework integration
        SafeTriggerClientEvent('cnr:setPlayerRole', pIdNum, "robber")
        if not skipNotify then SafeTriggerClientEvent('chat:addMessage', pIdNum, { args = {"^3Role", "You are now a Robber."} }) end
        Log("Player " .. pIdNum .. " (" .. playerName .. ") set to Robber role.")
    else
        SafeRemoveByPlayerId(copsOnDuty, pIdNum)
        SafeRemoveByPlayerId(robbersActive, pIdNum)
        -- player.Functions.SetJob("unemployed", 0) -- Placeholder for framework integration
        SafeTriggerClientEvent('cnr:setPlayerRole', pIdNum, "citizen")
        if not skipNotify then SafeTriggerClientEvent('chat:addMessage', pIdNum, { args = {"^3Role", "You are now a Citizen."} }) end
        Log("Player " .. pIdNum .. " (" .. playerName .. ") set to Citizen role.")
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
        Log("AddXP: Invalid player ID " .. tostring(playerId), "error")
        return
    end

    local pData = GetCnrPlayerData(pIdNum)
    if not pData then
        Log("AddXP: Player " .. (pIdNum or "unknown") .. " data not init.", "error")
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
        Log(string.format("Player %s leveled up to %d (XP: %d, Role: %s)", pIdNum, newLevel, pData.xp, pData.role))
        ApplyPerks(pIdNum, newLevel, pData.role)
    else
        SafeTriggerClientEvent('cnr:xpGained', pIdNum, amount, pData.xp)
        Log(string.format("Player %s gained %d XP (Total: %d, Role: %s)", pIdNum, amount, pData.xp, pData.role))
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
        Log("ApplyPerks: Invalid player ID " .. tostring(playerId), "error")
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
        Log(string.format("ApplyPerks: No level unlocks defined for role '%s'. Player %s will have no role-specific level perks.", tostring(role), pIdNum))
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
                            Log(string.format("Player %s unlocked perk: %s at level %d", pIdNum, perkDetail.perkId, levelKey))
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
                                Log(string.format("Player %s granted increased_armor_durability (modifier: %s).", pIdNum, pData.armorModifier))
                            elseif perkDetail.perkId == "extra_spike_strips" and role == "cop" then
                                pData.extraSpikeStrips = perkDetail.value or 1
                                Log(string.format("Player %s granted extra_spike_strips (value: %d).", pIdNum, pData.extraSpikeStrips))
                            elseif perkDetail.perkId == "faster_contraband_collection" and role == "robber" then
                                 pData.contrabandCollectionModifier = perkDetail.value or 0.8
                                 Log(string.format("Player %s granted faster_contraband_collection (modifier: %s).", pIdNum, pData.contrabandCollectionModifier))
                            end
                        end
                    else
                        Log(string.format("ApplyPerks: perkDetail at levelKey %s for role %s is not a table. Skipping.", levelKey, role), "warn")
                    end
                end
            else
                 Log(string.format("ApplyPerks: levelUnlocksTable at levelKey %s for role %s is not a table. Skipping.", levelKey, role), "warn")
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
            Log(string.format("Bounty of $%d placed on %s (ID: %d) for reaching %d stars.", bountyAmount, targetName, pIdNum, wantedData.stars))
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
                    Log(string.format("Bounty for %s (ID: %d) increased to $%d.", bountyData.name, playerId, bountyData.amount))
                    bountyUpdatedThisCycle = true
                end
            elseif currentTime >= bountyData.expiresAt or (isPlayerOnline and pData and wantedData and wantedData.stars < Config.BountySettings.wantedLevelThreshold) then
                local bountyAmount = bountyData.amount or 0
                local bountyName = bountyData.name or "Unknown"
                local starCount = (wantedData and wantedData.stars) or "N/A"                Log(string.format("Bounty of $%d expired/removed for %s (ID: %s). Player online: %s, Stars: %s", bountyAmount, bountyName, tostring(playerId), tostring(isPlayerOnline), tostring(starCount)))
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
        Log("UpdatePlayerWantedLevel: Invalid player ID " .. tostring(playerId), "error")
        return
    end

    if GetPlayerName(pIdNum) == nil or not IsPlayerRobber(pIdNum) then return end -- Check player online using GetPlayerName

    local crimeConfig = Config.WantedSettings.crimes[crimeKey]
    if not crimeConfig then
        Log("UpdatePlayerWantedLevel: Unknown crimeKey: " .. crimeKey, "error")
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
        Log(string.format("Player %s committed crime '%s'. Points: %s. Wanted Lvl: %d, Stars: %d", pIdNum, crimeKey, pointsToAdd, currentWanted.wantedLevel, newStars))
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
                Log(string.format("UpdatePlayerWantedLevel: NPC Response ENABLED. Triggering cops_and_robbers:wantedLevelResponseUpdate for player %s (%d stars) at Coords: X:%.2f, Y:%.2f, Z:%.2f", pIdNum, newStars, robberCoords.x, robberCoords.y, robberCoords.z), "info")
            else
                Log(string.format("UpdatePlayerWantedLevel: NPC Response ENABLED for player %s (%d stars), but robberCoords are nil. Event will still be triggered.", pIdNum, newStars), "warn")
            end
            SafeTriggerClientEvent('cops_and_robbers:wantedLevelResponseUpdate', pIdNum, pIdNum, newStars, currentWanted.wantedLevel, robberCoords)
        else
            Log(string.format("UpdatePlayerWantedLevel: NPC Response DISABLED via Config.WantedSettings.enableNPCResponse for player %s (%d stars). Not triggering event.", pIdNum, newStars), "info")
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
        Log("ReduceWantedLevel: Invalid player ID " .. tostring(playerId), "error")
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
        Log(string.format("Reduced wanted for %s. New Lvl: %d, Stars: %d", pIdNum, wantedPlayers[pIdNum].wantedLevel, newStars))
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
                Log(string.format("Cleared wanted level for player %s who switched from robber to cop", playerId), "info")
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
                                Log(string.format("Player %s caught speeding at %.1f mph (limit: %.1f mph)", playerId, speed, speedLimit), "info")
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
                                    Log(string.format("Player %s involved in hit and run (vehicle damage detected)", playerId), "info")
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
    Log(string.format("Player %s fired weapon (Hash: %s) - wanted level increased", src, weaponHash), "info")
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
                                            Log(string.format("Player %s entered restricted area: %s - wanted level increased", playerId, areaKey), "info")
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
            Log(string.format("Player %s murdered cop %s - high wanted level increase", src, targetPlayerId), "warn")
        else
            UpdatePlayerWantedLevel(src, "murder_civilian")
            Log(string.format("Player %s murdered civilian %s - wanted level increased", src, targetPlayerId), "info")
        end
    else
        -- Assault
        if targetData.role == "cop" then
            UpdatePlayerWantedLevel(src, "assault_cop")
            Log(string.format("Player %s assaulted cop %s - wanted level increased", src, targetPlayerId), "info")
        else
            UpdatePlayerWantedLevel(src, "assault_civilian")
            Log(string.format("Player %s assaulted civilian %s - wanted level increased", src, targetPlayerId), "info")
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
    
    Log(string.format("Officer %s (ID: %d) reported %s (ID: %d) for crime: %s", copName, src, targetName, targetId, crimeKey), "info")
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
        Log("CalculateJailTermFromStars: Config.WantedSettings.levels not found. Using default punishments.", "warn")
    end

    if maxPunishment < minPunishment then -- Sanity check
        maxPunishment = minPunishment
        Log("CalculateJailTermFromStars: maxPunishment was less than minPunishment. Adjusted. Stars: " .. stars, "warn")
    end

    return math.random(minPunishment, maxPunishment)
end

SendToJail = function(playerId, durationSeconds, arrestingOfficerId, arrestOptions)
    local pIdNum = tonumber(playerId)
    if not pIdNum or pIdNum <= 0 then
        Log("SendToJail: Invalid player ID " .. tostring(playerId), "error")
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
        Log(string.format("SendToJail: Calculated jail term for player %s (%d stars) as %d seconds.", pIdNum, originalWantedData.stars, finalDurationSeconds), "info")
    end

    jail[pIdNum] = { startTime = os.time(), duration = finalDurationSeconds, remainingTime = finalDurationSeconds, arrestingOfficer = arrestingOfficerId }
    wantedPlayers[pIdNum] = { wantedLevel = 0, stars = 0, lastCrimeTime = 0, crimesCommitted = {} } -- Reset wanted
    SafeTriggerClientEvent('cnr:wantedLevelSync', pIdNum, wantedPlayers[pIdNum])
    SafeTriggerClientEvent('cnr:sendToJail', pIdNum, finalDurationSeconds, Config.PrisonLocation)
    SafeTriggerClientEvent('chat:addMessage', pIdNum, { args = {"^1Jail", string.format("You have been jailed for %d seconds.", finalDurationSeconds)} })
    Log(string.format("Player %s jailed for %ds. Officer: %s. Options: %s", pIdNum, finalDurationSeconds, arrestingOfficerId or "N/A", json.encode(arrestOptions)))

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
            Log("SendToJail: Invalid arresting officer ID " .. tostring(arrestingOfficerId), "warn")
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
            Log(string.format("Cop %s K9 assist XP %d for robber %s.", officerIdNum, k9BonusXP, pIdNum))
            k9Engagements[pIdNum] = nil -- Clear engagement after awarding
        end

        -- Subdue Arrest Bonus (New Logic)
        if arrestOptions.isSubdueArrest and not arrestOptions.isK9Assist then -- Avoid double bonus if K9 was also involved somehow in subdue
            local subdueBonusXP = Config.XPActionsCop.subdue_arrest_bonus or 10
            AddXP(officerIdNum, subdueBonusXP, "cop")
            SafeTriggerClientEvent('chat:addMessage', officerIdNum, { args = {"^2XP", string.format("+%d XP for Subdue Arrest!", subdueBonusXP)} })
            Log(string.format("Cop %s Subdue Arrest XP %d for robber %s.", officerIdNum, subdueBonusXP, pIdNum))
        end
        if Config.BountySettings.enabled and Config.BountySettings.claimMethod == "arrest" and activeBounties[pIdNum] then
            local bountyInfo = activeBounties[pIdNum]
            local bountyAmt = bountyInfo.amount
            AddPlayerMoney(officerIdNum, bountyAmt)
            Log(string.format("Cop %s claimed $%d bounty on %s.", officerIdNum, bountyAmt, bountyInfo.name))
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
        Log(string.format("ForceReleasePlayerFromJail: Invalid player ID '%s'.", tostring(playerId)), "error")
        return false
    end

    reason = reason or "Released by server"
    local playerIsOnline = GetPlayerName(pIdNum) ~= nil

    -- Log the attempt
    Log(string.format("Attempting to release player %s from jail. Reason: %s. Online: %s", pIdNum, reason, tostring(playerIsOnline)), "info")

    -- Clear live jail data from the `jail` table
    if jail[pIdNum] then
        jail[pIdNum] = nil
        Log(string.format("Player %s removed from live jail tracking.", pIdNum), "info")
    else
        Log(string.format("Player %s was not in live jail tracking. Proceeding to check persisted data.", pIdNum), "info")
    end

    -- Clear persisted jail data from `playersData`
    local pData = GetCnrPlayerData(pIdNum)
    if pData and pData.jailData then
        pData.jailData = nil
        Log(string.format("Cleared persisted jail data for player %s.", pIdNum), "info")
        -- Mark for save. If player is online, normal save mechanisms will pick it up.
        -- If offline, this save might only happen if SavePlayerData can handle it or on next login.
        MarkPlayerForInventorySave(pIdNum) -- This marks pData for saving
    else
        Log(string.format("No persisted jail data found for player %s to clear.", pIdNum), "info")
    end

    if playerIsOnline then
        SafeTriggerClientEvent('cnr:releaseFromJail', pIdNum)
        SafeTriggerClientEvent('chat:addMessage', pIdNum, { args = {"^2Jail", "You have been released. (" .. reason .. ")"} })
        Log(string.format("Player %s (online) released. Client notified.", pIdNum), "info")
    else
        -- If player is offline, their data (now without jailData) will be saved by MarkPlayerForInventorySave
        -- if the periodic saver picks them up or if SavePlayerData is called by another process for offline players.
        -- Otherwise, it's saved on their next disconnect (if they were online briefly) or handled by LoadPlayerData on next join.
        Log(string.format("Player %s (offline) jail data cleared. They will be free on next login.", pIdNum), "info")
        -- Persist the updated data immediately so they won't be jailed again on reconnect
        local saveSuccess = SavePlayerDataImmediate(pIdNum, "unjail_offline")
        if not saveSuccess then
            Log(string.format("Failed to save data for player %s after unjailing. Retrying...", pIdNum), "error")
            saveSuccess = SavePlayerDataImmediate(pIdNum, "unjail_offline")
            if not saveSuccess then
                Log(string.format("Retry failed: Could not save data for player %s after unjailing. Manual intervention may be required.", pIdNum), "error")
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
                    Log(string.format("Player %s found in 'jail' table but is offline. Removing from live tracking. Persisted data will determine status on rejoin.", pIdNum), "warn")
                    jail[pIdNum] = nil
                end
            else
                 Log(string.format("Invalid player ID key '%s' found in jail table.", tostring(playerIdKey)), "error")
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
        Log(string.format("cnr:selectRole: Player data not ready for %s. pData exists: %s, isDataLoaded: %s", pIdNum, tostring(pData ~= nil), tostring(pData and pData.isDataLoaded or false)), "warn")
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
        Log(string.format("Player %s spawned as %s at %s", GetPlayerName(src), selectedRole, tostring(spawnLocation)))
    else
        Log(string.format("No spawn point found for role %s for player %s", selectedRole, src), "warn")
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
        Log(string.format("Immediate save completed for player %s (reason: %s)", pIdNum, reason))
        return true
    else
        Log(string.format("Failed immediate save for player %s (reason: %s)", pIdNum, reason), "error")
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
    Log(string.format("Player connecting: %s (ID: %s)", name, src))

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
                    name, identifier, banInfo.reason or "No reason"), "warn")
                return
            end
        end
    end

    -- Send Config.Items to player after connection is established
    Citizen.CreateThread(function()
        Citizen.Wait(Constants.TIME_MS.SECOND * 2) -- Wait for player to fully connect
        if Config and Config.Items then
            TriggerClientEvent(Constants.EVENTS.SERVER_TO_CLIENT.RECEIVE_CONFIG_ITEMS, src, Config.Items)
            Log(string.format("Sent Config.Items to connecting player %s", src))
        end
    end)
end)

-- REFACTORED: Player disconnection handler using new PlayerManager system
AddEventHandler('playerDropped', function(reason)
    local src = source
    local playerName = GetPlayerName(src) or "Unknown"

    Log(string.format("Player %s (ID: %s) disconnected. Reason: %s", playerName, src, reason))

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
    Log(string.format("Player %s respawned, restoring inventory", src))

    -- Reload and sync player inventory
    local pData = GetCnrPlayerData(src)
    if pData and pData.inventory then
        -- Send config items first so client can properly reconstruct inventory
        if Config and Config.Items and type(Config.Items) == "table" then
            SafeTriggerClientEvent('cnr:receiveConfigItems', src, Config.Items)
        end
        
        -- Send fresh inventory sync
        SafeTriggerClientEvent('cnr:syncInventory', src, MinimizeInventoryForSync(pData.inventory))
        Log(string.format("Restored inventory for respawned player %s with %d items", src, tablelength(pData.inventory or {})))
    else
        Log(string.format("No inventory to restore for player %s", src), "warn")
    end
end)

-- REFACTORED: Player spawn handler using new PlayerManager system
RegisterNetEvent('cnr:playerSpawned')
AddEventHandler('cnr:playerSpawned', function()
    local src = source
    Log(string.format("Player %s spawned, initializing with PlayerManager", src))

    -- Use PlayerManager for proper initialization
    PlayerManager.OnPlayerConnected(src)

    -- Ensure data sync after a brief delay for client readiness
    Citizen.SetTimeout(Constants.TIME_MS.SECOND * 2, function()
        -- Validate player is still online
        if not GetPlayerName(src) then return end
        
        -- Sync player data to client using PlayerManager
        PlayerManager.SyncPlayerDataToClient(src)
        
        Log(string.format("Player %s initialization and sync completed", src))
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
            Log(string.format("AddItemToPlayerInventory: CRITICAL - Item details not found in Config.Items for itemId '%s' and not passed correctly. Cannot add to inventory for player %s.", itemId, playerId), "error")
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
    Log(string.format("Added/updated %d of %s to player %s inventory. New count: %d. Name: %s, Category: %s", quantity, itemId, playerId, newCount, itemDetails.name, itemDetails.category))
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

Log("Enhanced Progression System integration loaded", "info")

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
    Log(string.format("Removed %d of %s from player %s inventory.", quantity, itemId, playerId))
    return true, "Item removed"
end

-- Handle client request for Config.Items
RegisterServerEvent('cnr:requestConfigItems')
AddEventHandler('cnr:requestConfigItems', function()
    local source = source
    Log(string.format("Received Config.Items request from player %s", source), "info")

    -- Give some time for Config to be fully loaded if this is early in startup
    Citizen.Wait(100)

    if Config and Config.Items and type(Config.Items) == "table" then
        local itemCount = 0
        for _ in pairs(Config.Items) do itemCount = itemCount + 1 end
        TriggerClientEvent('cnr:receiveConfigItems', source, Config.Items)
        Log(string.format("Sent Config.Items to player %s (%d items)", source, itemCount), "info")
    else
        Log(string.format("Failed to send Config.Items to player %s - Config.Items not found or invalid. Config exists: %s, Config.Items type: %s", source, tostring(Config ~= nil), type(Config and Config.Items)), "error")
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
            source, targetPlayerId, fineAmount, speed, Config.SpeedLimitMph))
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
        Log(string.format("Admin status check failed - no player data for %s", source), "warn")
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
        Log(string.format("Admin panel opened for player %s", source), "info")
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
    Log(string.format("Role selection requested by player %s", source), "info")
    
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

