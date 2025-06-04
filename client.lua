-- client.lua
-- Cops & Robbers FiveM Game Mode - Client Script
-- Version: 1.2 | Date: <current date>
-- Ped readiness flag and guards implemented.

local g_isPlayerPedReady = false

-- =====================================
--           CONFIGURATION
-- =====================================

-- Config is loaded from shared_scripts 'config.lua'

-- =====================================
--           VARIABLES
-- =====================================

-- Player-related variables
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

-- Wanted System Client State
local currentWantedStarsClient = 0
local currentWantedPointsClient = 0
local wantedUiLabel = ""

local xpForNextLevelDisplay = 0

-- Contraband Drop Client State
local activeDropBlips = {}
local clientActiveContrabandDrops = {}
local isCollectingFromDrop = nil
local collectionTimerEnd = 0

-- Safe Zone Client State
local isCurrentlyInSafeZone = false
local currentSafeZoneName = ""

-- Wanted System Expansion Client State
local currentPlayerNPCResponseEntities = {}
local corruptOfficialNPCs = {}

-- =====================================
--           HELPER FUNCTIONS
-- =====================================

local function ShowNotification(text)
    if not text or text == "" then
        print("ShowNotification: Received nil or empty text.")
        return
    end
    SetNotificationTextEntry("STRING")
    AddTextComponentSubstringPlayerName(text)
    DrawNotification(false, true)
end

local function DisplayHelpText(text)
    if not text or text == "" then
        print("DisplayHelpText: Received nil or empty text.")
        return
    end
    BeginTextCommandDisplayHelp("STRING")
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, true, -1)
end

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

-- =====================================
--           NETWORK EVENTS
-- =====================================

AddEventHandler('playerSpawned', function()
    TriggerServerEvent('cops_and_robbers:requestPlayerData')
    SendNUIMessage({ action = 'showRoleSelection', resourceName = GetCurrentResourceName() })
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

    local playerPedOnUpdate = PlayerPedId() -- Get ped ID at this point

    if role and oldRole ~= role then
        if playerPedOnUpdate and playerPedOnUpdate ~= 0 and playerPedOnUpdate ~= -1 and DoesEntityExist(playerPedOnUpdate) then
            spawnPlayer(role)
        else
            print("[CNR_CLIENT_WARN] cnr:updatePlayerData: playerPed invalid during role change spawn.")
        end
    elseif not oldRole and role then
        if playerPedOnUpdate and playerPedOnUpdate ~= 0 and playerPedOnUpdate ~= -1 and DoesEntityExist(playerPedOnUpdate) then
            spawnPlayer(role)
        else
            print("[CNR_CLIENT_WARN] cnr:updatePlayerData: playerPed invalid during initial role spawn.")
        end
    end

    SendNUIMessage({ action = 'updateMoney', cash = playerCash })
    SendNUIMessage({
        action = "updateXPBar",
        currentXP = playerData.xp,
        currentLevel = playerData.level,
        xpForNextLevel = CalculateXpForNextLevelClient(playerData.level, playerData.role)
    })
    ShowNotification(string.format("Data Synced: Lvl %d, XP %d, Role %s", playerData.level, playerData.xp, playerData.role), "info", 2000)

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
            print("[CNR_CLIENT] Player Ped is now considered READY (g_isPlayerPedReady = true). Role: " .. role)
        end)
    elseif role == "citizen" and g_isPlayerPedReady then
         g_isPlayerPedReady = false -- Reset if player goes back to citizen (e.g. admin setrole)
         print("[CNR_CLIENT] Player Ped is NO LONGER READY (g_isPlayerPedReady = false) due to role change to citizen.")
    end
end)

-- RegisterNetEvent('cnr:setNuiFocus')
-- AddEventHandler('cnr:setNuiFocus', function(data)
--     if type(data) == "table" and data.hasFocus ~= nil and data.hasCursor ~= nil then
--         print(string.format("[CNR_CLIENT] Setting NUI focus via event: hasFocus=%s, hasCursor=%s", tostring(data.hasFocus), tostring(data.hasCursor)))
--         SetNuiFocus(data.hasFocus, data.hasCursor)
--     else
--         print(string.format("[CNR_CLIENT_WARN] cnr:setNuiFocus received invalid data: %s", json.encode and json.encode(data) or tostring(data)))
--     end
-- end)

function CalculateXpForNextLevelClient(currentLevel, playerRole)
    if not Config.LevelingSystemEnabled then return 999999 end
    local maxLvl = Config.MaxLevel or 10
    if currentLevel >= maxLvl then return playerData.xp end
    if Config.XPTable and Config.XPTable[currentLevel] then return Config.XPTable[currentLevel]
    else print("CalculateXpForNextLevelClient: XP requirement for level " .. currentLevel .. " not found. Returning high value.", "warn"); return 999999 end
end

RegisterNetEvent('cnr:xpGained')
AddEventHandler('cnr:xpGained', function(amount, newTotalXp)
    playerData.xp = newTotalXp
    ShowNotification(string.format("~g~+%d XP! (Total: %d)", amount, newTotalXp), "info", 3000)
    SendNUIMessage({ action = "updateXPBar", currentXP = playerData.xp, currentLevel = playerData.level, xpForNextLevel = CalculateXpForNextLevelClient(playerData.level, playerData.role) })
end)

RegisterNetEvent('cnr:levelUp')
AddEventHandler('cnr:levelUp', function(newLevel, newTotalXp)
    playerData.level = newLevel
    playerData.xp = newTotalXp
    ShowNotification("~g~LEVEL UP!~w~ You reached Level " .. newLevel .. "!", "success", 10000)
    SendNUIMessage({ action = "updateXPBar", currentXP = playerData.xp, currentLevel = playerData.level, xpForNextLevel = CalculateXpForNextLevelClient(playerData.level, playerData.role) })
end)

RegisterNetEvent('cops_and_robbers:updateWantedDisplay')
AddEventHandler('cops_and_robbers:updateWantedDisplay', function(stars, points)
    currentWantedStarsClient = stars
    currentWantedPointsClient = points
    local newUiLabel = ""
    if stars > 0 then
        for _, levelData in ipairs(Config.WantedSettings.levels) do if levelData.stars == stars then newUiLabel = levelData.uiLabel; break end end
        if newUiLabel == "" then newUiLabel = "Wanted: " .. string.rep("*", stars) end
    end
    wantedUiLabel = newUiLabel
    local playerId = PlayerId()
    if playerId and playerId ~= -1 then -- Guard for PlayerId()
        SetPlayerWantedLevel(playerId, stars, false)
        SetPlayerWantedLevelNow(playerId, false)
    end
end)

