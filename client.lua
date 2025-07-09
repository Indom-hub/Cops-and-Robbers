-- client.lua
-- Cops & Robbers FiveM Game Mode - Client Script
-- Version: 1.2 | Date: June 17, 2025
-- Ped readiness flag and guards implemented.

-- =====================================
--     REGISTER NET EVENTS (MUST BE FIRST)
-- =====================================

-- Register all client events that will be triggered from server
RegisterNetEvent('cnr:sendInventoryForUI')
RegisterNetEvent('cnr:updatePlayerData')
RegisterNetEvent('cnr:spawnPlayerAt')
RegisterNetEvent('cnr:receiveMyInventory')
RegisterNetEvent('cnr:syncInventory')
RegisterNetEvent('cnr:inventoryUpdated')
RegisterNetEvent('cnr:receiveConfigItems')
RegisterNetEvent('cnr:showWantedLevel')
RegisterNetEvent('cnr:hideWantedLevel')
RegisterNetEvent('cnr:updateWantedLevel')
RegisterNetEvent('cops_and_robbers:sendPlayerInventory')
RegisterNetEvent('cops_and_robbers:buyResult')
RegisterNetEvent('cnr:showAdminPanel')
RegisterNetEvent('cnr:showRobberMenu')
RegisterNetEvent('cnr:xpGained')
RegisterNetEvent('cnr:levelUp')
RegisterNetEvent('cops_and_robbers:updateWantedDisplay')
RegisterNetEvent('cnr:heistAlert')
RegisterNetEvent('cnr:startHeistTimer')
RegisterNetEvent('cnr:heistCompleted')
RegisterNetEvent('cops_and_robbers:sendItemList')
RegisterNetEvent('cnr:openContrabandStoreUI')
RegisterNetEvent('cnr:sendNUIMessage') -- Register new event for NUI messages
RegisterNetEvent('cnr:sendToJail')
RegisterNetEvent('cnr:releaseFromJail')
RegisterNetEvent('cnr:wantedLevelSync') -- Register wanted level sync event

-- =====================================
--           VARIABLES
-- =====================================

-- Ensure Config is available (fallback initialization)
Config = Config or {}
Config.SpeedLimitMph = Config.SpeedLimitMph or 60.0
Config.Keybinds = Config.Keybinds or {}
Config.NPCVendors = Config.NPCVendors or {}
Config.RobberVehicleSpawns = Config.RobberVehicleSpawns or {}
Config.ContrabandDealers = Config.ContrabandDealers or {}
Config.WantedSettings = Config.WantedSettings or { levels = {} }
Config.SpawnPoints = Config.SpawnPoints or {
    cop = vector3(452.6, -980.0, 30.7),
    robber = vector3(2126.7, 4794.1, 41.1),
    citizen = vector3(-260.0, -970.0, 31.2)
}

-- Player-related variables
local g_isPlayerPedReady = false
local role = nil
local playerCash = 0
local currentSpikeStrips = {}
local spikeStripModelHash = GetHashKey("p_ld_stinger_s")
local playerStats = {
    heists = 0,
    arrests = 0,
    rewards = 0
}
local currentObjective = nil
local playerWeapons = {}
local playerAmmo = {}

-- Player Data (Synced from Server)
local playerData = {
    xp = 0,
    level = 1,
    role = "citizen",
    perks = {},
    armorModifier = 1.0,
    money = 0
}

-- Wanted System Client State (Server-side managed)
local currentWantedStarsClient = 0
local currentWantedPointsClient = 0
local wantedUiLabel = ""

local xpForNextLevelDisplay = 0

-- Contraband Drop Client State
local activeDropBlips = {}
local clientActiveContrabandDrops = {}

-- Blip tracking
local copStoreBlips = {}
local robberStoreBlips = {}

-- Track protected peds to prevent NPC suppression from affecting them
local g_protectedPolicePeds = {}

-- Track spawned NPCs to prevent duplicates
local g_spawnedNPCs = {}
local g_spawnedVehicles = {}
local g_robberVehiclesSpawned = false

-- Safe Zone Client State
local isCurrentlyInSafeZone = false
local currentSafeZoneName = ""

-- Wanted System Expansion Client State
local currentPlayerNPCResponseEntities = {}
local corruptOfficialNPCs = {}
local currentHelpTextTarget = nil

-- Contraband collection state
local isCollectingFromDrop = nil
local collectionTimerEnd = 0

-- Store UI state
local isCopStoreUiOpen = false
local isRobberStoreUiOpen = false

-- Jail System Client State
local isJailed = false
local jailTimeRemaining = 0
local jailTimerDisplayActive = false
local jailReleaseLocation = nil -- To be set by config or default spawn
local JailMainPoint = vector3(1651.0, 2570.0, 45.5) -- Default, will be updated by server
local JailRadius = 50.0 -- Max distance from JailMainPoint before teleported back
local originalPlayerModelHash = nil -- Variable to store the player's model before jailing

-- =====================================
--           HELPER FUNCTIONS
-- =====================================


-- Helper function to draw text on screen
function DrawText2D(x, y, text, scale, color)
    SetTextFont(4)
    SetTextProportional(false)
    SetTextScale(scale, scale)
    SetTextColour(color[1], color[2], color[3], color[4])
    SetTextDropShadow()
    SetTextOutline()
    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(x, y)
end

-- Helper function to show notifications
local function ShowNotification(text)
    if not text or text == "" then
        print("ShowNotification: Received nil or empty text.")
        return
    end
    SetNotificationTextEntry("STRING")
    AddTextComponentSubstringPlayerName(text)
    DrawNotification(false, true)
end

-- Helper function to display help text
local function DisplayHelpText(text)
    if not text or text == "" then
        print("DisplayHelpText: Received nil or empty text.")
        return
    end
    BeginTextCommandDisplayHelp("STRING")
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, true, -1)
end

-- Helper function to calculate XP required for next level
function CalculateXpForNextLevelClient(currentLevel, playerRole)
    -- Base XP requirements
    local baseXP = 100
    local multiplier = 1.5
    
    -- Role-specific XP scaling
    local roleMultiplier = 1.0
    if playerRole == "cop" then
        roleMultiplier = 1.2  -- Cops need slightly more XP to level up
    elseif playerRole == "robber" then
        roleMultiplier = 1.0  -- Robbers have standard XP requirements
    end
    
    -- Calculate next level XP requirement: baseXP * (multiplier ^ currentLevel) * roleMultiplier
    return math.floor(baseXP * (multiplier ^ currentLevel) * roleMultiplier)
end

-- Helper function to count table entries
function tablelength(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end

-- Helper function to spawn player at role-specific location
local function spawnPlayer(playerRole)
    if not playerRole then
        print("Error: spawnPlayer called with nil role.")
        ShowNotification("~r~Error: Could not determine spawn point. Role not set.")
        return
    end
    local spawnPoint = Config.SpawnPoints[playerRole]
    if spawnPoint and spawnPoint.x and spawnPoint.y and spawnPoint.z then
        local playerPed = PlayerPedId()
        if playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed) then
            SetEntityCoords(playerPed, spawnPoint.x, spawnPoint.y, spawnPoint.z, false, false, false, true)
            ShowNotification("Spawned as " .. playerRole)
        else
            print("[CNR_CLIENT_WARN] spawnPlayer: playerPed invalid, cannot set coords.")
        end
    else
        print("Error: Invalid or missing spawn point for role: " .. tostring(playerRole))
        ShowNotification("~r~Error: Spawn point not found for your role.")
    end
end

-- Apply role-specific visual appearance and basic loadout
local function ApplyRoleVisualsAndLoadout(newRole, oldRole)
    local playerPed = PlayerPedId()
    if not (playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed)) then
        print("[CNR_CLIENT_ERROR] ApplyRoleVisualsAndLoadout: Invalid playerPed.")
        return
    end
    
    RemoveAllPedWeapons(playerPed, true)
    playerWeapons = {}
    playerAmmo = {}
    
    -- Get character data from server
    local characterData = nil
    
    -- Request character data from server (will be handled asynchronously)
    TriggerServerEvent('cnr:getCharacterForRole', newRole, 1)
    
    local modelToLoad = nil
    local modelHash = nil
    
    if characterData and characterData.model then
        -- Use saved character model
        modelToLoad = characterData.model
    else
        -- Use default role models
        if newRole == "cop" then
            modelToLoad = "mp_m_freemode_01"  -- Changed to freemode for customization
        elseif newRole == "robber" then
            modelToLoad = "mp_m_freemode_01"  -- Changed to freemode for customization
        else
            modelToLoad = "mp_m_freemode_01"
        end
    end
    
    modelHash = GetHashKey(modelToLoad)
    if modelHash and modelHash ~= 0 and modelHash ~= -1 then
        RequestModel(modelHash)
        local attempts = 0
        while not HasModelLoaded(modelHash) and attempts < 100 do
            Citizen.Wait(50)
            attempts = attempts + 1
        end
        
        if HasModelLoaded(modelHash) then
            SetPlayerModel(PlayerId(), modelHash)
            Citizen.Wait(100) -- Increased wait time for model to fully load
            
            -- Get the new ped after model change
            playerPed = PlayerPedId()
            
            if characterData then
                -- Apply saved character data
                if exports['cops-and-robbers'] and exports['cops-and-robbers'].ApplyCharacterData then
                    local success = exports['cops-and-robbers']:ApplyCharacterData(characterData, playerPed)
                    if success then
                        print("[CNR_CHARACTER_EDITOR] Applied saved character data")
                    else
                        print("[CNR_CHARACTER_EDITOR] Failed to apply saved character data, using defaults")
                        SetPedDefaultComponentVariation(playerPed)
                    end
                else
                    print("[CNR_CHARACTER_EDITOR] Character editor not available, using defaults")
                    SetPedDefaultComponentVariation(playerPed)
                end
            else
                -- Apply default appearance
                SetPedDefaultComponentVariation(playerPed)
                
                -- Apply basic role-specific uniform if no saved character
                if newRole == "cop" then
                    -- Basic cop uniform
                    SetPedComponentVariation(playerPed, 11, 55, 0, 0)  -- Tops - Police shirt
                    SetPedComponentVariation(playerPed, 4, 35, 0, 0)   -- Legs - Police pants
                    SetPedComponentVariation(playerPed, 6, 25, 0, 0)   -- Shoes - Police boots
                    SetPedPropIndex(playerPed, 0, 46, 0, true)         -- Hat - Police cap
                elseif newRole == "robber" then
                    -- Basic robber outfit
                    SetPedComponentVariation(playerPed, 11, 4, 0, 0)   -- Tops - Casual shirt
                    SetPedComponentVariation(playerPed, 4, 1, 0, 0)    -- Legs - Jeans
                    SetPedComponentVariation(playerPed, 6, 1, 0, 0)    -- Shoes - Sneakers
                    SetPedPropIndex(playerPed, 0, 18, 0, true)         -- Hat - Beanie
                end
            end
            
            SetModelAsNoLongerNeeded(modelHash)
        else
            print(string.format("[CNR_CLIENT_ERROR] ApplyRoleVisualsAndLoadout: Failed to load model %s after 100 attempts.", modelToLoad))
        end
    else
        print(string.format("[CNR_CLIENT_ERROR] ApplyRoleVisualsAndLoadout: Invalid model hash for %s.", modelToLoad))
    end
    
    Citizen.Wait(500)
    playerPed = PlayerPedId()
    if not (playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed)) then
        print("[CNR_CLIENT_ERROR] ApplyRoleVisualsAndLoadout: Invalid playerPed after model change attempt.")
        return
    end    if newRole == "cop" then
        local taserHash = GetHashKey("weapon_stungun")
        GiveWeaponToPed(playerPed, taserHash, 5, false, true)
        playerWeapons["weapon_stungun"] = true
        playerAmmo["weapon_stungun"] = 5
    elseif newRole == "robber" then
        local batHash = GetHashKey("weapon_bat")
        GiveWeaponToPed(playerPed, batHash, 1, false, true)
        playerWeapons["weapon_bat"] = true
        playerAmmo["weapon_bat"] = 1

        -- Note: Robber vehicles are spawned on resource start, not per-player
    end
    ShowNotification(string.format("~g~Role changed to %s. Model and basic loadout applied.", newRole))

   -- Equip weapons from inventory after role visuals and loadout are applied
   Citizen.Wait(50) -- Optional small delay to ensure ped model is fully set and previous weapons are processed.
   local currentResourceName = GetCurrentResourceName()
   if exports[currentResourceName] and exports[currentResourceName].EquipInventoryWeapons then
       exports[currentResourceName]:EquipInventoryWeapons()
   else
       print(string.format("[CNR_CLIENT_ERROR] ApplyRoleVisualsAndLoadout: Could not find export EquipInventoryWeapons in resource %s.", currentResourceName))
   end
