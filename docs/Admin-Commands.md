# Admin Commands

Complete list of administrative commands for managing your Cops & Robbers server.

## Command Usage

All admin commands start with `/cr_` prefix. Permission levels are required based on command severity.

## Player Management

### Basic Commands

**`/cr_kick [player_id] [reason]`**
- **Permission**: Moderator+
- **Description**: Kicks a player from the server
- **Example**: `/cr_kick 15 "Fail RP"`

**`/cr_ban [player_id] [duration] [reason]`**
- **Permission**: Moderator+
- **Description**: Bans a player for specified duration (in minutes, 0 = permanent)
- **Example**: `/cr_ban 15 1440 "Cheating"` (24 hour ban)

**`/cr_unban [identifier]`**
- **Permission**: Admin+
- **Description**: Unbans a player by their identifier
- **Example**: `/cr_unban steam:110000112345678`

**`/cr_warn [player_id] [reason]`**
- **Permission**: Helper+
- **Description**: Issues a warning to a player
- **Example**: `/cr_warn 15 "Breaking traffic laws as cop"`

### Team Management

**`/cr_setteam [player_id] [team]`**
- **Permission**: Moderator+
- **Description**: Forces a player to a specific team
- **Example**: `/cr_setteam 15 cops`

**`/cr_balance_teams`**
- **Permission**: Moderator+
- **Description**: Force balances teams
- **Example**: `/cr_balance_teams`

## Economy Commands

**`/cr_givemoney [player_id] [amount]`**
- **Permission**: Admin+
- **Description**: Gives money to a player
- **Example**: `/cr_givemoney 15 10000`

**`/cr_setmoney [player_id] [amount]`**
- **Permission**: Admin+
- **Description**: Sets a player's cash amount
- **Example**: `/cr_setmoney 15 5000`

**`/cr_givebank [player_id] [amount]`**
- **Permission**: Admin+
- **Description**: Adds money to player's bank
- **Example**: `/cr_givebank 15 50000`

**`/cr_economy_reset [player_id]`**
- **Permission**: Admin+
- **Description**: Resets player's economy to default
- **Example**: `/cr_economy_reset 15`

## Rank & Progression

**`/cr_setrank [player_id] [rank]`**
- **Permission**: Admin+
- **Description**: Sets police rank (1-7) or criminal reputation
- **Example**: `/cr_setrank 15 4` (Sergeant)

**`/cr_addxp [player_id] [amount]`**
- **Permission**: Moderator+
- **Description**: Adds experience points
- **Example**: `/cr_addxp 15 1000`

**`/cr_resetstats [player_id]`**
- **Permission**: Admin+
- **Description**: Resets all player statistics
- **Example**: `/cr_resetstats 15`

## Vehicle Commands

**`/cr_spawnveh [vehicle_model]`**
- **Permission**: Moderator+
- **Description**: Spawns a vehicle
- **Example**: `/cr_spawnveh police3`

**`/cr_delveh [radius]`**
- **Permission**: Moderator+
- **Description**: Deletes vehicles within radius
- **Example**: `/cr_delveh 50`

**`/cr_fix`**
- **Permission**: Helper+
- **Description**: Repairs current vehicle
- **Example**: `/cr_fix`

**`/cr_impound [player_id]`**
- **Permission**: Moderator+
- **Description**: Impounds player's current vehicle
- **Example**: `/cr_impound 15`

## Teleportation

**`/cr_tp [player_id]`**
- **Permission**: Helper+
- **Description**: Teleport to a player
- **Example**: `/cr_tp 15`

**`/cr_tphere [player_id]`**
- **Permission**: Moderator+
- **Description**: Teleport player to you
- **Example**: `/cr_tphere 15`

**`/cr_tpcoords [x] [y] [z]`**
- **Permission**: Helper+
- **Description**: Teleport to coordinates
- **Example**: `/cr_tpcoords 215.5 -810.0 30.7`

**`/cr_tpmarker`**
- **Permission**: Helper+
- **Description**: Teleport to waypoint
- **Example**: `/cr_tpmarker`

## Game Control

**`/cr_startbank`**
- **Permission**: Moderator+
- **Description**: Manually starts a bank heist
- **Example**: `/cr_startbank`

**`/cr_stopheist`**
- **Permission**: Moderator+
- **Description**: Stops active heist
- **Example**: `/cr_stopheist`

**`/cr_settime [hour] [minute]`**
- **Permission**: Moderator+
- **Description**: Sets game time
- **Example**: `/cr_settime 14 30`

**`/cr_setweather [type]`**
- **Permission**: Moderator+
- **Description**: Sets weather (clear, rain, thunder, fog, snow)
- **Example**: `/cr_setweather rain`

## Debug Commands

**`/cr_debug [on/off]`**
- **Permission**: Admin+
- **Description**: Toggles debug mode
- **Example**: `/cr_debug on`

**`/cr_coords`**
- **Permission**: Helper+
- **Description**: Shows current coordinates
- **Example**: `/cr_coords`

**`/cr_playerinfo [player_id]`**
- **Permission**: Moderator+
- **Description**: Shows detailed player information
- **Example**: `/cr_playerinfo 15`

**`/cr_serverinfo`**
- **Permission**: Admin+
- **Description**: Shows server statistics
- **Example**: `/cr_serverinfo`

## Moderation Tools

**`/cr_spectate [player_id]`**
- **Permission**: Helper+
- **Description**: Spectate a player
- **Example**: `/cr_spectate 15`

**`/cr_freeze [player_id]`**
- **Permission**: Moderator+
- **Description**: Freeze/unfreeze player
- **Example**: `/cr_freeze 15`

**`/cr_announce [message]`**
- **Permission**: Moderator+
- **Description**: Server-wide announcement
- **Example**: `/cr_announce Server restart in 5 minutes!`

**`/cr_clearchat`**
- **Permission**: Moderator+
- **Description**: Clears chat for all players
- **Example**: `/cr_clearchat`

## Database Management

**`/cr_wipe_player [identifier]`**
- **Permission**: Owner
- **Description**: Completely wipes player data
- **Example**: `/cr_wipe_player steam:110000112345678`

**`/cr_backup`**
- **Permission**: Owner
- **Description**: Creates database backup
- **Example**: `/cr_backup`

**`/cr_restore [backup_name]`**
- **Permission**: Owner
- **Description**: Restores from backup
- **Example**: `/cr_restore backup_2025_07_08`

## Console Commands

These commands can only be run from server console:

**`cr_reload_config`**
- Reloads server configuration without restart

**`cr_player_list`**
- Shows all connected players with details

**`cr_performance_report`**
- Generates performance metrics report

**`cr_clear_cache`**
- Clears server cache

## Permission Levels

1. **Helper** - Basic moderation
2. **Moderator** - Standard moderation
3. **Admin** - Full administration
4. **Owner** - Server owner only

## Command Logging

All admin commands are logged with:
- Timestamp
- Admin name and identifier
- Command used
- Target player (if applicable)
- Result of command

Logs are stored in `admin_commands.log` and optionally sent to Discord webhook.

## Best Practices

1. Always include reasons for kicks/bans
2. Use appropriate ban durations
3. Document admin actions
4. Follow server admin guidelines
5. Use spectate before taking action
6. Communicate with players when possible