RegisterNetEvent('cops_and_robbers:wantedLevelResponseUpdate')
AddEventHandler('cops_and_robbers:wantedLevelResponseUpdate', function(targetPlayerId, stars, points, lastKnownCoords)
    local localPlayerId = PlayerId()
    if not (localPlayerId and localPlayerId ~= -1) then return end -- Guard for PlayerId()
    if targetPlayerId ~= localPlayerId then return end

    for _, entity in ipairs(currentPlayerNPCResponseEntities) do
        if DoesEntityExist(entity) then DeleteEntity(entity) end -- Model release handled by DeleteEntity for mission entities
    end
    currentPlayerNPCResponseEntities = {}

    if stars == 0 then ShowNotification("~g~Police response stood down."); return end

    local presetStarLevel = math.min(stars, #Config.WantedNPCPresets)
    if not Config.WantedNPCPresets[presetStarLevel] then print("No NPC response preset for level: " .. presetStarLevel); return end

    local responseGroupsConfig = Config.WantedNPCPresets[presetStarLevel]
    local playerPed = PlayerPedId() -- Guarded by the initial PlayerId() check at the top of event

    if not (playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed)) then
        print("[CNR_CLIENT_WARN] wantedLevelResponseUpdate: playerPed invalid, cannot spawn NPC response.")
        return
    end

    local activeSpawnedGroupsCount = 0
    for _, groupInfo in ipairs(responseGroupsConfig) do
        if activeSpawnedGroupsCount >= Config.MaxActiveNPCResponseGroups then break end
        CreateThread(function()
             while not g_isPlayerPedReady do Citizen.Wait(500) end -- Ensure player is ready before this thread's logic
            local currentGroupPlayerPed = PlayerPedId() -- Re-fetch in thread if needed, or use playerPed from outer scope carefully
            if not (currentGroupPlayerPed and currentGroupPlayerPed ~= 0 and currentGroupPlayerPed ~= -1 and DoesEntityExist(currentGroupPlayerPed)) then return end

            local groupEntitiesThisSpawn = {}
            local vehicle = nil
            local actualSpawnPos = vector3(lastKnownCoords.x, lastKnownCoords.y, lastKnownCoords.z)
            local spawnOffsetAttempt = vector3(math.random(70,120) * (math.random(0,1)*2-1) + 0.01, math.random(70,120) * (math.random(0,1)*2-1) + 0.01, 2.0)
            local foundSpawn, safeSpawnPos = GetSafeCoordForPed(actualSpawnPos.x + spawnOffsetAttempt.x, actualSpawnPos.y + spawnOffsetAttempt.y, actualSpawnPos.z + spawnOffsetAttempt.z, true, 0)
            if not foundSpawn then
                local foundRoadNode, nodePos = GetClosestVehicleNode(actualSpawnPos.x + spawnOffsetAttempt.x, actualSpawnPos.y + spawnOffsetAttempt.y, actualSpawnPos.z, vector3(0,0,0), 1, 3.0, 0)
                if foundRoadNode then
                    local nodeX, nodeY, nodeZ = table.unpack(GetVehicleNodePosition(nodePos, vector3(0,0,0)))
                    foundSpawn, safeSpawnPos = GetSafeCoordForPed(nodeX, nodeY, nodeZ, true, 0)
                    if not foundSpawn then safeSpawnPos = vector3(nodeX, nodeY, nodeZ); foundSpawn = true end
                end
            end
            if foundSpawn then actualSpawnPos = safeSpawnPos else actualSpawnPos = actualSpawnPos + vector3(0,0,1.0) end
            local currentHeading = GetEntityHeading(currentGroupPlayerPed)

            if groupInfo.helicopterChance and groupInfo.helicopter and math.random() < groupInfo.helicopterChance then
                local heliModel = (type(groupInfo.helicopter) == "number" and groupInfo.helicopter) or GetHashKey(groupInfo.helicopter)
                RequestModel(heliModel); local attempts = 0; while not HasModelLoaded(heliModel) and attempts < 50 do Citizen.Wait(50); attempts = attempts + 1 end
                if HasModelLoaded(heliModel) then vehicle = CreateVehicle(heliModel, actualSpawnPos.x, actualSpawnPos.y, actualSpawnPos.z + 50.0, currentHeading, true, false); table.insert(groupEntitiesThisSpawn, vehicle); table.insert(currentPlayerNPCResponseEntities, vehicle) end
                SetModelAsNoLongerNeeded(heliModel)
            elseif groupInfo.vehicle then
                local vehicleModel = (type(groupInfo.vehicle) == "number" and groupInfo.vehicle) or GetHashKey(groupInfo.vehicle)
                RequestModel(vehicleModel); local attempts = 0; while not HasModelLoaded(vehicleModel) and attempts < 50 do Citizen.Wait(50); attempts = attempts + 1 end
                if HasModelLoaded(vehicleModel) then vehicle = CreateVehicle(vehicleModel, actualSpawnPos.x, actualSpawnPos.y, actualSpawnPos.z, currentHeading + 180.0, true, false); table.insert(groupEntitiesThisSpawn, vehicle); table.insert(currentPlayerNPCResponseEntities, vehicle) end
                SetModelAsNoLongerNeeded(vehicleModel)
            end
            local weaponHash = (type(groupInfo.weapon) == "number" and groupInfo.weapon) or GetHashKey(groupInfo.weapon)
            local pedModelHash = (type(groupInfo.pedModel) == "number" and groupInfo.pedModel) or GetHashKey(groupInfo.pedModel or "s_m_y_cop_01")
            RequestModel(pedModelHash); local attempts = 0; while not HasModelLoaded(pedModelHash) and attempts < 50 do Citizen.Wait(50); attempts = attempts + 1 end
            if HasModelLoaded(pedModelHash) then
                for i = 1, groupInfo.count do
                    local ped
                    if vehicle and i <= GetVehicleMaxNumberOfPassengers(vehicle) and GetPedInVehicleSeat(vehicle, -1 + (i-1)) == 0 then ped = CreatePedInsideVehicle(vehicle, 26, pedModelHash, -1 + (i-1), true, false)
                    else ped = CreatePed(26, pedModelHash, actualSpawnPos.x + math.random(-5,5), actualSpawnPos.y + math.random(-5,5), actualSpawnPos.z, currentHeading, true, false) end
                    if ped then
                        GiveWeaponToPed(ped, weaponHash, 250, false, true); SetPedArmour(ped, groupInfo.armour or 25); SetPedAccuracy(ped, groupInfo.accuracy or 15)
                        SetPedCombatAttributes(ped, 46, true); if groupInfo.combatAttributes then for attrId, valBool in pairs(groupInfo.combatAttributes) do SetPedCombatAttributes(ped, attrId, valBool) end end
                        SetPedSeeingRange(ped, groupInfo.sightDistance or 80.0); SetEntityIsTargetPriority(ped, true, 0); SetPedRelationshipGroupHash(ped, GetHashKey("COP"))
                        if vehicle and GetPedInVehicleSeat(vehicle, -1) == ped then TaskVehicleDriveToCoord(ped, vehicle, GetEntityCoords(currentGroupPlayerPed).x, GetEntityCoords(currentGroupPlayerPed).y, GetEntityCoords(currentGroupPlayerPed).z, 25.0, 1, GetHashKey(Config.PoliceVehicles[1] or "police"), 786603, 10.0, -1); SetPedKeepTask(ped, true)
                        else TaskCombatPed(ped, currentGroupPlayerPed, 0, 16) end
                        table.insert(groupEntitiesThisSpawn, ped); table.insert(currentPlayerNPCResponseEntities, ped)
                    end
                end
            end
            SetModelAsNoLongerNeeded(pedModelHash); activeSpawnedGroupsCount = activeSpawnedGroupsCount + 1
            Citizen.Wait(180000)
            for _, entityToClean in pairs(groupEntitiesThisSpawn) do if DoesEntityExist(entityToClean) then for k, trackedEntity in pairs(currentPlayerNPCResponseEntities) do if trackedEntity == entityToClean then table.remove(currentPlayerNPCResponseEntities, k); break end end; DeleteEntity(entityToClean) end end
        end)
    end
end)

RegisterNetEvent('cops_and_robbers:contrabandDropSpawned')
AddEventHandler('cops_and_robbers:contrabandDropSpawned', function(dropId, location, itemName, itemModelHash)
    if activeDropBlips[dropId] then RemoveBlip(activeDropBlips[dropId]) end
    local blip = AddBlipForCoord(location.x, location.y, location.z)
    SetBlipSprite(blip, 1); SetBlipColour(blip, 2); SetBlipScale(blip, 1.5); SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName("STRING"); AddTextComponentSubstringPlayerName("Contraband: " .. itemName); EndTextCommandSetBlipName(blip)
    activeDropBlips[dropId] = blip
    local propEntity = nil
    if itemModelHash then
        local model = (type(itemModelHash) == "number" and itemModelHash) or GetHashKey(itemModelHash)
        RequestModel(model)
        CreateThread(function()
             while not g_isPlayerPedReady do Citizen.Wait(500) end
            local attempts = 0; while not HasModelLoaded(model) and attempts < 100 do Citizen.Wait(100); attempts = attempts + 1 end
            if HasModelLoaded(model) then
                propEntity = CreateObject(model, location.x, location.y, location.z - 0.9, false, true, true)
                PlaceObjectOnGroundProperly(propEntity)
                if clientActiveContrabandDrops[dropId] then clientActiveContrabandDrops[dropId].propEntity = propEntity else DeleteEntity(propEntity) end
            end
            SetModelAsNoLongerNeeded(model)
        end)
    end
    clientActiveContrabandDrops[dropId] = { id = dropId, location = location, name = itemName, modelHash = itemModelHash, propEntity = propEntity }
    ShowNotification("~y~A new contraband drop has appeared: " .. itemName)
end)

RegisterNetEvent('cops_and_robbers:contrabandDropCollected')
AddEventHandler('cops_and_robbers:contrabandDropCollected', function(dropId, collectorName, itemName)
    if activeDropBlips[dropId] then RemoveBlip(activeDropBlips[dropId]); activeDropBlips[dropId] = nil end
    if clientActiveContrabandDrops[dropId] then
        if clientActiveContrabandDrops[dropId].propEntity and DoesEntityExist(clientActiveContrabandDrops[dropId].propEntity) then DeleteEntity(clientActiveContrabandDrops[dropId].propEntity) end
        clientActiveContrabandDrops[dropId] = nil
    end
    if isCollectingFromDrop == dropId then isCollectingFromDrop = nil; collectionTimerEnd = 0 end
    ShowNotification("~g~Contraband '" .. itemName .. "' was collected by " .. collectorName .. ".")
end)

RegisterNetEvent('cops_and_robbers:collectingContrabandStarted')
AddEventHandler('cops_and_robbers:collectingContrabandStarted', function(dropId, collectionTime)
    isCollectingFromDrop = dropId; collectionTimerEnd = GetGameTimer() + collectionTime
    ShowNotification("~b~Collecting contraband... Hold position.")
end)