end

-- Ensure SetWantedLevelForPlayerRole is defined before all uses
local function SetWantedLevelForPlayerRole(stars, points)
    local playerId = PlayerId()
    
    -- Always set the game's wanted level to 0 to prevent the native wanted UI from showing
    SetPlayerWantedLevel(playerId, 0, false)
    SetPlayerWantedLevelNow(playerId, false)
    
    -- Instead, we use our custom UI based on the stars parameter
    currentWantedStarsClient = stars
    currentWantedPointsClient = points
    
    -- Only show our custom wanted UI if player has stars
    if stars > 0 then
        SendNUIMessage({
            action = 'showWantedUI',
            stars = stars,
            points = points
        })
    else
        SendNUIMessage({
            action = 'hideWantedUI'
        })
    end
end

-- Patch: Exclude protected peds from police suppression
local function IsPedProtected(ped)
    return g_protectedPolicePeds[ped] == true
end

-- =====================================
--       WANTED LEVEL NOTIFICATIONS
-- =====================================

-- Handle wanted level notifications from server
AddEventHandler('cnr:showWantedLevel', function(stars, points, level)
    SendNUIMessage({
        action = 'showWantedNotification',
        stars = stars,
        points = points,
        level = level
    })
end)

AddEventHandler('cnr:hideWantedLevel', function()
    SendNUIMessage({
        action = 'hideWantedNotification'
    })
end)

AddEventHandler('cnr:updateWantedLevel', function(stars, points, level)
    -- Ensure all parameters have default values to prevent nil concatenation errors
    stars = stars or 0
    points = points or 0
    level = level or ("" .. stars .. " star" .. (stars ~= 1 and "s" or ""))
    
    SendNUIMessage({
        action = 'showWantedNotification', 
        stars = stars,
        points = points,
        level = level
    })
end)

-- =====================================
--   NPC POLICE SUPPRESSION
-- =====================================

-- Helper: Safe call for SetDispatchServiceActive (for environments where it may not be defined)
local function SafeSetDispatchServiceActive(service, toggle)
    local hash = GetHashKey("SetDispatchServiceActive")
    if Citizen and Citizen.InvokeNative and hash then
        -- 0xDC0F817884CDD856 is the native hash for SetDispatchServiceActive
        local nativeHash = 0xDC0F817884CDD856
        local ok, err = pcall(function()
            Citizen.InvokeNative(nativeHash, service, toggle)
        end)
        if not ok then
            print("[CNR_CLIENT_WARN] SetDispatchServiceActive (InvokeNative) failed for service " .. tostring(service) .. ": " .. tostring(err))
        end
    else
        -- fallback: do nothing
    end
end

-- Utility: Check if a ped is an NPC cop (by model or relationship group)
local function IsPedNpcCop(ped)
    if not DoesEntityExist(ped) then return false end
    local model = GetEntityModel(ped)
    local relGroup = GetPedRelationshipGroupHash(ped)
    local copModels = {
        [GetHashKey("s_m_y_cop_01")] = true,
        [GetHashKey("s_f_y_cop_01")] = true,
        [GetHashKey("s_m_y_swat_01")] = true,
        [GetHashKey("s_m_y_hwaycop_01")] = true,
        [GetHashKey("s_m_y_sheriff_01")] = true,
        [GetHashKey("s_f_y_sheriff_01")] = true,
    }
    return (copModels[model] or relGroup == GetHashKey("COP")) and not IsPedAPlayer(ped)
end

-- Aggressive police NPC suppression: Removes police NPCs and their vehicles near players with a wanted level.
Citizen.CreateThread(function()
    local policeSuppressInterval = 500 -- ms
    while true do
        Citizen.Wait(policeSuppressInterval)
        local playerPed = PlayerPedId()
        if playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed) then
            local handle, ped = FindFirstPed()
            local success, nextPed = true, ped
            repeat
                if DoesEntityExist(ped) and ped ~= playerPed and IsPedNpcCop(ped) and not IsPedProtected(ped) then
                    local vehicle = GetVehiclePedIsIn(ped, false)
                    local wasDriver = false
                    
                    -- Check if this ped is the driver before deleting the ped
                    if vehicle ~= 0 and DoesEntityExist(vehicle) then
                        wasDriver = GetPedInVehicleSeat(vehicle, -1) == ped
                    end
                    
                    SetEntityAsMissionEntity(ped, false, true)
                    ClearPedTasksImmediately(ped)
                    DeletePed(ped)
                    
                    -- Only delete the vehicle if the ped was the driver and no other player is in it
                    if wasDriver and vehicle ~= 0 and DoesEntityExist(vehicle) then
                        local hasPlayerInVehicle = false
                        for i = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
                            local seat_ped = GetPedInVehicleSeat(vehicle, i)
                            if seat_ped ~= 0 and seat_ped ~= ped and IsPedAPlayer(seat_ped) then
                                hasPlayerInVehicle = true
                                break
                            end
                        end
                        
                        -- Only delete if no players are using the vehicle
                        if not hasPlayerInVehicle then
                            SetEntityAsMissionEntity(vehicle, false, true)
                            DeleteEntity(vehicle)
                        end
                    end
                end
                success, nextPed = FindNextPed(handle)
                ped = nextPed
            until not success
            EndFindPed(handle)
        end
    end
end)

-- Prevent NPC police from responding to wanted levels (but keep wanted level for robbers)
Citizen.CreateThread(function()
    local interval = 1000
    while true do
        Citizen.Wait(interval)
        local playerId = PlayerId()
        local playerPed = PlayerPedId()
        if playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed) then
            SetPoliceIgnorePlayer(playerPed, true)
            for i = 1, 15 do
                SafeSetDispatchServiceActive(i, false)
            end
            if role == "cop" then
                if GetPlayerWantedLevel(playerId) > 0 then
                    SetPlayerWantedLevel(playerId, 0, false)
                    SetPlayerWantedLevelNow(playerId, false)
                end
            end
        end
    end
end)

-- Enhanced GTA native wanted level suppression for all players (we use custom system)
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000)

        local playerId = PlayerId()
        local currentWantedLevel = GetPlayerWantedLevel(playerId)

        if currentWantedLevel > 0 then
            if role == "cop" then
            elseif role == "robber" then
            end
            SetPlayerWantedLevel(playerId, 0, false)
            SetPlayerWantedLevelNow(playerId, false)
        end

        -- Ensure police blips are hidden and police ignore all players (we handle this via custom system)
        SetPoliceIgnorePlayer(PlayerPedId(), true)
    end
end)

-- Unlimited Stamina Thread
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(100)
        local playerPed = PlayerPedId()
        if playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed) then
            RestorePlayerStamina(PlayerId(), 100.0)
        end
    end
end)

-- Inventory Key Binding (M Key)
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(100) -- Reduced frequency to prevent performance issues
        if IsControlJustPressed(0, Config.Keybinds.openInventory or 244) then -- M Key (INPUT_INTERACTION_MENU)
            local currentResourceName = GetCurrentResourceName()

            if exports[currentResourceName] and exports[currentResourceName].ToggleInventoryUI then
                exports[currentResourceName]:ToggleInventoryUI()
            else
                -- Fallback: try to trigger inventory event
                TriggerEvent('cnr:openInventory')
            end
        end
    end
end)

-- Register the inventory commands that are missing
RegisterCommand('getweapons', function()
    local currentResourceName = GetCurrentResourceName()
    if exports[currentResourceName] and exports[currentResourceName].EquipInventoryWeapons then
        exports[currentResourceName]:EquipInventoryWeapons()
    else
        print("[CNR_CLIENT_ERROR] EquipInventoryWeapons export not found")
    end
end, false)

RegisterCommand('equipweapns', function()
    local currentResourceName = GetCurrentResourceName()
    if exports[currentResourceName] and exports[currentResourceName].EquipInventoryWeapons then
        exports[currentResourceName]:EquipInventoryWeapons()
    else
        print("[CNR_CLIENT_ERROR] EquipInventoryWeapons export not found")
    end
end, false)

-- =====================================
--       WANTED LEVEL DETECTION SYSTEM
-- =====================================

-- Client-side wanted level detection removed - now handled entirely server-side
-- This ensures only robbers can get wanted levels and prevents conflicts

-- Weapon firing detection for server-side processing
CreateThread(function()
    while true do
        Wait(0)
        
        local playerPed = PlayerPedId()
        if playerPed and DoesEntityExist(playerPed) then
            if IsPedShooting(playerPed) then
                local weaponHash = GetSelectedPedWeapon(playerPed)
                local coords = GetEntityCoords(playerPed)
                
                -- Send to server for processing (server will check if player is robber)
                TriggerServerEvent('cnr:weaponFired', weaponHash, coords)
                
                -- Small delay to prevent spam
                Wait(1000)
            end
        end
    end
end)

-- Player damage detection for server-side processing
local lastHealthCheck = {}

CreateThread(function()
    while true do
        Wait(500) -- Check every 500ms
        
        local players = GetActivePlayers()
        for _, player in ipairs(players) do
            local playerId = GetPlayerServerId(player)
            local playerPed = GetPlayerPed(player)
            
            if playerPed and DoesEntityExist(playerPed) and playerId ~= GetPlayerServerId(PlayerId()) then
                local currentHealth = GetEntityHealth(playerPed)
                local maxHealth = GetEntityMaxHealth(playerPed)
                
                if not lastHealthCheck[playerId] then
                    lastHealthCheck[playerId] = currentHealth
                else
                    local lastHealth = lastHealthCheck[playerId]
                    
                    if currentHealth < lastHealth then
                        -- Player took damage
                        local damage = lastHealth - currentHealth
                        local isFatal = currentHealth <= 0
                        local weaponHash = GetPedCauseOfDeath(playerPed)
                        
                        -- Send to server for processing
                        TriggerServerEvent('cnr:playerDamaged', playerId, damage, weaponHash, isFatal)
                    end
                    
                    lastHealthCheck[playerId] = currentHealth
                end
            end
        end
    end
end)

-- =====================================
--          MISSING KEYBINDS
-- =====================================

-- F2 - Robber Menu / Admin Panel
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        
        if IsControlJustPressed(0, Config.Keybinds.toggleAdminPanel or 289) then -- F2
            -- Check if player is admin first, otherwise show robber menu
            TriggerServerEvent('cnr:checkAdminStatus')
        end
    end
end)

-- F5 - Role Selection Menu
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        
        if IsControlJustPressed(0, 166) then -- F5 key
            TriggerEvent('cnr:showRoleSelection')
        end
    end
end)

-- Event handlers for admin status check
AddEventHandler('cnr:showAdminPanel', function()
    -- Show admin panel UI
    SendNUIMessage({
        action = 'showAdminPanel'
    })
    SetNuiFocus(true, true)
end)

AddEventHandler('cnr:showRobberMenu', function()
    -- Show robber-specific menu
    SendNUIMessage({
        action = 'showRobberMenu'
    })
    SetNuiFocus(true, true)
end)

-- =====================================
--           STORE BLIP MANAGEMENT
-- =====================================

function UpdateCopStoreBlips()
    if not Config.NPCVendors then
        print("[CNR_CLIENT_WARN] UpdateCopStoreBlips: Config.NPCVendors not found.")
        return
    end
    if type(Config.NPCVendors) ~= "table" or (getmetatable(Config.NPCVendors) and getmetatable(Config.NPCVendors).__name == "Map") then
        print("[CNR_CLIENT_ERROR] UpdateCopStoreBlips: Config.NPCVendors is not an array. Cannot iterate.")
        return
    end
    for i, vendor in ipairs(Config.NPCVendors) do
        if vendor and vendor.location and vendor.name then
            local blipKey = tostring(vendor.location.x .. "_" .. vendor.location.y .. "_" .. vendor.location.z)
            if vendor.name == "Cop Store" then
                if role == "cop" then
                    if not copStoreBlips[blipKey] or not DoesBlipExist(copStoreBlips[blipKey]) then
                        local blip = AddBlipForCoord(vendor.location.x, vendor.location.y, vendor.location.z)
                        SetBlipSprite(blip, 60)
                        SetBlipColour(blip, 3)
                        SetBlipScale(blip, 0.8)
                        SetBlipAsShortRange(blip, true)
                        BeginTextCommandSetBlipName("STRING")
                        AddTextComponentSubstringPlayerName(vendor.name)
                        EndTextCommandSetBlipName(blip)
                        copStoreBlips[blipKey] = blip
                    end
                else
                    if copStoreBlips[blipKey] and DoesBlipExist(copStoreBlips[blipKey]) then
                        RemoveBlip(copStoreBlips[blipKey])
                        copStoreBlips[blipKey] = nil
                    end
                end
            else
                if copStoreBlips[blipKey] and DoesBlipExist(copStoreBlips[blipKey]) then
                    print(string.format("[CNR_CLIENT_WARN] Removing stray blip from copStoreBlips, associated with a non-Cop Store: '%s' at %s", vendor.name, blipKey))
                    RemoveBlip(copStoreBlips[blipKey])
                    copStoreBlips[blipKey] = nil
                end
            end
        else
            print(string.format("[CNR_CLIENT_WARN] UpdateCopStoreBlips: Invalid vendor entry at index %d.", i))
        end
    end
    for blipKey, blipId in pairs(copStoreBlips) do
        local stillExistsAndIsCopStore = false
        if Config.NPCVendors and type(Config.NPCVendors) == "table" then
            for _, vendor in ipairs(Config.NPCVendors) do
                if vendor and vendor.location and vendor.name then
                    if tostring(vendor.location.x .. "_" .. vendor.location.y .. "_" .. vendor.location.z) == blipKey and vendor.name == "Cop Store" then
                        stillExistsAndIsCopStore = true
                        break
                    end
                end
            end
        end
        if not stillExistsAndIsCopStore then
            if blipId and DoesBlipExist(blipId) then
                RemoveBlip(blipId)
            end
            copStoreBlips[blipKey] = nil
        end
    end
