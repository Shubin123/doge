-- Game configuration module
local config = {}

-- Ensure save directory exists at startup
local function ensureSaveDirectory()
    local save_dir = "./saves/"
    
    -- Try to create directory (will fail silently if exists)
    local success = os.execute("mkdir -p " .. save_dir .. " 2>/dev/null")
    if not success then
        -- Try Windows command
        os.execute("mkdir " .. save_dir .. " 2>nul")
    end
    
    -- Test if we can write to the directory
    local test_file = save_dir .. ".test"
    local f = io.open(test_file, "w")
    if f then
        f:write("test")
        f:close()
        os.remove(test_file)
        return true
    else
        print("Warning: Cannot write to save directory!")
        return false
    end
end

-- Initialize configuration
function config.init()
    -- Ensure save directory exists
    local save_dir_ok = ensureSaveDirectory()
    
    -- Set up default configuration values
    config.save_directory_writable = save_dir_ok
    config.auto_save_enabled = save_dir_ok  -- Only enable auto-save if we can write
    config.auto_save_interval = 60  -- seconds
    
    return config
end

return config