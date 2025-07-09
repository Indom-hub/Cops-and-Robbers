-- constants.lua
-- Centralized constants to replace magic numbers and hardcoded strings
-- Version: 1.2.0

-- Initialize Constants table
Constants = Constants or {}

-- ====================================================================
-- SYSTEM CONSTANTS
-- ====================================================================

-- Logging levels
Constants.LOG_LEVELS = {
    ERROR = "error",
    WARN = "warn", 
    INFO = "info",
    DEBUG = "debug"
}

-- Player limits and defaults
Constants.PLAYER_LIMITS = {
    MAX_INVENTORY_SLOTS = 50,
    DEFAULT_STARTING_MONEY = 5000,
    MAX_WANTED_LEVEL = 5,
    MIN_WANTED_LEVEL = 0,
    MAX_PLAYER_LEVEL = 100,
    DEFAULT_WEAPON_AMMO = 250
}

-- Time constants (in milliseconds)
Constants.TIME_MS = {
    SECOND = 1000,
    MINUTE = 60000,
    HOUR = 3600000,
    DAY = 86400000,
    
    -- Specific timeouts
    SAVE_INTERVAL = 300000,        -- 5 minutes
    WANTED_DECAY_INTERVAL = 20000, -- 20 seconds
    BOUNTY_DURATION = 1800000,     -- 30 minutes
    JAIL_CHECK_INTERVAL = 5000,    -- 5 seconds
    HEIST_COOLDOWN = 600000,       -- 10 minutes
    CONTRABAND_DROP_INTERVAL = 1800000, -- 30 minutes
    
    -- Client-side intervals
    UI_UPDATE_INTERVAL = 1000,     -- 1 second
    POSITION_UPDATE_INTERVAL = 5000, -- 5 seconds
    HEALTH_CHECK_INTERVAL = 2000   -- 2 seconds
}

-- Distance constants (in meters)
Constants.DISTANCES = {
    INTERACTION_RANGE = 3.0,
    STORE_INTERACTION_RANGE = 5.0,
    COP_SIGHT_DISTANCE = 50.0,
    HEIST_RADIUS = 1000.0,
    SAFE_ZONE_DEFAULT_RADIUS = 25.0,
    EMP_RADIUS = 15.0,
    SPIKE_STRIP_EFFECT_RADIUS = 10.0
}

-- Money and economy constants
Constants.ECONOMY = {
    SELL_PRICE_MULTIPLIER = 0.6,   -- Items sell for 60% of base price
    DYNAMIC_PRICE_MIN_MULTIPLIER = 0.5,
    DYNAMIC_PRICE_MAX_MULTIPLIER = 2.0,
    BOUNTY_BASE_AMOUNT = 5000,
    BOUNTY_MULTIPLIER = 0.5,
    BOUNTY_MAX_AMOUNT = 50000,
    TEAM_BALANCE_INCENTIVE = 1000,
    CORRUPT_OFFICIAL_COST_PER_STAR = 5000
}

-- Validation constants
Constants.VALIDATION = {
    MAX_ITEM_QUANTITY = 999,
    MIN_ITEM_QUANTITY = 1,
    MAX_MONEY_TRANSACTION = 1000000,
    MIN_MONEY_TRANSACTION = 1,
    MAX_STRING_LENGTH = 255,
    MAX_REASON_LENGTH = 500,
    
    -- Rate limiting
    MAX_EVENTS_PER_SECOND = 10,
    MAX_PURCHASES_PER_MINUTE = 20,
    MAX_INVENTORY_OPERATIONS_PER_SECOND = 5
}

-- File system constants
Constants.FILES = {
    PLAYER_DATA_DIR = "player_data",
    BANS_FILE = "bans.json",
    PURCHASE_HISTORY_FILE = "purchase_history.json",
    BANKING_DATA_FILE = "banking_data.json",
    BACKUP_DIR = "backups",
    
    -- File extensions
    JSON_EXT = ".json",
    BACKUP_EXT = ".bak",
    
    -- Backup settings
    MAX_BACKUPS_PER_FILE = 5,
    BACKUP_INTERVAL_HOURS = 24
}