Citizen.CreateThread(function()
    while not g_isPlayerPedReady do Citizen.Wait(500) end
    print("[CNR_CLIENT] Thread for Contraband Interaction now starting its main loop.")
    local lastInteractionCheck = 0; local interactionCheckInterval = 250; local activeCollectionWait = 50
    while true do
        local loopWait = interactionCheckInterval
        local playerPed = PlayerPedId()
        if not (playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed)) then Citizen.Wait(1000); goto continue_contraband_loop end
        if role == 'robber' then
            local playerCoords = GetEntityCoords(playerPed)
            if not isCollectingFromDrop then
                if (GetGameTimer() - lastInteractionCheck) > interactionCheckInterval then
                    for dropId, dropData in pairs(clientActiveContrabandDrops) do
                        if dropData.location and #(playerCoords - dropData.location) < 3.0 then
                            DisplayHelpText("Press ~INPUT_CONTEXT~ to collect contraband (" .. dropData.name .. ")")
                            if IsControlJustReleased(0, 51) then TriggerServerEvent('cops_and_robbers:startCollectingContraband', dropId) end
                            loopWait = activeCollectionWait; break
                        end
                    end; lastInteractionCheck = GetGameTimer()
                end
            else
                loopWait = activeCollectionWait
                local currentDropData = clientActiveContrabandDrops[isCollectingFromDrop]
                if currentDropData and currentDropData.location then
                    if #(playerCoords - currentDropData.location) > 5.0 then ShowNotification("~r~Contraband collection cancelled: Moved too far."); isCollectingFromDrop = nil; collectionTimerEnd = 0
                    elseif GetGameTimer() >= collectionTimerEnd then ShowNotification("~g~Collection complete! Verifying with server..."); TriggerServerEvent('cops_and_robbers:finishCollectingContraband', isCollectingFromDrop); isCollectingFromDrop = nil; collectionTimerEnd = 0 end
                else isCollectingFromDrop = nil; collectionTimerEnd = 0 end
            end
        end
        Citizen.Wait(loopWait)
        ::continue_contraband_loop::
    end
end)

Citizen.CreateThread(function()
    while not g_isPlayerPedReady do Citizen.Wait(500) end
    print("[CNR_CLIENT] Thread for SafeZone/RestrictedArea Interaction now starting its main loop.")
    local checkInterval = 1000
    while true do
        Citizen.Wait(checkInterval)
        local playerPed = PlayerPedId()
        if not (playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed)) then goto continue_main_interaction_loop end
        local playerCoords = GetEntityCoords(playerPed)

        if Config.SafeZones and #Config.SafeZones > 0 then
            local foundSafeZoneThisCheck = false; local enteredZoneName = ""; local enteredZoneMessage = ""
            for _, zone in ipairs(Config.SafeZones) do
                if #(playerCoords - zone.location) < zone.radius then foundSafeZoneThisCheck = true; enteredZoneName = zone.name; enteredZoneMessage = zone.message or "You have entered a Safe Zone."; break end
            end
            if foundSafeZoneThisCheck then
                if not isCurrentlyInSafeZone then isCurrentlyInSafeZone = true; currentSafeZoneName = enteredZoneName; ShowNotification(enteredZoneMessage); SetEntityInvincible(playerPed, true); DisablePlayerFiring(PlayerId(), true); SetPlayerCanDoDriveBy(PlayerId(), false) end
            elseif isCurrentlyInSafeZone then ShowNotification("~g~You have left " .. currentSafeZoneName .. "."); isCurrentlyInSafeZone = false; currentSafeZoneName = ""; SetEntityInvincible(playerPed, false); DisablePlayerFiring(PlayerId(), false); SetPlayerCanDoDriveBy(PlayerId(), true) end
        elseif isCurrentlyInSafeZone then isCurrentlyInSafeZone = false; currentSafeZoneName = ""; SetEntityInvincible(playerPed, false); DisablePlayerFiring(PlayerId(), false); SetPlayerCanDoDriveBy(PlayerId(), true); ShowNotification("~g~Safe zone status reset (zones removed).") end

        if Config.RestrictedAreas and #Config.RestrictedAreas > 0 then
            for _, area in ipairs(Config.RestrictedAreas) do if #(playerCoords - area.center) < area.radius and currentWantedStarsClient >= area.wantedThreshold then ShowNotification(area.message); break end end
        end

        if role == 'robber' or currentWantedStarsClient > 0 then
            if Config.CorruptOfficials then
                for i, official in ipairs(Config.CorruptOfficials) do
                    if #(playerCoords - official.location) < 10.0 then
                        if not corruptOfficialNPCs[i] or not DoesEntityExist(corruptOfficialNPCs[i]) then
                            local modelHash = GetHashKey(official.model); RequestModel(modelHash); local attempts = 0; while not HasModelLoaded(modelHash) and attempts < 50 do Citizen.Wait(50); attempts=attempts+1; end
                            if HasModelLoaded(modelHash) then corruptOfficialNPCs[i] = CreatePed(4, modelHash, official.location.x, official.location.y, official.location.z - 1.0, GetRandomFloatInRange(0.0,360.0), false, true); FreezeEntityPosition(corruptOfficialNPCs[i], true); SetEntityInvincible(corruptOfficialNPCs[i], true); SetBlockingOfNonTemporaryEvents(corruptOfficialNPCs[i], true); SetModelAsNoLongerNeeded(modelHash) end
                        end
                        if corruptOfficialNPCs[i] and DoesEntityExist(corruptOfficialNPCs[i]) then DisplayHelpText(official.dialogue .. "\nPress ~INPUT_CONTEXT~ to bribe (" .. official.name .. ")"); if IsControlJustReleased(0, 51) then TriggerServerEvent('cops_and_robbers:payOffOfficial', i) end end
                        break
                    elseif corruptOfficialNPCs[i] and DoesEntityExist(corruptOfficialNPCs[i]) then DeleteEntity(corruptOfficialNPCs[i]); corruptOfficialNPCs[i] = nil end
                end
            end
            if Config.AppearanceChangeStores then
                for i, store_loc in ipairs(Config.AppearanceChangeStores) do if #(playerCoords - store_loc.location) < 3.0 then DisplayHelpText("Press ~INPUT_CONTEXT~ to change appearance at " .. store_loc.name .. " ($" .. store_loc.cost .. ")"); if IsControlJustReleased(0, 51) then TriggerServerEvent('cops_and_robbers:changeAppearance', i) end; break end end
            end
        end
        ::continue_main_interaction_loop::
    end
end)

Citizen.CreateThread(function()
    while not g_isPlayerPedReady do Citizen.Wait(500) end
    print("[CNR_CLIENT] Thread for Crime Detection now starting its main loop.")
    local lastPlayerVehicle = 0; local lastVehicleDriver = 0; local lastAssaultReportTime = 0; local assaultReportCooldown = 5000
    while true do
        Citizen.Wait(1000)
        local playerPed = PlayerPedId()
        if not (playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed)) or not role or role == 'cop' then Citizen.Wait(5000); goto continue_crime_detection_loop end

        local currentVehicle = GetVehiclePedIsIn(playerPed, false)
        if currentVehicle ~= 0 and currentVehicle ~= lastPlayerVehicle then
            local driver = GetPedInVehicleSeat(currentVehicle, -1)
            if driver == playerPed and DoesEntityExist(lastVehicleDriver) and lastVehicleDriver ~= playerPed and not IsPedAPlayer(lastVehicleDriver) and IsPedHuman(lastVehicleDriver) then
                ShowNotification("~r~Grand Theft Auto!"); TriggerServerEvent('cops_and_robbers:reportCrime', 'grand_theft_auto', GetVehicleNumberPlateText(currentVehicle))
            end
        end
        if currentVehicle ~= 0 then lastVehicleDriver = GetPedInVehicleSeat(currentVehicle, -1) else lastVehicleDriver = 0 end
        lastPlayerVehicle = currentVehicle

        if IsPedInMeleeCombat(playerPed) and (GetGameTimer() - lastAssaultReportTime) > assaultReportCooldown then
            local _, targetPed = GetPedMeleeTargetForPed(playerPed)
            if DoesEntityExist(targetPed) and not IsPedAPlayer(targetPed) and IsPedHuman(targetPed) then
                local targetModel = GetEntityModel(targetPed)
                if targetModel ~= GetHashKey("s_m_y_cop_01") and targetModel ~= GetHashKey("s_f_y_cop_01") and targetModel ~= GetHashKey("s_m_y_swat_01") and GetPedRelationshipGroupHash(targetPed) ~= GetHashKey("COP") then
                    ShowNotification("~r~Civilian Assaulted!"); TriggerServerEvent('cops_and_robbers:reportCrime', 'assault_civilian'); lastAssaultReportTime = GetGameTimer()
                end
            end
        end
        ::continue_crime_detection_loop::
    end
end)

