-- character_editor_client.lua
-- Comprehensive Character Editor System for Cops and Robbers
-- Handles all character customization, role-specific uniforms, and character management

local isInCharacterEditor = false
local currentCharacterData = {}
local originalPlayerData = {}
local editorCamera = nil
local currentCameraMode = "face"
local currentRole = nil
local currentCharacterSlot = 1
local playerCharacters = {}
local previewingUniform = false
local currentUniformPreset = nil
local renderThread = false

-- Player data from main client
local playerRole = nil
local playerData = nil

-- Character editor UI state
local editorUI = {
    currentCategory = "appearance",
    currentSubCategory = "face",
    isVisible = false
}

-- Initialize character editor
Citizen.CreateThread(function()
    -- Load player characters on resource start
    TriggerServerEvent('cnr:loadPlayerCharacters')
end)

-- =========================
-- Character Data Management
-- =========================

function GetDefaultCharacterData()
    local defaultData = {}
    
    -- Ensure Config.CharacterEditor exists
    if not Config.CharacterEditor or not Config.CharacterEditor.defaultCharacter then
        print("[CNR_CHARACTER_EDITOR] Warning: Config.CharacterEditor.defaultCharacter not found, using fallback")
        -- Fallback default character data
        return {
            model = "mp_m_freemode_01",
            face = 0,
            skin = 0,
            hair = 0,
            hairColor = 0,
            hairHighlight = 0,
            beard = -1,
            beardColor = 0,
            beardOpacity = 1.0,
            eyebrows = -1,
            eyebrowsColor = 0,
            eyebrowsOpacity = 1.0,
            eyeColor = 0,
            faceFeatures = {
                noseWidth = 0.0,
                noseHeight = 0.0,
                noseLength = 0.0,
                noseBridge = 0.0,
                noseTip = 0.0,
                noseShift = 0.0,
                browHeight = 0.0,
                browWidth = 0.0,
                cheekboneHeight = 0.0,
                cheekboneWidth = 0.0,
                cheeksWidth = 0.0,
                eyesOpening = 0.0,
                lipsThickness = 0.0,
                jawWidth = 0.0,
                jawHeight = 0.0,
                chinLength = 0.0,
                chinPosition = 0.0,
                chinWidth = 0.0,
                chinShape = 0.0,
                neckWidth = 0.0
            },
            components = {},
            props = {},
            tattoos = {}
        }
    end
    
    -- Lua 5.4 compatible deep copy
    for k, v in next, Config.CharacterEditor.defaultCharacter do
        if type(v) == "table" then
            defaultData[k] = {}
            for k2, v2 in next, v do
                defaultData[k][k2] = v2
            end
        else
            defaultData[k] = v
        end
    end
    return defaultData
end

