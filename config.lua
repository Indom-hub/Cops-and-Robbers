-- config.lua
-- Cops & Robbers FiveM Game Mode Configuration File
-- Version: 1.1 | Date: 2025-02-11
-- This file contains all the configuration settings for the game mode.
-- Make sure this file is loaded before any scripts that depend on Config.

-- Initialize Config table if not already initialized
Config = Config or {}

-- =========================
--        General Settings
-- =========================

Config.MaxPlayers = 64
Config.HeistCooldown = 600 -- seconds (10 minutes)
Config.HeistRadius = 1000.0 -- meters

-- Spawn locations based on roles
Config.CopSpawn = vector3(452.6, -980.0, 30.7)
Config.RobberSpawn = vector3(2126.7, 4794.1, 41.1)

-- Jail Location (players are sent here when jailed)
Config.PrisonLocation = vector3(1651.0, 2570.0, 45.5)

-- =========================
--       Bank Vaults
-- =========================

Config.BankVaults = {
    { location = vector3(150.0, -1040.0, 29.0), name = "Pacific Standard Bank", id = 1 },
    { location = vector3(-1212.0, -330.0, 37.8), name = "Fleeca Bank", id = 2 },
    { location = vector3(-2962.6, 482.9, 15.7), name = "Great Ocean Highway Bank", id = 3 },
    { location = vector3(1175.0, 2706.8, 38.1), name = "Route 68 Bank", id = 4 },
}

-- =========================
-- Police and Civilian Vehicles
-- =========================

Config.PoliceVehicles = { 'police', 'police2', 'police3', 'fbi', 'fbi2' }
Config.CivilianVehicles = { 'sultan', 'futo', 'blista', 'banshee', 'elegy2' }

-- =========================
-- Experience and Leveling System
-- =========================

Config.Experience = {
    Levels = {
        { level = 1, exp = 0 },
        { level = 2, exp = 1000 },
        { level = 3, exp = 3000 },
        { level = 4, exp = 6000 },
        { level = 5, exp = 10000 },
    },
    Rewards = {
        ['robber'] = {
            [2] = { cash = 500, item = 'lockpick' },
            [3] = { cash = 1000, item = 'drill' },
            [4] = { cash = 2000, item = 'thermal_charge' },
            [5] = { cash = 5000, item = 'gold_bar' },
        },
        ['cop'] = {
            [2] = { cash = 500, item = 'taser' },
            [3] = { cash = 1000, item = 'stun_gun' },
            [4] = { cash = 2000, item = 'carbine_rifle' },
            [5] = { cash = 5000, item = 'swat_gear' },
        },
    },
}

-- =========================
--    Wanted Level System
-- =========================

Config.WantedLevels = {
    [1] = { stars = 1, description = "Minor Offenses" },
    [2] = { stars = 2, description = "Felony" },
    [3] = { stars = 3, description = "Serious Crime" },
    [4] = { stars = 4, description = "High Alert" },
    [5] = { stars = 5, description = "Most Wanted" },
}

-- =========================
--   Ammu-Nation Store Locations
-- =========================

Config.AmmuNationStores = {
    vector3(1692.41, 3758.22, 34.70),
    vector3(252.89, -49.25, 69.94),
    vector3(844.35, -1033.42, 28.19),
    vector3(-331.35, 6083.45, 31.45),
    vector3(-662.1, -935.3, 21.8),
    vector3(-1305.18, -393.48, 36.70),
    vector3(2567.69, 294.38, 108.73),
    vector3(-1117.58, 2698.61, 18.55),
    vector3(811.19, -2157.67, 29.62),
}

-- =========================
--     NPC Vendor Configurations
-- =========================

Config.NPCVendors = {
    {
        location = vector3(-1107.17, 4949.54, 218.65),
        heading = 140.0,
        model = "s_m_y_dealer_01",
        name = "Black Market Dealer",
        items = {"weapon_knife", "weapon_switchblade", "weapon_microsmg", "ammo_smg", "lockpick", "mask", "c4", "drill"}
    },
    {
        location = vector3(1961.48, 3740.69, 32.34),
        heading = 300.0,
        model = "g_m_y_mexgang_01",
        name = "Gang Supplier",
        items = {"weapon_pistol50", "weapon_sawnoffshotgun", "ammo_shotgun", "armor", "bandana"}
    },
    -- Additional NPC vendors can be added here
}

-- =========================
--      Item Definitions
-- =========================

