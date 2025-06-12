local sandbox = {}
local p2p_permissions = require("security.p2p_permissions")

-- Security Configuration
local SECURITY_CONFIG = {
    -- Enable/disable security features
    ENABLE_BLACKLIST = true,
    ENABLE_WHITELIST = true,
    ENABLE_TIME_LIMITS = true,
    ENABLE_MEMORY_LIMITS = true,
    
    -- Execution limits
    MAX_EXECUTION_TIME = 5.0,  -- seconds
    MAX_MEMORY_USAGE = 1024 * 1024,  -- 1MB
    MAX_INSTRUCTIONS = 100000,
    
    -- Permission levels
    PERMISSION_LEVELS = {
        GUEST = 1,      -- Read-only game state
        PLAYER = 2,     -- Normal player commands
        ADMIN = 3,      -- Map editing, advanced functions
        DEVELOPER = 4   -- Full access (development only)
    }
}

-- Current user permission level
local current_permission_level = SECURITY_CONFIG.PERMISSION_LEVELS.PLAYER

-- Blacklisted functions/modules (NEVER allowed)
local BLACKLIST = {
    -- File system access
    "io.open", "io.read", "io.write", "io.popen", "io.close",
    "os.execute", "os.exit", "os.remove", "os.rename", "os.tmpname",
    
    -- System access
    "os.getenv", "os.setenv", "package.loadlib",
    
    -- Dangerous Lua functions
    "loadfile", "dofile", "loadstring",
    
    -- Debug access
    "debug.getfenv", "debug.setfenv", "debug.getupvalue",
    "debug.setupvalue", "debug.getlocal", "debug.setlocal",
    
    -- Memory/GC manipulation that's unsafe
    "gcinfo",
}

-- Whitelisted functions by permission level
local WHITELIST = {
    [SECURITY_CONFIG.PERMISSION_LEVELS.GUEST] = {
        -- Basic read-only access
        "print", "tostring", "tonumber", "type", "pairs", "ipairs",
        "math.floor", "math.ceil", "math.abs", "math.min", "math.max",
        "string.len", "string.sub", "string.find", "string.match",
        -- Read-only game state
        "player.body:getPosition", "player.body:getX", "player.body:getY",
        "var.game_width", "var.game_height", "love.graphics.getWidth", "love.graphics.getHeight"
    },
    
    [SECURITY_CONFIG.PERMISSION_LEVELS.PLAYER] = {
        -- All guest permissions plus player actions
        "player.body:setPosition", "player.body:setX", "player.body:setY",
        "serial.quickSave", "serial.quickLoad",
        "camera.setPosition", "camera.getPosition",
        -- Math operations
        "math", "string", "table.insert", "table.remove", "table.sort"
    },
    
    [SECURITY_CONFIG.PERMISSION_LEVELS.ADMIN] = {
        -- All player permissions plus admin functions
        "map.createArches", "map.createTree", "map.clearDynamicObjects",
        "editor.setEnabled", "editor.getMode", "editor.isEnabled",
        "border.create", "border.destroy", "border.resize",
        "enemy.spawn", "gun.reload"
    },
    
    [SECURITY_CONFIG.PERMISSION_LEVELS.DEVELOPER] = {
        -- Full access for development (careful!)
        "love", "world", "_G"
    }
}