-- Network event names (centralized to prevent typos)
Constants.EVENTS = {
    -- Client to Server
    CLIENT_TO_SERVER = {
        GET_PLAYER_ROLE = "cnr:getPlayerRole",
        REQUEST_INVENTORY = "cnr:requestMyInventory",
        REQUEST_CONFIG_ITEMS = "cnr:requestConfigItems",
        BUY_ITEM = "cops_and_robbers:buyItem",
        SELL_ITEM = "cops_and_robbers:sellItem",
        EQUIP_ITEM = "cnr:equipItem",
        USE_ITEM = "cnr:useItem",
        DROP_ITEM = "cnr:dropItem",
        WEAPON_FIRED = "cnr:weaponFired",
        PLAYER_DAMAGED = "cnr:playerDamaged",
        REPORT_CRIME = "cops_and_robbers:reportCrime",
        ACCESS_CONTRABAND_DEALER = "cnr:accessContrabandDealer",
        REQUEST_BOUNTY_LIST = "cnr:requestBountyList"
    },
    
    -- Server to Client
    SERVER_TO_CLIENT = {
        RETURN_PLAYER_ROLE = "cnr:returnPlayerRole",
        RECEIVE_INVENTORY = "cnr:receiveMyInventory",
        RECEIVE_CONFIG_ITEMS = "cnr:receiveConfigItems",
        SYNC_INVENTORY = "cnr:syncInventory",
        INVENTORY_UPDATED = "cnr:inventoryUpdated",
        UPDATE_PLAYER_DATA = "cnr:updatePlayerData",
        SHOW_NOTIFICATION = "cnr:showNotification",
        SEND_NUI_MESSAGE = "cnr:sendNUIMessage",
        EQUIP_ITEM_RESULT = "cnr:equipItemResult",
        USE_ITEM_RESULT = "cnr:useItemResult",
        DROP_ITEM_RESULT = "cnr:dropItemResult",
        RECEIVE_BOUNTY_LIST = "cnr:receiveBountyList",
        SEND_TO_JAIL = "cnr:sendToJail",
        RELEASE_FROM_JAIL = "cnr:releaseFromJail"
    }
}

-- Error messages
Constants.ERROR_MESSAGES = {
    PLAYER_NOT_FOUND = "Player data not found",
    INSUFFICIENT_FUNDS = "Insufficient funds",
    INSUFFICIENT_ITEMS = "You don't have enough of this item",
    INVALID_ITEM = "Invalid item",
    INVALID_QUANTITY = "Invalid quantity",
    INVENTORY_FULL = "Inventory is full",
    PERMISSION_DENIED = "Permission denied",
    RATE_LIMITED = "Too many requests, please slow down",
    SERVER_ERROR = "Server error occurred",
    VALIDATION_FAILED = "Data validation failed",
    ITEM_NOT_FOUND = "Item not found in configuration",
    ROLE_REQUIRED = "Specific role required for this action",
    LEVEL_REQUIRED = "Insufficient level for this action"
}

-- Success messages
Constants.SUCCESS_MESSAGES = {
    ITEM_PURCHASED = "Item purchased successfully",
    ITEM_SOLD = "Item sold successfully",
    ITEM_EQUIPPED = "Item equipped",
    ITEM_UNEQUIPPED = "Item unequipped",
    ITEM_USED = "Item used",
    ITEM_DROPPED = "Item dropped",
    MONEY_ADDED = "Money added to account",
    MONEY_REMOVED = "Money deducted from account",
    DATA_SAVED = "Data saved successfully",
    PLAYER_SPAWNED = "Player spawned successfully"
}