RegisterNetEvent('cops_and_robbers:sendItemList')
AddEventHandler('cops_and_robbers:sendItemList', function(storeName, itemList)
    SendNUIMessage({ action = 'openStore', storeName = storeName, items = itemList, playerLevel = playerData.level, playerRole = playerData.role, playerPerks = playerData.perks, playerMoney = playerCash, resourceName = GetParentResourceName() })
end)

RegisterNetEvent('cops_and_robbers:notifyBankRobbery')
AddEventHandler('cops_and_robbers:notifyBankRobbery', function(bankId, bankLocation, bankName)
    if role == 'cop' then ShowNotification("~r~Bank Robbery in Progress!~s~\nBank: " .. bankName); SetNewWaypoint(bankLocation.x, bankLocation.y) end
end)

RegisterNetEvent('cops_and_robbers:renderSpikeStrip')
AddEventHandler('cops_and_robbers:renderSpikeStrip', function(stripId, location)
    if not HasModelLoaded(spikeStripModelHash) then RequestModel(spikeStripModelHash); while not HasModelLoaded(spikeStripModelHash) do Citizen.Wait(50) end end
    local deployCoords = vector3(location.x, location.y, location.z)
    local _, groundZ = GetGroundZFor_3dCoord(deployCoords.x, deployCoords.y, deployCoords.z + 1.0, false)
    local finalCoords = vector3(deployCoords.x, deployCoords.y, groundZ)
    local spikeProp = CreateObject(spikeStripModelHash, finalCoords.x, finalCoords.y, finalCoords.z, true, true, false)
    FreezeEntityPosition(spikeProp, true); SetEntityCollision(spikeProp, true, true)
    currentSpikeStrips[stripId] = { id = stripId, obj = spikeProp, location = finalCoords }
end)

RegisterNetEvent('cops_and_robbers:removeSpikeStrip')
AddEventHandler('cops_and_robbers:removeSpikeStrip', function(stripId)
    if currentSpikeStrips[stripId] and DoesEntityExist(currentSpikeStrips[stripId].obj) then DeleteEntity(currentSpikeStrips[stripId].obj) end
    currentSpikeStrips[stripId] = nil
end)

RegisterNetEvent('cops_and_robbers:applySpikeEffectToVehicle')
AddEventHandler('cops_and_robbers:applySpikeEffectToVehicle', function(vehicleNetId)
    local vehicle = NetToVeh(vehicleNetId)
    if DoesEntityExist(vehicle) and IsEntityAVehicle(vehicle) then
        SetVehicleTyreBurst(vehicle, 0, true, 1000.0); SetVehicleTyreBurst(vehicle, 1, true, 1000.0)
        SetVehicleTyreBurst(vehicle, 2, true, 1000.0); SetVehicleTyreBurst(vehicle, 3, true, 1000.0)
        ShowNotification("~r~Your tires have been spiked!")
    end
end)

RegisterNetEvent('cops_and_robbers:showHeistTimerUI')
AddEventHandler('cops_and_robbers:showHeistTimerUI', function(bankName, duration)
    SendNUIMessage({ action = 'startHeistTimer', duration = duration, bankName = bankName })
end)

RegisterNetEvent('cops_and_robbers:toggleFreeze')
AddEventHandler('cops_and_robbers:toggleFreeze', function()
    local playerPed = PlayerPedId()
    if playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed) then
        local currentlyFrozen = IsEntityFrozen(playerPed)
        FreezeEntityPosition(playerPed, not currentlyFrozen)
        ShowNotification(not currentlyFrozen and "~r~An admin has frozen you." or "~g~An admin has unfrozen you.")
    end
end)

RegisterNetEvent('cops_and_robbers:teleportToPlayer')
AddEventHandler('cops_and_robbers:teleportToPlayer', function(targetPlayerIdToTeleportTo)
    local playerPed = PlayerPedId()
    if not (playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed)) then return end
    local targetPed = GetPlayerPed(targetPlayerIdToTeleportTo)
    if DoesEntityExist(targetPed) then
        SetEntityCoords(playerPed, GetEntityCoords(targetPed), false, false, false, true)
        ShowNotification("~b~You have been teleported by an admin.")
    else ShowNotification("~r~Target player for teleport not found or too far away.") end
end)

RegisterNetEvent('cops_and_robbers:sendToJail')
AddEventHandler('cops_and_robbers:sendToJail', function(jailTime)
    local playerPed = PlayerPedId()
    if not (playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed)) then return end
    SetEntityCoords(playerPed, Config.PrisonLocation.x, Config.PrisonLocation.y, Config.PrisonLocation.z, false, false, false, true)
    ShowNotification("~r~You have been sent to jail for " .. jailTime .. " seconds.")
    Citizen.CreateThread(function()
         while not g_isPlayerPedReady do Citizen.Wait(500) end
        local remainingTime = jailTime
        while remainingTime > 0 do Citizen.Wait(1000); remainingTime = remainingTime - 1
            DisableControlAction(0, 24, true); DisableControlAction(0, 25, true); DisableControlAction(0, 47, true); DisableControlAction(0, 58, true)
        end
        ShowNotification("~g~You have been released from jail.")
        local pData = playerData
        if pData and pData.role then spawnPlayer(pData.role) else spawnPlayer("robber") end
    end)
end)

RegisterNetEvent('cops_and_robbers:purchaseConfirmed')
AddEventHandler('cops_and_robbers:purchaseConfirmed', function(itemId, quantity)
    quantity = quantity or 1; local itemName = nil
    for _, item in ipairs(Config.Items) do if item.itemId == itemId then itemName = item.name; break end end
    ShowNotification(itemName and ('You purchased: ' .. quantity .. ' x ' .. itemName) or 'Purchase successful.')
end)

RegisterNetEvent('cops_and_robbers:purchaseFailed')
AddEventHandler('cops_and_robbers:purchaseFailed', function(reason) ShowNotification('Purchase failed: ' .. reason) end)

RegisterNetEvent('cops_and_robbers:sellConfirmed')
AddEventHandler('cops_and_robbers:sellConfirmed', function(itemId, quantity)
    quantity = quantity or 1; local itemName = nil
    for _, item in ipairs(Config.Items) do if item.itemId == itemId then itemName = item.name; break end end
    ShowNotification(itemName and ('You sold: ' .. quantity .. ' x ' .. itemName) or 'Sale successful.')
end)

RegisterNetEvent('cops_and_robbers:sellFailed')
AddEventHandler('cops_and_robbers:sellFailed', function(reason) ShowNotification('Sale failed: ' .. reason) end)

RegisterNetEvent('cops_and_robbers:addWeapon')
AddEventHandler('cops_and_robbers:addWeapon', function(weaponName, ammoCount)
    local playerPed = PlayerPedId()
    if not (playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed)) then ShowNotification("~r~Cannot add weapon: Player ped invalid."); return end
    local weaponHash = GetHashKey(weaponName)
    if weaponHash ~= 0 and weaponHash ~= -1 then
        GiveWeaponToPed(playerPed, weaponHash, ammoCount or 0, false, false)
        playerWeapons[weaponName] = true; playerAmmo[weaponName] = ammoCount or 0
        ShowNotification("~g~Weapon equipped: " .. (Config.WeaponNames[weaponName] or weaponName))
    else ShowNotification("~r~Invalid weapon specified: " .. tostring(weaponName)) end
end)

RegisterNetEvent('cops_and_robbers:removeWeapon')
AddEventHandler('cops_and_robbers:removeWeapon', function(weaponName)
    local playerPed = PlayerPedId()
    if not (playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed)) then ShowNotification("~r~Cannot remove weapon: Player ped invalid."); return end
    local weaponHash = GetHashKey(weaponName)
    if weaponHash ~= 0 and weaponHash ~= -1 then
        RemoveWeaponFromPed(playerPed, weaponHash)
        playerWeapons[weaponName] = nil; playerAmmo[weaponName] = nil
        ShowNotification("~y~Weapon removed: " .. (Config.WeaponNames[weaponName] or weaponName))
    else ShowNotification("~r~Invalid weapon specified for removal: " .. tostring(weaponName)) end
end)

RegisterNetEvent('cops_and_robbers:addAmmo')
AddEventHandler('cops_and_robbers:addAmmo', function(weaponName, ammoToAdd)
    local playerPed = PlayerPedId()
    if not (playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed)) then ShowNotification("~r~Cannot add ammo: Player ped invalid."); return end
    local weaponHash = GetHashKey(weaponName)
    if weaponHash ~= 0 and weaponHash ~= -1 then
        if HasPedGotWeapon(playerPed, weaponHash, false) then AddAmmoToPed(playerPed, weaponHash, ammoToAdd); playerAmmo[weaponName] = (playerAmmo[weaponName] or 0) + ammoToAdd; ShowNotification(string.format("~g~Added %d ammo to %s.", ammoToAdd, (Config.WeaponNames[weaponName] or weaponName)))
        else ShowNotification("~y~You don't have the weapon (" .. (Config.WeaponNames[weaponName] or weaponName) .. ") for this ammo.") end
    else ShowNotification("~r~Invalid weapon specified for ammo: " .. tostring(weaponName)) end