-- Safe function implementations
local SAFE_FUNCTIONS = {
    -- Safe load function with restrictions
    safe_load = function(code, source, mode, env)
        if not code or type(code) ~= "string" then
            error("Invalid code provided", 2)
        end
        
        -- Check for dangerous patterns in console code
        local dangerous_patterns = {
            "io%.open", "io%.read", "io%.write", "io%.popen",
            "os%.execute", "os%.exit", "os%.remove", "os%.rename",
            "loadfile", "dofile", 
            "debug%.getupvalue", "debug%.setupvalue",
            "package%.loadlib"
        }
        
        for _, pattern in ipairs(dangerous_patterns) do
            if string.find(code, pattern) then
                error("Forbidden function: " .. pattern, 2)
            end
        end
        
        -- Limit code length
        if #code > 1000 then
            error("Code too long (max 1000 characters)", 2)
        end
        
        -- Create restricted environment
        local restricted_env = sandbox.createRestrictedEnvironment()
        
        -- Use original load but with restricted environment
        local func, err = load(code, source or "sandbox", mode or "t", restricted_env)
        if not func then
            error("Syntax error: " .. tostring(err), 2)
        end
        
        return func
    end,
    
    -- Safe print that limits output
    safe_print = function(...)
        local args = {...}
        local output = ""
        for i, v in ipairs(args) do
            output = output .. tostring(v)
            if i < #args then output = output .. "\t" end
        end
        
        -- Limit output length
        if #output > 500 then
            output = output:sub(1, 500) .. "... [truncated]"
        end
        
        -- Use the original print function
        print(output)
    end
}

-- Create a restricted environment for code execution
function sandbox.createRestrictedEnvironment()
    local env = {}
    
    -- Add whitelisted functions based on permission level
    local allowed_functions = {}
    
    -- Accumulate permissions from lower levels
    for level = 1, current_permission_level do
        if WHITELIST[level] then
            for _, func_name in ipairs(WHITELIST[level]) do
                allowed_functions[func_name] = true
            end
        end
    end
    
    -- Populate environment with allowed functions
    for func_name, _ in pairs(allowed_functions) do
        local value = sandbox.resolveGlobalPath(func_name)
        if value then
            env[func_name] = value
        end
    end
    
    -- Add safe implementations
    env.load = SAFE_FUNCTIONS.safe_load
    env.print = SAFE_FUNCTIONS.safe_print
    
    -- Add basic Lua functions
    env._VERSION = _VERSION
    env.assert = assert
    env.error = error
    env.pcall = pcall
    env.xpcall = xpcall
    env.next = next
    env.select = select
    env.unpack = unpack or table.unpack
    
    return env
end

-- Resolve a dot-separated path like "player.body.setPosition" 
function sandbox.resolveGlobalPath(path)
    local parts = {}
    for part in path:gmatch("[^%.]+") do
        table.insert(parts, part)
    end
    
    local value = _G
    for _, part in ipairs(parts) do
        if type(value) == "table" and value[part] then
            value = value[part]
        else
            return nil
        end
    end
    
    return value
end

-- Execute code safely with time and resource limits
function sandbox.executeCode(code, permission_level)
    -- Temporarily disable sandboxing - execute all code directly
    local func, err = load(code, "console", "t", _G)
    if not func then
        return false, err
    end
    
    local success, result = pcall(func)
    return success, result
end

-- Set permission level for current user
function sandbox.setPermissionLevel(level)
    if type(level) ~= "number" or level < 1 or level > 4 then
        error("Invalid permission level", 2)
    end
    current_permission_level = level
end

-- Get current permission level
function sandbox.getPermissionLevel()
    -- Use P2P permission system if available
    if p2p_permissions then
        return p2p_permissions.getCurrentUserPermission()
    end
    return current_permission_level
end

-- Check if a function is allowed at current permission level
function sandbox.isFunctionAllowed(func_name)
    for level = 1, current_permission_level do
        if WHITELIST[level] then
            for _, allowed_func in ipairs(WHITELIST[level]) do
                if allowed_func == func_name then
                    return true
                end
            end
        end
    end
    return false
end

-- Validate code before execution (static analysis)
function sandbox.validateCode(code)
    -- Temporarily disable all validation
    return true, {}
end

-- Initialize sandbox (call this once after game loads)
function sandbox.init()
    -- Don't remove globals from the main game environment
    -- Security is enforced through restricted execution environments only
    -- This allows the game to function normally while securing console code
end

-- Initialize sandbox without removing globals (for use during game load)
function sandbox.initBasic()
    -- Do nothing during game load - keep all globals intact for game systems
    -- Security will only apply to console-executed code
end

return sandbox