function ApplyCharacterData(characterData, ped)
    if not characterData or not ped or not DoesEntityExist(ped) then
        return false
    end

    -- Set basic appearance
    SetPedHeadBlendData(ped, characterData.face or 0, characterData.face or 0, 0, 
                       characterData.skin or 0, characterData.skin or 0, 0, 
                       0.5, 0.5, 0.0, false)

    -- Set hair
    SetPedComponentVariation(ped, 2, characterData.hair or 0, 0, 0)
    SetPedHairColor(ped, characterData.hairColor or 0, characterData.hairHighlight or 0)

    -- Set facial features
    if characterData.faceFeatures then
        local features = {
            {0, characterData.faceFeatures.noseWidth or 0.0},
            {1, characterData.faceFeatures.noseHeight or 0.0},
            {2, characterData.faceFeatures.noseLength or 0.0},
            {3, characterData.faceFeatures.noseBridge or 0.0},
            {4, characterData.faceFeatures.noseTip or 0.0},
            {5, characterData.faceFeatures.noseShift or 0.0},
            {6, characterData.faceFeatures.browHeight or 0.0},
            {7, characterData.faceFeatures.browWidth or 0.0},
            {8, characterData.faceFeatures.cheekboneHeight or 0.0},
            {9, characterData.faceFeatures.cheekboneWidth or 0.0},
            {10, characterData.faceFeatures.cheeksWidth or 0.0},
            {11, characterData.faceFeatures.eyesOpening or 0.0},
            {12, characterData.faceFeatures.lipsThickness or 0.0},
            {13, characterData.faceFeatures.jawWidth or 0.0},
            {14, characterData.faceFeatures.jawHeight or 0.0},
            {15, characterData.faceFeatures.chinLength or 0.0},
            {16, characterData.faceFeatures.chinPosition or 0.0},
            {17, characterData.faceFeatures.chinWidth or 0.0},
            {18, characterData.faceFeatures.chinShape or 0.0},
            {19, characterData.faceFeatures.neckWidth or 0.0}
        }
        
        for _, feature in ipairs(features) do
            SetPedFaceFeature(ped, feature[1], feature[2])
        end
    end

    -- Set overlays (beard, eyebrows, makeup, etc.)
    local overlays = {
        {1, characterData.beard or -1, characterData.beardOpacity or 1.0, characterData.beardColor or 0, characterData.beardColor or 0},
        {2, characterData.eyebrows or -1, characterData.eyebrowsOpacity or 1.0, characterData.eyebrowsColor or 0, characterData.eyebrowsColor or 0},
        {5, characterData.blush or -1, characterData.blushOpacity or 0.0, characterData.blushColor or 0, characterData.blushColor or 0},
        {8, characterData.lipstick or -1, characterData.lipstickOpacity or 0.0, characterData.lipstickColor or 0, characterData.lipstickColor or 0},
        {4, characterData.makeup or -1, characterData.makeupOpacity or 0.0, characterData.makeupColor or 0, characterData.makeupColor or 0},
        {3, characterData.ageing or -1, characterData.ageingOpacity or 0.0, 0, 0},
        {6, characterData.complexion or -1, characterData.complexionOpacity or 0.0, 0, 0},
        {7, characterData.sundamage or -1, characterData.sundamageOpacity or 0.0, 0, 0},
        {9, characterData.freckles or -1, characterData.frecklesOpacity or 0.0, 0, 0},
        {0, characterData.bodyBlemishes or -1, characterData.bodyBlemishesOpacity or 0.0, 0, 0},
        {10, characterData.chesthair or -1, characterData.chesthairOpacity or 0.0, characterData.chesthairColor or 0, characterData.chesthairColor or 0},
        {11, characterData.addBodyBlemishes or -1, characterData.addBodyBlemishesOpacity or 0.0, 0, 0},
        {12, characterData.moles or -1, characterData.molesOpacity or 0.0, 0, 0}
    }

    for _, overlay in ipairs(overlays) do
        if overlay[2] ~= -1 then
            SetPedHeadOverlay(ped, overlay[1], overlay[2], overlay[3])
            if overlay[4] ~= 0 or overlay[5] ~= 0 then
                SetPedHeadOverlayColor(ped, overlay[1], 1, overlay[4], overlay[5])
            end
        else
            SetPedHeadOverlay(ped, overlay[1], 255, 0.0)
        end
    end

    -- Set eye color
    SetPedEyeColor(ped, characterData.eyeColor or 0)

    -- Apply components (clothing)
    if characterData.components then
        for componentId, component in pairs(characterData.components) do
            SetPedComponentVariation(ped, tonumber(componentId), component.drawable, component.texture, 0)
        end
    end

    -- Apply props (accessories)
    if characterData.props then
        for propId, prop in pairs(characterData.props) do
            if prop.drawable == -1 then
                ClearPedProp(ped, tonumber(propId))
            else
                SetPedPropIndex(ped, tonumber(propId), prop.drawable, prop.texture, true)
            end
        end
    end

    -- Apply tattoos
    if characterData.tattoos then
        ClearPedDecorations(ped)
        for _, tattoo in ipairs(characterData.tattoos) do
            AddPedDecorationFromHashes(ped, GetHashKey(tattoo.collection), GetHashKey(tattoo.name))
        end
    end

    return true
end

