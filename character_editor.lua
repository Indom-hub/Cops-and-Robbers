-- character_editor.lua
-- Consolidated character editor system (server and client)
-- Version: 1.2.0
-- Consolidated from: character_editor_server.lua, character_editor_client.lua

if IsDuplicityVersion() then
    -- ====================================================================
    -- SERVER-SIDE CHARACTER EDITOR
    -- ====================================================================
    
    -- Character data storage
    local characterData = {}
    local characterSlots = {}
    
    --- Save character data for player
    --- @param playerId number Player ID
    --- @param slotId number Character slot ID
    --- @param data table Character data
    function SaveCharacterData(playerId, slotId, data)
        if not characterData[playerId] then
            characterData[playerId] = {}
        end
        
        characterData[playerId][slotId] = data
        
        -- Save to file system
        if DataManager then
            DataManager.MarkPlayerForSave(playerId)
        end
        
        print(string.format("[CNR_CHARACTER_EDITOR] Saved character slot %d for player %d", slotId, playerId))
    end
    
    --- Load character data for player
    --- @param playerId number Player ID
    --- @param slotId number Character slot ID
    --- @return table Character data
    function LoadCharacterData(playerId, slotId)
        if not characterData[playerId] then
            return nil
        end
        
        return characterData[playerId][slotId]
    end
    
    --- Get all character slots for player
    --- @param playerId number Player ID
    --- @return table All character slots
    function GetPlayerCharacterSlots(playerId)
        return characterData[playerId] or {}
    end
    
    -- ====================================================================
    -- SERVER EVENT HANDLERS
    -- ====================================================================
    
    RegisterNetEvent('cnr:saveCharacter')
    AddEventHandler('cnr:saveCharacter', function(slotId, characterData)
        local source = source
        
        -- Validate player
        if not Validation or not Validation.ValidatePlayer(source) then
            return
        end
        
        -- Validate slot ID
        if not slotId or type(slotId) ~= "number" or slotId < 1 or slotId > 5 then
            return
        end
        
        -- Validate character data
        if not characterData or type(characterData) ~= "table" then
            return
        end
        
        SaveCharacterData(source, slotId, characterData)
        TriggerClientEvent('cnr:characterSaved', source, slotId)
    end)
    
    RegisterNetEvent('cnr:loadCharacter')
    AddEventHandler('cnr:loadCharacter', function(slotId)
        local source = source
        
        -- Validate player
        if not Validation or not Validation.ValidatePlayer(source) then
            return
        end
        
        -- Validate slot ID
        if not slotId or type(slotId) ~= "number" or slotId < 1 or slotId > 5 then
            return
        end
        
        local data = LoadCharacterData(source, slotId)
        TriggerClientEvent('cnr:characterLoaded', source, slotId, data)
    end)
    
    RegisterNetEvent('cnr:getCharacterSlots')
    AddEventHandler('cnr:getCharacterSlots', function()
        local source = source
        
        -- Validate player
        if not Validation or not Validation.ValidatePlayer(source) then
            return
        end
        
        local slots = GetPlayerCharacterSlots(source)
        TriggerClientEvent('cnr:receiveCharacterSlots', source, slots)
    end)
    
    RegisterNetEvent('cnr:applyCharacter')
    AddEventHandler('cnr:applyCharacter', function(slotId)
        local source = source
        
        -- Validate player
        if not Validation or not Validation.ValidatePlayer(source) then
            return
        end
        
        local data = LoadCharacterData(source, slotId)
        if data then
            TriggerClientEvent('cnr:applyCharacterData', source, data)
        end
    end)
    
