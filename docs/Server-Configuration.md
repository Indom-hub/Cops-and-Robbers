# Server Configuration

Complete guide for configuring your Cops & Robbers server.

## Basic Configuration

### server.cfg Settings

```cfg
# Basic Server Settings
sv_hostname "Cops & Robbers Roleplay"
sv_maxclients 64
sv_licenseKey "your_license_key"
sv_scriptHookAllowed 0

# Cops & Robbers Configuration
ensure cops-and-robbers
ensure mysql-async # or oxmysql

# Game Mode Settings
setr cops_robbers_max_cops 20
setr cops_robbers_max_robbers 40
setr cops_robbers_team_balance 1
setr cops_robbers_auto_balance 1

# Economy Settings
setr cops_robbers_starting_cash 5000
setr cops_robbers_starting_bank 10000
setr cops_robbers_economy_multiplier 1.0
setr cops_robbers_cop_salary_base 500
setr cops_robbers_cop_salary_interval 15 # minutes

# Crime Settings
setr cops_robbers_store_robbery_payout "500:2000"
setr cops_robbers_bank_heist_payout "10000:25000"
setr cops_robbers_jewelry_heist_payout "20000:50000"
setr cops_robbers_crime_cooldown_multiplier 1.0

# Police Settings
setr cops_robbers_police_response_time 30 # seconds
setr cops_robbers_swat_unlock_stars 4
setr cops_robbers_k9_units_enabled 1
setr cops_robbers_helicopter_enabled 1

# Vehicle Settings
setr cops_robbers_vehicle_spawn_limit 3
setr cops_robbers_vehicle_despawn_time 300 # seconds
setr cops_robbers_pursuit_vehicle_boost 1.2

# Weapon Settings
setr cops_robbers_weapon_damage_multiplier 1.0
setr cops_robbers_headshot_multiplier 2.0
setr cops_robbers_armor_effectiveness 0.5
```

## Advanced Configuration

### config.lua

```lua
Config = {}

-- Team Settings
Config.Teams = {
    cops = {
        name = "Police",
        color = {0, 100, 255},
        spawn_points = {
            {x = 425.1, y = -979.5, z = 30.7},
            {x = 1857.0, y = 3680.0, z = 34.2},
            {x = -448.0, y = 6012.0, z = 31.7}
        },
        default_weapons = {"WEAPON_PISTOL", "WEAPON_NIGHTSTICK", "WEAPON_STUNGUN"},
        max_players = 20
    },
    robbers = {
        name = "Criminals",
        color = {255, 0, 0},
        spawn_points = {
            {x = -1037.7, y = -2738.0, z = 20.1},
            {x = 1641.0, y = 2570.0, z = 45.5},
            {x = 86.0, y = -1959.0, z = 21.1}
        },
        default_weapons = {"WEAPON_PISTOL"},
        max_players = 40
    }
}

-- Rank System
Config.PoliceRanks = {
    [1] = {name = "Cadet", salary = 500, weapons = {}},
    [2] = {name = "Officer", salary = 750, weapons = {"WEAPON_COMBATPISTOL"}},
    [3] = {name = "Senior Officer", salary = 1000, weapons = {"WEAPON_SMG"}},
    [4] = {name = "Sergeant", salary = 1500, weapons = {"WEAPON_CARBINERIFLE"}},
    [5] = {name = "Lieutenant", salary = 2000, weapons = {"WEAPON_SPECIALCARBINE"}},
    [6] = {name = "Captain", salary = 3000, weapons = {"WEAPON_SNIPERRIFLE"}},
    [7] = {name = "Chief", salary = 5000, weapons = {"WEAPON_RPG"}}
}

-- Heist Configuration
Config.Heists = {
    fleeca_banks = {
        locations = {
            {x = 147.04, y = -1044.29, z = 29.36},
            {x = -1212.98, y = -330.84, z = 37.78},
            {x = -2962.58, y = 482.62, z = 15.70},
            {x = 1175.06, y = 2706.41, z = 38.09}
        },
        cooldown = 1800, -- 30 minutes
        min_cops = 2,
        rewards = {min = 10000, max = 25000}
    },
    pacific_standard = {
        location = {x = 235.40, y = 216.45, z = 106.28},
        cooldown = 7200, -- 2 hours
        min_cops = 4,
        rewards = {min = 75000, max = 150000},
        required_items = {"thermite", "laptop"}
    }
}

-- Vehicle Classes
Config.VehicleClasses = {
    police = {
        patrol = {"police", "police2", "police3"},
        pursuit = {"police4", "policeb", "fbi"},
        tactical = {"riot", "pbus", "polmav"}
    },
    criminal = {
        standard = {"sultan", "kuruma", "elegy"},
        sports = {"adder", "zentorno", "t20"},
        bikes = {"akuma", "bati", "sanchez"}
    }
}

-- Zone Control
Config.Territories = {
    grove_street = {
        center = {x = 126.73, y = -1929.95, z = 21.38},
        radius = 150,
        control_time = 300, -- 5 minutes to capture
        rewards = {cash = 1000, respect = 50}
    },
    vespucci_beach = {
        center = {x = -1341.34, y = -1216.54, z = 4.95},
        radius = 200,
        control_time = 420,
        rewards = {cash = 1500, respect = 75}
    }
}
```