end

-- Update Robber Store Blips (visible only to robbers)
function UpdateRobberStoreBlips()
    if not Config.NPCVendors then
        print("[CNR_CLIENT_WARN] UpdateRobberStoreBlips: Config.NPCVendors not found.")
        return
    end
    if type(Config.NPCVendors) ~= "table" or (getmetatable(Config.NPCVendors) and getmetatable(Config.NPCVendors).__name == "Map") then
        print("[CNR_CLIENT_ERROR] UpdateRobberStoreBlips: Config.NPCVendors is not an array. Cannot iterate.")
        return
    end
      for i, vendor in ipairs(Config.NPCVendors) do
        -- Skip invalid vendor entries
        if not vendor or not vendor.location or not vendor.name then
            if not vendor then
                print(string.format("[CNR_CLIENT_WARN] UpdateRobberStoreBlips: Nil vendor entry at index %d.", i))
            elseif not vendor.location then
                print(string.format("[CNR_CLIENT_WARN] UpdateRobberStoreBlips: Missing location for vendor at index %d.", i))
            elseif not vendor.name then
                print(string.format("[CNR_CLIENT_WARN] UpdateRobberStoreBlips: Missing name for vendor at index %d.", i))
            end
            -- Skip processing this invalid entry
        elseif vendor and vendor.location and vendor.name then
            -- Process valid vendor entries
            if vendor.name == "Black Market Dealer" or vendor.name == "Gang Supplier" then
                local blipKey = tostring(vendor.location.x .. "_" .. vendor.location.y .. "_" .. vendor.location.z)
                
                -- Only show robber store blips to robbers
                if role == "robber" then
                    if not robberStoreBlips[blipKey] or not DoesBlipExist(robberStoreBlips[blipKey]) then
                        local blip = AddBlipForCoord(vendor.location.x, vendor.location.y, vendor.location.z)
                        if vendor.name == "Black Market Dealer" then
                            SetBlipSprite(blip, 266) -- Gun store icon
                            SetBlipColour(blip, 1) -- Red
                            BeginTextCommandSetBlipName("STRING")
                            AddTextComponentString("Black Market")
                            EndTextCommandSetBlipName(blip)
                        else -- Gang Supplier
                            SetBlipSprite(blip, 267) -- Ammu-nation icon
                            SetBlipColour(blip, 5) -- Yellow
                            BeginTextCommandSetBlipName("STRING")
                            AddTextComponentString("Gang Supplier")
                            EndTextCommandSetBlipName(blip)
                        end
                        SetBlipScale(blip, 0.8)
                        SetBlipAsShortRange(blip, true)
                        robberStoreBlips[blipKey] = blip
                    end
                else
                    -- Remove robber store blips for non-robbers
                    if robberStoreBlips[blipKey] and DoesBlipExist(robberStoreBlips[blipKey]) then
                        RemoveBlip(robberStoreBlips[blipKey])
                        robberStoreBlips[blipKey] = nil
                    end
                end
            else
                print(string.format("[CNR_CLIENT_WARN] UpdateRobberStoreBlips: Invalid vendor entry at index %d. Vendor: %s", i, vendor and vendor.name or "unknown"))
            end
        end
    end
    -- Clean up orphaned blips
    for blipKey, blipId in pairs(robberStoreBlips) do
        local stillExistsAndIsRobberStore = false
        if Config.NPCVendors and type(Config.NPCVendors) == "table" then
            for _, vendor in ipairs(Config.NPCVendors) do
                if vendor and vendor.location and vendor.name then
                    if tostring(vendor.location.x .. "_" .. vendor.location.y .. "_" .. vendor.location.z) == blipKey and (vendor.name == "Black Market Dealer" or vendor.name == "Gang Supplier") then
                        stillExistsAndIsRobberStore = true
                        break
                    end
                end
            end
        end
        if not stillExistsAndIsRobberStore then
            if blipId and DoesBlipExist(blipId) then
                RemoveBlip(blipId)
            end
            robberStoreBlips[blipKey] = nil
        end
    end
end

-- =====================================
--           NPC MANAGEMENT
-- =====================================