function GetCurrentCharacterData(ped)
    if not ped or not DoesEntityExist(ped) then
        return nil
    end

    local characterData = GetDefaultCharacterData()
    
    -- Get basic appearance (this is simplified - in a real implementation you'd need to extract all current values)
    -- For now, we'll use the current character data or defaults
    return currentCharacterData
end

-- =========================
-- Camera Management
-- =========================

function CreateEditorCamera(mode)
    if editorCamera then
        DestroyCam(editorCamera, false)
        editorCamera = nil
    end

    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then
        print("[CNR_CHARACTER_EDITOR] Error: Ped does not exist")
        return
    end
    
    -- Ensure ped is properly visible and lit
    SetEntityVisible(ped, true, false)
    SetEntityAlpha(ped, 255, false)
    SetEntityLights(ped, true)
    SetEntityProofs(ped, false, false, false, false, false, false, false, false)
    
    local coords = GetEntityCoords(ped)
    
    -- Set ped to face north for consistent camera angles
    SetEntityHeading(ped, 0.0)
    
    -- Wait a frame for heading to update
    Wait(50)
    
    -- Get updated coordinates after heading change
    coords = GetEntityCoords(ped)

    editorCamera = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    
    -- Position camera to show character centered in left 40% of screen
    -- Adjust camera position to properly center character in UI viewport
    local screenWidth, screenHeight = GetActiveScreenResolution()
    local aspectRatio = screenWidth / screenHeight
    
    -- Calculate offsets based on screen aspect ratio to center character better
    local baseDistance = 2.5
    local lateralOffset = baseDistance * (aspectRatio / 1.77) -- Adjust for different aspect ratios
    local heightOffset = 0.0
    
    if mode == "face" then
        -- Face view - closer camera with proper centering
        SetCamCoord(editorCamera, coords.x + (lateralOffset * 0.4), coords.y - (baseDistance * 0.6), coords.z + 0.65)
        PointCamAtPedBone(editorCamera, ped, 31086, 0.0, 0.0, 0.0, true) -- Head bone
        SetCamFov(editorCamera, 40.0)
    elseif mode == "body" then
        -- Body view - medium distance with better centering
        SetCamCoord(editorCamera, coords.x + (lateralOffset * 0.6), coords.y - (baseDistance * 0.8), coords.z + 0.3)
        PointCamAtEntity(editorCamera, ped, 0.0, 0.0, 0.2, true)
        SetCamFov(editorCamera, 50.0)
    else -- full body view
        -- Full body - farther camera with complete centering
        SetCamCoord(editorCamera, coords.x + lateralOffset, coords.y - baseDistance, coords.z + 0.0)
        PointCamAtEntity(editorCamera, ped, 0.0, 0.0, -0.1, true)
        SetCamFov(editorCamera, 60.0)
    end

    -- Activate the camera
    SetCamActive(editorCamera, true)
    RenderScriptCams(true, true, 500, true, true)
    
    currentCameraMode = mode
    
    -- Start render thread to constrain view to left side
    if not renderThread then
        renderThread = true
        Citizen.CreateThread(function()
            while renderThread and isInCharacterEditor do
                -- Hide everything except the character in the left portion
                HideHudAndRadarThisFrame()
                Citizen.Wait(0)
            end
        end)
    end
    
    -- Additional lighting and visibility settings (only for the ped)
    -- Don't use SetArtificialLightsState as it affects the entire world
    -- Instead, use ped-specific lighting
    SetEntityLights(ped, true)
    
end

function DestroyCameraEditor()
    if editorCamera then
        RenderScriptCams(false, true, 1000, true, true)
        DestroyCam(editorCamera, false)
        editorCamera = nil
    end
    
    -- Stop render thread
    renderThread = false
    
    -- Restore normal lighting
    local ped = PlayerPedId()
    if DoesEntityExist(ped) then
        SetEntityLights(ped, false)
    end
    
    -- Restore HUD and UI elements
    DisplayHud(true)
    DisplayRadar(true)
    
    -- Ensure artificial lights are restored to normal state
    SetArtificialLightsState(false)
end

-- =========================
-- Character Editor Core Functions
-- =========================

function OpenCharacterEditor(role, characterSlot)
    if isInCharacterEditor then
        return
    end

    currentRole = role or "cop"
    currentCharacterSlot = characterSlot or 1
    
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then
        ShowNotification("~r~Error: Player ped not found")
        return
    end
    
    -- Store original player data
    originalPlayerData = GetCurrentCharacterData(ped)
    
    -- Load character data for the slot
    local characterKey = currentRole .. "_" .. currentCharacterSlot
    if playerCharacters[characterKey] then
        currentCharacterData = playerCharacters[characterKey]
    else
        currentCharacterData = GetDefaultCharacterData()
        -- Set appropriate model based on current ped
        local currentModel = GetEntityModel(ped)
        if currentModel == GetHashKey("mp_f_freemode_01") then
            currentCharacterData.model = "mp_f_freemode_01"
        else
            currentCharacterData.model = "mp_m_freemode_01"
        end
    end
    
    -- Ensure the correct model is loaded first
    local modelToUse = currentCharacterData.model or "mp_m_freemode_01"
    local modelHash = GetHashKey(modelToUse)
    
    RequestModel(modelHash)
    local attempts = 0
    while not HasModelLoaded(modelHash) and attempts < 100 do
        Citizen.Wait(50)
        attempts = attempts + 1
    end
    
    if HasModelLoaded(modelHash) then
        SetPlayerModel(PlayerId(), modelHash)
        Citizen.Wait(100)
        ped = PlayerPedId() -- Get the new ped after model change
    end

    -- Use a safe outdoor location for character preview
    -- Position character in an isolated area for better camera control
    local previewLocation = vector3(-1042.0, -2745.0, 21.36) -- Isolated location at airport
    SetEntityCoords(ped, previewLocation.x, previewLocation.y, previewLocation.z, false, false, false, true)
    SetEntityHeading(ped, 180.0) -- Face south for better lighting
    
    -- Ensure the teleport completed
    Wait(200)
    
    -- Disable HUD and UI elements to create clean preview
    DisplayHud(false)
    DisplayRadar(false)
    
    -- Wait for teleport to complete
    Wait(100)
    
    -- Apply current character data after model and position are set
    ApplyCharacterData(currentCharacterData, ped)
    
    -- Freeze player and make invincible
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    
    -- Set up camera after a small delay
    Citizen.SetTimeout(200, function()
        CreateEditorCamera("face")
    end)
    
    -- Set editor state
    isInCharacterEditor = true
    editorUI.isVisible = true
    
    -- Send data to NUI with comprehensive error handling
    local success, errorMsg = pcall(function()
        SendNUIMessage({
            action = 'openCharacterEditor',
            role = currentRole,
            characterSlot = currentCharacterSlot,
            characterData = currentCharacterData,
            uniformPresets = (Config.CharacterEditor and Config.CharacterEditor.uniformPresets and Config.CharacterEditor.uniformPresets[currentRole]) or {},
            customizationRanges = (Config.CharacterEditor and Config.CharacterEditor.customization) or {},
            playerCharacters = playerCharacters
        })
    end)
    
    if not success then
        print("[CNR_CHARACTER_EDITOR] Error sending NUI message: " .. tostring(errorMsg))
        CloseCharacterEditor(false)
        return
    end
    
    -- Enable NUI focus after a short delay
    Citizen.SetTimeout(100, function()
        if isInCharacterEditor then
            SetNuiFocus(true, true)
        end
    end)
    
end

function CloseCharacterEditor(save)
    if not isInCharacterEditor then
        return
    end

    local ped = PlayerPedId()
    
    -- Always disable NUI focus first to prevent getting stuck
    SetNuiFocus(false, false)
    
    if save then
        -- Save current character data
        local characterKey = string.format("%s_%d", currentRole, currentCharacterSlot)
        
        -- Ensure we have valid character data to save
        if currentCharacterData and type(currentCharacterData) == "table" then
            -- Deep copy the character data to prevent reference issues
            local dataToSave = {}
            for k, v in next, currentCharacterData do
                if type(v) == "table" then
                    dataToSave[k] = {}
                    for k2, v2 in next, v do
                        dataToSave[k][k2] = v2
                    end
                else
                    dataToSave[k] = v
                end
            end
            
            -- Ensure all required fields are present with defaults
            local requiredDefaults = {
                model = "mp_m_freemode_01",
                face = 0,
                skin = 0,
                hair = 0,
                hairColor = 0,
                hairHighlight = 0,
                eyeColor = 0,
                beard = 0,
                beardColor = 0,
                eyebrows = 0,
                eyebrowsColor = 0,
                makeup = 0,
                lipstick = 0,
                blemishes = 0,
                ageing = 0,
                complexion = 0,
                sunDamage = 0,
                freckles = 0,
                chestHair = 0,
                chestHairColor = 0
            }
            
            -- Fill in missing required fields
            for field, defaultValue in next, requiredDefaults do
                if dataToSave[field] == nil then
                    dataToSave[field] = defaultValue
                end
            end
            
            -- Ensure faceFeatures table exists
            if not dataToSave.faceFeatures then
                dataToSave.faceFeatures = {}
            end
            
            playerCharacters[characterKey] = dataToSave
            TriggerServerEvent('cnr:saveCharacterData', characterKey, dataToSave)
            ShowNotification(string.format("~b~Saving character to %s slot %d...", currentRole, currentCharacterSlot))
        else
            ShowNotification("~r~Error: No character data to save")
            print("[CNR_CHARACTER_EDITOR] Error: currentCharacterData is invalid")
        end
    else
        -- Restore original appearance
        if originalPlayerData then
            ApplyCharacterData(originalPlayerData, ped)
        end
        ShowNotification("~y~Character editor closed without saving")
    end
    
    -- Cleanup camera
    DestroyCameraEditor()
    
    -- Unfreeze player and remove invincibility
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    
    -- Ensure player is visible
    SetEntityVisible(ped, true, false)
    SetEntityAlpha(ped, 255, false)
    
    -- Return to spawn location
    if currentRole and Config.SpawnPoints and Config.SpawnPoints[currentRole] then
        local spawnPoint = Config.SpawnPoints[currentRole]
        SetEntityCoords(ped, spawnPoint.x, spawnPoint.y, spawnPoint.z, false, false, false, true)
        SetEntityHeading(ped, 0.0)
    end
    
    -- Reset editor state
    isInCharacterEditor = false
    editorUI.isVisible = false
    previewingUniform = false
    currentUniformPreset = nil
    currentRole = nil
    currentCharacterSlot = 1
    
    -- Send close message to NUI
    pcall(function()
        SendNUIMessage({
            action = 'closeCharacterEditor'
        })
    end)
    
end

function UpdateCharacterFeature(category, feature, value)
    if not isInCharacterEditor then
        return
    end

    local ped = PlayerPedId()
    
    -- Ensure currentCharacterData exists
    if not currentCharacterData then
        currentCharacterData = GetDefaultCharacterData()
    end
    
    if category == "faceFeatures" then
        if not currentCharacterData.faceFeatures then
            currentCharacterData.faceFeatures = {}
        end
        currentCharacterData.faceFeatures[feature] = value
        
        -- Apply face feature immediately
        local featureMap = {
            noseWidth = 0, noseHeight = 1, noseLength = 2, noseBridge = 3, noseTip = 4, noseShift = 5,
            browHeight = 6, browWidth = 7, cheekboneHeight = 8, cheekboneWidth = 9, cheeksWidth = 10,
            eyesOpening = 11, lipsThickness = 12, jawWidth = 13, jawHeight = 14, chinLength = 15,
            chinPosition = 16, chinWidth = 17, chinShape = 18, neckWidth = 19
        }
        
        if featureMap[feature] then
            SetPedFaceFeature(ped, featureMap[feature], value)
        end
    else
        currentCharacterData[feature] = value
        
        -- Apply specific changes immediately
        if feature == "hair" then
            SetPedComponentVariation(ped, 2, value, 0, 0)
        elseif feature == "hairColor" then
            SetPedHairColor(ped, value, currentCharacterData.hairHighlight or 0)
        elseif feature == "hairHighlight" then
            SetPedHairColor(ped, currentCharacterData.hairColor or 0, value)
        elseif feature == "eyeColor" then
            SetPedEyeColor(ped, value)
        else
            -- For overlays and other complex features, reapply all character data
            ApplyCharacterData(currentCharacterData, ped)
        end
    end
    
end

function PreviewUniformPreset(presetIndex)
    if not isInCharacterEditor or not currentRole then
        return
    end

    local presets = Config.CharacterEditor.uniformPresets[currentRole]
    if not presets or not presets[presetIndex] then
        return
    end

    local preset = presets[presetIndex]
    local ped = PlayerPedId()
    
    -- Store current clothing if not already previewing
    if not previewingUniform then
        currentCharacterData.originalComponents = {}
        currentCharacterData.originalProps = {}
        
        for i = 0, 11 do
            currentCharacterData.originalComponents[i] = {
                drawable = GetPedDrawableVariation(ped, i),
                texture = GetPedTextureVariation(ped, i)
            }
        end
        
        for i = 0, 7 do
            if GetPedPropIndex(ped, i) ~= -1 then
                currentCharacterData.originalProps[i] = {
                    drawable = GetPedPropIndex(ped, i),
                    texture = GetPedPropTextureIndex(ped, i)
                }
            else
                currentCharacterData.originalProps[i] = { drawable = -1, texture = 0 }
            end
        end
    end
    
    -- Apply preset components
    if preset.components then
        for componentId, component in pairs(preset.components) do
            SetPedComponentVariation(ped, tonumber(componentId), component.drawable, component.texture, 0)
        end
    end
    
    -- Apply preset props
    if preset.props then
        for propId, prop in pairs(preset.props) do
            if prop.drawable == -1 then
                ClearPedProp(ped, tonumber(propId))
            else
                SetPedPropIndex(ped, tonumber(propId), prop.drawable, prop.texture, true)
            end
        end
    end
    
    previewingUniform = true
    currentUniformPreset = presetIndex
    
    ShowNotification("Previewing: " .. preset.name)
end

function ApplyUniformPreset(presetIndex)
    if not isInCharacterEditor or not currentRole then
        return
    end

    local presets = Config.CharacterEditor.uniformPresets[currentRole]
    if not presets or not presets[presetIndex] then
        return
    end

    local preset = presets[presetIndex]
    
    -- Save preset to character data
    currentCharacterData.components = {}
    currentCharacterData.props = {}
    
    if preset.components then
        for componentId, component in pairs(preset.components) do
            currentCharacterData.components[componentId] = {
                drawable = component.drawable,
                texture = component.texture
            }
        end
    end
    
    if preset.props then
        for propId, prop in pairs(preset.props) do
            currentCharacterData.props[propId] = {
                drawable = prop.drawable,
                texture = prop.texture
            }
        end
    end
    
    previewingUniform = false
    currentUniformPreset = nil
    
    ShowNotification("Applied uniform: " .. preset.name)
end

function CancelUniformPreview()
    if not previewingUniform or not isInCharacterEditor then
        return
    end

    local ped = PlayerPedId()
    
    -- Restore original clothing
    if currentCharacterData.originalComponents then
        for componentId, component in pairs(currentCharacterData.originalComponents) do
            SetPedComponentVariation(ped, tonumber(componentId), component.drawable, component.texture, 0)
        end
    end
    
    if currentCharacterData.originalProps then
        for propId, prop in pairs(currentCharacterData.originalProps) do
            if prop.drawable == -1 then
                ClearPedProp(ped, tonumber(propId))
            else
                SetPedPropIndex(ped, tonumber(propId), prop.drawable, prop.texture, true)
            end
        end
    end
    
    previewingUniform = false
    currentUniformPreset = nil
    
    ShowNotification("Uniform preview cancelled")
end

-- =========================
-- Event Handlers
-- =========================

RegisterNetEvent('cnr:openCharacterEditor')
AddEventHandler('cnr:openCharacterEditor', function(role, characterSlot)
    OpenCharacterEditor(role, characterSlot)
end)

RegisterNetEvent('cnr:loadedPlayerCharacters')
AddEventHandler('cnr:loadedPlayerCharacters', function(characters)
    playerCharacters = characters or {}
end)

RegisterNetEvent('cnr:applyCharacterData')
AddEventHandler('cnr:applyCharacterData', function(characterData)
    local ped = PlayerPedId()
    ApplyCharacterData(characterData, ped)
end)

-- Listen for player data updates from main client
RegisterNetEvent('cnr:updatePlayerData')
AddEventHandler('cnr:updatePlayerData', function(newPlayerData)
    if newPlayerData then
        playerData = newPlayerData
        playerRole = newPlayerData.role
    end
end)

-- =========================
-- NUI Callbacks
-- =========================

RegisterNUICallback('characterEditor_updateFeature', function(data, cb)
    if data.category and data.feature and data.value ~= nil then
        UpdateCharacterFeature(data.category, data.feature, data.value)
    end
    cb({success = true})
end)

-- Handle gender/model changes
RegisterNUICallback('characterEditor_switchGender', function(data, cb)
    if not isInCharacterEditor then
        cb({success = false})
        return
    end
    
    local ped = PlayerPedId()
    local gender = data.gender
    local newModel
    
    if gender == "male" then
        newModel = "mp_m_freemode_01"
    elseif gender == "female" then
        newModel = "mp_f_freemode_01"
    else
        cb({success = false, error = "Invalid gender"})
        return
    end
    
    -- Update character data
    currentCharacterData.model = newModel
    
    -- Apply the new model
    local modelHash = GetHashKey(newModel)
    RequestModel(modelHash)
    
    local timeout = 0
    while not HasModelLoaded(modelHash) and timeout < 5000 do
        Wait(100)
        timeout = timeout + 100
    end
    
    if HasModelLoaded(modelHash) then
        SetPlayerModel(PlayerId(), modelHash)
        Wait(100) -- Wait for model to fully load
        
        -- Get the new ped and apply character data
        ped = PlayerPedId()
        ApplyCharacterData(currentCharacterData, ped)
        
        -- Recreate camera for new ped
        CreateEditorCamera(currentCameraMode or "face")
        
        cb({success = true})
    else
        print("[CNR_CHARACTER_EDITOR] Failed to load model: " .. newModel)
        cb({success = false})
    end
end)

RegisterNUICallback('characterEditor_previewUniform', function(data, cb)
    if data.presetIndex then
        -- Convert from 0-based JavaScript index to 1-based Lua index
        local luaIndex = data.presetIndex + 1
        PreviewUniformPreset(luaIndex)
    end
    cb({success = true})
end)

RegisterNUICallback('characterEditor_applyUniform', function(data, cb)
    if data.presetIndex then
        -- Convert from 0-based JavaScript index to 1-based Lua index
        local luaIndex = data.presetIndex + 1
        ApplyUniformPreset(luaIndex)
    end
    cb({success = true})
end)

RegisterNUICallback('characterEditor_cancelUniformPreview', function(data, cb)
    CancelUniformPreview()
    cb({success = true})
end)

RegisterNUICallback('characterEditor_changeCamera', function(data, cb)
    if data.mode then
        CreateEditorCamera(data.mode)
    end
    cb({success = true})
end)

RegisterNUICallback('characterEditor_rotateCharacter', function(data, cb)
    if data.direction then
        local ped = PlayerPedId()
        local currentHeading = GetEntityHeading(ped)
        local newHeading = currentHeading + (data.direction == "left" and -15 or 15)
        SetEntityHeading(ped, newHeading)
    end
    cb({success = true})
end)

RegisterNUICallback('characterEditor_switchGender', function(data, cb)
    if data.gender then
        local ped = PlayerPedId()
        local newModel = data.gender == "male" and "mp_m_freemode_01" or "mp_f_freemode_01"
        
        currentCharacterData.model = newModel
        
        -- Change player model
        RequestModel(GetHashKey(newModel))
        while not HasModelLoaded(GetHashKey(newModel)) do
            Citizen.Wait(0)
        end
        
        SetPlayerModel(PlayerId(), GetHashKey(newModel))
        SetModelAsNoLongerNeeded(GetHashKey(newModel))
        
        -- Reapply character data to new model
        Citizen.Wait(100)
        local newPed = PlayerPedId()
        ApplyCharacterData(currentCharacterData, newPed)
        
        -- Update camera
        CreateEditorCamera(currentCameraMode)
    end
    cb({success = true})
end)

RegisterNUICallback('characterEditor_save', function(data, cb)
    CloseCharacterEditor(true)
    cb({success = true})
end)

RegisterNUICallback('characterEditor_cancel', function(data, cb)
    CloseCharacterEditor(false)
    cb({success = true})
end)

-- Handle character editor opened confirmation
RegisterNUICallback('characterEditor_opened', function(data, cb)
    cb({success = true})
end)

-- Handle character editor errors
RegisterNUICallback('characterEditor_error', function(data, cb)
    local errorMsg = data.error or "unknown"
    print(string.format("[CNR_CHARACTER_EDITOR] NUI reported error: %s", errorMsg))
    ShowNotification(string.format("~r~Character Editor Error: %s", errorMsg))
    CloseCharacterEditor(false)
    cb({success = true})
end)

-- Handle character editor closed confirmation
RegisterNUICallback('characterEditor_closed', function(data, cb)
    cb({success = true})
end)

-- Handle character save result from server
RegisterNetEvent('cnr:characterSaveResult')
AddEventHandler('cnr:characterSaveResult', function(success, message)
    if success then
        ShowNotification(string.format("~g~%s", message))
        
        -- Reload character data to update UI
        TriggerServerEvent('cnr:loadPlayerCharacters')
    else
        ShowNotification(string.format("~r~Save failed: %s", message))
    end
end)

-- Handle test result
RegisterNUICallback('characterEditor_test_result', function(data, cb)
    if data.elementFound then
        ShowNotification("~g~Character editor element found in UI")
    else
        ShowNotification("~r~Character editor element missing from UI")
    end
    cb({success = true})
end)

RegisterNUICallback('characterEditor_loadCharacter', function(data, cb)
    if data.characterKey and playerCharacters[data.characterKey] then
        currentCharacterData = playerCharacters[data.characterKey]
        local ped = PlayerPedId()
        ApplyCharacterData(currentCharacterData, ped)
        ShowNotification("Character loaded")
    end
    cb({success = true})
end)

RegisterNUICallback('characterEditor_deleteCharacter', function(data, cb)
    if data.characterKey then
        playerCharacters[data.characterKey] = nil
        TriggerServerEvent('cnr:deleteCharacterData', data.characterKey)
        ShowNotification("Character deleted")
    end
    cb({success = true})
end)

RegisterNUICallback('openCharacterEditor', function(data, cb)
    if data.role and (data.role == "cop" or data.role == "robber") then
        OpenCharacterEditor(data.role, data.characterSlot or 1)
        cb({success = true})
    else
        cb({success = false, error = "Invalid role specified"})
    end
end)

-- =========================
-- Keybind Handler
-- =========================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        
        if IsControlJustPressed(0, Config.Keybinds.openCharacterEditor) then
            if not isInCharacterEditor and role and (role == "cop" or role == "robber") then
                OpenCharacterEditor(role, 1)
            end
        end
        
        -- ESC key to close character editor
        if isInCharacterEditor and IsControlJustPressed(0, 322) then -- ESC key
            CloseCharacterEditor(false)
        end
    end
end)