## Database Configuration

### MySQL Setup

```sql
-- Create database
CREATE DATABASE IF NOT EXISTS cops_robbers;
USE cops_robbers;

-- Players table
CREATE TABLE IF NOT EXISTS players (
    id INT AUTO_INCREMENT PRIMARY KEY,
    identifier VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(50) NOT NULL,
    team ENUM('cops', 'robbers') NOT NULL,
    rank INT DEFAULT 1,
    cash INT DEFAULT 5000,
    bank INT DEFAULT 10000,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_seen TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Crime records
CREATE TABLE IF NOT EXISTS crime_records (
    id INT AUTO_INCREMENT PRIMARY KEY,
    player_id INT,
    crime_type VARCHAR(50),
    location VARCHAR(100),
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (player_id) REFERENCES players(id)
);

-- Vehicle ownership
CREATE TABLE IF NOT EXISTS vehicles (
    id INT AUTO_INCREMENT PRIMARY KEY,
    owner_id INT,
    model VARCHAR(50),
    plate VARCHAR(8) UNIQUE,
    garage_location VARCHAR(100),
    impounded BOOLEAN DEFAULT FALSE,
    FOREIGN KEY (owner_id) REFERENCES players(id)
);
```

## Performance Optimization

### Resource Limits

```cfg
# CPU and Memory limits
set sv_enforcegamebuild 2699
set onesync on
set onesync_population true

# Reduce entity limits for better performance
set entity_lockdown_mode 1
set entity_cleanup_interval 300

# Thread configuration
set game_enablethreadedrendering 1
set citizen_thread_count 8
```

### Network Settings

```cfg
# Network optimization
sv_endpointprivacy true
sv_requestParanoia 1
set net_maxPacketLoss 0.1
set net_maxPing 150

# Rate limiting
sv_projectile_rate_limit 100
sv_explosion_rate_limit 10
```

## Security Configuration

### Anti-Cheat Settings

```cfg
# Enable anti-cheat
setr cops_robbers_anticheat_enabled 1
setr cops_robbers_anticheat_teleport_detection 1
setr cops_robbers_anticheat_speedhack_detection 1
setr cops_robbers_anticheat_weapon_detection 1

# Ban configuration
setr cops_robbers_ban_duration_teleport 10080 # 7 days in minutes
setr cops_robbers_ban_duration_speedhack 10080
setr cops_robbers_ban_duration_weapons 43200 # 30 days
```

### Permission System

```cfg
# Admin levels
add_ace group.admin cops_robbers.admin allow
add_ace group.moderator cops_robbers.moderate allow
add_ace group.helper cops_robbers.help allow

# Command permissions
add_ace group.admin command.cr_give_money allow
add_ace group.admin command.cr_set_rank allow
add_ace group.moderator command.cr_kick allow
add_ace group.helper command.cr_teleport allow
```

## Monitoring & Logging

### Log Settings

```cfg
# Enable detailed logging
setr cops_robbers_log_level "debug" # options: error, warn, info, debug
setr cops_robbers_log_file "cops_robbers.log"
setr cops_robbers_log_rotation_size 10 # MB
setr cops_robbers_log_retention_days 30

# Discord webhook for important events
setr cops_robbers_discord_webhook "your_webhook_url"
setr cops_robbers_discord_log_arrests 1
setr cops_robbers_discord_log_heists 1
setr cops_robbers_discord_log_admin_actions 1
```

## Troubleshooting

### Common Issues

1. **High Server CPU Usage**
   - Reduce `sv_maxclients`
   - Increase `entity_cleanup_interval`
   - Disable unused features

2. **Database Connection Issues**
   - Check MySQL credentials
   - Verify firewall settings
   - Monitor connection pool size

3. **Synchronization Problems**
   - Enable OneSync
   - Check network latency
   - Reduce entity spawn rates