-- Helper to spawn the Cop Store ped and protect it from suppression
function SpawnCopStorePed()
    -- Check if already spawned
    if g_spawnedNPCs["CopStore"] then
        return
    end

    local vendor = nil
    if Config and Config.NPCVendors then
        for _, v in ipairs(Config.NPCVendors) do
            if v.name == "Cop Store" then
                vendor = v
                break
            end
        end
    end
    if not vendor then
        print("[CNR_CLIENT_ERROR] Cop Store vendor not found in Config.NPCVendors")
        return
    end

    local model = GetHashKey("s_m_m_ciasec_01") -- Use a unique cop-like model not used by NPC police
    RequestModel(model)
    while not HasModelLoaded(model) do Citizen.Wait(10) end

    -- Handle both vector3 and vector4 formats for location
    local x, y, z, heading
    if vendor.location.w then
        -- vector4 format
        x, y, z, heading = vendor.location.x, vendor.location.y, vendor.location.z, vendor.location.w
    else
        -- vector3 format with separate heading
        x, y, z = vendor.location.x, vendor.location.y, vendor.location.z
        heading = vendor.heading or 0.0
    end

    local ped = CreatePed(4, model, x, y, z - 1.0, heading, false, true)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false) -- Corrected: use boolean false
    SetPedCombatAttributes(ped, 17, true) -- Corrected: use boolean true
    SetPedCanRagdoll(ped, false)
    SetPedDiesWhenInjured(ped, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    g_protectedPolicePeds[ped] = true
    g_spawnedNPCs["CopStore"] = ped
end

-- Helper to spawn Robber Store peds and protect them from suppression
function SpawnRobberStorePeds()
    if not Config or not Config.NPCVendors then
        print("[CNR_CLIENT_ERROR] SpawnRobberStorePeds: Config.NPCVendors not found")
        return
    end    for _, vendor in ipairs(Config.NPCVendors) do
        if vendor.name == "Black Market Dealer" or vendor.name == "Gang Supplier" then
            -- Check if already spawned
            if not g_spawnedNPCs[vendor.name] then
                local modelHash = GetHashKey(vendor.model or "s_m_y_dealer_01")
                RequestModel(modelHash)
                while not HasModelLoaded(modelHash) do
                    Citizen.Wait(10)
                end

                -- Handle both vector3 and vector4 formats for location
                local x, y, z, heading
                if vendor.location.w then
                    -- vector4 format
                    x, y, z, heading = vendor.location.x, vendor.location.y, vendor.location.z, vendor.location.w
                else
                    -- vector3 format with separate heading
                    x, y, z = vendor.location.x, vendor.location.y, vendor.location.z
                    heading = vendor.heading or 0.0
                end

                local ped = CreatePed(4, modelHash, x, y, z - 1.0, heading, false, true)
                SetEntityAsMissionEntity(ped, true, true)
                SetBlockingOfNonTemporaryEvents(ped, true)
                SetPedFleeAttributes(ped, 0, false)
                SetPedCombatAttributes(ped, 17, true)
                SetPedCanRagdoll(ped, false)
                SetPedDiesWhenInjured(ped, false)
                SetEntityInvincible(ped, true)
                FreezeEntityPosition(ped, true)

                -- Add to protected peds to prevent deletion by NPC suppression
                g_protectedPolicePeds[ped] = true
                g_spawnedNPCs[vendor.name] = ped

            end
        end
    end
end

-- Vehicle spawning system for robbers
function SpawnRobberVehicles()
    -- Prevent multiple spawning
    if g_robberVehiclesSpawned then
        return
    end

    if not Config or not Config.RobberVehicleSpawns then
        print("[CNR_CLIENT_ERROR] SpawnRobberVehicles: Config.RobberVehicleSpawns not found")
        return
    end

    g_robberVehiclesSpawned = true

    for _, vehicleSpawn in ipairs(Config.RobberVehicleSpawns) do
        if vehicleSpawn.location and vehicleSpawn.model then
            local modelHash = GetHashKey(vehicleSpawn.model)
            RequestModel(modelHash)

            -- Wait for model to load
            local attempts = 0
            while not HasModelLoaded(modelHash) and attempts < 100 do
                Citizen.Wait(50)
                attempts = attempts + 1
            end
              if HasModelLoaded(modelHash) then
                -- Handle both vector3 and vector4 formats
                local x, y, z, heading
                if vehicleSpawn.location.w then
                    -- vector4 format
                    x, y, z, heading = vehicleSpawn.location.x, vehicleSpawn.location.y, vehicleSpawn.location.z, vehicleSpawn.location.w
                else
                    -- vector3 format with separate heading
                    x, y, z = vehicleSpawn.location.x, vehicleSpawn.location.y, vehicleSpawn.location.z
                    heading = vehicleSpawn.heading or 0.0
                end

                local vehicle = CreateVehicle(
                    modelHash,
                    x, y, z,
                    heading,
                    true, -- isNetwork
                    false -- netMissionEntity
                )

                if vehicle and DoesEntityExist(vehicle) then
                    -- Make vehicle available and persistent
                    SetEntityAsMissionEntity(vehicle, true, true)
                    SetVehicleOnGroundProperly(vehicle)
                    SetVehicleEngineOn(vehicle, false, true, false)
                    SetVehicleDoorsLocked(vehicle, 1) -- Unlocked
                else
                    print(string.format("[CNR_CLIENT_ERROR] Failed to create vehicle %s", vehicleSpawn.model))
                end
            else
                print(string.format("[CNR_CLIENT_ERROR] Failed to load model %s after 100 attempts", vehicleSpawn.model))
            end

            SetModelAsNoLongerNeeded(modelHash)
        end
    end
end

-- Call this on resource start and when player spawns
Citizen.CreateThread(function()
    Citizen.Wait(2000)
    SpawnCopStorePed()
    SpawnRobberStorePeds()
    SpawnRobberVehicles() -- Added vehicle spawning for robbers
    -- Initial blip setup based on current role
    if role == "cop" then
        UpdateCopStoreBlips()
    elseif role == "robber" then
        UpdateRobberStoreBlips()
    end
end)

-- =====================================
--           NETWORK EVENTS
-- =====================================

AddEventHandler('playerSpawned', function()
    TriggerServerEvent('cnr:playerSpawned') -- Corrected event name

    -- Only show role selection if player doesn't have a role yet
    if not role or role == "" then
        SendNUIMessage({ action = 'showRoleSelection', resourceName = GetCurrentResourceName() })
        SetNuiFocus(true, true) -- Ensure mouse pointer appears for role selection
    else
        -- Player already has a role, respawn them at their role's spawn point
        local spawnPoint = Config.SpawnPoints[role]
        if spawnPoint then
            local playerPed = PlayerPedId()
            SetEntityCoords(playerPed, spawnPoint.x, spawnPoint.y, spawnPoint.z, false, false, false, true)
            if role == "cop" then
                SetEntityHeading(playerPed, 270.0)
            elseif role == "robber" then
                SetEntityHeading(playerPed, 180.0)
            end
            ShowNotification("Respawned as " .. role)
            -- Reapply role visuals and loadout
            ApplyRoleVisualsAndLoadout(role, nil)
        end
    end
end)

RegisterNetEvent('cnr:updatePlayerData')
AddEventHandler('cnr:updatePlayerData', function(newPlayerData)
    if not newPlayerData then
        print("Error: 'cnr:updatePlayerData' received nil data.")
        ShowNotification("~r~Error: Failed to load player data.")
        return
    end
    local oldRole = playerData.role
    playerData = newPlayerData
    playerCash = newPlayerData.money or 0
    role = playerData.role
    local playerPedOnUpdate = PlayerPedId()
    -- Inventory is now handled by cnr:syncInventory event

    -- Update blips based on role
    if role == "cop" then
        UpdateCopStoreBlips()
        -- Clear robber store blips for cops
        for blipKey, blipId in pairs(robberStoreBlips) do
            if blipId and DoesBlipExist(blipId) then
                RemoveBlip(blipId)
            end
            robberStoreBlips[blipKey] = nil
        end
    elseif role == "robber" then
        UpdateRobberStoreBlips()
        -- Clear cop store blips for robbers
        for blipKey, blipId in pairs(copStoreBlips) do
            if blipId and DoesBlipExist(blipId) then
                RemoveBlip(blipId)
            end
            copStoreBlips[blipKey] = nil
        end
    else
        -- Clear all store blips for citizens
        for blipKey, blipId in pairs(copStoreBlips) do
            if blipId and DoesBlipExist(blipId) then
                RemoveBlip(blipId)
            end
            copStoreBlips[blipKey] = nil
        end
        for blipKey, blipId in pairs(robberStoreBlips) do
            if blipId and DoesBlipExist(blipId) then
                RemoveBlip(blipId)
            end
            robberStoreBlips[blipKey] = nil
        end
    end

    if role and oldRole ~= role then
        if playerPedOnUpdate and playerPedOnUpdate ~= 0 and playerPedOnUpdate ~= -1 and DoesEntityExist(playerPedOnUpdate) then
            ApplyRoleVisualsAndLoadout(role, oldRole)
            Citizen.Wait(100)
            spawnPlayer(role)
        else
            print("[CNR_CLIENT_WARN] cnr:updatePlayerData: playerPed invalid during role change spawn.")
        end
    elseif not oldRole and role and role ~= "citizen" then
        if playerPedOnUpdate and playerPedOnUpdate ~= 0 and playerPedOnUpdate ~= -1 and DoesEntityExist(playerPedOnUpdate) then
            ApplyRoleVisualsAndLoadout(role, oldRole)
            Citizen.Wait(100)
            spawnPlayer(role)
        else
            print("[CNR_CLIENT_WARN] cnr:updatePlayerData: playerPed invalid during initial role spawn.")
        end
    elseif not oldRole and role and role == "citizen" then
        if playerPedOnUpdate and playerPedOnUpdate ~= 0 and playerPedOnUpdate ~= -1 and DoesEntityExist(playerPedOnUpdate) then
            spawnPlayer(role)
        else
            print("[CNR_CLIENT_WARN] cnr:updatePlayerData: playerPed invalid during initial citizen spawn.")
        end
    end
    SendNUIMessage({ action = 'updateMoney', cash = playerCash })
    UpdateCopStoreBlips() -- removed argument
    SendNUIMessage({
        action = "updateXPBar",
        currentXP = playerData.xp,
        currentLevel = playerData.level,
        xpForNextLevel = CalculateXpForNextLevelClient(playerData.level, playerData.role)
    })
    ShowNotification(string.format("Data Synced: Lvl %d, XP %d, Role %s", playerData.level, playerData.xp, playerData.role))
    if newPlayerData.weapons and type(newPlayerData.weapons) == "table" then
        if playerPedOnUpdate and playerPedOnUpdate ~= 0 and playerPedOnUpdate ~= -1 and DoesEntityExist(playerPedOnUpdate) then
            playerWeapons = {}
            playerAmmo = {}
            for weaponName, ammoCount in pairs(newPlayerData.weapons) do
                local weaponHash = GetHashKey(weaponName)
                if weaponHash ~= 0 and weaponHash ~= -1 then
                    GiveWeaponToPed(playerPedOnUpdate, weaponHash, ammoCount or 0, false, false)
                    playerWeapons[weaponName] = true
                    playerAmmo[weaponName] = ammoCount or 0
                else
                    print("Warning: Invalid weaponName received in newPlayerData: " .. tostring(weaponName))
                end
            end
        else
            print("[CNR_CLIENT_WARN] cnr:updatePlayerData: playerPed invalid, cannot give weapons.")
        end
    end
    if not g_isPlayerPedReady and role and role ~= "citizen" then
        Citizen.CreateThread(function()
            Citizen.Wait(1500)
            g_isPlayerPedReady = true
            end)
    elseif role == "citizen" and g_isPlayerPedReady then
        g_isPlayerPedReady = false
        print("[CNR_CLIENT] Player Ped is NO LONGER READY (g_isPlayerPedReady = false) due to role change to citizen.")
    end
end)

RegisterNetEvent('cnr:xpGained')
AddEventHandler('cnr:xpGained', function(amount, newTotalXp)
    amount = amount or 0
    newTotalXp = newTotalXp or 0
    playerData.xp = newTotalXp
    ShowNotification(string.format("~g~+%d XP! (Total: %d)", amount, newTotalXp))
    SendNUIMessage({
        action = "updateXPBar",
        currentXP = playerData.xp,
        currentLevel = playerData.level,
        xpForNextLevel = CalculateXpForNextLevelClient(playerData.level, playerData.role),
        xpGained = amount
    })
end)

RegisterNetEvent('cnr:levelUp')
AddEventHandler('cnr:levelUp', function(newLevel, newTotalXp)
    local oldLevel = playerData.level
    playerData.level = newLevel
    playerData.xp = newTotalXp
    ShowNotification("~g~LEVEL UP!~w~ You reached Level " .. newLevel .. "!" )
    SendNUIMessage({
        action = "updateXPBar",
        currentXP = playerData.xp,
        currentLevel = playerData.level,
        xpForNextLevel = CalculateXpForNextLevelClient(playerData.level, playerData.role),
        xpGained = 0 -- Level up doesn't show XP gain, just the level animation
    })
end)

RegisterNetEvent('cops_and_robbers:updateWantedDisplay')
AddEventHandler('cops_and_robbers:updateWantedDisplay', function(stars, points)    currentWantedStarsClient = stars
    currentWantedPointsClient = points
    local newUiLabel = ""
    if stars > 0 then
        for _, levelData in ipairs(Config.WantedSettings.levels) do
            if levelData.stars == stars then
                newUiLabel = levelData.uiLabel
                break
            end
        end
        if newUiLabel == "" then newUiLabel = "Wanted: " .. string.rep("*", stars) end
    end
    wantedUiLabel = newUiLabel
    SetWantedLevelForPlayerRole(stars, points)
end)

-- Handle wanted level synchronization from server
AddEventHandler('cnr:wantedLevelSync', function(wantedData)
    if not wantedData then return end
    
    -- Update client-side wanted level data
    currentWantedStarsClient = wantedData.stars or 0
    currentWantedPointsClient = wantedData.wantedLevel or 0
    
    -- Update UI label
    local newUiLabel = ""
    if currentWantedStarsClient > 0 then
        for _, levelData in ipairs(Config.WantedSettings.levels or {}) do
            if levelData.stars == currentWantedStarsClient then
                newUiLabel = levelData.uiLabel
                break
            end
        end
        if newUiLabel == "" then 
            newUiLabel = "Wanted: " .. string.rep("*", currentWantedStarsClient) 
        end
    end
    wantedUiLabel = newUiLabel
    
    -- Update the wanted level display
    SetWantedLevelForPlayerRole(currentWantedStarsClient, currentWantedPointsClient)
    
end)

-- =====================================
--           HEIST ALERT SYSTEM
-- =====================================

-- Handler for receiving heist alerts (for cops)
AddEventHandler('cnr:heistAlert', function(heistType, coords)
    if role ~= 'cop' then return end

    -- Default location if no coords provided
    if not coords then
        coords = {x = 0, y = 0}
    end
    
    local heistName = ""
    if heistType == "bank" then
        heistName = "Bank Heist"
    elseif heistType == "jewelry" then
        heistName = "Jewelry Store Robbery"
    elseif heistType == "store" then
        heistName = "Store Robbery"
    else
        heistName = "Unknown Heist"
    end
    
    -- Show notification to cop
    local message = string.format("~r~ALERT:~w~ %s in progress! Check your map for location.", heistName)
    ShowNotification(message)
    
    -- Create a temporary blip at the heist location
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, 161) -- Red circle
    SetBlipColour(blip, 1)   -- Red color
    SetBlipScale(blip, 1.5)  -- Larger size
    SetBlipAsShortRange(blip, false)
    
    -- Add blip name/label
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(heistName)
    EndTextCommandSetBlipName(blip)
    
    -- Flash blip for attention
    SetBlipFlashes(blip, true)
    
    -- Remove blip after 2 minutes
    Citizen.SetTimeout(120000, function()
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end)
end)

-- Handler for heist timer display
AddEventHandler('cnr:startHeistTimer', function(duration, heistName)
    -- Show heist timer UI for robber
    SendNUIMessage({
        action = 'startHeistTimer',
        duration = duration,
        bankName = heistName
    })
end)

-- Handler for heist completion
AddEventHandler('cnr:heistCompleted', function(reward, xpEarned)
    -- Show completion message
    local message = string.format("~g~Heist completed!~w~ You earned ~g~$%s~w~ and ~b~%d XP~w~.", reward, xpEarned)
    ShowNotification(message)
      -- Play success sound
    PlaySoundFrontend(-1, "MISSION_PASS_NOTIFY", "HUD_AWARDS", true)
    
    -- Update stats UI if needed
    if playerStats then
        playerStats.heists = (playerStats.heists or 0) + 1
    end
end)

-- =====================================
--           NUI CALLBACKS
-- =====================================

-- NUI Callback for Role Selection
RegisterNUICallback('selectRole', function(data, cb)
    if not data or not data.role then
        cb({ success = false, error = "Invalid role data received" })
        return
    end
    
    local selectedRole = data.role
    if selectedRole ~= "cop" and selectedRole ~= "robber" then
        cb({ success = false, error = "Invalid role selected" })
        return
    end
    
    -- Send role selection to server
    TriggerServerEvent('cnr:selectRole', selectedRole)
    
    -- Hide the UI
    SetNuiFocus(false, false)
    
    -- Return success to NUI
    cb({ success = true })
end)

-- Register NUI callback for setting NUI focus
RegisterNUICallback('setNuiFocus', function(data, cb)
    SetNuiFocus(data.hasFocus, data.hasCursor)
    cb({success = true})
end)

-- Register NUI callbacks for robber menu actions
RegisterNUICallback('startHeist', function(data, cb)
    TriggerEvent('cnr:startHeist')
    cb({success = true})
end)

RegisterNUICallback('viewBounties', function(data, cb)
    TriggerEvent('cnr:viewBounties')
    cb({success = true})
end)

RegisterNUICallback('findHideout', function(data, cb)
    TriggerEvent('cnr:findHideout')
    cb({success = true})
end)

RegisterNUICallback('buyContraband', function(data, cb)
    
    -- Check if player is near a contraband dealer
    local playerPos = GetEntityCoords(PlayerPedId())
    local nearDealer = false
    
    for _, dealer in pairs(Config.ContrabandDealers or {}) do
        local dealerPos = vector3(dealer.x, dealer.y, dealer.z)
        local distance = #(playerPos - dealerPos)
        
        if distance < 5.0 then
            nearDealer = true
            break
        end
    end
    
    if nearDealer then
        -- Open the store with contraband items
        TriggerServerEvent('cnr:accessContrabandDealer')
    else
        ShowNotification("~r~You must be near a contraband dealer to buy contraband.")
    end
    
    cb({success = true})
end)

-- Register NUI callback for buying items
RegisterNUICallback('buyItem', function(data, cb)
    Log("buyItem NUI callback received for itemId: " .. tostring(data.itemId) .. " quantity: " .. tostring(data.quantity), "info", "CNR_CLIENT")
    
    if not data.itemId or not data.quantity then
        Log("buyItem NUI callback missing required data", "error", "CNR_CLIENT")
        cb({success = false, message = "Missing required data"})
        return
    end
    
    -- Trigger server event to buy the item
    TriggerServerEvent('cops_and_robbers:buyItem', data.itemId, data.quantity)
    
    -- Send success response
    cb({success = true})
end)

-- Register NUI callback for selling items
RegisterNUICallback('sellItem', function(data, cb)
    Log("sellItem NUI callback received for itemId: " .. tostring(data.itemId) .. " quantity: " .. tostring(data.quantity), "info", "CNR_CLIENT")
    
    if not data.itemId or not data.quantity then
        Log("sellItem NUI callback missing required data", "error", "CNR_CLIENT")
        cb({success = false, message = "Missing required data"})
        return
    end
    
    -- Trigger server event to sell the item
    TriggerServerEvent('cops_and_robbers:sellItem', data.itemId, data.quantity)
    
    -- Send success response
    cb({success = true})
end)

-- Register NUI callback for getting player inventory
RegisterNUICallback('getPlayerInventory', function(data, cb)
    Log("getPlayerInventory NUI callback received", "info", "CNR_CLIENT")
    
    -- Trigger server event to get player inventory
    TriggerServerEvent('cops_and_robbers:getPlayerInventory')
    
    -- Send success response (the actual inventory will be sent via a separate event)
    cb({success = true})
end)

