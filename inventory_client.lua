-- inventory_client.lua
-- Handles client-side custom inventory logic and NUI interaction.

local clientConfigItems = nil -- Will store Config.Items from server
local isInventoryOpen = false -- Track inventory UI state

-- Function to get the items, accessible by other parts of this script
function GetClientConfigItems()
    return clientConfigItems
end

-- Export placeholder - functions will be defined below and exports set at end of file


RegisterNetEvent('cnr:receiveMyInventory') -- Ensure client is registered to receive this event from server
local localPlayerInventory = {} -- This will store the RECONSTRUCTED rich inventory

-- Event handler for receiving inventory from server
AddEventHandler('cnr:receiveMyInventory', function(minimalInventoryData, equippedItemsArray)
    Log("Received cnr:receiveMyInventory event. Processing inventory data...", "info", "CNR_INV_CLIENT")
    
    -- Update equipped items if provided
    if equippedItemsArray and type(equippedItemsArray) == "table" then
        Log("Received equipped items list with " .. #equippedItemsArray .. " items", "info", "CNR_INV_CLIENT")
        
        -- Convert array to dictionary for faster lookups
        localPlayerEquippedItems = {}
        for _, itemId in ipairs(equippedItemsArray) do
            localPlayerEquippedItems[itemId] = true
        end
    end
    
    -- Process the inventory data
    UpdateFullInventory(minimalInventoryData)
end)

-- Add the missing cnr:syncInventory event handler
RegisterNetEvent('cnr:syncInventory')
AddEventHandler('cnr:syncInventory', function(minimalInventoryData)
    Log("Received cnr:syncInventory event. Processing inventory data...", "info", "CNR_INV_CLIENT")
    UpdateFullInventory(minimalInventoryData)
end)

RegisterNetEvent('cnr:inventoryUpdated')
AddEventHandler('cnr:inventoryUpdated', function(updatedMinimalInventory)
    Log("Received cnr:inventoryUpdated. This event might need review if cnr:syncInventory is primary.", "warn", "CNR_INV_CLIENT")
    UpdateFullInventory(updatedMinimalInventory)
end)

RegisterNetEvent('cnr:receiveConfigItems')
AddEventHandler('cnr:receiveConfigItems', function(receivedConfigItems)
    clientConfigItems = receivedConfigItems
    Log("Received Config.Items from server. Item count: " .. tablelength(clientConfigItems or {}), "info", "CNR_INV_CLIENT")

    SendNUIMessage({
        action = 'storeFullItemConfig',
        itemConfig = clientConfigItems
    })
    Log("Sent Config.Items to NUI via SendNUIMessage.", "info", "CNR_INV_CLIENT")

    -- Check if localPlayerInventory currently holds minimal data (e.g. from an early sync before config arrived)
    -- A simple heuristic: if an item exists and its 'name' field is the same as its 'itemId', it's likely minimal.
    if localPlayerInventory and next(localPlayerInventory) then
        local firstItemId = next(localPlayerInventory)
        if localPlayerInventory[firstItemId] and (localPlayerInventory[firstItemId].name == firstItemId or localPlayerInventory[firstItemId].name == nil) then
             Log("Config.Items received after minimal inventory was stored. Attempting full reconstruction.", "info", "CNR_INV_CLIENT")
             UpdateFullInventory(localPlayerInventory) -- Re-process with the now available config
        else
             -- Config arrived but inventory seems already processed, just re-equip to be safe
             Log("Config.Items received, inventory appears processed. Re-equipping weapons to ensure visibility.", "info", "CNR_INV_CLIENT")
             EquipInventoryWeapons()
        end
    else
        Log("Config.Items received but no pending inventory to reconstruct.", "info", "CNR_INV_CLIENT")
    end
end)

-- Request Config.Items when this script loads/player initializes
Citizen.CreateThread(function()
    -- Wait for player to be fully spawned
    while not NetworkIsPlayerActive(PlayerId()) do
        Citizen.Wait(500)
    end

    Citizen.Wait(3000) -- Wait 3 seconds after player is active

    local attempts = 0
    local maxAttempts = 10

    while not clientConfigItems and attempts < maxAttempts do
        attempts = attempts + 1
        TriggerServerEvent('cnr:requestConfigItems')
        Log("Requested Config.Items from server (attempt " .. attempts .. "/" .. maxAttempts .. ")", "info", "CNR_INV_CLIENT")

        -- Wait 3 seconds for response
        Citizen.Wait(3000)
    end

    if not clientConfigItems then
        Log("Failed to receive Config.Items from server after " .. maxAttempts .. " attempts", "error", "CNR_INV_CLIENT")
    end
end)

function UpdateFullInventory(minimalInventoryData)
    Log("UpdateFullInventory received data. Attempting reconstruction...", "info", "CNR_INV_CLIENT")
    local reconstructedInventory = {}
    local configItems = GetClientConfigItems()

    if not configItems then
        -- Store the minimal inventory data for now
        localPlayerInventory = minimalInventoryData or {}
        
        -- Request config items from server
        TriggerServerEvent('cnr:requestConfigItems')
        Log("Requested Config.Items from server due to missing data.", "info", "CNR_INV_CLIENT")
        
        -- Display a subtle notification to the player
        TriggerEvent('chat:addMessage', {
            color = {255, 165, 0},
            multiline = true,
            args = {"System", "Loading inventory data..."}
        })
        
        -- Set up a timer to retry if needed, but with reduced frequency
        Citizen.CreateThread(function()
            local attempts = 0
            local maxAttempts = 3
            
            while not GetClientConfigItems() and attempts < maxAttempts do
                Citizen.Wait(3000) -- Wait longer between attempts (3 seconds)
                attempts = attempts + 1
                
                if not GetClientConfigItems() then
                    TriggerServerEvent('cnr:requestConfigItems')
                    Log("Retry requesting Config.Items from server (attempt " .. attempts .. "/" .. maxAttempts .. ")", "warn", "CNR_INV_CLIENT")
                end
            end

            -- If we got the config items, try to update inventory again
            if GetClientConfigItems() and localPlayerInventory and next(localPlayerInventory) then
                Log("Config.Items received after retry, attempting inventory reconstruction again", "info", "CNR_INV_CLIENT")
                UpdateFullInventory(localPlayerInventory)
            end
        end)

        return
    end

    Log("Config.Items available, proceeding with inventory reconstruction. Config items count: " .. tablelength(configItems), "info", "CNR_INV_CLIENT")

    if minimalInventoryData and type(minimalInventoryData) == 'table' then
        for itemId, minItemData in pairs(minimalInventoryData) do
            if minItemData and minItemData.count and minItemData.count > 0 then
                local itemDetails = nil
                -- Find the item in the local Config.Items (assuming configItems is an array as per typical Config.Items structure)
                for _, cfgItem in ipairs(configItems) do
                    if cfgItem.itemId == itemId then
                        itemDetails = cfgItem
                        break
                    end
                end

                if itemDetails then
                    reconstructedInventory[itemId] = {
                        itemId = itemId,
                        name = itemDetails.name,
                        category = itemDetails.category,
                        count = minItemData.count,
                        basePrice = itemDetails.basePrice -- Store other useful info if needed
                    }
                else
                    Log(string.format("UpdateFullInventory: ItemId '%s' not found in local clientConfigItems. Storing with minimal details.", itemId), "warn", "CNR_INV_CLIENT")
                    reconstructedInventory[itemId] = { -- Fallback if item not in config (should be rare)
                        itemId = itemId,
                        name = itemId,
                        category = "Unknown",
                        count = minItemData.count
                    }
                end
            end
        end
    end

    localPlayerInventory = reconstructedInventory
    Log("Full inventory reconstructed. Item count: " .. tablelength(localPlayerInventory), "info", "CNR_INV_CLIENT")

    -- NUI is now primarily responsible for using its own fullItemConfig for the Sell tab.
    -- This message just signals that an update happened.
    SendNUIMessage({
        action = 'refreshSellListIfNeeded'
    })

    EquipInventoryWeapons()
    Log("UpdateFullInventory: Called EquipInventoryWeapons() after inventory reconstruction.", "info", "CNR_INV_CLIENT")
end


function RequestInventoryForNUI(callback)
    -- This function is now simplified. It returns the current client-side reconstructed inventory.
    -- The NUI should rely on `refreshSellListIfNeeded` (triggered by `cnr:syncInventory -> UpdateFullInventory`)
    -- for knowing when to re-fetch/re-render its sell list by calling the NUI callback `getPlayerInventory`.
    if callback then
        callback(GetLocalInventory())
    end
    Log("RequestInventoryForNUI: Provided current localPlayerInventory to callback.", "info", "CNR_INV_CLIENT")
end

function GetLocalInventory()
    return localPlayerInventory
end

Log("Custom Inventory System (client-side) loaded.", "info", "CNR_INV_CLIENT")

local function tablelength(T)
  if type(T) ~= "table" then return 0 end
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end

function EquipInventoryWeapons()
    local playerPed = PlayerPedId()

    if not playerPed or playerPed == 0 or playerPed == -1 then
        Log("EquipInventoryWeapons: Invalid playerPed. Cannot equip weapons/armor.", "error", "CNR_INV_CLIENT")
        return
    end

    -- Reset equipped items tracking
    localPlayerEquippedItems = {}

    Log("EquipInventoryWeapons: Starting equipment process. Inv count: " .. tablelength(localPlayerInventory), "info", "CNR_INV_CLIENT")

    if not localPlayerInventory or tablelength(localPlayerInventory) == 0 then
        Log("EquipInventoryWeapons: Player inventory is empty or nil.", "info", "CNR_INV_CLIENT")
        return
    end

    -- Debug: Log all items in inventory
    for itemId, itemData in pairs(localPlayerInventory) do
        Log(string.format("  DEBUG_INVENTORY: Item %s - Name: %s, Category: %s, Count: %s", itemId, tostring(itemData.name), tostring(itemData.category), tostring(itemData.count)), "info", "CNR_INV_CLIENT")
    end

    -- First, remove all weapons from the player to ensure clean state (armor is preserved)
    Log("EquipInventoryWeapons: Removing all existing weapons to ensure clean state.", "info", "CNR_INV_CLIENT")
    RemoveAllPedWeapons(playerPed, true)

    Citizen.Wait(500) -- Longer wait to ensure weapons are removed and game state is clean

    local processedItemCount = 0
    local weaponsEquipped = 0
    local armorApplied = false

    -- Process each inventory item once
    for itemId, itemData in pairs(localPlayerInventory) do
        processedItemCount = processedItemCount + 1

        if type(itemData) == "table" and itemData.category and itemData.count and itemData.name then
            -- Handle Armor items first (apply to player's armor bar)
            if itemData.category == "Armor" and itemData.count > 0 and not armorApplied then
                local armorAmount = 100 -- Default armor amount
                if itemId == "heavy_armor" then
                    armorAmount = 200 -- Heavy armor gives more protection
                end

                SetPedArmour(playerPed, armorAmount)
                armorApplied = true
                Log(string.format("  ✓ APPLIED ARMOR: %s (Amount: %d)", itemData.name or itemId, armorAmount), "info", "CNR_INV_CLIENT")

            -- Handle weapon items (including gas weapons in Utility category)
            elseif (itemData.category == "Weapons" or itemData.category == "Melee Weapons" or
                   (itemData.category == "Utility" and string.find(itemId, "weapon_"))) and itemData.count > 0 then
                
                -- Multiple hash attempts for better compatibility
                local weaponHash = 0
                local attemptedHashes = {}
                
                -- Try original itemId
                weaponHash = GetHashKey(itemId)
                table.insert(attemptedHashes, itemId .. " -> " .. weaponHash)
                
                -- Try uppercase version
                if weaponHash == 0 or weaponHash == -1 then
                    local upperItemId = string.upper(itemId)
                    weaponHash = GetHashKey(upperItemId)
                    table.insert(attemptedHashes, upperItemId .. " -> " .. weaponHash)
                end
                
                -- Try with WEAPON_ prefix if not present
                if (weaponHash == 0 or weaponHash == -1) and not string.find(itemId, "weapon_") then
                    local prefixedId = "weapon_" .. itemId
                    weaponHash = GetHashKey(prefixedId)
                    table.insert(attemptedHashes, prefixedId .. " -> " .. weaponHash)
                end

                Log(string.format("  DEBUG_HASH: ItemId: %s, Attempted hashes: %s, Final hash: %s", itemId, table.concat(attemptedHashes, ", "), weaponHash), "info", "CNR_INV_CLIENT")

                if weaponHash ~= 0 and weaponHash ~= -1 then
                    -- Determine ammo: use itemData.ammo if present, else default
                    local ammoCount = itemData.ammo
                    if ammoCount == nil then
                        if Config and Config.DefaultWeaponAmmo and Config.DefaultWeaponAmmo[itemId] then
                           ammoCount = Config.DefaultWeaponAmmo[itemId]
                        else
                           ammoCount = 250 -- Increased default ammo for better testing
                        end
                    end

                    -- Ensure weapon model is loaded before giving weapon
                    if not HasWeaponAssetLoaded(weaponHash) then
                        RequestWeaponAsset(weaponHash, 31, 0)
                        local loadTimeout = 0
                        while not HasWeaponAssetLoaded(weaponHash) and loadTimeout < 50 do
                            Citizen.Wait(100)
                            loadTimeout = loadTimeout + 1
                        end
                        
                        if not HasWeaponAssetLoaded(weaponHash) then
                            Log(string.format("  ✗ WEAPON_LOAD_FAILED: %s (Hash: %s) - Asset failed to load", itemId, weaponHash), "error", "CNR_INV_CLIENT")
                        end
                    end

                    -- Give weapon with ammo (without immediately equipping)
                    GiveWeaponToPed(playerPed, weaponHash, ammoCount, false, false)
                    Citizen.Wait(300) -- Increased wait time for better compatibility

                    -- Ensure ammo is set correctly with multiple attempts
                    SetPedAmmo(playerPed, weaponHash, ammoCount)
                    Citizen.Wait(100)
                    
                    -- Verify and retry if needed
                    local actualAmmo = GetAmmoInPedWeapon(playerPed, weaponHash)
                    if actualAmmo ~= ammoCount then
                        SetPedAmmo(playerPed, weaponHash, ammoCount)
                        Citizen.Wait(100)
                    end

                    -- Verify the weapon was equipped with improved retries
                    local hasWeapon = false
                    local maxRetries = 8
                    local retryCount = 0
                    
                    -- Initial check with delay
                    Citizen.Wait(200)
                    hasWeapon = HasPedGotWeapon(playerPed, weaponHash, false)
                    
                    while retryCount < maxRetries and not hasWeapon do
                        retryCount = retryCount + 1
                        Citizen.Wait(400) -- Increased wait time for better stability
                        
                        -- Different retry strategies based on attempt number
                        if retryCount <= 3 then
                            -- First attempts: Re-give weapon with different parameters
                            RemoveWeaponFromPed(playerPed, weaponHash)
                            Citizen.Wait(100)
                            GiveWeaponToPed(playerPed, weaponHash, ammoCount, false, true)
                        elseif retryCount <= 6 then
                            -- Middle attempts: Force equip approach
                            SetCurrentPedWeapon(playerPed, weaponHash, true)
                            Citizen.Wait(100)
                            SetPedAmmo(playerPed, weaponHash, ammoCount)
                        else
                            -- Final attempts: Complete re-add with component check
                            RemoveAllPedWeapons(playerPed, true)
                            Citizen.Wait(200)
                            GiveWeaponToPed(playerPed, weaponHash, ammoCount, false, true)
                            SetCurrentPedWeapon(playerPed, weaponHash, true)
                        end
                        
                        Citizen.Wait(200)
                        hasWeapon = HasPedGotWeapon(playerPed, weaponHash, false)
                    end
                      if hasWeapon then
                        weaponsEquipped = weaponsEquipped + 1
                        -- Track this as equipped for UI
                        localPlayerEquippedItems[itemId] = true
                        Log(string.format("  ✓ EQUIPPED: %s (ID: %s, Hash: %s) Ammo: %d (Retries: %d)", itemData.name or itemId, itemId, weaponHash, ammoCount, retryCount), "info", "CNR_INV_CLIENT")
                    else
                        localPlayerEquippedItems[itemId] = false
                        Log(string.format("  ✗ FAILED_EQUIP: %s (ID: %s, Hash: %s) - HasPedGotWeapon returned false after %d retries", itemData.name or itemId, itemId, weaponHash, maxRetries), "error", "CNR_INV_CLIENT")
                    end
                else
                    Log(string.format("  ✗ INVALID_HASH: ItemId: %s (Name: %s) - Could not get valid weapon hash", itemId, itemData.name), "error", "CNR_INV_CLIENT")
                end
            else
                Log(string.format("  SKIPPED: Item %s (Name: %s) - Category: %s, Count: %s", itemId, tostring(itemData.name), tostring(itemData.category), tostring(itemData.count)), "info", "CNR_INV_CLIENT")
            end
        else
            Log(string.format("  WARNING: Item ID: %s missing data (Name: %s, Category: %s, Count: %s).", itemId, tostring(itemData.name), tostring(itemData.category), tostring(itemData.count)), "warn", "CNR_INV_CLIENT")
        end
    end

    Log(string.format("EquipInventoryWeapons: Finished. Processed %d items. Successfully equipped %d weapons. Armor applied: %s", processedItemCount, weaponsEquipped, armorApplied and "Yes" or "No"), "info", "CNR_INV_CLIENT")

    -- Select the first weapon if any weapons were equipped
    if weaponsEquipped > 0 then
        Citizen.Wait(200)
        -- Try to select the first weapon we found
        for itemId, itemData in pairs(localPlayerInventory) do
            if type(itemData) == "table" and itemData.category and itemData.count and itemData.name then
                if (itemData.category == "Weapons" or itemData.category == "Melee Weapons") and itemData.count > 0 then
                    local upperItemId = string.upper(itemId)
                    local weaponHash = GetHashKey(upperItemId)
                    if weaponHash == 0 or weaponHash == -1 then
                        weaponHash = GetHashKey(itemId)
                    end
                    if weaponHash ~= 0 and weaponHash ~= -1 then
                        -- Select this weapon to make it visible in the weapon wheel
                        SetCurrentPedWeapon(playerPed, weaponHash, true)
                        Log(string.format("  SELECTED: %s as current weapon", itemData.name or itemId), "info", "CNR_INV_CLIENT")
                        break -- Only select the first weapon
                    end
                end
            end
        end
    end

    -- Final verification - list all weapons the player currently has
    Citizen.Wait(100)
    Log("EquipInventoryWeapons: Final weapon check:", "info", "CNR_INV_CLIENT")
    local configItems = GetClientConfigItems()
    if configItems then
        for _, cfgItem in ipairs(configItems) do
            if cfgItem.category == "Weapons" then
                local weaponHash = GetHashKey(cfgItem.itemId)
                if weaponHash ~= 0 and weaponHash ~= -1 then
                    local hasWeapon = HasPedGotWeapon(playerPed, weaponHash, false)
                    if hasWeapon then
                        local ammoCount = GetAmmoInPedWeapon(playerPed, weaponHash)
                        Log(string.format("  FINAL_CHECK: Player has %s (%s) with %d ammo", cfgItem.name, cfgItem.itemId, ammoCount), "info", "CNR_INV_CLIENT")
                    end
                end
            end
        end
    end
end

-- Add test event handler for testing weapon equipping from client.lua
RegisterNetEvent('cnr:testEquipWeapons')
AddEventHandler('cnr:testEquipWeapons', function()
    Log("Test equip weapons event received", "info", "CNR_INV_CLIENT")
    EquipInventoryWeapons()
end)

-- Debug command to manually request config items
RegisterCommand('requestconfig', function()
    if clientConfigItems then
        Log("Config.Items already available. Item count: " .. tablelength(clientConfigItems), "info", "CNR_INV_CLIENT")
    else
        TriggerServerEvent('cnr:requestConfigItems')
        Log("Manually requested Config.Items from server", "info", "CNR_INV_CLIENT")
    end
end, false)

-- Debug command to check current config status
RegisterCommand('checkconfig', function()
    if clientConfigItems then
        Log("Config.Items available. Item count: " .. tablelength(clientConfigItems), "info", "CNR_INV_CLIENT")
        Log("Sample items:", "info", "CNR_INV_CLIENT")
        local count = 0
        for _, item in ipairs(clientConfigItems) do
            count = count + 1
            Log("  " .. count .. ". " .. (item.name or "NO_NAME") .. " (" .. (item.itemId or "NO_ID") .. ") - " .. (item.category or "NO_CATEGORY"), "info", "CNR_INV_CLIENT")
            if count >= 5 then break end -- Show only first 5 items
        end
    else
        Log("Config.Items NOT available!", "error", "CNR_INV_CLIENT")
    end

    Log("Current localPlayerInventory item count: " .. tablelength(localPlayerInventory), "info", "CNR_INV_CLIENT")
end, false)

-- Add toggle inventory UI function
function ToggleInventoryUI()
    if isInventoryOpen then
        TriggerEvent('cnr:closeInventory')
    else
        TriggerEvent('cnr:openInventory')
    end
end

-- Track equipped items
local localPlayerEquippedItems = {}

-- Register NUI callback for retrieving player inventory
RegisterNUICallback('getPlayerInventoryForUI', function(data, cb)
    Log("NUI requested inventory via getPlayerInventoryForUI", "info", "CNR_INV_CLIENT")
    
    -- Check if inventory data is available
    if localPlayerInventory and next(localPlayerInventory) then
        -- Collect equipped weapons for UI
        local equippedItems = {}
        local playerPed = PlayerPedId()
        
        -- Check each weapon in inventory to see if it's equipped
        for itemId, itemData in pairs(localPlayerInventory) do
            if itemData.type == "weapon" and itemData.weaponHash then
                if HasPedGotWeapon(playerPed, itemData.weaponHash, false) then
                    table.insert(equippedItems, itemId)
                    localPlayerEquippedItems[itemId] = true
                else
                    localPlayerEquippedItems[itemId] = false
                end
            end
        end
        
        Log("Returning inventory with " .. tablelength(localPlayerInventory) .. " items and " .. #equippedItems .. " equipped items", "info", "CNR_INV_CLIENT")
        
        cb({
            success = true,
            inventory = localPlayerInventory,
            equippedItems = equippedItems
        })
    else        -- Request inventory from server if not available locally
        TriggerServerEvent('cnr:requestMyInventory')
        
        -- Return empty inventory with error message
        cb({
            success = false,
            error = "Inventory data not available, requesting from server",
            inventory = {},
            equippedItems = {} -- Return empty equipped items array to prevent undefined
        })
    end
end)

-- Register NUI callback for getting player inventory (used by store sell tab)
RegisterNUICallback('getPlayerInventory', function(data, cb)
    Log("NUI requested inventory via getPlayerInventory", "info", "CNR_INV_CLIENT")
    
    -- Check if inventory data is available
    if localPlayerInventory and next(localPlayerInventory) then
        Log("Returning inventory with " .. tablelength(localPlayerInventory) .. " items for sell tab", "info", "CNR_INV_CLIENT")
        
        cb({
            success = true,
            inventory = localPlayerInventory
        })
    else
        -- Request inventory from server if not available locally
        TriggerServerEvent('cnr:requestMyInventory')
        
        -- Return empty inventory with error message
        cb({
            success = false,
            error = "Inventory data not available, requesting from server",
            inventory = {}
        })
    end
end)

-- Register NUI callback for setting NUI focus (called from JavaScript)
RegisterNUICallback('setNuiFocus', function(data, cb)
    Log("NUI requested SetNuiFocus: " .. tostring(data.hasFocus) .. ", " .. tostring(data.hasCursor), "info", "CNR_INV_CLIENT")
    
    -- Set NUI focus based on the data received
    SetNuiFocus(data.hasFocus or false, data.hasCursor or false)
    
    -- Acknowledge the request
    cb({
        success = true
    })
end)

-- Register NUI callback for closing inventory (called from JavaScript)
RegisterNUICallback('closeInventory', function(data, cb)
    Log("NUI requested to close inventory", "info", "CNR_INV_CLIENT")
    
    -- Trigger the close inventory event
    TriggerEvent('cnr:closeInventory')
    
    -- Acknowledge the request
    cb({
        success = true
    })
end)

-- Ensure Config.Items are available to NUI when stores open
RegisterNetEvent('cnr:ensureConfigItems')
AddEventHandler('cnr:ensureConfigItems', function()
    if clientConfigItems and next(clientConfigItems) then
        -- Config is available, send to NUI
        SendNUIMessage({
            action = 'storeFullItemConfig',
            itemConfig = clientConfigItems
        })
        Log("Re-sent Config.Items to NUI to ensure availability", "info", "CNR_INV_CLIENT")
    else
        -- Config not available, request from server
        TriggerServerEvent('cnr:requestConfigItems')
        Log("Config.Items not available, requested from server", "warn", "CNR_INV_CLIENT")
    end
end)

-- Export functions for other client scripts
exports('EquipInventoryWeapons', EquipInventoryWeapons)
exports('GetClientConfigItems', GetClientConfigItems)
exports('UpdateFullInventory', UpdateFullInventory)
exports('ToggleInventoryUI', ToggleInventoryUI)

-- Event handlers for inventory UI
RegisterNetEvent('cnr:openInventory')
AddEventHandler('cnr:openInventory', function()
    Log("Received cnr:openInventory event", "info", "CNR_INV_CLIENT")

    -- Check if we have Config.Items available
    if not clientConfigItems or not next(clientConfigItems) then
        -- Show error message to player
        TriggerEvent('chat:addMessage', { args = {"^1[Inventory]", "Inventory system is still loading. Please try again in a few seconds."} })
        Log("Inventory open failed: Config.Items not yet available", "warn", "CNR_INV_CLIENT")
        return
    end

    if not isInventoryOpen then
        isInventoryOpen = true
        SendNUIMessage({
            action = 'openInventory',
            inventory = localPlayerInventory
        })
        SetNuiFocus(true, true)
        Log("Inventory UI opened via event", "info", "CNR_INV_CLIENT")
    end
end)

RegisterNetEvent('cnr:closeInventory')
AddEventHandler('cnr:closeInventory', function()
    Log("Received cnr:closeInventory event", "info", "CNR_INV_CLIENT")
    if isInventoryOpen then
        isInventoryOpen = false
        SendNUIMessage({
            action = 'closeInventory'
        })
        
        -- Ensure the NUI focus is properly reset
        SetNuiFocus(false, false)
        
        -- Ensure the game controls are re-enabled
        SetPlayerControl(PlayerId(), true, 0)
        
        Log("Inventory UI closed via event", "info", "CNR_INV_CLIENT")
    end
end)
