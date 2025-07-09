-- performance_optimizer.lua
-- Performance optimization utilities and monitoring for the CNR game mode
-- Version: 1.2.0

-- Ensure Constants are loaded
if not Constants then
    error("Constants must be loaded before performance_optimizer.lua")
end

-- Initialize PerformanceOptimizer module
PerformanceOptimizer = PerformanceOptimizer or {}

-- Utility function to get table length (for tables with non-numeric keys)
local function tablelength(T)
    if not T or type(T) ~= "table" then return 0 end
    local count = 0
    for _ in pairs(T) do count = count + 1 end
    return count
end

-- Performance monitoring data
local performanceMetrics = {
    frameTime = 0,
    memoryUsage = 0,
    activeThreads = 0,
    networkEvents = 0,
    lastUpdate = 0
}

-- Optimized loop management
local optimizedLoops = {}
local loopCounter = 0

-- Event batching system
local eventBatches = {}
local batchTimers = {}

-- ====================================================================
-- LOOP OPTIMIZATION SYSTEM
-- ====================================================================

--- Adjust loop interval based on performance metrics
--- @param loopData table Loop data structure
--- @param lastExecutionTime number Last execution time in milliseconds
local function AdjustLoopInterval(loopData, lastExecutionTime)
    -- If execution time is high, increase interval
    if lastExecutionTime > Constants.PERFORMANCE.MAX_EXECUTION_TIME_MS then
        loopData.currentInterval = math.min(loopData.currentInterval * 1.2, loopData.maxInterval)
    -- If execution time is low and we're not at base interval, decrease it
    elseif lastExecutionTime < Constants.PERFORMANCE.MAX_EXECUTION_TIME_MS * 0.5 and 
           loopData.currentInterval > loopData.baseInterval then
        loopData.currentInterval = math.max(loopData.currentInterval * 0.9, loopData.baseInterval)
    end
    
    -- Priority-based adjustments
    if loopData.priority <= 2 then
        -- High priority loops get preference
        loopData.currentInterval = math.max(loopData.currentInterval * 0.8, loopData.baseInterval)
    elseif loopData.priority >= 4 then
        -- Low priority loops get throttled more aggressively
        loopData.currentInterval = math.min(loopData.currentInterval * 1.5, loopData.maxInterval)
    end
end

--- Create an optimized loop that automatically adjusts its interval based on performance
--- @param callback function Function to execute
--- @param baseInterval number Base interval in milliseconds
--- @param maxInterval number Maximum interval in milliseconds
--- @param priority number Priority level (1-5, 1 being highest)
--- @return number Loop ID for management
function PerformanceOptimizer.CreateOptimizedLoop(callback, baseInterval, maxInterval, priority)
    loopCounter = loopCounter + 1
    priority = priority or 3
    maxInterval = maxInterval or baseInterval * 5
    
    local loopData = {
        id = loopCounter,
        callback = callback,
        baseInterval = baseInterval,
        maxInterval = maxInterval,
        currentInterval = baseInterval,
        priority = priority,
        lastExecution = 0,
        executionCount = 0,
        totalExecutionTime = 0,
        averageExecutionTime = 0,
        active = true
    }
    
    optimizedLoops[loopCounter] = loopData
    
    -- Start the loop thread
    Citizen.CreateThread(function()
        while loopData.active do
            local startTime = GetGameTimer()
            
            -- Execute callback with error handling
            local success, error = pcall(callback)
            if not success then
                print(string.format("[CNR_PERFORMANCE] Loop %d error: %s", loopData.id, tostring(error)))
            end
            
            -- Update performance metrics
            local executionTime = GetGameTimer() - startTime
            loopData.executionCount = loopData.executionCount + 1
            loopData.totalExecutionTime = loopData.totalExecutionTime + executionTime
            loopData.averageExecutionTime = loopData.totalExecutionTime / loopData.executionCount
            loopData.lastExecution = startTime
            
            -- Adjust interval based on performance
            AdjustLoopInterval(loopData, executionTime)
            
            Citizen.Wait(loopData.currentInterval)
        end
    end)
    
    print(string.format("[CNR_PERFORMANCE] Created optimized loop %d (base: %dms, max: %dms, priority: %d)", 
        loopCounter, baseInterval, maxInterval, priority))
    
    return loopCounter
end

--- Stop an optimized loop
--- @param loopId number Loop ID to stop
function PerformanceOptimizer.StopOptimizedLoop(loopId)
    if optimizedLoops[loopId] then
        optimizedLoops[loopId].active = false
        optimizedLoops[loopId] = nil
        print(string.format("[CNR_PERFORMANCE] Stopped optimized loop %d", loopId))
    end
end

-- ====================================================================
-- EVENT BATCHING SYSTEM
-- ====================================================================

