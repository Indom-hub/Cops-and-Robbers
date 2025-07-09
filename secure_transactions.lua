-- secure_transactions.lua
-- Secure transaction system for purchases, sales, and money transfers
-- Version: 1.2.0

-- Ensure required modules are loaded
if not Constants then
    error("Constants must be loaded before secure_transactions.lua")
end

if not Validation then
    error("Validation must be loaded before secure_transactions.lua")
end

if not SecureInventory then
    error("SecureInventory must be loaded before secure_transactions.lua")
end

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
-- UTILITY FUNCTIONS
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

--- Calculate sell price for an item
--- @param itemConfig table Item configuration
--- @param quantity number Quantity being sold
--- @return number Sell price
local function CalculateSellPrice(itemConfig, quantity)
    local basePrice = itemConfig.basePrice or 0
    local sellPrice = math.floor(basePrice * Constants.ECONOMY.SELL_PRICE_MULTIPLIER)
    return sellPrice * quantity
end

--- Calculate dynamic buy price (if dynamic economy is enabled)
--- @param itemConfig table Item configuration
--- @param quantity number Quantity being purchased
--- @return number Buy price
local function CalculateBuyPrice(itemConfig, quantity)
    local basePrice = itemConfig.basePrice or 0
    
    -- TODO: Implement dynamic pricing based on purchase history
    -- For now, just return base price
    return basePrice * quantity
end

-- ====================================================================
-- TRANSACTION MANAGEMENT
-- ====================================================================

--- Start a new transaction
--- @param playerId number Player ID
--- @param transactionType string Type of transaction
--- @param details table Transaction details
--- @return string, boolean Transaction ID and success status
local function StartTransaction(playerId, transactionType, details)
    local transactionId = GenerateTransactionId()
    
    activeTransactions[transactionId] = {
        id = transactionId,
        playerId = playerId,
        type = transactionType,
        details = details,
        startTime = GetGameTimer(),
        status = "active"
    }
    
    LogTransaction(playerId, transactionType, 
        string.format("Transaction started: %s", transactionId))
    
    return transactionId, true
end

--- Complete a transaction
--- @param transactionId string Transaction ID
--- @param success boolean Whether transaction was successful
--- @param result table Transaction result details
local function CompleteTransaction(transactionId, success, result)
    local transaction = activeTransactions[transactionId]
    if not transaction then
        return false
    end
    
    transaction.endTime = GetGameTimer()
    transaction.success = success
    transaction.result = result
    transaction.status = "completed"
    
    -- Update statistics
    transactionStats.totalTransactions = transactionStats.totalTransactions + 1
    if success then
        transactionStats.successfulTransactions = transactionStats.successfulTransactions + 1
        if result and result.moneyAmount then
            transactionStats.totalMoneyTransferred = transactionStats.totalMoneyTransferred + result.moneyAmount
        end
    else
        transactionStats.failedTransactions = transactionStats.failedTransactions + 1
    end
    
    local transactionTime = transaction.endTime - transaction.startTime
    transactionStats.averageTransactionTime = (transactionStats.averageTransactionTime + transactionTime) / 2
    
    -- Move to history
    transactionHistory[transactionId] = transaction
    activeTransactions[transactionId] = nil
    
    LogTransaction(transaction.playerId, transaction.type, 
        string.format("Transaction completed: %s (%s, took %dms)", 
            transactionId, success and "SUCCESS" or "FAILED", transactionTime))
    
    return true
end

-- ====================================================================
-- SECURE PURCHASE SYSTEM
-- ====================================================================