else
    -- ====================================================================
    -- CLIENT-SIDE CHARACTER EDITOR
    -- ====================================================================
    
    -- Character editor state
    local characterEditorOpen = false
    local currentCharacterData = {}
    local characterSlots = {}
    local selectedSlot = 1
    
    -- ====================================================================
    -- CLIENT CHARACTER FUNCTIONS
    -- ====================================================================
    
    --- Open character editor
    function OpenCharacterEditor()
        if characterEditorOpen then return end
        
        characterEditorOpen = true
        SetNuiFocus(true, true)
        
        -- Request character slots from server
        TriggerServerEvent('cnr:getCharacterSlots')
        
        SendNUIMessage({
            type = "showCharacterEditor",
            slots = characterSlots,
            selectedSlot = selectedSlot
        })
    end
    
    --- Close character editor
    function CloseCharacterEditor()
        if not characterEditorOpen then return end
        
        characterEditorOpen = false
        SetNuiFocus(false, false)
        
        SendNUIMessage({
            type = "hideCharacterEditor"
        })
    end
    
    --- Apply character appearance
    --- @param data table Character data
    function ApplyCharacterAppearance(data)
        if not data then return end
        
        local playerPed = PlayerPedId()
        
        -- Apply basic appearance
        if data.model then
            local modelHash = GetHashKey(data.model)
            RequestModel(modelHash)
            while not HasModelLoaded(modelHash) do
                Citizen.Wait(0)
            end
            SetPlayerModel(PlayerId(), modelHash)
            SetModelAsNoLongerNeeded(modelHash)
            playerPed = PlayerPedId()
        end
        
        -- Apply face features
        if data.faceFeatures then
            for i, value in pairs(data.faceFeatures) do
                SetPedFaceFeature(playerPed, i, value)
            end
        end
        
        -- Apply head overlays
        if data.headOverlays then
            for i, overlay in pairs(data.headOverlays) do
                SetPedHeadOverlay(playerPed, i, overlay.index, overlay.opacity)
                if overlay.color then
                    SetPedHeadOverlayColor(playerPed, i, overlay.colorType, overlay.color, overlay.secondColor or 0)
                end
            end
        end
        
        -- Apply hair
        if data.hair then
            SetPedComponentVariation(playerPed, 2, data.hair.style, data.hair.texture, 0)
            SetPedHairColor(playerPed, data.hair.color, data.hair.highlight)
        end
        
        -- Apply clothing
        if data.clothing then
            for component, item in pairs(data.clothing) do
                SetPedComponentVariation(playerPed, component, item.drawable, item.texture, 0)
            end
        end
        
        -- Apply accessories
        if data.accessories then
            for prop, item in pairs(data.accessories) do
                if item.drawable >= 0 then
                    SetPedPropIndex(playerPed, prop, item.drawable, item.texture, true)
                else
                    ClearPedProp(playerPed, prop)
                end
            end
        end
    end
    
    --- Get current character appearance
    --- @return table Current character data
    function GetCurrentCharacterAppearance()
        local playerPed = PlayerPedId()
        local data = {}
        
        -- Get model
        data.model = GetEntityModel(playerPed)
        
        -- Get face features
        data.faceFeatures = {}
        for i = 0, 19 do
            data.faceFeatures[i] = GetPedFaceFeature(playerPed, i)
        end
        
        -- Get head overlays
        data.headOverlays = {}
        for i = 0, 12 do
            local index, opacity = GetPedHeadOverlay(playerPed, i)
            data.headOverlays[i] = {
                index = index,
                opacity = opacity
            }
        end
        
        -- Get hair
        data.hair = {
            style = GetPedDrawableVariation(playerPed, 2),
            texture = GetPedTextureVariation(playerPed, 2),
            color = GetPedHairColor(playerPed),
            highlight = GetPedHairHighlightColor(playerPed)
        }
        
        -- Get clothing
        data.clothing = {}
        for i = 0, 11 do
            data.clothing[i] = {
                drawable = GetPedDrawableVariation(playerPed, i),
                texture = GetPedTextureVariation(playerPed, i)
            }
        end
        
        -- Get accessories
        data.accessories = {}
        for i = 0, 7 do
            data.accessories[i] = {
                drawable = GetPedPropIndex(playerPed, i),
                texture = GetPedPropTextureIndex(playerPed, i)
            }
        end
        
        return data
    end
    
    -- ====================================================================
    -- CLIENT EVENT HANDLERS
    -- ====================================================================
    
    RegisterNetEvent('cnr:receiveCharacterSlots')
    AddEventHandler('cnr:receiveCharacterSlots', function(slots)
        characterSlots = slots
        
        if characterEditorOpen then
            SendNUIMessage({
                type = "updateCharacterSlots",
                slots = characterSlots
            })
        end
    end)
    
    RegisterNetEvent('cnr:characterSaved')
    AddEventHandler('cnr:characterSaved', function(slotId)
        print(string.format("[CNR_CHARACTER_EDITOR] Character saved to slot %d", slotId))
        
        if characterEditorOpen then
            SendNUIMessage({
                type = "characterSaved",
                slotId = slotId
            })
        end
    end)
    
    RegisterNetEvent('cnr:characterLoaded')
    AddEventHandler('cnr:characterLoaded', function(slotId, data)
        if data then
            ApplyCharacterAppearance(data)
            print(string.format("[CNR_CHARACTER_EDITOR] Character loaded from slot %d", slotId))
        end
    end)
    
    RegisterNetEvent('cnr:applyCharacterData')
    AddEventHandler('cnr:applyCharacterData', function(data)
        ApplyCharacterAppearance(data)
    end)
    
    -- ====================================================================
    -- NUI CALLBACKS
    -- ====================================================================
    
    RegisterNUICallback('saveCharacter', function(data, cb)
        local characterData = GetCurrentCharacterAppearance()
        TriggerServerEvent('cnr:saveCharacter', data.slotId, characterData)
        cb('ok')
    end)
    
    RegisterNUICallback('loadCharacter', function(data, cb)
        TriggerServerEvent('cnr:loadCharacter', data.slotId)
        cb('ok')
    end)
    
    RegisterNUICallback('applyCharacter', function(data, cb)
        TriggerServerEvent('cnr:applyCharacter', data.slotId)
        cb('ok')
    end)
    
    RegisterNUICallback('closeCharacterEditor', function(data, cb)
        CloseCharacterEditor()
        cb('ok')
    end)
    
    RegisterNUICallback('updateCharacter', function(data, cb)
        -- Apply real-time character changes
        if data.type == "faceFeature" then
            SetPedFaceFeature(PlayerPedId(), data.index, data.value)
        elseif data.type == "headOverlay" then
            SetPedHeadOverlay(PlayerPedId(), data.index, data.overlay.index, data.overlay.opacity)
            if data.overlay.color then
                SetPedHeadOverlayColor(PlayerPedId(), data.index, data.overlay.colorType, data.overlay.color, data.overlay.secondColor or 0)
            end
        elseif data.type == "hair" then
            SetPedComponentVariation(PlayerPedId(), 2, data.hair.style, data.hair.texture, 0)
            SetPedHairColor(PlayerPedId(), data.hair.color, data.hair.highlight)
        elseif data.type == "clothing" then
            SetPedComponentVariation(PlayerPedId(), data.component, data.drawable, data.texture, 0)
        elseif data.type == "accessory" then
            if data.drawable >= 0 then
                SetPedPropIndex(PlayerPedId(), data.prop, data.drawable, data.texture, true)
            else
                ClearPedProp(PlayerPedId(), data.prop)
            end
        end
        
        cb('ok')
    end)
    
    -- ====================================================================
    -- CLIENT KEYBINDS
    -- ====================================================================
    
    -- Character editor toggle keybind
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(0)
            
            if IsControlJustPressed(0, 167) then -- F6 key
                if characterEditorOpen then
                    CloseCharacterEditor()
                else
                    OpenCharacterEditor()
                end
            end
        end
    end)
    
end