end)

RegisterNetEvent('cops_and_robbers:applyArmor')
AddEventHandler('cops_and_robbers:applyArmor', function(armorType)
    local playerPed = PlayerPedId()
    if not (playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed)) then ShowNotification("~r~Cannot apply armor: Player ped invalid."); return end
    local armorValue = 0; local armorConfig = Config.Items[armorType]
    if armorConfig and armorConfig.armorValue then armorValue = armorConfig.armorValue
    else if armorType == "armor" then armorValue = 50 elseif armorType == "heavy_armor" then armorValue = 100 else ShowNotification("Invalid armor type: " .. tostring(armorType)); return end end
    local finalArmor = armorValue
    if playerData and playerData.perks and playerData.perks.increased_armor_durability and playerData.armorModifier and playerData.armorModifier > 1.0 then finalArmor = math.floor(armorValue * playerData.armorModifier); ShowNotification(string.format("~g~Perk Active: Increased Armor Durability! (%.0f -> %.0f)", armorValue, finalArmor)) end
    SetPedArmour(playerPed, finalArmor)
    ShowNotification(string.format("~g~Armor Applied: %s (~w~%d Armor)", (armorConfig and armorConfig.label or armorType), finalArmor))
end)

RegisterNUICallback('selectRole', function(data, cb)
    local selectedRole = data.role
    if selectedRole == 'cop' or selectedRole == 'robber' then TriggerServerEvent('cops_and_robbers:setPlayerRole', selectedRole); cb('ok')
    else ShowNotification("Invalid role selected."); cb('error') end
end)

RegisterNUICallback('getPlayerInventory', function(data, cb)
    if RequestInventoryForNUI then RequestInventoryForNUI(cb)
    else print("Error: RequestInventoryForNUI function not found.", "error"); cb({ error = "Internal error: Inventory system not available." }) end
end)

RegisterNUICallback('setNuiFocus', function(data, cb)
    if type(data) == "table" and data.hasFocus ~= nil and data.hasCursor ~= nil then
        print(string.format("[CNR_CLIENT] Setting NUI focus via NUI callback: hasFocus=%s, hasCursor=%s", tostring(data.hasFocus), tostring(data.hasCursor)))
        SetNuiFocus(data.hasFocus, data.hasCursor)
        cb('ok')
    else
        print(string.format("[CNR_CLIENT_WARN] NUI callback 'setNuiFocus' received invalid data: %s", json.encode and json.encode(data) or tostring(data)))
        cb('error') -- Or cb({status='error', message='Invalid data'})
    end
end)

Citizen.CreateThread(function()
    while not g_isPlayerPedReady do Citizen.Wait(500) end
    print("[CNR_CLIENT] Thread for Spike Strip Deployment & Collision now starting its main loop.")
    local deployStripKey = (Config.Keybinds and Config.Keybinds.deploySpikeStrip) or 19
    local collisionCheckInterval = 250; local lastCollisionCheck = 0
    while true do
        local frameWait = 500
        local playerPed = PlayerPedId()
        if not (playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed)) then Citizen.Wait(1000); goto continue_spike_loop end

        if role == 'cop' then
            frameWait = 100
            if IsControlJustPressed(0, deployStripKey) then
                local forwardVector = GetEntityForwardVector(playerPed)
                local deployCoords = GetOffsetFromEntityInWorldCoords(playerPed, forwardVector.x * 2.5, forwardVector.y * 2.5, -0.95)
                ShowNotification("~b~Attempting to deploy spike strip...")
                TriggerServerEvent('cops_and_robbers:deploySpikeStrip', vector3(deployCoords.x, deployCoords.y, deployCoords.z))
            end
        end
        if #(currentSpikeStrips) > 0 and (GetGameTimer() - lastCollisionCheck > collisionCheckInterval) then
            frameWait = math.min(frameWait, collisionCheckInterval)
            lastCollisionCheck = GetGameTimer()
            local playerVeh = GetVehiclePedIsIn(playerPed, false)
            if playerVeh and playerVeh ~= 0 and DoesEntityExist(playerVeh) then
                local vehCoords = GetEntityCoords(playerVeh)
                for stripId, stripData in pairs(currentSpikeStrips) do
                    if stripData and stripData.obj and DoesEntityExist(stripData.obj) and stripData.location and #(vehCoords - stripData.location) < 3.0 then
                        ShowNotification("~r~You ran over spikes!"); TriggerServerEvent('cops_and_robbers:vehicleHitSpikeStrip', stripId, VehToNet(playerVeh)); break
                    end
                end
            end
        end
        Citizen.Wait(frameWait)
        ::continue_spike_loop::
    end
end)

Citizen.CreateThread(function()
    while not g_isPlayerPedReady do Citizen.Wait(500) end
    print("[CNR_CLIENT] Thread for Speed Radar now starting its main loop.")
    local isRadarActive = false; local radarPosition = nil; local radarHeading = nil; local detectedSpeeders = {}
    local function CalculateRelativeAngle(radarPos, radarHead, targetPos) if not radarPos or not targetPos then return 999 end; local angle = math.atan2(targetPos.y - radarPos.y, targetPos.x - radarPos.x) * (180 / math.pi); local relativeAngle = angle - (radarHead or 0); if relativeAngle < -180 then relativeAngle = relativeAngle + 360 end; if relativeAngle > 180 then relativeAngle = relativeAngle - 360 end; return relativeAngle end
    local function CleanOldDetections(timeoutMs) local currentTime = GetGameTimer(); for key, data in pairs(detectedSpeeders) do if currentTime - (data.timestamp or 0) > timeoutMs then detectedSpeeders[key] = nil end end end
    while true do
        local frameWait = 500
        local playerPed = PlayerPedId()
        if not (playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed)) then Citizen.Wait(1000); goto continue_radar_loop end

        if role == 'cop' then
            local toggleRadarKey = (Config.Keybinds and Config.Keybinds.toggleSpeedRadar) or 17
            local fineSpeederKey = (Config.Keybinds and Config.Keybinds.fineSpeeder) or 74
            local fineSpeederKeyName = (Config.Keybinds and Config.Keybinds.fineSpeederKeyName) or "H"
            if IsControlJustPressed(0, toggleRadarKey) then
                isRadarActive = not isRadarActive
                if isRadarActive then radarPosition = GetEntityCoords(playerPed); radarHeading = GetEntityHeading(playerPed); ShowNotification("~g~Speed radar activated."); detectedSpeeders = {} else ShowNotification("~r~Speed radar deactivated.") end
            end
            if isRadarActive then
                frameWait = 250
                local vehicles = GetGamePool('CVehicle')
                for _, veh in ipairs(vehicles) do
                    if DoesEntityExist(veh) and IsEntityAVehicle(veh) and NetworkGetEntityIsNetworked(veh) then
                        local driver = GetPedInVehicleSeat(veh, -1)
                        if DoesEntityExist(driver) and IsPedAPlayer(driver) and driver ~= playerPed then
                            local targetPlayerNetId = NetworkGetPlayerIndexFromPed(driver); local targetPlayerServerId = GetPlayerServerId(targetPlayerNetId)
                            local detectionKey = tostring(targetPlayerServerId) .. GetVehicleNumberPlateText(veh); local cooldownTime = (Config.SpeedRadarCooldownPerVehicle or 30000)
                            if not (detectedSpeeders[detectionKey] and (GetGameTimer() - (detectedSpeeders[detectionKey].timestamp or 0) < cooldownTime)) then
                                local vehCoords = GetEntityCoords(veh)
                                if radarPosition and #(vehCoords - radarPosition) < (Config.SpeedRadarRange or 50.0) and math.abs(CalculateRelativeAngle(radarPosition, radarHeading, vehCoords)) < (Config.SpeedRadarAngle or 45.0) then
                                    local speedKmh = GetEntitySpeed(veh) * 3.6
                                    if speedKmh > (Config.SpeedLimitKmh or 80.0) then
                                        local vehicleName = GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(veh))); if vehicleName == "NULL" or vehicleName == "" then vehicleName = GetDisplayNameFromVehicleModel(GetEntityModel(veh)) end
                                        ShowNotification(string.format("~y~Speeding: %s (%s) at %.0f km/h. Press %s to fine.", GetPlayerName(targetPlayerNetId), vehicleName, speedKmh, fineSpeederKeyName))
                                        detectedSpeeders[detectionKey] = { playerId = targetPlayerServerId, playerName = GetPlayerName(targetPlayerNetId), vehicleName = vehicleName, speed = speedKmh, timestamp = GetGameTimer() }
                                    end
                                end
                            end
                        end
                    end
                end
                if IsControlJustPressed(0, fineSpeederKey) then
                    local bestTargetKey = nil; local mostRecentTime = 0
                    for key, data in pairs(detectedSpeeders) do if data.timestamp and data.timestamp > mostRecentTime and DoesEntityExist(GetPlayerPed(GetPlayerFromServerId(data.playerId))) then mostRecentTime = data.timestamp; bestTargetKey = key else detectedSpeeders[key] = nil end end
                    if bestTargetKey and detectedSpeeders[bestTargetKey] then local speederData = detectedSpeeders[bestTargetKey]; TriggerServerEvent('cops_and_robbers:vehicleSpeeding', speederData.playerId, speederData.vehicleName, speederData.speed); ShowNotification(string.format("~b~Fine issued to %s for speeding at %.0f km/h.", speederData.playerName, speederData.speed)); detectedSpeeders[bestTargetKey].timestamp = GetGameTimer() - (cooldownTime - (Config.SpeedRadarFineGracePeriodMs or 5000))
                    else ShowNotification("~y~No recent speeder targeted, or target no longer valid.") end
                end
                CleanOldDetections(Config.SpeedRadarCleanupTime or 60000)
            end
        elseif isRadarActive then isRadarActive = false; ShowNotification("~r~Speed radar deactivated due to role change.") end
        Citizen.Wait(frameWait)
        ::continue_radar_loop::
    end
