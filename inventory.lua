-- inventory.lua
-- Consolidated inventory system (server and client)
-- Version: 1.2.0
-- Consolidated from: inventory_server.lua, inventory_client.lua, secure_inventory.lua

-- This file will contain all inventory-related functionality
-- Server-side and client-side code will be separated by conditional checks

if IsDuplicityVersion() then
    -- ====================================================================
    -- SERVER-SIDE INVENTORY SYSTEM
    -- ====================================================================
    
    -- Ensure required modules are loaded
    if not Constants then
        error("Constants must be loaded before inventory.lua")
    end
    
    if not Validation then
        error("Validation must be loaded before inventory.lua")
    end
    
    if not DataManager then
        error("DataManager must be loaded before inventory.lua")
    end
    
    -- Initialize SecureInventory module
    SecureInventory = SecureInventory or {}
    
    -- Transaction tracking to prevent duplication
    local activeTransactions = {}
    local transactionHistory = {}
    local inventoryLocks = {}
    
    -- Performance monitoring
    local inventoryStats = {
        totalOperations = 0,
        failedOperations = 0,
        duplicateAttempts = 0,
        averageOperationTime = 0
    }
    
    -- ====================================================================
    -- SERVER UTILITY FUNCTIONS
    -- ====================================================================
    
    --- Generate unique transaction ID
    --- @return string Unique transaction ID
    local function GenerateTransactionId()
        return string.format("txn_%d_%d", GetGameTimer(), math.random(10000, 99999))
    end
    
    --- Log inventory operations
    --- @param playerId number Player ID
    --- @param operation string Operation type
    --- @param message string Log message
    --- @param level string Log level
    local function LogInventory(playerId, operation, message, level)
        level = level or Constants.LOG_LEVELS.INFO
        local playerName = GetPlayerName(playerId) or "Unknown"
        
        if level == Constants.LOG_LEVELS.ERROR or level == Constants.LOG_LEVELS.WARN then
            print(string.format("[CNR_SECURE_INVENTORY] [%s] Player %s (%d) - %s: %s", 
                string.upper(level), playerName, playerId, operation, message))
        end
    end
    
    --- Check if inventory is locked for a player
    --- @param playerId number Player ID
    --- @return boolean Whether inventory is locked
    local function IsInventoryLocked(playerId)
        local lock = inventoryLocks[playerId]
        if not lock then return false end
        
        -- Check if lock has expired
        if GetGameTimer() - lock.timestamp > Constants.TIME_MS.SECOND * 5 then
            inventoryLocks[playerId] = nil
            return false
        end
        
        return true
    end
    
    --- Lock inventory for a player during operations
    --- @param playerId number Player ID
    --- @param operation string Operation type
    local function LockInventory(playerId, operation)
        inventoryLocks[playerId] = {
            operation = operation,
            timestamp = GetGameTimer()
        }
    end
    
    --- Unlock inventory for a player
    --- @param playerId number Player ID
    local function UnlockInventory(playerId)
        inventoryLocks[playerId] = nil
    end
    
    -- ====================================================================
    -- SERVER INVENTORY FUNCTIONS
    -- ====================================================================
    
    --- Add item to player inventory with validation
    --- @param playerId number Player ID
    --- @param itemId string Item ID
    --- @param quantity number Quantity to add
    --- @param source string Source of the item
    --- @return boolean, string Success status and error message
    function SecureInventory.AddItem(playerId, itemId, quantity, source)
        local startTime = GetGameTimer()
        inventoryStats.totalOperations = inventoryStats.totalOperations + 1
        
        -- Validate inputs
        local valid, error = Validation.ValidatePlayer(playerId)
        if not valid then
            inventoryStats.failedOperations = inventoryStats.failedOperations + 1
            return false, error
        end
        
        local validItem, itemConfig, itemError = Validation.ValidateItem(itemId)
        if not validItem then
            inventoryStats.failedOperations = inventoryStats.failedOperations + 1
            return false, itemError
        end
        
        local validQuantity, validatedQuantity, quantityError = Validation.ValidateQuantity(quantity)
        if not validQuantity then
            inventoryStats.failedOperations = inventoryStats.failedOperations + 1
            return false, quantityError
        end
        
        -- Check inventory lock
        if IsInventoryLocked(playerId) then
            inventoryStats.failedOperations = inventoryStats.failedOperations + 1
            return false, "Inventory is locked for another operation"
        end
        
        -- Lock inventory
        LockInventory(playerId, "add_item")
        
        -- Get player data
        local playerData = GetCnrPlayerData(playerId)
        if not playerData then
            UnlockInventory(playerId)
            inventoryStats.failedOperations = inventoryStats.failedOperations + 1
            return false, Constants.ERROR_MESSAGES.PLAYER_NOT_FOUND
        end
        
        -- Initialize inventory if needed
        if not playerData.inventory then
            playerData.inventory = {}
        end
        
        -- Check inventory space
        local spaceValid, spaceError = Validation.ValidateInventorySpace(playerData, validatedQuantity)
        if not spaceValid then
            UnlockInventory(playerId)
            inventoryStats.failedOperations = inventoryStats.failedOperations + 1
            return false, spaceError
        end
        
        -- Add item
        if not playerData.inventory[itemId] then
            playerData.inventory[itemId] = { count = 0 }
        end
        
        playerData.inventory[itemId].count = (playerData.inventory[itemId].count or 0) + validatedQuantity
        
        -- Save player data
        DataManager.MarkPlayerForSave(playerId)
        
        -- Unlock inventory
        UnlockInventory(playerId)
        
        -- Update statistics
        local operationTime = GetGameTimer() - startTime
        inventoryStats.averageOperationTime = (inventoryStats.averageOperationTime + operationTime) / 2
        
        LogInventory(playerId, "ADD_ITEM", string.format("Added %d x %s (source: %s)", validatedQuantity, itemId, source or "unknown"))
        
        -- Sync inventory to client
        TriggerClientEvent('cnr:syncInventory', playerId, MinimizeInventoryForSync(playerData.inventory))
        
        return true, nil
    end
    
    --- Remove item from player inventory with validation
    --- @param playerId number Player ID
    --- @param itemId string Item ID
    --- @param quantity number Quantity to remove
    --- @param reason string Reason for removal
    --- @return boolean, string Success status and error message
    function SecureInventory.RemoveItem(playerId, itemId, quantity, reason)
        local startTime = GetGameTimer()
        inventoryStats.totalOperations = inventoryStats.totalOperations + 1
        
        -- Validate inputs
        local valid, error = Validation.ValidatePlayer(playerId)
        if not valid then
            inventoryStats.failedOperations = inventoryStats.failedOperations + 1
            return false, error
        end
        
        local validQuantity, validatedQuantity, quantityError = Validation.ValidateQuantity(quantity)
        if not validQuantity then
            inventoryStats.failedOperations = inventoryStats.failedOperations + 1
            return false, quantityError
        end
        
        -- Check inventory lock
        if IsInventoryLocked(playerId) then
            inventoryStats.failedOperations = inventoryStats.failedOperations + 1
            return false, "Inventory is locked for another operation"
        end
        
        -- Lock inventory
        LockInventory(playerId, "remove_item")
        
        -- Get player data
        local playerData = GetCnrPlayerData(playerId)
        if not playerData or not playerData.inventory then
            UnlockInventory(playerId)
            inventoryStats.failedOperations = inventoryStats.failedOperations + 1
            return false, Constants.ERROR_MESSAGES.PLAYER_NOT_FOUND
        end
        
        -- Validate player has enough items
        local validSale, saleError = Validation.ValidateItemSale(playerId, itemId, validatedQuantity, playerData)
        if not validSale then
            UnlockInventory(playerId)
            inventoryStats.failedOperations = inventoryStats.failedOperations + 1
            return false, saleError
        end
        
        -- Remove item
        playerData.inventory[itemId].count = playerData.inventory[itemId].count - validatedQuantity
        
        -- Remove item entry if count reaches 0
        if playerData.inventory[itemId].count <= 0 then
            playerData.inventory[itemId] = nil
        end
        
        -- Save player data
        DataManager.MarkPlayerForSave(playerId)
        
        -- Unlock inventory
        UnlockInventory(playerId)
        
        -- Update statistics
        local operationTime = GetGameTimer() - startTime
        inventoryStats.averageOperationTime = (inventoryStats.averageOperationTime + operationTime) / 2
        
        LogInventory(playerId, "REMOVE_ITEM", string.format("Removed %d x %s (reason: %s)", validatedQuantity, itemId, reason or "unknown"))
        
        -- Sync inventory to client
        TriggerClientEvent('cnr:syncInventory', playerId, MinimizeInventoryForSync(playerData.inventory))
        
        return true, nil
    end
    
    --- Get player inventory
    --- @param playerId number Player ID
    --- @return boolean, table Success status and inventory data
    function SecureInventory.GetInventory(playerId)
        local valid, error = Validation.ValidatePlayer(playerId)
        if not valid then
            return false, error
        end
        
        local playerData = GetCnrPlayerData(playerId)
        if not playerData then
            return false, Constants.ERROR_MESSAGES.PLAYER_NOT_FOUND
        end
        
        return true, playerData.inventory or {}
    end
    
    --- Check if player has specific item and quantity
    --- @param playerId number Player ID
    --- @param itemId string Item ID
    --- @param quantity number Required quantity
    --- @return boolean Whether player has the item
    function SecureInventory.HasItem(playerId, itemId, quantity)
        quantity = quantity or 1
        
        local success, inventory = SecureInventory.GetInventory(playerId)
        if not success then
            return false
        end
        
        local item = inventory[itemId]
        if not item or not item.count then
            return false
        end
        
        return item.count >= quantity
    end
    
    --- Get inventory statistics
    --- @return table Inventory statistics
    function SecureInventory.GetStats()
        return {
            totalOperations = inventoryStats.totalOperations,
            failedOperations = inventoryStats.failedOperations,
            successRate = inventoryStats.totalOperations > 0 and ((inventoryStats.totalOperations - inventoryStats.failedOperations) / inventoryStats.totalOperations * 100) or 0,
            duplicateAttempts = inventoryStats.duplicateAttempts,
            averageOperationTime = inventoryStats.averageOperationTime,
            activeTransactions = tablelength(activeTransactions),
            lockedInventories = tablelength(inventoryLocks)
        }
    end
    
    --- Initialize secure inventory system
    function SecureInventory.Initialize()
        print("[CNR_SECURE_INVENTORY] Secure Inventory System initialized")
        
        -- Statistics logging thread
        Citizen.CreateThread(function()
            while true do
                Citizen.Wait(10 * Constants.TIME_MS.MINUTE) -- Every 10 minutes
                local stats = SecureInventory.GetStats()
                print(string.format("[CNR_SECURE_INVENTORY] Stats - Operations: %d, Failed: %d, Success Rate: %.1f%%, Avg Time: %.1fms",
                    stats.totalOperations, stats.failedOperations, stats.successRate, stats.averageOperationTime))
            end
        end)
    end
    
    --- Cleanup inventory data for disconnected player
    --- @param playerId number Player ID
    function SecureInventory.CleanupPlayer(playerId)
        activeTransactions[playerId] = nil
        inventoryLocks[playerId] = nil
    end
    
    -- Initialize when loaded
    SecureInventory.Initialize()
    
