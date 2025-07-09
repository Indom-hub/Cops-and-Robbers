# API Reference

Developer documentation for extending and integrating with Cops & Robbers.

## Client-Side API

### Player Functions

#### `CR.GetPlayerTeam()`
Returns the player's current team.
```lua
local team = CR.GetPlayerTeam()
-- Returns: "cops" or "robbers"
```

#### `CR.GetPlayerRank()`
Returns the player's rank/reputation level.
```lua
local rank = CR.GetPlayerRank()
-- Returns: 1-7 for cops, 1-5 for robbers
```

#### `CR.GetPlayerMoney()`
Returns player's cash and bank balance.
```lua
local cash, bank = CR.GetPlayerMoney()
-- Returns: cash amount, bank amount
```

#### `CR.IsPlayerWanted()`
Checks if player has wanted level.
```lua
local wanted, level = CR.IsPlayerWanted()
-- Returns: boolean, wanted level (1-5)
```

### Team Functions

#### `CR.RequestTeamChange(team)`
Request to change teams.
```lua
CR.RequestTeamChange("cops")
-- team: "cops" or "robbers"
```

#### `CR.GetTeamCount(team)`
Get number of players on a team.
```lua
local count = CR.GetTeamCount("cops")
-- Returns: number of players
```

### Crime Functions

#### `CR.StartRobbery(location)`
Initiates a robbery at location.
```lua
CR.StartRobbery("fleeca_legion")
-- location: robbery identifier
```

#### `CR.IsRobberyActive()`
Checks if player is in active robbery.
```lua
local active = CR.IsRobberyActive()
-- Returns: boolean
```

### Police Functions

#### `CR.ArrestPlayer(targetId)`
Attempt to arrest a player.
```lua
CR.ArrestPlayer(targetServerId)
-- targetId: server ID of target
```

#### `CR.CallBackup(priority)`
Request police backup.
```lua
CR.CallBackup(3)
-- priority: 1-3 (1 = routine, 3 = emergency)
```

## Server-Side API

### Player Management

#### `CR.GetPlayer(source)`
Get player object.
```lua
local player = CR.GetPlayer(source)
-- Returns: player object with methods
```

#### `CR.CreatePlayer(source, identifier)`
Create new player profile.
```lua
local player = CR.CreatePlayer(source, "steam:xxxxx")
```

### Player Object Methods

```lua
-- Money management
player:addMoney(amount)
player:removeMoney(amount)
player:addBank(amount)
player:removeBank(amount)
player:getMoney()
player:getBank()

-- Rank/progression
player:setRank(rank)
player:getRank()
player:addXP(amount)
player:getXP()

-- Team management
player:setTeam(team)
player:getTeam()

-- Wanted system
player:setWantedLevel(level)
player:getWantedLevel()
player:clearWanted()
```

### Economy Functions

#### `CR.PaySalaries()`
Process salary payments for cops.
```lua
CR.PaySalaries()
-- Called automatically, can be triggered manually
```

#### `CR.ProcessTransaction(source, amount, type)`
Process money transaction with logging.
```lua
CR.ProcessTransaction(source, 5000, "heist_payout")
```

### Crime System

#### `CR.StartHeist(type, players)`
Initialize a heist.
```lua
CR.StartHeist("pacific_standard", {1, 2, 3, 4})
-- type: heist identifier
-- players: table of source IDs
```

#### `CR.EndHeist(heistId, success)`
Complete or fail a heist.
```lua
CR.EndHeist(heistId, true)
-- heistId: active heist ID
-- success: boolean
```

### Law Enforcement

#### `CR.DispatchAlert(crime, location)`
Send alert to all cops.
```lua
CR.DispatchAlert("robbery", {x = 100, y = 200, z = 30})
```

#### `CR.ImpoundVehicle(vehicleNetId)`
Impound a vehicle.
```lua
CR.ImpoundVehicle(vehicleNetId)
```

## Events

### Client Events