-- =========================
-- Utility Functions
-- =========================

function ShowNotification(text)
    SetNotificationTextEntry("STRING")
    AddTextComponentString(text)
    DrawNotification(false, false)
end

-- Export functions for other scripts
exports('OpenCharacterEditor', OpenCharacterEditor)
exports('ApplyCharacterData', ApplyCharacterData)
exports('GetCurrentCharacterData', GetCurrentCharacterData)

-- Test command for character editor
RegisterCommand('chareditor', function(source, args, rawCommand)
    local role = args[1] or "cop"
    local slot = tonumber(args[2]) or 1
    
    if role ~= "cop" and role ~= "robber" then
        ShowNotification("~r~Invalid role. Use 'cop' or 'robber'")
        return
    end
    
    if slot < 1 or slot > 2 then
        ShowNotification("~r~Invalid slot. Use 1 or 2")
        return
    end
    
    OpenCharacterEditor(role, slot)
end, false)

TriggerEvent('chat:addSuggestion', '/chareditor', 'Open character editor', {
    { name="role", help="Role (cop/robber)" },
    { name="slot", help="Character slot (1-2)" }
})

-- Emergency command to force close character editor
RegisterCommand('closechareditor', function(source, args, rawCommand)
    
    -- Force disable NUI focus regardless of state
    SetNuiFocus(false, false)
    
    -- Force close camera
    if editorCamera then
        DestroyCam(editorCamera, false)
        editorCamera = nil
    end
    RenderScriptCams(false, true, 1000, true, true)
    
    -- Unfreeze player
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    SetEntityVisible(ped, true, false)
    SetEntityAlpha(ped, 255, false)
    
    -- Reset all editor states
    isInCharacterEditor = false
    editorUI.isVisible = false
    previewingUniform = false
    currentUniformPreset = nil
    currentRole = nil
    currentCharacterSlot = 1
    
    -- Send close message to NUI
    pcall(function()
        SendNUIMessage({
            action = 'closeCharacterEditor'
        })
    end)
    
    ShowNotification("~y~Character editor emergency closed - you should now be able to move")
end, false)

