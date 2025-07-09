fx_version 'cerulean'
game 'gta5'

name 'Cops and Robbers - Enhanced'
description 'An immersive Cops and Robbers game mode with advanced features and administrative control'
author 'The Axiom Collective'
version '1.2.0'

-- Define shared scripts, loaded first on both server and client.
shared_scripts {
    'config.lua',       -- Game mode configuration.
    'constants.lua',    -- Centralized constants and configuration values.
    'safe_utils.lua'    -- Safe utility functions (shared between client and server).
}

-- Define server-side scripts in dependency order.
server_scripts {
    -- Core utilities and constants (loaded first)
    
    -- New refactored systems (loaded in dependency order)
    'validation.lua',    -- Server-side validation system.
    'data_manager.lua',  -- Improved data persistence system.
    'secure_inventory.lua', -- Secure inventory system with anti-duplication.
    'secure_transactions.lua', -- Secure transaction system for purchases/sales.
    'player_manager.lua', -- Refactored player data management system.
    'performance_optimizer.lua', -- Performance optimization and monitoring.
    'integration_manager.lua', -- Integration and compatibility manager.
    
    -- Original systems (maintained for compatibility)
    'server.lua',       -- Core server logic (refactored to use new systems).
    'admin.lua',         -- Admin commands and server-side admin functionalities.
    'inventory_server.lua', -- Legacy inventory system (will be phased out).
    'character_editor_server.lua', -- Character editor server logic.
    'progression_server.lua' -- Enhanced progression system server logic.
}

-- Define client-side scripts.
client_scripts {
    'client.lua',        -- Core client logic and event handling.
    'inventory_client.lua',
    'character_editor_client.lua', -- Character editor client logic
    'progression_client.lua' -- Enhanced progression system client logic
}

-- Define the NUI page.
ui_page 'html/main_ui.html' -- Consolidated NUI page for role selection, store, admin panel, etc.

-- Define files to be included with the resource.
-- These files are accessible by the client and NUI.
files {
    'html/main_ui.html',     -- Main HTML file for the NUI.
    'html/styles.css',       -- CSS styles for the NUI.
    'html/scripts.js',       -- JavaScript for NUI interactions.
    'purchase_history.json', -- For dynamic pricing persistence (ensure write access for server).
    'player_data/*',         -- Wildcard for player save files (ensure server has write access to this conceptual path).
    'bans.json'
}

-- Declare resource dependencies.
dependencies {
}

export 'UpdateFullInventory'
export 'EquipInventoryWeapons'

-- Network events
server_export 'GetCharacterForRoleSelection'