Config.Items = {
    -- Weapons
    { name = "Pistol", itemId = "weapon_pistol", basePrice = 500, category = "Weapons" },
    { name = "Combat Pistol", itemId = "weapon_combatpistol", basePrice = 750, category = "Weapons" },
    { name = "Heavy Pistol", itemId = "weapon_heavypistol", basePrice = 1000, category = "Weapons" },
    { name = "SMG", itemId = "weapon_smg", basePrice = 1500, category = "Weapons" },
    { name = "Micro SMG", itemId = "weapon_microsmg", basePrice = 1250, category = "Weapons" },
    { name = "Assault Rifle", itemId = "weapon_assaultrifle", basePrice = 2500, category = "Weapons" },
    { name = "Carbine Rifle", itemId = "weapon_carbinerifle", basePrice = 3000, category = "Weapons" },
    { name = "Sniper Rifle", itemId = "weapon_sniperrifle", basePrice = 5000, category = "Weapons" },
    { name = "Pump Shotgun", itemId = "weapon_pumpshotgun", basePrice = 1200, category = "Weapons" },
    { name = "Sawed-Off Shotgun", itemId = "weapon_sawnoffshotgun", basePrice = 1000, category = "Weapons" },
    { name = "Knife", itemId = "weapon_knife", basePrice = 100, category = "Melee Weapons" },
    { name = "Bat", itemId = "weapon_bat", basePrice = 50, category = "Melee Weapons" },
    { name = "Crowbar", itemId = "weapon_crowbar", basePrice = 75, category = "Melee Weapons" },
    { name = "Switchblade", itemId = "weapon_switchblade", basePrice = 150, category = "Melee Weapons" },
    -- Ammunition
    { name = "Pistol Ammo", itemId = "ammo_pistol", basePrice = 50, category = "Ammunition" },
    { name = "SMG Ammo", itemId = "ammo_smg", basePrice = 75, category = "Ammunition" },
    { name = "Rifle Ammo", itemId = "ammo_rifle", basePrice = 100, category = "Ammunition" },
    { name = "Shotgun Ammo", itemId = "ammo_shotgun", basePrice = 60, category = "Ammunition" },
    { name = "Sniper Ammo", itemId = "ammo_sniper", basePrice = 200, category = "Ammunition" },
    -- Armor and Utility
    { name = "Body Armor", itemId = "armor", basePrice = 500, category = "Armor" },
    { name = "Heavy Armor", itemId = "heavy_armor", basePrice = 1000, category = "Armor" },
    { name = "Medkit", itemId = "medkit", basePrice = 250, category = "Utility" },
    { name = "First Aid Kit", itemId = "firstaidkit", basePrice = 100, category = "Utility" },
    { name = "Lockpick", itemId = "lockpick", basePrice = 150, category = "Utility" },
    { name = "Advanced Lockpick", itemId = "adv_lockpick", basePrice = 300, category = "Utility" },
    { name = "Flashlight", itemId = "weapon_flashlight", basePrice = 100, category = "Utility" },
    { name = "Parachute", itemId = "gadget_parachute", basePrice = 300, category = "Utility" },
    { name = "Drill", itemId = "drill", basePrice = 500, category = "Utility" },
    { name = "C4 Explosive", itemId = "c4", basePrice = 2000, category = "Utility" },
    -- Accessories
    { name = "Mask", itemId = "mask", basePrice = 200, category = "Accessories" },
    { name = "Gloves", itemId = "gloves", basePrice = 100, category = "Accessories" },
    { name = "Hat", itemId = "hat", basePrice = 150, category = "Accessories" },
    { name = "Bandana", itemId = "bandana", basePrice = 80, category = "Accessories" },
    { name = "Sunglasses", itemId = "sunglasses", basePrice = 120, category = "Accessories" },
    -- Add more items as needed
}

-- =========================
--  Dynamic Economy Settings
-- =========================

-- Timeframe for popularity tracking (in seconds)
Config.PopularityTimeframe = 3 * 60 * 60  -- 3 hours

-- Price adjustment factors
Config.PriceIncreaseFactor = 1.2  -- Increase price by 20% for popular items
Config.PriceDecreaseFactor = 0.8  -- Decrease price by 20% for less popular items

-- Thresholds for popularity
Config.PopularityThreshold = {
    high = 10,  -- Items purchased more than 10 times are considered popular
    low = 2,    -- Items purchased less than 2 times are considered less popular
}

-- Sell price factor (percentage of the item's dynamic price)
Config.SellPriceFactor = 0.5  -- Players get 50% of the item's price when selling

-- =========================
--   Additional Configurations
-- =========================

-- List of banned player identifiers (e.g., Steam IDs)
Config.BannedPlayers = {
    -- ["steam:110000112345678"] = { reason = "Cheating", timestamp = 1625078400 },
    -- ["license:abcdefghijk"] = { reason = "Harassment", timestamp = 1625078400 },
}

-- Admin identifiers for privileged actions
Config.Admins = {
    -- ["steam:110000112345678"] = true,
    -- ["license:abcdefghijk"] = true,
}

-- =========================
--      Heist Settings
-- =========================

-- Heist timer durations
Config.HeistTimers = {
    heistDuration = 600, -- Duration of the heist in seconds (10 minutes)
}

-- =========================
--    Vehicle Spawn Settings
-- =========================

-- Police vehicle spawn points (using vector3 for location)
Config.PoliceVehicleSpawns = {
    { location = vector3(452.6, -980.0, 30.7), heading = 90.0 },
    -- Add more spawn points as needed
}

-- Civilian vehicle spawn points
Config.CivilianVehicleSpawns = {
    { location = vector3(2126.7, 4794.1, 41.1), heading = 180.0 },
    -- Add more spawn points as needed
}