#### `cr:teamChanged`
Triggered when player changes team.
```lua
RegisterNetEvent('cr:teamChanged')
AddEventHandler('cr:teamChanged', function(newTeam)
    -- Handle team change
end)
```

#### `cr:moneyUpdated`
Money balance updated.
```lua
RegisterNetEvent('cr:moneyUpdated')
AddEventHandler('cr:moneyUpdated', function(cash, bank)
    -- Update UI
end)
```

#### `cr:wantedLevelChanged`
Wanted level changed.
```lua
RegisterNetEvent('cr:wantedLevelChanged')
AddEventHandler('cr:wantedLevelChanged', function(level)
    -- Update wanted stars
end)
```

### Server Events

#### `cr:playerJoined`
Player joined server.
```lua
RegisterServerEvent('cr:playerJoined')
AddEventHandler('cr:playerJoined', function()
    local source = source
    -- Initialize player
end)
```

#### `cr:robberyStarted`
Robbery initiated.
```lua
RegisterServerEvent('cr:robberyStarted')
AddEventHandler('cr:robberyStarted', function(location)
    -- Handle robbery start
end)
```

#### `cr:playerArrested`
Player arrested.
```lua
RegisterServerEvent('cr:playerArrested')
AddEventHandler('cr:playerArrested', function(copId, robberId)
    -- Process arrest
end)
```

## Exports

### Client Exports

```lua
-- Get player data
exports['cops-and-robbers']:GetPlayerData()

-- Check team
exports['cops-and-robbers']:IsPlayerCop()
exports['cops-and-robbers']:IsPlayerRobber()

-- UI functions
exports['cops-and-robbers']:ShowNotification(message, type)
exports['cops-and-robbers']:ShowHelpText(message)
```

### Server Exports

```lua
-- Player management
exports['cops-and-robbers']:GetPlayerFromId(source)
exports['cops-and-robbers']:GetPlayerFromIdentifier(identifier)

-- Economy
exports['cops-and-robbers']:AddMoney(source, amount)
exports['cops-and-robbers']:RemoveMoney(source, amount)

-- Statistics
exports['cops-and-robbers']:GetServerStats()
```

## Callbacks

### Client Callbacks

```lua
CR.TriggerServerCallback('cr:checkBalance', function(cash, bank)
    -- Handle response
end)

CR.TriggerServerCallback('cr:canRobLocation', function(canRob)
    if canRob then
        -- Start robbery
    end
end, locationId)
```

### Server Callbacks

```lua
CR.RegisterServerCallback('cr:checkBalance', function(source, cb)
    local player = CR.GetPlayer(source)
    cb(player:getMoney(), player:getBank())
end)

CR.RegisterServerCallback('cr:canRobLocation', function(source, cb, locationId)
    local canRob = CR.CanRobLocation(locationId)
    cb(canRob)
end)
```

## Database Queries

### Async Queries

```lua
-- Fetch player data
MySQL.Async.fetchAll('SELECT * FROM players WHERE identifier = @identifier', {
    ['@identifier'] = identifier
}, function(result)
    -- Process result
end)

-- Update player money
MySQL.Async.execute('UPDATE players SET cash = @cash WHERE id = @id', {
    ['@cash'] = amount,
    ['@id'] = playerId
})
```

### Sync Queries

```lua
-- Get player by ID (use sparingly)
local result = MySQL.Sync.fetchScalar('SELECT name FROM players WHERE id = @id', {
    ['@id'] = playerId
})
```

## Webhook Integration

```lua
function CR.SendWebhook(webhook, title, description, color)
    PerformHttpRequest(webhook, function(err, text, headers) end, 'POST', json.encode({
        embeds = {{
            title = title,
            description = description,
            color = color,
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
        }}
    }), {['Content-Type'] = 'application/json'})
end
```

## Performance Tips

1. Use callbacks instead of constant polling
2. Batch database operations when possible
3. Cache frequently accessed data
4. Use events sparingly for high-frequency updates
5. Optimize loops and avoid nested loops
6. Clean up event handlers when not needed