else
    -- ====================================================================
    -- CLIENT-SIDE INVENTORY SYSTEM
    -- ====================================================================
    
    -- Client-side inventory variables
    local playerInventory = {}
    local inventoryOpen = false
    local selectedCategory = "weapons"
    
    -- ====================================================================
    -- CLIENT INVENTORY FUNCTIONS
    -- ====================================================================
    
    --- Update local inventory cache
    --- @param inventory table Inventory data from server
    function UpdateLocalInventory(inventory)
        playerInventory = inventory or {}
        
        -- Update UI if inventory is open
        if inventoryOpen then
            SendNUIMessage({
                type = "updateInventory",
                inventory = playerInventory
            })
        end
    end
    
    --- Open inventory UI
    function OpenInventory()
        if inventoryOpen then return end
        
        inventoryOpen = true
        SetNuiFocus(true, true)
        
        SendNUIMessage({
            type = "showInventory",
            inventory = playerInventory,
            selectedCategory = selectedCategory
        })
    end
    
    --- Close inventory UI
    function CloseInventory()
        if not inventoryOpen then return end
        
        inventoryOpen = false
        SetNuiFocus(false, false)
        
        SendNUIMessage({
            type = "hideInventory"
        })
    end
    
    --- Use item from inventory
    --- @param itemId string Item ID to use
    function UseInventoryItem(itemId)
        if not playerInventory[itemId] or playerInventory[itemId].count <= 0 then
            return
        end
        
        -- Trigger server event to use item
        TriggerServerEvent('cnr:useItem', itemId)
    end
    
    -- ====================================================================
    -- CLIENT EVENT HANDLERS
    -- ====================================================================
    
    -- Handle inventory sync from server
    RegisterNetEvent('cnr:syncInventory')
    AddEventHandler('cnr:syncInventory', function(inventory)
        UpdateLocalInventory(inventory)
    end)
    
    -- Handle inventory UI callbacks
    RegisterNUICallback('useItem', function(data, cb)
        UseInventoryItem(data.itemId)
        cb('ok')
    end)
    
    RegisterNUICallback('closeInventory', function(data, cb)
        CloseInventory()
        cb('ok')
    end)
    
    RegisterNUICallback('changeCategory', function(data, cb)
        selectedCategory = data.category
        cb('ok')
    end)
    
    -- ====================================================================
    -- CLIENT KEYBINDS
    -- ====================================================================
    
    -- Inventory toggle keybind
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(0)
            
            if IsControlJustPressed(0, 244) then -- M key
                if inventoryOpen then
                    CloseInventory()
                else
                    OpenInventory()
                end
            end
        end
    end)
    
end