--- Process item purchase with full validation and security
--- @param playerId number Player ID
--- @param itemId string Item ID to purchase
--- @param quantity number Quantity to purchase
--- @return boolean, string, table Success status, message, and transaction details
function SecureTransactions.ProcessPurchase(playerId, itemId, quantity)
    local startTime = GetGameTimer()
    
    -- Rate limiting for purchases
    if not Validation.CheckRateLimit(playerId, "purchases", 
        Constants.VALIDATION.MAX_PURCHASES_PER_MINUTE, 
        Constants.TIME_MS.MINUTE) then
        return false, Constants.ERROR_MESSAGES.RATE_LIMITED, nil
    end
    
    -- Validate player
    local validPlayer, playerError = Validation.ValidatePlayer(playerId)
    if not validPlayer then
        return false, playerError, nil
    end
    
    -- Validate item
    local validItem, itemConfig, itemError = Validation.ValidateItem(itemId)
    if not validItem then
        return false, itemError, nil
    end
    
    -- Validate quantity
    local validQty, validatedQuantity, qtyError = Validation.ValidateQuantity(quantity)
    if not validQty then
        return false, qtyError, nil
    end
    
    -- Get player data
    local playerData = GetCnrPlayerData(playerId)
    if not playerData then
        return false, Constants.ERROR_MESSAGES.PLAYER_NOT_FOUND, nil
    end
    
    -- Validate purchase (role, level, funds)
    local validPurchase, totalCost, purchaseError = Validation.ValidateItemPurchase(
        playerId, itemConfig, validatedQuantity, playerData)
    if not validPurchase then
        return false, purchaseError, nil
    end
    
    -- Start transaction
    local transactionId, txnSuccess = StartTransaction(playerId, "purchase", {
        itemId = itemId,
        quantity = validatedQuantity,
        cost = totalCost,
        itemName = itemConfig.name
    })
    
    if not txnSuccess then
        return false, "Failed to start transaction", nil
    end
    
    -- Deduct money first (prevents duplication if inventory add fails)
    local oldMoney = playerData.money or 0
    playerData.money = oldMoney - totalCost
    
    -- Add item to inventory
    local addSuccess, addError = SecureInventory.AddItem(playerId, itemId, validatedQuantity, "purchase")
    
    if not addSuccess then
        -- Rollback money deduction
        playerData.money = oldMoney
        CompleteTransaction(transactionId, false, {error = addError})
        return false, "Purchase failed: " .. addError, nil
    end
    
    -- Mark player for save
    DataManager.MarkPlayerForSave(playerId)
    
    -- Record purchase in history (for dynamic pricing)
    if Config.DynamicEconomy and Config.DynamicEconomy.enabled then
        -- TODO: Record purchase for dynamic pricing
    end
    
    -- Complete transaction
    local transactionResult = {
        itemId = itemId,
        itemName = itemConfig.name,
        quantity = validatedQuantity,
        moneyAmount = totalCost,
        newBalance = playerData.money
    }
    
    CompleteTransaction(transactionId, true, transactionResult)
    
    LogTransaction(playerId, "purchase", 
        string.format("Purchased %dx %s for $%d (balance: $%d)", 
            validatedQuantity, itemConfig.name, totalCost, playerData.money))
    
    return true, string.format("Successfully purchased %dx %s for $%d", 
        validatedQuantity, itemConfig.name, totalCost), transactionResult
end

-- ====================================================================
-- SECURE SALE SYSTEM
-- ====================================================================

--- Process item sale with full validation and security
--- @param playerId number Player ID
--- @param itemId string Item ID to sell
--- @param quantity number Quantity to sell
--- @return boolean, string, table Success status, message, and transaction details
function SecureTransactions.ProcessSale(playerId, itemId, quantity)
    -- Validate player
    local validPlayer, playerError = Validation.ValidatePlayer(playerId)
    if not validPlayer then
        return false, playerError, nil
    end
    
    -- Validate item
    local validItem, itemConfig, itemError = Validation.ValidateItem(itemId)
    if not validItem then
        return false, itemError, nil
    end
    
    -- Validate quantity
    local validQty, validatedQuantity, qtyError = Validation.ValidateQuantity(quantity)
    if not validQty then
        return false, qtyError, nil
    end
    
    -- Get player data
    local playerData = GetCnrPlayerData(playerId)
    if not playerData then
        return false, Constants.ERROR_MESSAGES.PLAYER_NOT_FOUND, nil
    end
    
    -- Validate sale (player has items)
    local validSale, saleError = Validation.ValidateItemSale(playerId, itemId, validatedQuantity, playerData)
    if not validSale then
        return false, saleError, nil
    end
    
    -- Calculate sell price
    local sellPrice = CalculateSellPrice(itemConfig, validatedQuantity)
    
    -- Start transaction
    local transactionId, txnSuccess = StartTransaction(playerId, "sale", {
        itemId = itemId,
        quantity = validatedQuantity,
        earnings = sellPrice,
        itemName = itemConfig.name
    })
    
    if not txnSuccess then
        return false, "Failed to start transaction", nil
    end
    
    -- Remove item from inventory first
    local removeSuccess, removeError = SecureInventory.RemoveItem(playerId, itemId, validatedQuantity, "sale")
    
    if not removeSuccess then
        CompleteTransaction(transactionId, false, {error = removeError})
        return false, "Sale failed: " .. removeError, nil
    end
    
    -- Add money
    local oldMoney = playerData.money or 0
    playerData.money = oldMoney + sellPrice
    
    -- Mark player for save
    DataManager.MarkPlayerForSave(playerId)
    
    -- Complete transaction
    local transactionResult = {
        itemId = itemId,
        itemName = itemConfig.name,
        quantity = validatedQuantity,
        moneyAmount = sellPrice,
        newBalance = playerData.money
    }
    
    CompleteTransaction(transactionId, true, transactionResult)
    
    LogTransaction(playerId, "sale", 
        string.format("Sold %dx %s for $%d (balance: $%d)", 
            validatedQuantity, itemConfig.name, sellPrice, playerData.money))
    
    return true, string.format("Successfully sold %dx %s for $%d", 
        validatedQuantity, itemConfig.name, sellPrice), transactionResult
end

-- ====================================================================
-- MONEY TRANSFER SYSTEM
-- ====================================================================