-- =====================================
--           EVENT HANDLERS
-- =====================================

-- Event handler for showing role selection UI
RegisterNetEvent('cnr:showRoleSelection')
AddEventHandler('cnr:showRoleSelection', function()
    SendNUIMessage({ 
        action = 'showRoleSelection', 
        resourceName = GetCurrentResourceName() 
    })
    SetNuiFocus(true, true)
end)

-- =====================================
--           ROBBER MENU ACTIONS
-- =====================================

RegisterNetEvent('cnr:startHeist')
AddEventHandler('cnr:startHeist', function()
    -- Check if player is near a heist location
    local playerPos = GetEntityCoords(PlayerPedId())
    local nearHeist = false
    local heistType = nil
    
    -- Example: Check if player is near a bank
    for _, location in pairs(Config.HeistLocations or {}) do
        local distance = #(playerPos - vector3(location.x, location.y, location.z))
        if distance < 20.0 then
            nearHeist = true
            heistType = location.type
            break
        end
    end
    
    if nearHeist then
        TriggerServerEvent('cnr:initiateHeist', heistType)
    else
        ShowNotification("~r~You must be near a valid heist location to start a heist.")
    end
end)

RegisterNetEvent('cnr:viewBounties')
AddEventHandler('cnr:viewBounties', function()
    TriggerServerEvent('cnr:requestBountyList')
end)

-- Add new event handler for receiving bounty list
RegisterNetEvent('cnr:receiveBountyList')
AddEventHandler('cnr:receiveBountyList', function(bountyList)
    
    -- Send the bounty list to the UI
    SendNUIMessage({
        action = 'showBountyList',
        bounties = bountyList
    })
    
    -- Set focus to the UI
    SetNuiFocus(true, true)
end)

RegisterNetEvent('cnr:findHideout')
AddEventHandler('cnr:findHideout', function()
    
    -- Example: Show the nearest hideout on the map
    local nearestHideout = nil
    local shortestDistance = 1000000
    local playerPos = GetEntityCoords(PlayerPedId())
    
    for _, hideout in pairs(Config.RobberHideouts or {}) do
        local hideoutPos = vector3(hideout.x, hideout.y, hideout.z)
        local distance = #(playerPos - hideoutPos)
        
        if distance < shortestDistance then
            shortestDistance = distance
            nearestHideout = hideout
        end
    end
    
    if nearestHideout then
        -- Create a temporary blip for the hideout
        local blip = AddBlipForCoord(nearestHideout.x, nearestHideout.y, nearestHideout.z)
        SetBlipSprite(blip, 40) -- House icon
        SetBlipColour(blip, 1) -- Red
        SetBlipAsShortRange(blip, false)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString("Robber Hideout")
        EndTextCommandSetBlipName(blip)
        
        -- Show notification
        ShowNotification("~g~Hideout location marked on your map.")
        
        -- Remove blip after 60 seconds
        Citizen.SetTimeout(60000, function()
            RemoveBlip(blip)
            ShowNotification("~y~Hideout location removed from map.")
        end)
    else
        ShowNotification("~r~No hideout locations found.")
    end
end)

RegisterNetEvent('cnr:buyContraband')
AddEventHandler('cnr:buyContraband', function()
    
    -- Check if player is near a contraband dealer
    local playerPos = GetEntityCoords(PlayerPedId())
    local nearDealer = false
    
    for _, dealer in pairs(Config.ContrabandDealers or {}) do
        local dealerPos = vector3(dealer.x, dealer.y, dealer.z)
        local distance = #(playerPos - dealerPos)
        
        if distance < 5.0 then
            nearDealer = true
            break
        end
    end
    
    if nearDealer then
        -- Open the store with contraband items
        TriggerServerEvent('cnr:openContrabandStore')
    else
        ShowNotification("~r~You must be near a contraband dealer to buy contraband.")
    end
end)

-- Function to check for nearby stores and display help text
function CheckNearbyStores()
    local playerPed = PlayerPedId()
    if not playerPed or not DoesEntityExist(playerPed) then return end
    
    local playerPos = GetEntityCoords(playerPed)
    local isNearStore = false
    local storeType = nil
    local storeName = nil
    local storeItems = nil
    
    if Config and Config.NPCVendors then
        for _, vendor in ipairs(Config.NPCVendors) do
            if vendor and vendor.location then
                -- Handle both vector3 and vector4 formats
                local storePos
                if vendor.location.w then
                    storePos = vector3(vendor.location.x, vendor.location.y, vendor.location.z)
                else
                    storePos = vendor.location
                end
                
                local distance = #(playerPos - storePos)
                -- Check if player is within proximity radius (3.0 units)
                if distance <= 3.0 then
                    isNearStore = true
                    
                    -- Proper store type classification and role-based access validation
                    local hasAccess = false
                    local storeType = "civilian" -- default
                    
                    if vendor.name == "Cop Store" then
                        storeType = "cop"
                        hasAccess = (role == "cop")
                    elseif vendor.name == "Gang Supplier" or vendor.name == "Black Market Dealer" then
                        storeType = "robber"
                        hasAccess = (role == "robber")
                    else
                        -- General stores accessible to all roles
                        storeType = "civilian"
                        hasAccess = true
                    end
                    
                    storeName = vendor.name
                    storeItems = vendor.items
                    
                    -- Display appropriate help text
                    if hasAccess then
                        DisplayHelpText("Press ~INPUT_CONTEXT~ to open " .. storeName)
                    else
                        DisplayHelpText("~r~Access Restricted: " .. storeName .. " (Role: " .. (storeType == "cop" and "Police Only" or "Robbers Only") .. ")")
                    end
                    
                    -- Check for E key press (INPUT_CONTEXT = 38)
                    if IsControlJustPressed(0, 38) then
                        if hasAccess then
                            OpenStoreMenu(storeType, storeItems, storeName)
                        else
                            ShowNotification("~r~You don't have access to this store. This is restricted to " .. (storeType == "cop" and "police officers" or "robbers") .. " only.")
                        end
                    end
                    break
                end
            end
        end
    end
end

-- Function to open the store menu
function OpenStoreMenu(storeType, storeItems, storeName)
    if not storeType or not storeItems or not storeName then
        Log("OpenStoreMenu called with invalid parameters", "error", "CNR_CLIENT")
        return
    end
    
    -- Set the appropriate UI flag
    if storeType == "cop" then
        isCopStoreUiOpen = true
    elseif storeType == "robber" then
        isRobberStoreUiOpen = true
    end
      -- Ensure fullItemConfig is available to NUI before opening store
    TriggerEvent('cnr:ensureConfigItems')
    
    -- Send message to NUI to open store with current player data
    SendNUIMessage({
        action = "openStore",
        storeType = storeType,
        items = storeItems,
        storeName = storeName,
        playerCash = playerData.money or playerCash or 0,  -- Use server data first, then client fallback
        playerLevel = playerData.level or 1,
        cash = playerData.money or playerCash or 0,  -- Add for backward compatibility
        level = playerData.level or 1  -- Add for backward compatibility
    })
    
    -- Enable NUI focus
    SetNuiFocus(true, true)
    
    -- Trigger server event to get detailed item information
    TriggerServerEvent('cops_and_robbers:getItemList', storeType, storeItems, storeName)
end

-- Register NUI callback for closing the store
RegisterNUICallback('closeStore', function(data, cb)
    Log("closeStore NUI callback received", "info", "CNR_CLIENT")
    
    -- Reset UI flags
    isCopStoreUiOpen = false
    isRobberStoreUiOpen = false
    
    -- Disable NUI focus
    SetNuiFocus(false, false)
    
    cb({success = true})
end)

-- Handle detailed item list from server for store UI
RegisterNetEvent('cops_and_robbers:sendItemList')
AddEventHandler('cops_and_robbers:sendItemList', function(storeName, itemList, playerInfo)
    Log("Received detailed item list for store: " .. tostring(storeName) .. " with " .. (#itemList or 0) .. " items", "info", "CNR_CLIENT")
    
    if not itemList or #itemList == 0 then
        Log("Received empty item list for store: " .. tostring(storeName), "warning", "CNR_CLIENT")
        return
    end
    
    -- Update local player data if server provides it
    if playerInfo then
        if playerInfo.cash and playerInfo.cash ~= playerCash then
            playerCash = playerInfo.cash
            Log("Updated playerCash from server: " .. tostring(playerCash), "info", "CNR_CLIENT")
        end
        if playerInfo.level and playerData.level ~= playerInfo.level then
            playerData.level = playerInfo.level
            Log("Updated playerData.level from server: " .. tostring(playerData.level), "info", "CNR_CLIENT")
        end
    end
    
    -- Send the complete item data to NUI
    SendNUIMessage({
        action = "updateStoreData",
        storeName = storeName,
        items = itemList,
        playerInfo = playerInfo or {
            level = playerData.level or 1,
            role = playerData.role or "citizen",
            cash = playerCash or 0
        }
    })
    
    Log("Sent store data to NUI for " .. tostring(storeName), "info", "CNR_CLIENT")
end)

-- Handle contraband store UI opening
RegisterNetEvent('cnr:openContrabandStoreUI')
AddEventHandler('cnr:openContrabandStoreUI', function(contrabandItems)
    Log("Opening contraband store UI with " .. #contrabandItems .. " items", "info", "CNR_CLIENT")
    
    -- Open store menu as a special contraband store
    OpenStoreMenu("contraband", contrabandItems, "Contraband Dealer")
    
    -- Trigger server event to get detailed item information
    TriggerServerEvent('cops_and_robbers:getItemList', "contraband", contrabandItems, "Contraband Dealer")
end)

-- Register event to send NUI messages from server
RegisterNetEvent('cnr:sendNUIMessage')
AddEventHandler('cnr:sendNUIMessage', function(message)
    -- Validate message before sending to NUI
    if not message or type(message) ~= 'table' then
        print('[CNR_CLIENT_ERROR] Invalid NUI message received from server:', message)
        return
    end
    
    if not message.action or type(message.action) ~= 'string' then
        print('[CNR_CLIENT_ERROR] NUI message missing action field:', json.encode(message))
        return
    end
    
    SendNUIMessage(message)
end)

-- Thread to check for nearby stores
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0) -- Run every frame for responsive key detection
        
        -- Only check for nearby stores if player ped exists and is ready
        if g_isPlayerPedReady then
            CheckNearbyStores()
        end
    end
end)

-- OLD CLIENT-SIDE CRIME DETECTION DISABLED
-- This has been replaced by server-side crime detection systems
-- The new system handles:
-- - Weapon discharge detection (cnr:weaponFired event)
-- - Player damage detection (cnr:playerDamaged event)  
-- - Speeding detection (server-side vehicle monitoring)
-- - Restricted area detection (server-side position monitoring)
-- - Hit-and-run detection (server-side vehicle damage monitoring)

--[[
-- Thread to detect when player commits a crime (like killing NPCs or other players)
-- DISABLED - Replaced by server-side detection to prevent conflicts
Citizen.CreateThread(function()
    local lastMurderCheckTime = 0
    local nearbyPedsTracked = {}
    
    while true do
        Citizen.Wait(1000) -- Check once per second
        
        -- Only check if player is ready and is a robber
        if g_isPlayerPedReady and role == "robber" then
            local playerPed = PlayerPedId()
            local currentTime = GetGameTimer()
            
            -- Check if player killed an NPC (check nearby peds for recent deaths)
            if (currentTime - lastMurderCheckTime) > 2000 then -- Check every 2 seconds to avoid spam
                local playerCoords = GetEntityCoords(playerPed)
                local nearbyPeds = GetGamePool('CPed')
                
                for i = 1, #nearbyPeds do
                    local ped = nearbyPeds[i]
                    if ped ~= playerPed and DoesEntityExist(ped) and not IsPedAPlayer(ped) then
                        local pedCoords = GetEntityCoords(ped)
                        local distance = #(playerCoords - pedCoords)
                        
                        -- Check if ped is close and recently died
                        if distance < 15.0 and IsEntityDead(ped) then
                            -- Check if this ped wasn't tracked as dead before
                            if not nearbyPedsTracked[ped] then
                                local killer = GetPedSourceOfDeath(ped)
                                -- If player was the killer
                                if killer == playerPed then
                                    TriggerServerEvent('cops_and_robbers:reportCrime', 'murder')
                                    nearbyPedsTracked[ped] = true
                                end
                            end
                        elseif distance > 50.0 then
                            -- Remove tracking for peds that are far away to prevent memory issues
                            nearbyPedsTracked[ped] = nil
                        end
                    end
                end
                lastMurderCheckTime = currentTime
            end
            
            -- Check for kill (player vs player)
            if IsEntityDead(playerPed) then
                -- Player died, check who killed them
                local killer = GetPedSourceOfDeath(playerPed)
                if killer ~= playerPed and DoesEntityExist(killer) and IsEntityAPed(killer) then
                    local killerType = GetEntityType(killer)
                    if killerType == 1 then -- Ped type
                        if IsPedAPlayer(killer) then
                            -- Player killed by another player
                            local killerServerId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(killer))
                            if killerServerId ~= GetPlayerServerId(PlayerId()) then
                                -- Report murder crime
                                TriggerServerEvent('cops_and_robbers:reportCrime', 'murder')
                            end
                        end
                    end
                end
            end
            
            -- Check for hit and run
            if IsPedInAnyVehicle(playerPed, false) then
                local vehicle = GetVehiclePedIsIn(playerPed, false)
                  -- Check if we hit a pedestrian
                if HasEntityCollidedWithAnything(vehicle) then
                    -- Since GetEntityHit isn't available, check if any nearby peds are injured
                    local playerCoords = GetEntityCoords(playerPed)
                    local nearbyPeds = GetGamePool('CPed')
                    
                    for i=1, #nearbyPeds do
                        local ped = nearbyPeds[i]
                        if ped ~= playerPed and DoesEntityExist(ped) and not IsPedAPlayer(ped) then
                            local pedCoords = GetEntityCoords(ped)
                            local distance = #(playerCoords - pedCoords)
                            
                            -- If ped is close and injured, consider it a hit and run
                            if distance < 10.0 and (IsEntityDead(ped) or IsPedRagdoll(ped) or IsPedInjured(ped)) then
                                TriggerServerEvent('cops_and_robbers:reportCrime', 'hit_and_run')
                                break
                            end
                        end
                    end
                end
            end
            
            -- Check for property damage
            if HasPlayerDamagedAtLeastOneNonAnimalPed(PlayerId()) then
                TriggerServerEvent('cops_and_robbers:reportCrime', 'assault')
                -- Reset the flag
                ClearPlayerHasDamagedAtLeastOneNonAnimalPed(PlayerId())
            end
            
            -- Check for vehicle theft
            if IsPedInAnyVehicle(playerPed, false) then
                local vehicle = GetVehiclePedIsIn(playerPed, false)                if GetPedInVehicleSeat(vehicle, -1) == playerPed then -- If player is driver
                    -- Check if vehicle is potentially stolen by checking common police/emergency vehicles
                    local model = GetEntityModel(vehicle)
                    local isEmergencyVehicle = IsVehicleModel(vehicle, GetHashKey("police")) or 
                                               IsVehicleModel(vehicle, GetHashKey("police2")) or 
                                               IsVehicleModel(vehicle, GetHashKey("police3")) or
                                               IsVehicleModel(vehicle, GetHashKey("ambulance")) or
                                               IsVehicleModel(vehicle, GetHashKey("firetruk"))
                    
                    -- Consider it stolen if it's an emergency vehicle or marked as stolen
                    if isEmergencyVehicle or IsVehicleStolen(vehicle) or (DecorExistOn(vehicle, 'isStolen') and DecorGetBool(vehicle, 'isStolen')) then
                        -- Report vehicle theft
                        TriggerServerEvent('cops_and_robbers:reportCrime', 'grand_theft_auto')
                        -- Mark the vehicle as stolen to prevent repeated reports
                        if not DecorExistOn(vehicle, 'isStolen') then
                            DecorSetBool(vehicle, 'isStolen', true)
                        end
                    end
                end
            end
        end
    end
end)

-- OLD WEAPON DISCHARGE DETECTION DISABLED
-- This has been replaced by the new server-side weapon discharge detection
-- The new system uses cnr:weaponFired event for better accuracy and server authority

-- Add detection for weapon discharge
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        
        -- Only check if player is ready and is a robber
        if g_isPlayerPedReady and role == "robber" then
            local playerPed = PlayerPedId()
            
            -- Check for weapon discharge
            if IsPedShooting(playerPed) then
                local weapon = GetSelectedPedWeapon(playerPed)
                
                -- Only report for actual weapons, not non-lethal ones
                if weapon ~= GetHashKey('WEAPON_STUNGUN') and weapon ~= GetHashKey('WEAPON_FLASHLIGHT') then
                    -- Report weapon discharge                    TriggerServerEvent('cops_and_robbers:reportCrime', 'weapons_discharge')
                    -- Wait a bit to avoid spamming events
                    Citizen.Wait(5000)
                end
            end
        end
    end
end)
--]]