--- Batch events to reduce network overhead
--- @param eventName string Event name
--- @param playerId number Player ID (or -1 for all players)
--- @param data any Event data
--- @param batchInterval number Batching interval in milliseconds
function PerformanceOptimizer.BatchEvent(eventName, playerId, data, batchInterval)
    batchInterval = batchInterval or 100 -- Default 100ms batching
    
    local batchKey = string.format("%s_%s", eventName, tostring(playerId))
    
    -- Initialize batch if it doesn't exist
    if not eventBatches[batchKey] then
        eventBatches[batchKey] = {
            eventName = eventName,
            playerId = playerId,
            data = {},
            count = 0
        }
    end
    
    -- Add data to batch
    table.insert(eventBatches[batchKey].data, data)
    eventBatches[batchKey].count = eventBatches[batchKey].count + 1
    
    -- Set timer if not already set
    if not batchTimers[batchKey] then
        batchTimers[batchKey] = Citizen.SetTimeout(batchInterval, function()
            PerformanceOptimizer.FlushEventBatch(batchKey)
        end)
    end
end

--- Flush a specific event batch
--- @param batchKey string Batch key
function PerformanceOptimizer.FlushEventBatch(batchKey)
    local batch = eventBatches[batchKey]
    if not batch or batch.count == 0 then
        return
    end
    
    -- Send batched event
    if batch.playerId == -1 then
        -- Send to all players
        TriggerClientEvent(batch.eventName, -1, batch.data)
    else
        -- Send to specific player
        TriggerClientEvent(batch.eventName, batch.playerId, batch.data)
    end
    
    -- Clean up
    eventBatches[batchKey] = nil
    batchTimers[batchKey] = nil
    
    print(string.format("[CNR_PERFORMANCE] Flushed batch %s with %d events", batchKey, batch.count))
end

--- Flush all event batches immediately
function PerformanceOptimizer.FlushAllBatches()
    for batchKey, _ in pairs(eventBatches) do
        PerformanceOptimizer.FlushEventBatch(batchKey)
    end
end

-- ====================================================================
-- MEMORY OPTIMIZATION
-- ====================================================================

--- Optimize table memory usage by removing nil values and compacting
--- @param tbl table Table to optimize
--- @return table Optimized table
function PerformanceOptimizer.OptimizeTable(tbl)
    if type(tbl) ~= "table" then
        return tbl
    end
    
    local optimized = {}
    for k, v in pairs(tbl) do
        if v ~= nil then
            if type(v) == "table" then
                optimized[k] = PerformanceOptimizer.OptimizeTable(v)
            else
                optimized[k] = v
            end
        end
    end
    
    return optimized
end

--- Clean up unused references and force garbage collection
function PerformanceOptimizer.CleanupMemory()
    -- Clean up optimized loops that are no longer active
    for loopId, loopData in pairs(optimizedLoops) do
        if not loopData.active then
            optimizedLoops[loopId] = nil
        end
    end
    
    -- Clean up old event batches
    local currentTime = GetGameTimer()
    for batchKey, timer in pairs(batchTimers) do
        if currentTime - timer > 5000 then -- 5 second timeout
            eventBatches[batchKey] = nil
            batchTimers[batchKey] = nil
        end
    end
    
    -- Force garbage collection
    collectgarbage("collect")
    
    print("[CNR_PERFORMANCE] Memory cleanup completed")
end

-- ====================================================================
-- PERFORMANCE MONITORING
-- ====================================================================

--- Update performance metrics
local function UpdatePerformanceMetrics()
    performanceMetrics.lastUpdate = GetGameTimer()
    performanceMetrics.activeThreads = tablelength(optimizedLoops)
    
    -- Calculate memory usage (approximation)
    local memBefore = collectgarbage("count")
    collectgarbage("collect")
    local memAfter = collectgarbage("count")
    performanceMetrics.memoryUsage = memAfter
    
    -- Restore memory state
    collectgarbage("restart")
end

--- Get current performance metrics
--- @return table Performance metrics
function PerformanceOptimizer.GetMetrics()
    UpdatePerformanceMetrics()
    return {
        frameTime = performanceMetrics.frameTime,
        memoryUsage = performanceMetrics.memoryUsage,
        activeThreads = performanceMetrics.activeThreads,
        networkEvents = performanceMetrics.networkEvents,
        lastUpdate = performanceMetrics.lastUpdate,
        optimizedLoops = tablelength(optimizedLoops),
        eventBatches = tablelength(eventBatches)
    }
end

--- Log performance statistics
function PerformanceOptimizer.LogStats()
    local metrics = PerformanceOptimizer.GetMetrics()
    print(string.format("[CNR_PERFORMANCE] Stats - Memory: %.1fKB, Threads: %d, Loops: %d, Batches: %d",
        metrics.memoryUsage, metrics.activeThreads, metrics.optimizedLoops, metrics.eventBatches))
    
    -- Log individual loop performance
    for loopId, loopData in pairs(optimizedLoops) do
        if loopData.executionCount > 0 then
            print(string.format("[CNR_PERFORMANCE] Loop %d - Avg: %.1fms, Count: %d, Interval: %dms",
                loopId, loopData.averageExecutionTime, loopData.executionCount, loopData.currentInterval))
        end
    end
end

