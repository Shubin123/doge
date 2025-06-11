-- Logger utility for unified error/info output
-- Writes to 'logs/game.log' via love.filesystem and provides console color mapping

local logger = {}

-- Log levels
logger.levels = {
    info = "INFO",
    warn = "WARN", 
    error = "ERROR"
}

-- Console color mapping for cmndX
logger.consoleColours = {
    info = {0.8, 0.8, 0.8, 1},    -- Light gray
    warn = {1, 0.8, 0, 1},        -- Orange/yellow
    error = {1, 0.3, 0.3, 1}      -- Red
}

-- Ensure logs directory exists
local function ensureLogDirectory()
    local info = love.filesystem.getInfo("logs")
    if not info then
        love.filesystem.createDirectory("logs")
    end
end

-- Format timestamp for log entries
local function getTimestamp()
    return os.date("%Y-%m-%d %H:%M:%S")
end

-- Main logging function
-- @param level string - "info", "warn", or "error"
-- @param msg string - message to log
-- @return string - formatted log message
function logger.log(level, msg)
    level = level or "info"
    msg = msg or ""
    
    -- Validate level
    if not logger.levels[level] then
        level = "info"
    end
    
    -- Format the log message
    local timestamp = getTimestamp()
    local levelStr = logger.levels[level]
    local formattedMsg = string.format("[%s] %s: %s", timestamp, levelStr, msg)
    
    -- Ensure log directory exists
    ensureLogDirectory()
    
    -- Write to log file
    local success, err = pcall(function()
        love.filesystem.append("logs/game.log", formattedMsg .. "\n")
    end)
    
    -- If logging fails, at least return the formatted message
    if not success then
        print("Logger error:", err)
    end
    
    return formattedMsg
end

-- Convenience functions for different log levels
function logger.info(msg)
    return logger.log("info", msg)
end

function logger.warn(msg)
    return logger.log("warn", msg)
end

function logger.error(msg)
    return logger.log("error", msg)
end

return logger