end)

local function openStore(storeName, storeType, vendorItems) TriggerServerEvent('cops_and_robbers:getItemList', storeType, vendorItems, storeName) end

Citizen.CreateThread(function()
    while not g_isPlayerPedReady do Citizen.Wait(500) end
    print("[CNR_CLIENT] Thread for Store/Vendor Interaction now starting its main loop.")
    while true do
        Citizen.Wait(500)
        local playerPed = PlayerPedId()
        if not (playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed)) then goto continue_store_vendor_loop end
        local playerCoords = GetEntityCoords(playerPed)
        for _, store_location in ipairs(Config.AmmuNationStores) do
            if #(playerCoords - store_location) < 2.0 then DisplayHelpText('Press ~INPUT_CONTEXT~ to open Ammu-Nation'); if IsControlJustPressed(0, 51) then openStore('Ammu-Nation', 'AmmuNation', nil) end; goto continue_store_vendor_loop end
        end
        for _, vendor in ipairs(Config.NPCVendors) do
            if #(playerCoords - vendor.location) < 2.0 then DisplayHelpText('Press ~INPUT_CONTEXT~ to talk to ' .. vendor.name); if IsControlJustPressed(0, 51) then openStore(vendor.name, 'Vendor', vendor.items) end; goto continue_store_vendor_loop end
        end
        ::continue_store_vendor_loop::
    end
end)

Citizen.CreateThread(function()
    -- No g_isPlayerPedReady needed here as it doesn't use PlayerPedId()
    print("[CNR_CLIENT] Thread for NPC Vendor Spawn now starting its main loop.")
    for _, vendor in ipairs(Config.NPCVendors) do
        local hash = GetHashKey(vendor.model); RequestModel(hash); while not HasModelLoaded(hash) do Citizen.Wait(100) end
        local npc = CreatePed(4, hash, vendor.location.x, vendor.location.y, vendor.location.z - 1.0, vendor.heading, false, true)
        SetEntityInvincible(npc, true); SetBlockingOfNonTemporaryEvents(npc, true); FreezeEntityPosition(npc, true)
    end
end)

local isSubduing = false; local isBeingSubdued = false
Citizen.CreateThread(function()
    while not g_isPlayerPedReady do Citizen.Wait(500) end
    print("[CNR_CLIENT] Thread for Tackle/Subdue now starting its main loop.")
    while true do
        local frameWait = 500
        local playerPed = PlayerPedId()
        if not (playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed)) then Citizen.Wait(1000); goto continue_subdue_loop end

        if role == 'cop' and not isSubduing then
            frameWait = 0
            if IsControlJustPressed(0, (Config.Keybinds and Config.Keybinds.tackleSubdue) or 47) then
                local playerCoords = GetEntityCoords(playerPed); local closestPlayerId = -1; local closestDistance = -1
                for _, pId in ipairs(GetActivePlayers()) do
                    if pId ~= PlayerId() then local targetPed = GetPlayerPed(pId); if DoesEntityExist(targetPed) then local distance = #(playerCoords - GetEntityCoords(targetPed)); if closestDistance == -1 or distance < closestDistance then closestDistance = distance; closestPlayerId = pId end end end
                end
                if closestPlayerId ~= -1 and closestDistance <= (Config.TackleDistance or 2.0) then
                    local targetServerId = GetPlayerServerId(closestPlayerId)
                    if targetServerId ~= -1 then ShowNotification("~b~Attempting to tackle..."); TriggerServerEvent('cops_and_robbers:startSubdue', targetServerId); isSubduing = true; SetTimeout((Config.SubdueTimeMs or 3000) + 500, function() isSubduing = false end)
                    else ShowNotification("~r~Could not get target server ID.") end
                elseif closestPlayerId ~= -1 then ShowNotification(string.format("~r~Target too far (%.1fm). Required: %.1fm", closestDistance, (Config.TackleDistance or 2.0)))
                else ShowNotification("~y~No player nearby to tackle.") end
            end
        end
        Citizen.Wait(frameWait)
        ::continue_subdue_loop::
    end
end)

RegisterNetEvent('cops_and_robbers:beginSubdueSequence')
AddEventHandler('cops_and_robbers:beginSubdueSequence', function(copServerId)
    isBeingSubdued = true
    local playerPed = PlayerPedId()
    if not (playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed)) then return end
    local copName = GetPlayerName(GetPlayerFromServerId(copServerId)) or "a Cop"
    ShowNotification("~r~You are being tackled by " .. copName .. "!")
    FreezeEntityPosition(playerPed, true)
    SetTimeout(Config.SubdueTimeMs or 3000, function() if isBeingSubdued then isBeingSubdued = false; ShowNotification("~g~Subdue period ended.") end end)
end)

RegisterNetEvent('cops_and_robbers:subdueCancelled')
AddEventHandler('cops_and_robbers:subdueCancelled', function()
    if isBeingSubdued then isBeingSubdued = false; local playerPed = PlayerPedId(); if playerPed and playerPed ~=0 and playerPed ~=-1 and DoesEntityExist(playerPed) then FreezeEntityPosition(playerPed, false) end; ShowNotification("~g~No longer subdued.") end
end)

local k9Ped = nil
Citizen.CreateThread(function()
    while not g_isPlayerPedReady do Citizen.Wait(500) end
    print("[CNR_CLIENT] Thread for K9 Unit now starting its main loop.")
    local k9KeybindWait = 200; local k9FollowTaskWait = 1000; local lastFollowTaskTime = 0
    while true do
        Citizen.Wait(k9KeybindWait)
        local playerPed = PlayerPedId()
        if not (playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed)) then Citizen.Wait(1000); goto continue_k9_loop end

        if playerData.role == 'cop' then
            local toggleK9Key = (Config.Keybinds and Config.Keybinds.toggleK9) or 31
            if IsControlJustPressed(0, toggleK9Key) then
                if k9Ped and DoesEntityExist(k9Ped) then ShowNotification("~y~Dismissing K9..."); TriggerServerEvent('cops_and_robbers:dismissK9')
                else local k9WhistleConfig = Config.Items["k9_whistle"]; if k9WhistleConfig and playerData.level >= (k9WhistleConfig.minLevelCop or 1) then ShowNotification("~b~Using K9 Whistle..."); TriggerServerEvent('cops_and_robbers:spawnK9') else ShowNotification(string.format("~r~K9 Whistle requires Level %d Cop.", (k9WhistleConfig and k9WhistleConfig.minLevelCop or 1))) end end
            end
            local commandK9AttackKey = (Config.Keybinds and Config.Keybinds.commandK9Attack) or 38
            if k9Ped and DoesEntityExist(k9Ped) and IsControlJustPressed(0, commandK9AttackKey) then
                local searchRadius = (Config.K9AttackSearchRadius or 50.0); local closestTargetPed, _ = GetClosestPlayerPed(GetEntityCoords(playerPed), searchRadius, true)
                if closestTargetPed then local targetServerId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(closestTargetPed)); if targetServerId and targetServerId ~= -1 then ShowNotification("~y~K9: Attacking " .. GetPlayerName(NetworkGetPlayerIndexFromPed(closestTargetPed)) .. "!"); TriggerServerEvent('cops_and_robbers:commandK9', targetServerId, "attack"); TriggerServerEvent('cnr:k9EngagedTarget', targetServerId) else ShowNotification("~y~K9: Could not ID target.") end
                else ShowNotification("~y~K9: No target found.") end
            end
        end
        if k9Ped and DoesEntityExist(k9Ped) and IsPedOnFoot(playerPed) and (GetGameTimer() - lastFollowTaskTime) > k9FollowTaskWait then
            if GetActivityLevel(k9Ped) < 2 and #(GetEntityCoords(playerPed) - GetEntityCoords(k9Ped)) > Config.K9FollowDistance + 2.0 then TaskFollowToOffsetOfEntity(k9Ped, playerPed, vector3(0.0, -Config.K9FollowDistance, 0.0), 1.5, -1, Config.K9FollowDistance - 1.0, true) end
            lastFollowTaskTime = GetGameTimer()
        end
        ::continue_k9_loop::
    end