--- Check for performance warnings
function PerformanceOptimizer.CheckPerformanceWarnings()
    local metrics = PerformanceOptimizer.GetMetrics()
    
    -- Memory warning
    if metrics.memoryUsage > Constants.PERFORMANCE.MEMORY_WARNING_THRESHOLD_MB * 1024 then
        print(string.format("[CNR_PERFORMANCE] WARNING: High memory usage: %.1fMB", 
            metrics.memoryUsage / 1024))
        PerformanceOptimizer.CleanupMemory()
    end
    
    -- Loop performance warnings
    for loopId, loopData in pairs(optimizedLoops) do
        if loopData.averageExecutionTime > Constants.PERFORMANCE.MAX_EXECUTION_TIME_MS then
            print(string.format("[CNR_PERFORMANCE] WARNING: Loop %d slow execution: %.1fms average",
                loopId, loopData.averageExecutionTime))
        end
    end
end

-- ====================================================================
-- OPTIMIZED REPLACEMENTS FOR COMMON PATTERNS
-- ====================================================================

--- Optimized player iteration with early exit and batching
--- @param callback function Function to call for each player
--- @param batchSize number Number of players to process per frame
function PerformanceOptimizer.ForEachPlayerOptimized(callback, batchSize)
    batchSize = batchSize or 10
    local players = GetPlayers()
    local currentBatch = 0
    
    Citizen.CreateThread(function()
        for i, playerId in ipairs(players) do
            -- Validate player is still online
            if GetPlayerName(playerId) then
                local success, error = pcall(callback, tonumber(playerId))
                if not success then
                    print(string.format("[CNR_PERFORMANCE] Player iteration error for %s: %s", 
                        playerId, tostring(error)))
                end
            end
            
            currentBatch = currentBatch + 1
            
            -- Yield every batchSize players to prevent frame drops
            if currentBatch >= batchSize then
                currentBatch = 0
                Citizen.Wait(0)
            end
        end
    end)
end

--- Optimized distance checking with caching
local distanceCache = {}
local distanceCacheTime = {}

function PerformanceOptimizer.GetDistanceCached(pos1, pos2, cacheTime)
    cacheTime = cacheTime or 1000 -- 1 second cache by default
    
    local cacheKey = string.format("%.1f_%.1f_%.1f_%.1f_%.1f_%.1f", 
        pos1.x, pos1.y, pos1.z, pos2.x, pos2.y, pos2.z)
    
    local currentTime = GetGameTimer()
    
    -- Check cache
    if distanceCache[cacheKey] and 
       distanceCacheTime[cacheKey] and 
       (currentTime - distanceCacheTime[cacheKey]) < cacheTime then
        return distanceCache[cacheKey]
    end
    
    -- Calculate distance
    local distance = #(pos1 - pos2)
    
    -- Cache result
    distanceCache[cacheKey] = distance
    distanceCacheTime[cacheKey] = currentTime
    
    return distance
end

--- Clean distance cache periodically
local function CleanDistanceCache()
    local currentTime = GetGameTimer()
    local cleanupThreshold = 5000 -- 5 seconds
    
    for cacheKey, cacheTime in pairs(distanceCacheTime) do
        if (currentTime - cacheTime) > cleanupThreshold then
            distanceCache[cacheKey] = nil
            distanceCacheTime[cacheKey] = nil
        end
    end
end

-- ====================================================================
-- INITIALIZATION AND CLEANUP
-- ====================================================================

--- Initialize performance optimizer
function PerformanceOptimizer.Initialize()
    print("[CNR_PERFORMANCE] Performance Optimizer initialized")
    
    -- Create monitoring loop
    PerformanceOptimizer.CreateOptimizedLoop(function()
        PerformanceOptimizer.CheckPerformanceWarnings()
    end, 30000, 60000, 4) -- Low priority, 30s base interval
    
    -- Create cleanup loop
    PerformanceOptimizer.CreateOptimizedLoop(function()
        PerformanceOptimizer.CleanupMemory()
        CleanDistanceCache()
    end, 60000, 120000, 5) -- Lowest priority, 1 minute base interval
    
    -- Create stats logging loop
    PerformanceOptimizer.CreateOptimizedLoop(function()
        PerformanceOptimizer.LogStats()
    end, 300000, 600000, 5) -- Lowest priority, 5 minute base interval
end

--- Cleanup on resource stop
function PerformanceOptimizer.Cleanup()
    print("[CNR_PERFORMANCE] Cleaning up performance optimizer...")
    
    -- Stop all optimized loops
    for loopId, _ in pairs(optimizedLoops) do
        PerformanceOptimizer.StopOptimizedLoop(loopId)
    end
    
    -- Flush all event batches
    PerformanceOptimizer.FlushAllBatches()
    
    -- Final memory cleanup
    PerformanceOptimizer.CleanupMemory()
    
    print("[CNR_PERFORMANCE] Performance optimizer cleanup completed")
end

-- Initialize when loaded
PerformanceOptimizer.Initialize()

-- PerformanceOptimizer module is now available globally