-- Item categories (standardized)
Constants.ITEM_CATEGORIES = {
    WEAPONS = "Weapons",
    MELEE_WEAPONS = "Melee Weapons",
    AMMUNITION = "Ammunition",
    ARMOR = "Armor",
    MEDICAL = "Medical",
    UTILITY = "Utility",
    EXPLOSIVES = "Explosives",
    CONTRABAND = "Contraband",
    TOOLS = "Tools",
    CONSUMABLES = "Consumables"
}

-- Player roles
Constants.ROLES = {
    COP = "cop",
    ROBBER = "robber",
    CITIZEN = "citizen"
}

-- Wanted system constants
Constants.WANTED_SYSTEM = {
    MIN_STARS = 1,
    MAX_STARS = 5,
    DECAY_RATE_POINTS = 1,
    BASE_INCREASE_POINTS = 1,
    NO_CRIME_COOLDOWN_MS = 40000,
    COP_SIGHT_COOLDOWN_MS = 20000,
    AUTO_BOUNTY_THRESHOLD = 4  -- Auto-place bounty at 4+ stars
}

-- Admin permission levels
Constants.ADMIN_LEVELS = {
    MODERATOR = 1,
    ADMIN = 2,
    SUPER_ADMIN = 3,
    OWNER = 4
}

-- Notification types
Constants.NOTIFICATION_TYPES = {
    SUCCESS = "success",
    ERROR = "error", 
    WARNING = "warning",
    INFO = "info"
}

-- Weapon hash constants (commonly used weapons)
Constants.WEAPON_HASHES = {
    UNARMED = GetHashKey("WEAPON_UNARMED"),
    PISTOL = GetHashKey("WEAPON_PISTOL"),
    COMBAT_PISTOL = GetHashKey("WEAPON_COMBATPISTOL"),
    SMG = GetHashKey("WEAPON_SMG"),
    ASSAULT_RIFLE = GetHashKey("WEAPON_ASSAULTRIFLE"),
    CARBINE_RIFLE = GetHashKey("WEAPON_CARBINERIFLE"),
    SNIPER_RIFLE = GetHashKey("WEAPON_SNIPERRIFLE"),
    STUNGUN = GetHashKey("WEAPON_STUNGUN"),
    NIGHTSTICK = GetHashKey("WEAPON_NIGHTSTICK"),
    FLASHLIGHT = GetHashKey("WEAPON_FLASHLIGHT")
}

-- Vehicle model hashes (commonly used)
Constants.VEHICLE_HASHES = {
    POLICE = GetHashKey("police"),
    POLICE2 = GetHashKey("police2"),
    POLICE3 = GetHashKey("police3"),
    FBI = GetHashKey("fbi"),
    FBI2 = GetHashKey("fbi2"),
    SHERIFF = GetHashKey("sheriff"),
    STOCKADE = GetHashKey("stockade")
}

-- Ped model hashes
Constants.PED_HASHES = {
    COP = GetHashKey("s_m_y_cop_01"),
    FEMALE_COP = GetHashKey("s_f_y_cop_01"),
    SWAT = GetHashKey("s_m_y_swat_01"),
    DEALER = GetHashKey("s_m_y_dealer_01"),
    GANG_MEMBER = GetHashKey("g_m_y_mexgang_01")
}

-- Database/Storage constants (for future database implementation)
Constants.DATABASE = {
    BATCH_SIZE = 100,
    CONNECTION_TIMEOUT = 30000,
    QUERY_TIMEOUT = 10000,
    MAX_RETRIES = 3,
    RETRY_DELAY = 1000
}

-- Performance monitoring constants
Constants.PERFORMANCE = {
    MAX_EXECUTION_TIME_MS = 50,    -- Maximum time for a single operation
    MEMORY_WARNING_THRESHOLD_MB = 100,
    CPU_WARNING_THRESHOLD_PERCENT = 80,
    MAX_CONCURRENT_OPERATIONS = 10
}

-- Constants table is now available globally