end)

RegisterNetEvent('cops_and_robbers:clientSpawnK9Authorized')
AddEventHandler('cops_and_robbers:clientSpawnK9Authorized', function()
    if k9Ped and DoesEntityExist(k9Ped) then ShowNotification("~y~K9 already active."); return end
    local modelHash = GetHashKey('a_c_shepherd'); RequestModel(modelHash)
    CreateThread(function()
         while not g_isPlayerPedReady do Citizen.Wait(500) end
        local attempts = 0; while not HasModelLoaded(modelHash) and attempts < 100 do Citizen.Wait(100); attempts = attempts + 1 end
        local playerPed = PlayerPedId()
        if not (playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed)) then SetModelAsNoLongerNeeded(modelHash); ShowNotification("~r~Cannot spawn K9: Player ped invalid."); return end

        if HasModelLoaded(modelHash) then
            local coords = GetOffsetFromEntityInWorldCoords(playerPed, 0.0, Config.K9FollowDistance * -1.0, 0.5)
            k9Ped = CreatePed(4, modelHash, coords.x, coords.y, coords.z, GetEntityHeading(playerPed), false, true)
            SetEntityAsMissionEntity(k9Ped, true, true); SetPedAsCop(k9Ped, true); SetPedRelationshipGroupHash(k9Ped, GetPedRelationshipGroupHash(playerPed)); SetBlockingOfNonTemporaryEvents(k9Ped, true)
            TaskFollowToOffsetOfEntity(k9Ped, playerPed, vector3(0.0, -Config.K9FollowDistance, 0.0), 1.5, -1, Config.K9FollowDistance - 1.0, true)
            ShowNotification("~g~K9 unit arrived!")
        else ShowNotification("~r~Failed to spawn K9: Model not found.") end
        SetModelAsNoLongerNeeded(modelHash)
    end)
end)

RegisterNetEvent('cops_and_robbers:clientDismissK9')
AddEventHandler('cops_and_robbers:clientDismissK9', function()
    ShowNotification("~y~K9 unit dismissed.")
    if k9Ped and DoesEntityExist(k9Ped) then DeleteEntity(k9Ped) end; k9Ped = nil
end)

RegisterNetEvent('cops_and_robbers:k9ProcessCommand')
AddEventHandler('cops_and_robbers:k9ProcessCommand', function(targetRobberServerId, commandType)
    if k9Ped and DoesEntityExist(k9Ped) then
        local targetRobberPed = GetPlayerPed(GetPlayerFromServerId(targetRobberServerId))
        if targetRobberPed and DoesEntityExist(targetRobberPed) then
            if commandType == "attack" then ClearPedTasks(k9Ped); TaskCombatPed(k9Ped, targetRobberPed, 0, 16)
            elseif commandType == "follow" then local playerPed = PlayerPedId(); if playerPed and playerPed ~=0 and playerPed ~=-1 and DoesEntityExist(playerPed) then TaskFollowToOffsetOfEntity(k9Ped, playerPed, vector3(0.0, -Config.K9FollowDistance, 0.0), 1.5, -1, Config.K9FollowDistance - 1.0, true) end end
        end
    end
end)

function GetClosestPlayerPed(coords, radius, excludeSelf)
    local closestPed, closestDist = nil, -1; local selfPlayerId = PlayerId()
    for _, pId in ipairs(GetActivePlayers()) do
        if not (excludeSelf and pId == selfPlayerId) then
            local targetPed = GetPlayerPed(pId)
            if DoesEntityExist(targetPed) then local dist = #(coords - GetEntityCoords(targetPed)); if dist < radius and (not closestPed or dist < closestDist) then closestPed = targetPed; closestDist = dist end end
        end
    end; return closestPed, closestDist
end

local currentStoreRobbery = nil
Citizen.CreateThread(function()
    while not g_isPlayerPedReady do Citizen.Wait(500) end
    print("[CNR_CLIENT] Thread for Store Robbery Proximity now starting its main loop.")
    while true do
        Citizen.Wait(1000)
        local playerPed = PlayerPedId()
        if not (playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed)) then goto continue_store_robbery_prox_loop end
        if role == 'robber' then
            local playerCoords = GetEntityCoords(playerPed)
            for i, store_loc in ipairs(Config.RobbableStores) do
                if #(playerCoords - store_loc.location) < store_loc.radius + 5.0 then
                    if #(playerCoords - store_loc.location) < store_loc.radius then
                        DisplayHelpText(string.format("Press ~INPUT_CONTEXT~ to rob %s.", store_loc.name))
                        if IsControlJustPressed(0, 51) then if not currentStoreRobbery then TriggerServerEvent('cops_and_robbers:startStoreRobbery', i) else ShowNotification("~r~Already in a robbery.") end end
                    end; break
                end
            end
        end
        ::continue_store_robbery_prox_loop::
    end
end)

RegisterNetEvent('cops_and_robbers:beginStoreRobberySequence')
AddEventHandler('cops_and_robbers:beginStoreRobberySequence', function(store_data, duration)
    ShowNotification(string.format("~y~Robbing %s! Stay for %ds.", store_data.name, duration / 1000))
    currentStoreRobbery = { store = store_data, duration = duration, startTime = GetGameTimer() }
end)

Citizen.CreateThread(function()
    while not g_isPlayerPedReady do Citizen.Wait(500) end
    print("[CNR_CLIENT] Thread for Store Robbery Monitoring now starting its main loop.")
    while true do
        Citizen.Wait(1000)
        local playerPed = PlayerPedId()
        if not (playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed)) then goto continue_store_robbery_monitor_loop end

        if currentStoreRobbery and role == 'robber' then
            local playerCoords = GetEntityCoords(playerPed)
            local distToStore = #(playerCoords - currentStoreRobbery.store.location)
            local timeElapsed = GetGameTimer() - currentStoreRobbery.startTime
            if distToStore > currentStoreRobbery.store.radius + 2.0 then ShowNotification("~r~Fled store! Robbery failed."); TriggerServerEvent('cops_and_robbers:storeRobberyUpdate', "fled"); currentStoreRobbery = nil
            elseif timeElapsed >= currentStoreRobbery.duration then ShowNotification("~g~Robbery complete. Waiting server."); currentStoreRobbery = nil
            else DisplayHelpText(string.format("Robbing %s... Time left: %ds", currentStoreRobbery.store.name, math.ceil((currentStoreRobbery.duration - timeElapsed) / 1000))) end
        end
        ::continue_store_robbery_monitor_loop::
    end
end)

local armoredCarBlip = nil; local armoredCarNetIdClient = nil; local armoredCarClientData = { lastHealth = 0 }
RegisterNetEvent('cops_and_robbers:armoredCarSpawned')
AddEventHandler('cops_and_robbers:armoredCarSpawned', function(vehicleNetId, initialCoords)
    ShowNotification("~y~An armored car is on the move!"); armoredCarNetIdClient = vehicleNetId
    local vehicle = NetToVeh(vehicleNetId)
    if DoesEntityExist(vehicle) then
        if armoredCarBlip then RemoveBlip(armoredCarBlip) end
        armoredCarBlip = AddBlipForEntity(vehicle); SetBlipSprite(armoredCarBlip, 427); SetBlipColour(armoredCarBlip, 5); SetBlipAsShortRange(armoredCarBlip, false)
        BeginTextCommandSetBlipName("STRING"); AddTextComponentSubstringPlayerName("Armored Car"); EndTextCommandSetBlipName(armoredCarBlip)
        armoredCarClientData.lastHealth = GetEntityHealth(vehicle)
    else print("Armored car entity not found client-side for NetID: " .. vehicleNetId) end
end)

RegisterNetEvent('cops_and_robbers:armoredCarDestroyed')
AddEventHandler('cops_and_robbers:armoredCarDestroyed', function(vehicleNetId)
    ShowNotification("~g~Armored car looted!"); if armoredCarBlip then RemoveBlip(armoredCarBlip); armoredCarBlip = nil end
    armoredCarNetIdClient = nil; armoredCarClientData.lastHealth = 0
end)

Citizen.CreateThread(function()
    while not g_isPlayerPedReady do Citizen.Wait(500) end
    print("[CNR_CLIENT] Thread for Armored Car Damage now starting its main loop.")
    local damageCheckInterval = 1000
    while true do
        Citizen.Wait(damageCheckInterval)
        if role == 'robber' and armoredCarNetIdClient and NetworkDoesNetworkIdExist(armoredCarNetIdClient) then
            local carEntity = NetToVeh(armoredCarNetIdClient)
            if DoesEntityExist(carEntity) then
                local currentHealth = GetEntityHealth(carEntity)
                if armoredCarClientData.lastHealth == 0 then armoredCarClientData.lastHealth = GetMaxHealth(carEntity) end
                if currentHealth < armoredCarClientData.lastHealth then local damageDone = armoredCarClientData.lastHealth - currentHealth; if damageDone > 0 then TriggerServerEvent('cops_and_robbers:damageArmoredCar', armoredCarNetIdClient, damageDone) end end
                armoredCarClientData.lastHealth = currentHealth
            else armoredCarNetIdClient = nil; armoredCarClientData.lastHealth = 0 end
        end
    end
end)

