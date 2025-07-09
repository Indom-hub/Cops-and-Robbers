-- validation.lua
-- Comprehensive server-side validation system to prevent exploits
-- Version: 1.2.0

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
-- UTILITY FUNCTIONS
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
-- CLEANUP FUNCTIONS
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

-- Validation module is now available globally