TriggerEvent('chat:addSuggestion', '/closechareditor', 'Emergency close character editor if stuck')

-- Additional emergency command with shorter name
RegisterCommand('fixui', function(source, args, rawCommand)
    
    -- Force disable NUI focus
    SetNuiFocus(false, false)
    
    -- Close any open cameras
    if editorCamera then
        DestroyCam(editorCamera, false)
        editorCamera = nil
    end
    RenderScriptCams(false, true, 1000, true, true)
    
    -- Unfreeze player
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    
    -- Reset editor state
    isInCharacterEditor = false
    editorUI.isVisible = false
    
    ShowNotification("~g~UI fixed - NUI focus disabled")
end, false)

TriggerEvent('chat:addSuggestion', '/fixui', 'Fix stuck UI/mouse cursor')

-- Debug command to test character editor UI
RegisterCommand('testchareditor', function(source, args, rawCommand)
    
    -- Send a test message to check if NUI is responsive
    SendNUIMessage({
        action = 'testCharacterEditor'
    })
    
    ShowNotification("~b~Testing character editor UI - check console")
end, false)

TriggerEvent('chat:addSuggestion', '/testchareditor', 'Test character editor UI elements')

-- =========================
-- Keybind Handler
-- =========================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        
        if IsControlJustPressed(0, Config.Keybinds.openCharacterEditor) then
            -- Use the stored player role
            if not isInCharacterEditor and playerRole and (playerRole == "cop" or playerRole == "robber") then
                OpenCharacterEditor(playerRole, 1)
            elseif not isInCharacterEditor then
                -- Show notification if player doesn't have a valid role
                ShowNotification("~r~You must be a Cop or Robber to use the Character Editor")
            end
        end
        
        -- Character editor exit mechanisms
        if isInCharacterEditor then
            -- ESC key to close character editor (normal close)
            if IsControlJustPressed(0, 322) then -- ESC key
                CloseCharacterEditor(false)
            end
            
            -- Safety Close: Ctrl + F3 (emergency exit)
            if IsControlPressed(0, 36) and IsControlJustPressed(0, Config.Keybinds.openCharacterEditor) then -- CTRL + F3
                CloseCharacterEditor(false)
                ShowNotification("~y~Character editor safety closed")
            end
            
            -- Camera switching with arrow keys
            if IsControlJustPressed(0, 174) then -- LEFT ARROW - Face view
                CreateEditorCamera("face")
                ShowNotification("~b~Face View")
            elseif IsControlJustPressed(0, 175) then -- RIGHT ARROW - Body view
                CreateEditorCamera("body")
                ShowNotification("~b~Body View")
            elseif IsControlJustPressed(0, 172) then -- UP ARROW - Full view
                CreateEditorCamera("full")
                ShowNotification("~b~Full Body View")
            end
            
            -- BACKSPACE key emergency exit (kept for compatibility)
            if IsControlJustPressed(0, 194) then -- BACKSPACE key
                CloseCharacterEditor(false)
            end
        end
    end
end)