-- ====================================================================
-- Speedometer Functions
-- ====================================================================

-- Speedometer settings
local showSpeedometer = true
local speedometerUpdateInterval = 200 -- ms
local lastVehicleSpeed = 0

-- Cache for vehicle types we don't want to show speedometer for
local excludedVehicleTypes = {
    [8] = true,  -- Boats
    [14] = true, -- Boats
    [15] = true, -- Helicopters
    [16] = true, -- Planes
}

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(speedometerUpdateInterval)
        
        if showSpeedometer then
            local player = PlayerPedId()
            
            if IsPedInAnyVehicle(player, false) then
                local vehicle = GetVehiclePedIsIn(player, false)
               
                local vehicleClass = GetVehicleClass(vehicle)
                
                -- Only show speedometer for allowed vehicle types
                if not excludedVehicleTypes[vehicleClass] then
                    local speed = GetEntitySpeed(vehicle) * 2.236936 -- Convert to MPH
                    
                    -- Only update the UI if the speed has changed significantly
                    if math.abs(speed - lastVehicleSpeed) > 0.5 then
                        lastVehicleSpeed = speed
                        
                        -- Round to integer
                        local roundedSpeed = math.floor(speed + 0.5)
                        
                        -- Update UI
                        SendNUIMessage({
                            action = "updateSpeedometer",
                            speed = roundedSpeed
                        })
                        
                        -- Show speedometer if not already visible
                        SendNUIMessage({
                            action = "toggleSpeedometer",
                            show = true
                        })
                    end
                else
                    -- Hide speedometer for excluded vehicle types
                    SendNUIMessage({
                        action = "toggleSpeedometer",
                        show = false
                    })
                end
            else
                -- Hide speedometer when not in vehicle
                SendNUIMessage({
                    action = "toggleSpeedometer",
                    show = false
                })
            end
        end
    end
end)

-- Command to toggle speedometer
RegisterCommand('togglespeedometer', function()
    showSpeedometer = not showSpeedometer
    TriggerEvent('cnr:notification', 'Speedometer ' .. (showSpeedometer and 'enabled' or 'disabled'))
end, false)

-- Register event handler for receiving bounty list
RegisterNetEvent('cnr:receiveBountyList')
AddEventHandler('cnr:receiveBountyList', function(bounties)
    SendNUIMessage({
        action = 'showBountyList',
        bounties = bounties
    })
end)

-- ====================================================================
-- Robber Hideouts
-- ====================================================================

local hideoutBlips = {}
local isHideoutVisible = false

-- Function to get player's current role from server
function GetCurrentPlayerRole(callback)
    TriggerServerEvent('cnr:getPlayerRole')
    
    RegisterNetEvent('cnr:returnPlayerRole')
    AddEventHandler('cnr:returnPlayerRole', function(role)
        callback(role)
    end)
end

-- Create a blip for the nearest robber hideout
function FindNearestHideout()
    -- Check if player is a robber
    GetCurrentPlayerRole(function(role)
        if role ~= "robber" then
            TriggerEvent('cnr:notification', "Only robbers can access hideouts.", "error")
            return
        end
        
        -- Clean up any existing hideout blips
        RemoveHideoutBlips()
        
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local nearestHideout = nil
        local nearestDistance = 9999.0
        
        -- Find the nearest hideout
        for _, hideout in ipairs(Config.RobberHideouts) do
            local hideoutCoords = vector3(hideout.x, hideout.y, hideout.z)
            local distance = #(playerCoords - hideoutCoords)
            
            if distance < nearestDistance then
                nearestDistance = distance
                nearestHideout = hideout
            end
        end
        
        if nearestHideout then
            local hideoutCoords = vector3(nearestHideout.x, nearestHideout.y, nearestHideout.z)
            
            -- Create blip for the hideout
            local blip = AddBlipForCoord(hideoutCoords.x, hideoutCoords.y, hideoutCoords.z)
            SetBlipSprite(blip, 492) -- House icon
            SetBlipColour(blip, 1) -- Red
            SetBlipScale(blip, 0.8)
            SetBlipAsShortRange(blip, false)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString(nearestHideout.name)
            EndTextCommandSetBlipName(blip)
            
            -- Set route to the hideout
            SetBlipRoute(blip, true)
            SetBlipRouteColour(blip, 1) -- Red route
            
            -- Add to hideout blips table
            table.insert(hideoutBlips, blip)
            
            -- Notify player
            TriggerEvent('cnr:notification', "Route set to " .. nearestHideout.name .. ".")
            
            -- Set timer to remove the blip after 2 minutes
            Citizen.SetTimeout(120000, function()
                RemoveHideoutBlips()
                TriggerEvent('cnr:notification', "Hideout marker removed from map.")
            end)
            
            isHideoutVisible = true
        else
            TriggerEvent('cnr:notification', "No hideouts found nearby.", "error")
        end
    end)
end