--- Securely add money to player account
--- @param playerId number Player ID
--- @param amount number Amount to add
--- @param reason string Reason for money addition
--- @return boolean, string Success status and message
function SecureTransactions.AddMoney(playerId, amount, reason)
    reason = reason or "unknown"
    
    -- Validate player
    local validPlayer, playerError = Validation.ValidatePlayer(playerId)
    if not validPlayer then
        return false, playerError
    end
    
    -- Validate money amount
    local validMoney, validatedAmount, moneyError = Validation.ValidateMoney(amount, false)
    if not validMoney then
        return false, moneyError
    end
    
    -- Get player data
    local playerData = GetCnrPlayerData(playerId)
    if not playerData then
        return false, Constants.ERROR_MESSAGES.PLAYER_NOT_FOUND
    end
    
    -- Add money
    local oldMoney = playerData.money or 0
    playerData.money = oldMoney + validatedAmount
    
    -- Mark for save
    DataManager.MarkPlayerForSave(playerId)
    
    LogTransaction(playerId, "add_money", 
        string.format("Added $%d (reason: %s, balance: $%d)", 
            validatedAmount, reason, playerData.money))
    
    return true, string.format("Added $%d to account", validatedAmount)
end

--- Securely remove money from player account
--- @param playerId number Player ID
--- @param amount number Amount to remove
--- @param reason string Reason for money removal
--- @return boolean, string Success status and message
function SecureTransactions.RemoveMoney(playerId, amount, reason)
    reason = reason or "unknown"
    
    -- Validate player
    local validPlayer, playerError = Validation.ValidatePlayer(playerId)
    if not validPlayer then
        return false, playerError
    end
    
    -- Validate money amount
    local validMoney, validatedAmount, moneyError = Validation.ValidateMoney(amount, false)
    if not validMoney then
        return false, moneyError
    end
    
    -- Get player data
    local playerData = GetCnrPlayerData(playerId)
    if not playerData then
        return false, Constants.ERROR_MESSAGES.PLAYER_NOT_FOUND
    end
    
    -- Validate player has sufficient funds
    local validFunds, fundsError = Validation.ValidatePlayerFunds(playerId, validatedAmount, playerData)
    if not validFunds then
        return false, fundsError
    end
    
    -- Remove money
    local oldMoney = playerData.money or 0
    playerData.money = oldMoney - validatedAmount
    
    -- Mark for save
    DataManager.MarkPlayerForSave(playerId)
    
    LogTransaction(playerId, "remove_money", 
        string.format("Removed $%d (reason: %s, balance: $%d)", 
            validatedAmount, reason, playerData.money))
    
    return true, string.format("Removed $%d from account", validatedAmount)
end

-- ====================================================================
-- STATISTICS AND MONITORING
-- ====================================================================

--- Get transaction statistics
--- @return table Statistics
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

--- Log transaction statistics
function SecureTransactions.LogStats()
    local stats = SecureTransactions.GetStats()
    print(string.format("[CNR_SECURE_TRANSACTIONS] Stats - Total: %d, Success: %d, Failed: %d, Success Rate: %.1f%%, Money: $%d, Avg Time: %.1fms, Active: %d",
        stats.totalTransactions, stats.successfulTransactions, stats.failedTransactions,
        stats.successRate, stats.totalMoneyTransferred, stats.averageTransactionTime, stats.activeTransactions))
end

-- ====================================================================
-- CLEANUP AND INITIALIZATION
-- ====================================================================

--- Clean up old transactions
local function CleanupTransactions()
    local currentTime = GetGameTimer()
    local cleanupThreshold = 10 * Constants.TIME_MS.MINUTE
    
    -- Clean transaction history
    for txnId, txn in pairs(transactionHistory) do
        if currentTime - txn.endTime > cleanupThreshold then
            transactionHistory[txnId] = nil
        end
    end
    
    -- Clean stale active transactions (should not happen normally)
    for txnId, txn in pairs(activeTransactions) do
        if currentTime - txn.startTime > Constants.TIME_MS.MINUTE then
            LogTransaction(txn.playerId, txn.type, 
                string.format("Cleaning up stale transaction: %s", txnId), 
                Constants.LOG_LEVELS.WARN)
            activeTransactions[txnId] = nil
        end
    end
end

--- Initialize secure transactions system
function SecureTransactions.Initialize()
    print("[CNR_SECURE_TRANSACTIONS] Secure Transactions System initialized")
    
    -- Start cleanup thread
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(5 * Constants.TIME_MS.MINUTE)
            CleanupTransactions()
        end
    end)
    
    -- Statistics logging thread
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(15 * Constants.TIME_MS.MINUTE)
            SecureTransactions.LogStats()
        end
    end)
end

--- Cleanup on player disconnect
--- @param playerId number Player ID
function SecureTransactions.CleanupPlayer(playerId)
    -- Cancel any active transactions for this player
    for txnId, txn in pairs(activeTransactions) do
        if txn.playerId == playerId then
            CompleteTransaction(txnId, false, {error = "Player disconnected"})
        end
    end
    
    LogTransaction(playerId, "cleanup", "Player transactions cleaned up")
end

-- Initialize when loaded
SecureTransactions.Initialize()

-- SecureTransactions module is now available globally