Citizen.CreateThread(function()
    while not g_isPlayerPedReady do Citizen.Wait(500) end
    print("[CNR_CLIENT] Thread for EMP Device now starting its main loop.")
    while true do
        local frameWait = 500
        local playerPed = PlayerPedId()
        if not (playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed)) then Citizen.Wait(1000); goto continue_emp_loop end
        if playerData.role == 'robber' then
            frameWait = 100
            if IsControlJustPressed(0, (Config.Keybinds and Config.Keybinds.activateEMP) or 121) then
                local empDeviceConfig = Config.Items["emp_device"]; if empDeviceConfig and playerData.level >= (empDeviceConfig.minLevelRobber or 1) then ShowNotification("~b~Activating EMP..."); TriggerServerEvent('cops_and_robbers:activateEMP') else ShowNotification(string.format("~r~EMP Device requires Level %d Robber.", (empDeviceConfig and empDeviceConfig.minLevelRobber or 1))) end
            end
        end
        Citizen.Wait(frameWait)
        ::continue_emp_loop::
    end
end)

RegisterNetEvent('cops_and_robbers:vehicleEMPed')
AddEventHandler('cops_and_robbers:vehicleEMPed', function(vehicleNetIdToEMP, durationMs)
    local playerPed = PlayerPedId()
    if not (playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed)) then return end
    local currentVehicle = GetVehiclePedIsIn(playerPed, false)
    local targetVehicle = NetToVeh(vehicleNetIdToEMP)
    if DoesEntityExist(targetVehicle) and currentVehicle == targetVehicle then
        ShowNotification("~r~Vehicle EMPed!"); SetVehicleEngineOn(targetVehicle, false, true, true); SetVehicleUndriveable(targetVehicle, true)
        SetTimeout(durationMs, function() if DoesEntityExist(targetVehicle) then SetVehicleUndriveable(targetVehicle, false); if GetPedInVehicleSeat(targetVehicle, -1) == playerPed then SetVehicleEngineOn(targetVehicle, true, true, false) end; ShowNotification("~g~Vehicle systems recovering.") end end)
    end
end)

local activePowerOutages = {}
Citizen.CreateThread(function()
    while not g_isPlayerPedReady do Citizen.Wait(500) end
    print("[CNR_CLIENT] Thread for Power Grid Sabotage now starting its main loop.")
    while true do
        Citizen.Wait(1000)
        local playerPed = PlayerPedId()
        if not (playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed)) then goto continue_power_grid_loop end
        if playerData.role == 'robber' then
            local playerCoords = GetEntityCoords(playerPed)
            for i, grid in ipairs(Config.PowerGrids) do
                if #(playerCoords - grid.location) < 10.0 then
                    DisplayHelpText(string.format("Press ~INPUT_CONTEXT~ to sabotage %s.", grid.name))
                    if IsControlJustPressed(0, 51) then local sabotageToolConfig = Config.Items["emp_device"]; if sabotageToolConfig and playerData.level >= (sabotageToolConfig.minLevelRobber or 1) then ShowNotification("~b~Attempting sabotage..."); TriggerServerEvent('cops_and_robbers:sabotagePowerGrid', i); TriggerServerEvent('cops_and_robbers:reportCrime', 'power_grid_sabotaged_crime') else ShowNotification(string.format("~r~Sabotage requires Level %d Robber and gear.", (sabotageToolConfig and sabotageToolConfig.minLevelRobber or 1))) end end
                    break
                end
            end
        end
        ::continue_power_grid_loop::
    end
end)

RegisterNetEvent('cops_and_robbers:powerGridStateChanged')
AddEventHandler('cops_and_robbers:powerGridStateChanged', function(gridIndex, isOutage, duration)
    local grid = Config.PowerGrids[gridIndex]; if not grid then return end
    activePowerOutages[gridIndex] = isOutage
    if isOutage then ShowNotification(string.format("~r~Power outage at %s!", grid.name)); SetArtificialLightsState(true); print("Simplified power outage for grid: " .. grid.name)
    else ShowNotification(string.format("~g~Power restored at %s.", grid.name)); local anyOutageActive = false; for _, status in pairs(activePowerOutages) do if status then anyOutageActive = true; break end end; if not anyOutageActive then SetArtificialLightsState(false); print("All power outages resolved.") else print("Power restored for " .. grid.name .. ", but others may be active.") end end
end)

local isAdminPanelOpen = false; local currentBounties = {}; local isBountyBoardOpen = false
Citizen.CreateThread(function()
    -- No g_isPlayerPedReady needed for keybinds themselves, but actions triggered might need it.
    print("[CNR_CLIENT] Thread for Admin/Bounty Keybinds now starting its main loop.")
    while true do
        Citizen.Wait(0)
        local toggleAdminPanelKey = (Config.Keybinds and Config.Keybinds.toggleAdminPanel) or 289
        if IsControlJustPressed(0, toggleAdminPanelKey) then
            if not isAdminPanelOpen then ShowNotification("~b~Requesting Admin Panel..."); TriggerServerEvent('cops_and_robbers:requestAdminDataForUI')
            else SendNUIMessage({ action = 'hideAdminPanel' }); isAdminPanelOpen = false; ShowNotification("~y~Admin Panel closed.") end
        end
        local toggleBountyBoardKey = (Config.Keybinds and Config.Keybinds.toggleBountyBoard) or 168
        if IsControlJustPressed(0, toggleBountyBoardKey) then
            if playerData.role == 'cop' then
                isBountyBoardOpen = not isBountyBoardOpen
                if isBountyBoardOpen then SendNUIMessage({action = "showBountyBoard", bounties = currentBounties, resourceName = GetParentResourceName()}); ShowNotification("~g~Bounty Board opened.")
                else SendNUIMessage({action = "hideBountyBoard"}); ShowNotification("~y~Bounty Board closed.") end
            else ShowNotification("~r~Only Cops can access Bounty Board.") end
        end
    end
end)

RegisterNetEvent('cops_and_robbers:bountyListUpdate')
AddEventHandler('cops_and_robbers:bountyListUpdate', function(bountiesFromServer)
    currentBounties = bountiesFromServer
    if isBountyBoardOpen and playerData.role == 'cop' then SendNUIMessage({action="updateBountyList", bounties=currentBounties}) end
end)

RegisterNUICallback('closeBountyNUI', function(data, cb)
    isBountyBoardOpen = false; ShowNotification("~y~Bounty Board closed by NUI button."); cb('ok')
end)

RegisterNetEvent('cops_and_robbers:showAdminUI')
AddEventHandler('cops_and_robbers:showAdminUI', function(playerList, isAdminFlag)
    if not isAdminFlag then ShowNotification("~r~Admin Panel access denied."); isAdminPanelOpen = false; return end
    if not isAdminPanelOpen then isAdminPanelOpen = true; SendNUIMessage({ action = 'showAdminPanel', players = playerList, resourceName = GetParentResourceName() }); ShowNotification("~g~Admin Panel opened.")
    elseif isAdminPanelOpen and playerList then SendNUIMessage({ action = 'refreshAdminPanelPlayers', players = playerList }); ShowNotification("~b~Admin Panel refreshed.") end
end)

RegisterNetEvent('cops_and_robbers:teleportToPlayerAdminUI')
AddEventHandler('cops_and_robbers:teleportToPlayerAdminUI', function(targetCoordsTable)
    local playerPed = PlayerPedId()
    if not (playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed)) then return end
    local targetCoords = vector3(targetCoordsTable.x, targetCoordsTable.y, targetCoordsTable.z)
    SetEntityCoords(playerPed, targetCoords.x, targetCoords.y, targetCoords.z, false, false, false, true)
    ShowNotification("~b~Teleported by Admin UI.")
end)

Citizen.CreateThread(function()
    while not g_isPlayerPedReady do Citizen.Wait(500) end
    print("[CNR_CLIENT] Thread for Player Position Update now starting its main loop.")
    while true do
        Citizen.Wait(Config.ClientPositionUpdateInterval or 5000)
        local playerPed = PlayerPedId()
        if playerPed and playerPed ~= 0 and playerPed ~= -1 and DoesEntityExist(playerPed) and playerData.role and playerData.role ~= "citizen" then
            TriggerServerEvent('cops_and_robbers:updatePosition', GetEntityCoords(playerPed), currentWantedStarsClient)
        end
    end
end)