-- Remove all hideout blips
function RemoveHideoutBlips()
    for _, blip in ipairs(hideoutBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    hideoutBlips = {}
    isHideoutVisible = false
end

-- NUI Callback for Find Hideout button
RegisterNUICallback('findHideout', function(data, cb)
    FindNearestHideout()
    cb({})
end)

-- ====================================================================
-- Client-Side Jail System Logic
-- ====================================================================

-- Track if the jail update thread is running
local jailThreadRunning = false

local function StopJailUpdateThread()
    -- Thread checks the isJailed flag, so simply hide the timer display
    jailTimerDisplayActive = false
    jailThreadRunning = false
    Log("Jail update thread signaled to stop.", "info", "CNR_CLIENT")
end

local function StartJailUpdateThread(duration)
    jailTimeRemaining = duration
    jailTimerDisplayActive = true

    -- Avoid spawning multiple threads
    if jailThreadRunning then
        Log("Jail update thread already running. Timer updated to " .. jailTimeRemaining, "info", "CNR_CLIENT")
        return
    end

    jailThreadRunning = true
    Citizen.CreateThread(function()
        Log("Jail update thread started. Duration: " .. jailTimeRemaining, "info", "CNR_CLIENT")
        local playerPed = PlayerPedId()

        while isJailed and jailTimeRemaining > 0 do
            Citizen.Wait(1000) -- Update every second

            if not isJailed then -- Double check in case of async state change
                break
            end

            jailTimeRemaining = jailTimeRemaining - 1

            -- Send update to NUI to display remaining time
            SendNUIMessage({
                action = "updateJailTimer",
                time = jailTimeRemaining
            })

            -- Enforce Jail Restrictions (Step 3 of plan)
            -- Example: Disable combat controls
            DisableControlAction(0, 24, true)  -- INPUT_ATTACK
            DisableControlAction(0, 25, true)  -- INPUT_AIM
            DisableControlAction(0, 140, true) -- INPUT_MELEE_ATTACK_LIGHT
            DisableControlAction(0, 141, true) -- INPUT_MELEE_ATTACK_HEAVY
            DisableControlAction(0, 142, true) -- INPUT_MELEE_ATTACK_ALTERNATE
            DisableControlAction(0, 257, true) -- INPUT_ATTACK2
            DisableControlAction(0, 263, true) -- INPUT_MELEE_ATTACK1
            DisableControlAction(0, 264, true) -- INPUT_MELEE_ATTACK2


            -- Prevent equipping weapons (more robustly handled by clearing them on jail entry)
            -- Forcing unarmed:
             if GetSelectedPedWeapon(playerPed) ~= GetHashKey("WEAPON_UNARMED") then
                 SetCurrentPedWeapon(playerPed, GetHashKey("WEAPON_UNARMED"), true)
             end

            -- TODO: Add more restrictions like preventing inventory access, vehicle entry, etc.
            DisableControlAction(0, 23, true)    -- INPUT_ENTER_VEHICLE
            DisableControlAction(0, 51, true)    -- INPUT_CONTEXT (E) - Be careful if E is used for other things
            DisableControlAction(0, 22, true)    -- INPUT_JUMP
            if Config.Keybinds and Config.Keybinds.openInventory then
                DisableControlAction(0, Config.Keybinds.openInventory, true) -- Disable inventory key
            else
                DisableControlAction(0, 244, true) -- Fallback M key for inventory (INPUT_INTERACTION_MENU)
            end

            -- Additional restrictions for phone, weapon selection, cover, reload
            DisableControlAction(0, 246, true)   -- INPUT_PHONE (Up Arrow/Cellphone)
            DisableControlAction(0, 12, true)    -- INPUT_WEAPON_WHEEL_NEXT
            DisableControlAction(0, 13, true)    -- INPUT_WEAPON_WHEEL_PREV
            DisableControlAction(0, 14, true)    -- INPUT_SELECT_PREV_WEAPON
            DisableControlAction(0, 15, true)    -- INPUT_SELECT_NEXT_WEAPON
            DisableControlAction(0, 44, true)    -- INPUT_COVER (Q)
            DisableControlAction(0, 45, true)    -- INPUT_RELOAD (R)
            -- Add more specific keybinds to disable if needed (e.g., phone, specific menus)

            -- Confinement to jail area
            local currentPos = GetEntityCoords(playerPed)
            local distanceToJailCenter = #(currentPos - JailMainPoint)

            if distanceToJailCenter > JailRadius then
                Log("Jailed player attempted to escape. Teleporting back.", "warn", "CNR_CLIENT")
                ShowNotification("~r~You cannot leave the prison area.")
                SetEntityCoords(playerPed, JailMainPoint.x, JailMainPoint.y, JailMainPoint.z, false, false, false, true)
            end

            if jailTimeRemaining <= 0 then
                isJailed = false -- Ensure flag is set before potentially triggering release
                -- Server will trigger cnr:releaseFromJail, client should not do it directly
                Log("Jail time expired on client. Waiting for server release.", "info", "CNR_CLIENT")
                SendNUIMessage({ action = "hideJailTimer" })
                jailTimerDisplayActive = false
                break
            end
        end
        Log("Jail update thread finished or player released.", "info", "CNR_CLIENT")
        jailTimerDisplayActive = false
        SendNUIMessage({ action = "hideJailTimer" })
        jailThreadRunning = false
    end)
end

local function ApplyPlayerModel(modelHash)
    if not modelHash or modelHash == 0 then
        Log("ApplyPlayerModel: Invalid modelHash received: " .. tostring(modelHash), "error", "CNR_CLIENT")
        return
    end

    local playerPed = PlayerPedId()
    RequestModel(modelHash)
    local attempts = 0
    while not HasModelLoaded(modelHash) and attempts < 100 do
        Citizen.Wait(50)
        attempts = attempts + 1
    end

    if HasModelLoaded(modelHash) then
        Log("ApplyPlayerModel: Model " .. modelHash .. " loaded. Setting player model.", "info", "CNR_CLIENT")
        SetPlayerModel(PlayerId(), modelHash)
        Citizen.Wait(100) -- Allow model to apply
        SetPedDefaultComponentVariation(playerPed) -- Reset components to default for the new model
        SetModelAsNoLongerNeeded(modelHash)
    else
        Log("ApplyPlayerModel: Failed to load model " .. modelHash .. " after 100 attempts.", "error", "CNR_CLIENT")
        ShowNotification("~r~Error applying appearance change.")
    end
end

AddEventHandler('cnr:sendToJail', function(durationSeconds, prisonLocation)
    Log(string.format("Received cnr:sendToJail. Duration: %d, Location: %s", durationSeconds, json.encode(prisonLocation)), "info", "CNR_CLIENT")
    local playerPed = PlayerPedId()

    isJailed = true
    jailTimeRemaining = durationSeconds

    -- Store original player model
    originalPlayerModelHash = GetEntityModel(playerPed)
    Log("Stored original player model: " .. originalPlayerModelHash, "info", "CNR_CLIENT")

    -- Apply jail uniform
    local jailUniformModelKey = Config.JailUniformModel or "a_m_m_prisoner_01" -- Fallback if config is missing
    local jailUniformModelHash = GetHashKey(jailUniformModelKey)
    if jailUniformModelHash ~= 0 then
        ApplyPlayerModel(jailUniformModelHash)
    else
        Log("Invalid JailUniformModel in Config: " .. jailUniformModelKey, "error", "CNR_CLIENT")
    end

    -- Teleport player to prison
    if prisonLocation and prisonLocation.x and prisonLocation.y and prisonLocation.z then
        JailMainPoint = vector3(prisonLocation.x, prisonLocation.y, prisonLocation.z) -- Update the jail center point
        RequestCollisionAtCoord(JailMainPoint.x, JailMainPoint.y, JailMainPoint.z) -- Request collision for the jail area
        SetEntityCoords(playerPed, JailMainPoint.x, JailMainPoint.y, JailMainPoint.z, false, false, false, true)
        SetEntityHeading(playerPed, prisonLocation.w or 0.0) -- Use heading if provided
        ClearPedTasksImmediately(playerPed)
    else
        Log("cnr:sendToJail - Invalid prisonLocation received. Using default: " .. json.encode(JailMainPoint), "error", "CNR_CLIENT")
        ShowNotification("~r~Error: Could not teleport to jail - invalid location.")
        isJailed = false -- Don't proceed if teleport fails
        originalPlayerModelHash = nil -- Clear stored model if jailing fails
        return
    end

    -- Remove all weapons from player
    RemoveAllPedWeapons(playerPed, true)
    ShowNotification("~r~All weapons have been confiscated.")

    -- Send NUI message to show jail timer
    SendNUIMessage({
        action = "showJailTimer",
        initialTime = jailTimeRemaining
    })

    StartJailUpdateThread(durationSeconds)
end)

AddEventHandler('cnr:releaseFromJail', function()
    Log("Received cnr:releaseFromJail.", "info", "CNR_CLIENT")
    local playerPed = PlayerPedId()

    isJailed = false
    jailTimeRemaining = 0
    StopJailUpdateThread() -- Signal the jail loop to stop and hide UI

    -- Send NUI message to hide jail timer
    SendNUIMessage({ action = "hideJailTimer" })

    -- Restore player model
    if originalPlayerModelHash and originalPlayerModelHash ~= 0 then
        Log("Restoring original player model: " .. originalPlayerModelHash, "info", "CNR_CLIENT")
        ApplyPlayerModel(originalPlayerModelHash)
    else
        Log("No original player model stored or it was invalid. Attempting to restore to role default or citizen model.", "warn", "CNR_CLIENT")
        if playerData and playerData.role and playerData.role ~= "" and playerData.role ~= "citizen" then
            Log("Attempting to apply model for role: " .. playerData.role, "info", "CNR_CLIENT")
            ApplyRoleVisualsAndLoadout(playerData.role, nil) -- Applies role default model & basic loadout
        else
            Log("Player role unknown or citizen, applying default citizen model.", "info", "CNR_CLIENT")
            ApplyRoleVisualsAndLoadout("citizen", nil) -- Fallback to citizen visuals
        end
    end
    originalPlayerModelHash = nil -- Clear stored model hash after attempting restoration

    -- Determine release location
    local determinedReleaseLocation = nil
    local hardcodedDefaultSpawn = vector3(186.0, -946.0, 30.0) -- Legion Square, a very safe fallback

    if playerData and playerData.role and Config.SpawnPoints and Config.SpawnPoints[playerData.role] then
        determinedReleaseLocation = Config.SpawnPoints[playerData.role]
        Log(string.format("Using spawn point for role '%s'.", playerData.role), "info", "CNR_CLIENT")
    elseif Config.SpawnPoints and Config.SpawnPoints["citizen"] then
        determinedReleaseLocation = Config.SpawnPoints["citizen"]
        Log("Role spawn not found or role invalid, using citizen spawn point.", "warn", "CNR_CLIENT")
        ShowNotification("~y~Your role spawn was not found, using default citizen spawn.")
    else
        determinedReleaseLocation = hardcodedDefaultSpawn
        Log("Citizen spawn point also not found in Config. Using hardcoded default spawn.", "error", "CNR_CLIENT")
        ShowNotification("~r~Error: Default spawn locations not configured. Using a fallback location.")
    end    if determinedReleaseLocation and determinedReleaseLocation.x and determinedReleaseLocation.y and determinedReleaseLocation.z then
        SetEntityCoords(playerPed, determinedReleaseLocation.x, determinedReleaseLocation.y, determinedReleaseLocation.z, false, false, false, true)
        SetEntityHeading(playerPed, 0.0) -- Set default heading since spawn points don't include rotation
        Log(string.format("Player released from jail. Teleported to: %s", json.encode(determinedReleaseLocation)), "info", "CNR_CLIENT")
    else
        -- This case should be rare given the fallbacks, but as a last resort:
        Log("cnr:releaseFromJail - CRITICAL: No valid release spawn point determined even with fallbacks. Player may be stuck or at Zero Coords.", "error", "CNR_CLIENT")
        ShowNotification("~r~CRITICAL ERROR: Could not determine release location. Please contact an admin.")
        -- As an absolute last measure, teleport to a known safe spot if playerPed is valid
        if playerPed and playerPed ~= 0 then
             SetEntityCoords(playerPed, hardcodedDefaultSpawn.x, hardcodedDefaultSpawn.y, hardcodedDefaultSpawn.z, false, false, false, true)
        end
    end

    ClearPedTasksImmediately(playerPed)
    -- Player's weapons are not automatically restored here.
    -- They would get default role weapons upon next role sync or if they visit an armory.
    -- Or, could potentially save/restore their exact weapons pre-jailing if desired (more complex).
    ShowNotification("~g~You have been released from jail.")
end)


-- ====================================================================
-- Contraband Dealers
-- ====================================================================

local contrabandDealerBlips = {}
local contrabandDealerPeds = {}

-- Create contraband dealer blips and peds
Citizen.CreateThread(function()
    -- Wait for client to fully initialize
    Citizen.Wait(5000)
    
    -- Create dealers
    for _, dealer in ipairs(Config.ContrabandDealers) do
        -- Create blip
        local blip = AddBlipForCoord(dealer.x, dealer.y, dealer.z)
        SetBlipSprite(blip, 378) -- Mask icon
        SetBlipColour(blip, 1) -- Red
        SetBlipScale(blip, 0.7)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(dealer.name or "Contraband Dealer")
        EndTextCommandSetBlipName(blip)
        
        -- Add to dealer blips table
        table.insert(contrabandDealerBlips, blip)
        
        -- Create dealer ped
        local pedHash = GetHashKey("s_m_y_dealer_01") -- Default dealer model
        
        -- Request the model
        RequestModel(pedHash)
        while not HasModelLoaded(pedHash) do
            Citizen.Wait(10)
        end
        
        -- Create ped
        local ped = CreatePed(4, pedHash, dealer.x, dealer.y, dealer.z - 1.0, dealer.heading, false, true)
        FreezeEntityPosition(ped, true)
        SetEntityInvincible(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        
        -- Add to dealer peds table
        table.insert(contrabandDealerPeds, ped)
    end
end)

-- Interaction with contraband dealers
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        
        for _, dealer in ipairs(Config.ContrabandDealers) do
            local dealerCoords = vector3(dealer.x, dealer.y, dealer.z)
            local distance = #(playerCoords - dealerCoords)            if distance < 3.0 then
                -- Draw a simpler marker
                DrawSphere(dealer.x, dealer.y, dealer.z - 0.5, 0.5, 255, 0, 0, 0.2)
                
                -- Display help text
                BeginTextCommandDisplayHelp("STRING")
                AddTextComponentSubstringPlayerName("Press ~INPUT_CONTEXT~ to access the contraband dealer")
                EndTextCommandDisplayHelp(0, false, true, -1)
                
                -- Check for interaction key
                if IsControlJustReleased(0, 38) then -- E key
                    TriggerServerEvent('cnr:accessContrabandDealer')
                end
            end
        end
    end
end)

-- NUI Callback for Buy Contraband button
RegisterNUICallback('buyContraband', function(data, cb)
    TriggerServerEvent('cnr:accessContrabandDealer')
    cb({})
end)

-- ====================================================================
-- Robber Hideouts
-- ====================================================================

local hideoutBlips = {}
local isHideoutVisible = false

-- Function to get player's current role from server
function GetCurrentPlayerRole(callback)
    TriggerServerEvent('cnr:getPlayerRole')
    
    RegisterNetEvent('cnr:returnPlayerRole')
    AddEventHandler('cnr:returnPlayerRole', function(role)
        callback(role)
    end)
end

-- Create a blip for the nearest robber hideout
function FindNearestHideout()
    -- Check if player is a robber
    GetCurrentPlayerRole(function(role)
        if role ~= "robber" then
            TriggerEvent('cnr:notification', "Only robbers can access hideouts.", "error")
            return
        end
        
        -- Clean up any existing hideout blips
        RemoveHideoutBlips()
        
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local nearestHideout = nil
        local nearestDistance = 9999.0
        
        -- Find the nearest hideout
        for _, hideout in ipairs(Config.RobberHideouts) do
            local hideoutCoords = vector3(hideout.x, hideout.y, hideout.z)
            local distance = #(playerCoords - hideoutCoords)
            
            if distance < nearestDistance then
                nearestDistance = distance
                nearestHideout = hideout
            end
        end
        
        if nearestHideout then
            local hideoutCoords = vector3(nearestHideout.x, nearestHideout.y, nearestHideout.z)
            
            -- Create blip for the hideout
            local blip = AddBlipForCoord(hideoutCoords.x, hideoutCoords.y, hideoutCoords.z)
            SetBlipSprite(blip, 492) -- House icon
            SetBlipColour(blip, 1) -- Red
            SetBlipScale(blip, 0.8)
            SetBlipAsShortRange(blip, false)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString(nearestHideout.name)
            EndTextCommandSetBlipName(blip)
            
            -- Set route to the hideout
            SetBlipRoute(blip, true)
            SetBlipRouteColour(blip, 1) -- Red route
            
            -- Add to hideout blips table
            table.insert(hideoutBlips, blip)
            
            -- Notify player
            TriggerEvent('cnr:notification', "Route set to " .. nearestHideout.name .. ".")
            
            -- Set timer to remove the blip after 2 minutes
            Citizen.SetTimeout(120000, function()
                RemoveHideoutBlips()
                TriggerEvent('cnr:notification', "Hideout marker removed from map.")
            end)
            
            isHideoutVisible = true
        else
            TriggerEvent('cnr:notification', "No hideouts found nearby.", "error")
        end
    end)
end

-- Remove all hideout blips
function RemoveHideoutBlips()
    for _, blip in ipairs(hideoutBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    hideoutBlips = {}
    isHideoutVisible = false
end

-- NUI Callback for Find Hideout button
RegisterNUICallback('findHideout', function(data, cb)
    FindNearestHideout()
    cb({})
end)
-- Function to spawn player at a specific location
function SpawnPlayerAtLocation(spawnLocation, spawnHeading, role)
    if not spawnLocation then
        print("[CNR_CLIENT_ERROR] SpawnPlayerAtLocation: Invalid spawn location")
        return
    end
    
    local playerPed = PlayerPedId()
    
    -- Set player position and heading
    if type(spawnLocation) == "vector3" then
        SetEntityCoords(playerPed, spawnLocation.x, spawnLocation.y, spawnLocation.z, false, false, false, true)
    elseif type(spawnLocation) == "vector4" then
        SetEntityCoords(playerPed, spawnLocation.x, spawnLocation.y, spawnLocation.z, false, false, false, true)
        spawnHeading = spawnLocation.w
    elseif type(spawnLocation) == "table" and spawnLocation.x and spawnLocation.y and spawnLocation.z then
        SetEntityCoords(playerPed, spawnLocation.x, spawnLocation.y, spawnLocation.z, false, false, false, true)
    else
        print("[CNR_CLIENT_ERROR] SpawnPlayerAtLocation: Unsupported spawn location format")
        return
    end
    
    -- Set heading if provided
    if spawnHeading then
        SetEntityHeading(playerPed, spawnHeading)
    end
    
    -- Apply role-specific visuals and loadout
    if role then
        ApplyRoleVisualsAndLoadout(role)
    end
    
end

-- Register and handle the network event for receiving character data
RegisterNetEvent('cnr:receiveCharacterForRole')
AddEventHandler('cnr:receiveCharacterForRole', function(characterData)
    -- This will be used for future character loading logic
    if characterData then
        -- Process character data for role selection
        print("[CNR_CLIENT] Received character data for role selection")
    end
end)

-- Event handler for spawning player at location
AddEventHandler('cnr:spawnPlayerAt', function(spawnLocation, spawnHeading, role)
    SpawnPlayerAtLocation(spawnLocation, spawnHeading, role)
end)

-- =========================
--      Banking System Client
-- =========================

-- Banking client variables
local bankingData = {
    balance = 0,
    transactionHistory = {},
    currentATM = nil,
    currentBankTeller = nil,
    isUsingATM = false,
    isAtBank = false
}

local atmProps = {}
local bankTellerPeds = {}
local atmHackInProgress = false

-- Register banking events
RegisterNetEvent('cnr:updateBankBalance')
RegisterNetEvent('cnr:updateTransactionHistory')
RegisterNetEvent('cnr:startATMHack')
RegisterNetEvent('cnr:showNotification')

-- Update bank balance
AddEventHandler('cnr:updateBankBalance', function(balance)
    bankingData.balance = balance
    SendNUIMessage({
        type = "updateBankBalance",
        balance = balance
    })
end)

-- Update transaction history
AddEventHandler('cnr:updateTransactionHistory', function(history)
    bankingData.transactionHistory = history
    SendNUIMessage({
        type = "updateTransactionHistory",
        history = history
    })
end)

-- Show notification
AddEventHandler('cnr:showNotification', function(message, type)
    SendNUIMessage({
        type = "showNotification",
        message = message,
        notificationType = type or "info"
    })
end)

-- ATM hacking for robbers
AddEventHandler('cnr:startATMHack', function(atmId, duration)
    if atmHackInProgress then return end
    
    atmHackInProgress = true
    local playerPed = PlayerPedId()
    
    -- Play hacking animation
    RequestAnimDict("anim@amb@business@cfid@cfid_machine_use@")
    while not HasAnimDictLoaded("anim@amb@business@cfid@cfid_machine_use@") do
        Citizen.Wait(100)
    end
    
    TaskPlayAnim(playerPed, "anim@amb@business@cfid@cfid_machine_use@", "machine_use_enter", 8.0, -8.0, -1, 1, 0, false, false, false)
    
    -- Show progress bar
    SendNUIMessage({
        type = "showProgressBar",
        duration = duration,
        label = "Hacking ATM..."
    })
    
    -- Reset after duration
    SetTimeout(duration, function()
        atmHackInProgress = false
        ClearPedTasks(playerPed)
        SendNUIMessage({
            type = "hideProgressBar"
        })
    end)
end)

-- Initialize ATM props on resource start
function InitializeBankingProps()
    -- Create ATM props
    for i, atm in pairs(Config.ATMLocations) do
        local prop = CreateObject(GetHashKey(atm.model), atm.pos.x, atm.pos.y, atm.pos.z, false, false, false)
        SetEntityHeading(prop, atm.heading)
        FreezeEntityPosition(prop, true)
        
        atmProps[i] = {
            prop = prop,
            coords = atm.pos,
            id = i
        }
    end
    
    -- Create bank teller NPCs
    for i, teller in pairs(Config.BankTellers) do
        RequestModel(GetHashKey(teller.model))
        while not HasModelLoaded(GetHashKey(teller.model)) do
            Citizen.Wait(100)
        end
        
        local ped = CreatePed(4, GetHashKey(teller.model), teller.pos.x, teller.pos.y, teller.pos.z, teller.heading, false, true)
        SetEntityCanBeDamaged(ped, false)
        SetPedCanRagdollFromPlayerImpact(ped, false)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetEntityInvincible(ped, true)
        FreezeEntityPosition(ped, true)
        
        bankTellerPeds[i] = {
            ped = ped,
            coords = teller.pos,
            name = teller.name,
            services = teller.services,
            id = i
        }
    end
end

-- Main banking interaction thread
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local closestATM = nil
        local closestBankTeller = nil
        local closestATMDist = math.huge
        local closestTellerDist = math.huge
        
        -- Check ATM proximity
        for i, atm in pairs(atmProps) do
            if atm.prop and DoesEntityExist(atm.prop) then
                local dist = #(playerCoords - atm.coords)
                if dist < 2.0 and dist < closestATMDist then
                    closestATM = atm
                    closestATMDist = dist
                end
            end
        end
        
        -- Check bank teller proximity
        for i, teller in pairs(bankTellerPeds) do
            if teller.ped and DoesEntityExist(teller.ped) then
                local dist = #(playerCoords - teller.coords)
                if dist < 3.0 and dist < closestTellerDist then
                    closestBankTeller = teller
                    closestTellerDist = dist
                end
            end
        end
        
        -- Handle ATM interactions
        if closestATM and closestATMDist < 2.0 then
            if not bankingData.isUsingATM then
                ShowHelpText("Press ~INPUT_CONTEXT~ to use ATM\nPress ~INPUT_DETONATE~ to hack ATM (Robbers only)")
                
                if IsControlJustPressed(0, 38) then -- E key
                    OpenATMInterface(closestATM)
                elseif IsControlJustPressed(0, 47) then -- G key (hack)
                    TriggerServerEvent('cnr:hackATM', closestATM.id)
                end
            end
        end
        
        -- Handle bank teller interactions
        if closestBankTeller and closestTellerDist < 3.0 then
            if not bankingData.isAtBank then
                ShowHelpText("Press ~INPUT_CONTEXT~ to speak with " .. closestBankTeller.name)
                
                if IsControlJustPressed(0, 38) then -- E key
                    OpenBankInterface(closestBankTeller)
                end
            end
        end
        
        -- If no interactions available, hide help text
        if not closestATM and not closestBankTeller then
            bankingData.isUsingATM = false
            bankingData.isAtBank = false
        end
    end
end)

-- Open ATM interface
function OpenATMInterface(atm)
    bankingData.isUsingATM = true
    bankingData.currentATM = atm
    
    -- Request current balance
    TriggerServerEvent('cnr:getBankBalance')
    
    -- Open ATM UI
    SendNUIMessage({
        type = "openATM",
        atmData = {
            id = atm.id,
            balance = bankingData.balance
        }
    })
    
    SetNuiFocus(true, true)
end

-- Open bank interface
function OpenBankInterface(teller)
    bankingData.isAtBank = true
    bankingData.currentBankTeller = teller
    
    -- Request current balance and transaction history
    TriggerServerEvent('cnr:getBankBalance')
    TriggerServerEvent('cnr:getTransactionHistory')
    
    -- Open bank UI
    SendNUIMessage({
        type = "openBank",
        bankData = {
            tellerName = teller.name,
            services = teller.services,
            balance = bankingData.balance,
            transactions = bankingData.transactionHistory
        }
    })
    
    SetNuiFocus(true, true)
end

-- Close banking interfaces
function CloseBankingInterface()
    bankingData.isUsingATM = false
    bankingData.isAtBank = false
    bankingData.currentATM = nil
    bankingData.currentBankTeller = nil
    
    SendNUIMessage({
        type = "closeBanking"
    })
    
    SetNuiFocus(false, false)
end

-- NUI Callbacks for banking
RegisterNUICallback('closeBanking', function(data, cb)
    CloseBankingInterface()
    cb('ok')
end)

RegisterNUICallback('bankDeposit', function(data, cb)
    local amount = tonumber(data.amount)
    if amount and amount > 0 then
        TriggerServerEvent('cnr:bankDeposit', amount)
    end
    cb('ok')
end)

RegisterNUICallback('bankWithdraw', function(data, cb)
    local amount = tonumber(data.amount)
    if amount and amount > 0 then
        TriggerServerEvent('cnr:bankWithdraw', amount)
    end
    cb('ok')
end)

RegisterNUICallback('bankTransfer', function(data, cb)
    local targetId = tonumber(data.targetId)
    local amount = tonumber(data.amount)
    if targetId and amount and amount > 0 then
        TriggerServerEvent('cnr:bankTransfer', targetId, amount)
    end
    cb('ok')
end)

RegisterNUICallback('requestLoan', function(data, cb)
    local amount = tonumber(data.amount)
    local duration = tonumber(data.duration)
    if amount and amount > 0 then
        TriggerServerEvent('cnr:requestLoan', amount, duration)
    end
    cb('ok')
end)

RegisterNUICallback('repayLoan', function(data, cb)
    local amount = tonumber(data.amount)
    if amount and amount > 0 then
        TriggerServerEvent('cnr:repayLoan', amount)
    end
    cb('ok')
end)

RegisterNUICallback('makeInvestment', function(data, cb)
    local investmentId = data.investmentId
    local amount = tonumber(data.amount)
    if investmentId and amount and amount > 0 then
        TriggerServerEvent('cnr:makeInvestment', investmentId, amount)
    end
    cb('ok')
end)

-- Helper function to show help text
function ShowHelpText(text)
    SetTextComponentFormat("STRING")
    AddTextComponentString(text)
    DisplayHelpTextFromStringLabel(0, 0, 1, -1)
end

-- Initialize banking system when resource starts
AddEventHandler('onClientResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        -- Wait for game to load then initialize banking
        Citizen.Wait(5000)
        InitializeBankingProps()
    end
end)

-- Clean up banking props when resource stops
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        -- Clean up ATM props
        for _, atm in pairs(atmProps) do
            if atm.prop and DoesEntityExist(atm.prop) then
                DeleteEntity(atm.prop)
            end
        end
        
        -- Clean up bank teller peds
        for _, teller in pairs(bankTellerPeds) do
            if teller.ped and DoesEntityExist(teller.ped) then
                DeleteEntity(teller.ped)
            end
        end
    end
end)
