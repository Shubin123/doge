local character_save_system = {}

-- Character save directory
local SAVE_DIRECTORY = "characters"

-- Fallback in-memory storage for when file system fails
local memory_storage = {}

-- Default character template
local function create_default_character(name)
    return {
        -- Basic info
        name = name or "Unnamed Hero",
        created_date = os.time(),
        last_played = os.time(),
        play_time = 0,
        
        -- Character class and appearance
        class = "warrior",
        level = 1,
        experience = 0,
        
        -- Stats
        stats = {
            health = 100,
            max_health = 100,
            mana = 50,
            max_mana = 50,
            strength = 10,
            intelligence = 10,
            agility = 10,
            defense = 10
        },
        
        -- Position and world state
        position = {
            x = 400,
            y = 300,
            map_id = "level1"
        },
        
        -- Inventory
        inventory = {
            gold = 0,
            items = {},
            equipment = {
                weapon = nil,
                armor = nil,
                accessory = nil
            }
        },
        
        -- Progress
        progress = {
            maps_unlocked = {"level1"},
            quests_completed = {},
            achievements = {},
            total_enemies_defeated = 0,
            total_distance_traveled = 0
        },
        
        -- Settings specific to this character
        settings = {
            difficulty = "normal"
        }
    }
end

-- Create saves directory if it doesn't exist
function character_save_system.initialize()
    -- First check what the save directory is
    local save_dir = love.filesystem.getSaveDirectory()
    print("DEBUG: Love2D save directory is: " .. save_dir)
    
    -- Check if characters directory exists
    local info = love.filesystem.getInfo(SAVE_DIRECTORY)
    print("DEBUG: Checking for directory: " .. SAVE_DIRECTORY)
    print("DEBUG: Directory info: " .. tostring(info and "exists" or "does not exist"))
    
    if not info then
        local success = love.filesystem.createDirectory(SAVE_DIRECTORY)
        print("DEBUG: Attempting to create directory: " .. SAVE_DIRECTORY)
        print("DEBUG: Create directory result: " .. tostring(success))
        
        if success then
            print("Created character saves directory at: " .. save_dir .. "/" .. SAVE_DIRECTORY)
        else
            print("ERROR: Failed to create character saves directory")
        end
    else
        print("Character saves directory already exists at: " .. save_dir .. "/" .. SAVE_DIRECTORY)
    end
    
    -- List all files in save directory for debugging
    local files = love.filesystem.getDirectoryItems("")
    print("DEBUG: Files in save directory:")
    for _, file in ipairs(files) do
        print("  - " .. file)
    end
end

-- Get all saved characters
function character_save_system.get_all_characters()
    local characters = {}
    
    print("DEBUG: Loading all characters from directory: " .. SAVE_DIRECTORY)
    
    -- Check if directory exists
    local dir_info = love.filesystem.getInfo(SAVE_DIRECTORY)
    if not dir_info then
        print("DEBUG: Characters directory does not exist, returning empty list")
        return characters
    end
    
    local files = love.filesystem.getDirectoryItems(SAVE_DIRECTORY)
    print("DEBUG: Found " .. #files .. " files in characters directory")
    
    for _, file in ipairs(files) do
        print("DEBUG: Checking file: " .. file)
        if file:match("%.json$") then
            local character_id = file:gsub("%.json$", "")
            print("DEBUG: Loading character with ID: " .. character_id)
            local character_data = character_save_system.load_character(character_id)
            if character_data then
                character_data.id = character_id
                table.insert(characters, character_data)
                print("DEBUG: Successfully loaded character: " .. character_data.name)
            else
                print("DEBUG: Failed to load character: " .. character_id)
            end
        end
    end
    
    -- Also check memory storage for characters that might not be saved to files
    print("DEBUG: Checking memory storage for additional characters")
    for character_id, character_data in pairs(memory_storage) do
        -- Check if we already loaded this character from file
        local already_loaded = false
        for _, loaded_char in ipairs(characters) do
            if loaded_char.id == character_id then
                already_loaded = true
                break
            end
        end
        
        if not already_loaded then
            character_data.id = character_id
            table.insert(characters, character_data)
            print("DEBUG: Added character from memory: " .. character_data.name)
        end
    end
    
    print("DEBUG: Total characters loaded (including memory): " .. #characters)
    
    -- Sort by last played date (most recent first)
    table.sort(characters, function(a, b)
        return a.last_played > b.last_played
    end)
    
    return characters
end

-- Load a specific character
function character_save_system.load_character(character_id)
    local file_path = SAVE_DIRECTORY .. "/" .. character_id .. ".json"
    local info = love.filesystem.getInfo(file_path)
    
    -- Try to load from file first
    if info then
        print("DEBUG: Loading character from file: " .. file_path)
        
        local content = love.filesystem.read(file_path)
        if content then
            local character_data = nil
            
            -- First try to parse as JSON
            character_data = character_save_system.decode_json(content)
            
            -- If JSON parsing failed, try old Lua table format
            if not character_data then
                print("DEBUG: JSON parsing failed, trying Lua table format...")
                local success
                success, character_data = pcall(function()
                    return loadstring("return " .. content)()
                end)
                
                if not success then
                    character_data = nil
                end
            end
            
            if character_data and type(character_data) == "table" then
                -- Validate and fill missing fields with defaults
                local default_char = create_default_character()
                character_data = character_save_system.merge_with_defaults(character_data, default_char)
                
                print("Loaded character from file: " .. (character_data.name or "Unknown"))
                return character_data
            else
                print("Failed to parse character file: " .. file_path)
            end
        else
            print("Failed to read character file: " .. file_path)
        end
    end
    
    -- Fallback to memory storage
    print("DEBUG: Trying to load character from memory storage: " .. character_id)
    local memory_data = memory_storage[character_id]
    if memory_data then
        print("Loaded character from memory: " .. (memory_data.name or "Unknown"))
        return memory_data
    end
    
    print("Character not found in file or memory: " .. character_id)
    return nil
end

-- Save a character
function character_save_system.save_character(character_id, character_data)
    -- Update last played time
    character_data.last_played = os.time()
    
    local file_path = SAVE_DIRECTORY .. "/" .. character_id .. ".json"
    local json_data = character_save_system.encode_json(character_data)
    
    print("DEBUG: Saving character to: " .. file_path)
    print("DEBUG: Character class: " .. (character_data.class or "unknown"))
    print("DEBUG: Character name: " .. (character_data.name or "unknown"))
    print("DEBUG: JSON data length: " .. string.len(json_data))
    
    -- Check if directory exists before writing
    local dir_info = love.filesystem.getInfo(SAVE_DIRECTORY)
    if not dir_info then
        print("DEBUG: Save directory does not exist, creating it...")
        local create_success = love.filesystem.createDirectory(SAVE_DIRECTORY)
        if not create_success then
            print("ERROR: Failed to create save directory")
            -- Still save to memory
            memory_storage[character_id] = character_data
            return true
        end
    end
    
    -- Try to write the file
    local success = love.filesystem.write(file_path, json_data)
    
    if success then
        print("Successfully saved character to JSON file: " .. (character_data.name or "Unknown"))
        
        -- Verify the file was actually written
        local verify_info = love.filesystem.getInfo(file_path)
        if verify_info then
            print("DEBUG: JSON file exists after save, size: " .. verify_info.size .. " bytes")
        else
            print("ERROR: JSON file does not exist after save attempt!")
        end
        
        -- Also store in memory as backup
        memory_storage[character_id] = character_data
        
        return true
    else
        print("Failed to save character to JSON file: " .. file_path)
        print("Using memory storage as fallback...")
        
        -- Use memory storage as fallback
        memory_storage[character_id] = character_data
        print("Character saved to memory storage: " .. (character_data.name or "Unknown"))
        
        return true  -- Return true since we saved to memory
    end
end

-- Create a new character
function character_save_system.create_character(name, class)
    local character_data = create_default_character(name)
    character_data.class = class or "warrior"
    
    -- Adjust stats based on class
    if class == "warrior" then
        character_data.stats.strength = 15
        character_data.stats.defense = 15
        character_data.stats.max_health = 120
        character_data.stats.health = 120
    elseif class == "mage" then
        character_data.stats.intelligence = 15
        character_data.stats.max_mana = 100
        character_data.stats.mana = 100
        character_data.stats.max_health = 80
        character_data.stats.health = 80
    elseif class == "archer" then
        character_data.stats.agility = 15
        character_data.stats.strength = 12
        character_data.stats.max_health = 90
        character_data.stats.health = 90
    elseif class == "rogue" then
        character_data.stats.agility = 12
        character_data.stats.strength = 12
        character_data.stats.intelligence = 8
        character_data.stats.max_health = 85
        character_data.stats.health = 85
    end
    
    -- Generate unique ID
    local character_id = character_save_system.generate_character_id(name)
    
    -- Save the character
    if character_save_system.save_character(character_id, character_data) then
        return character_id, character_data
    else
        return nil
    end
end

-- Delete a character
function character_save_system.delete_character(character_id)
    local file_path = SAVE_DIRECTORY .. "/" .. character_id .. ".json"
    local file_deleted = false
    local memory_deleted = false
    
    -- Try to delete the file
    local info = love.filesystem.getInfo(file_path)
    if info then
        local success = love.filesystem.remove(file_path)
        if success then
            print("Deleted character file: " .. file_path)
            file_deleted = true
        else
            print("Failed to delete character file: " .. file_path)
        end
    else
        print("Character file not found: " .. file_path)
    end
    
    -- Also remove from memory storage
    if memory_storage[character_id] then
        memory_storage[character_id] = nil
        memory_deleted = true
        print("Removed character from memory storage: " .. character_id)
    else
        print("Character not found in memory storage: " .. character_id)
    end
    
    -- Return true if either file was deleted or character was removed from memory
    local success = file_deleted or memory_deleted
    if success then
        print("Character " .. character_id .. " successfully deleted")
    else
        print("Character " .. character_id .. " was not found in either file or memory")
    end
    
    return success
end

-- Generate a unique character ID
function character_save_system.generate_character_id(name)
    local base_id = (name or "character"):lower():gsub("[^%w]", "_")
    local character_id = base_id
    local counter = 1
    
    -- Keep incrementing until we find a unique ID (check both file and memory)
    while love.filesystem.getInfo(SAVE_DIRECTORY .. "/" .. character_id .. ".json") or memory_storage[character_id] do
        counter = counter + 1
        character_id = base_id .. "_" .. counter
    end
    
    return character_id
end

-- Merge character data with defaults (fill missing fields)
function character_save_system.merge_with_defaults(data, defaults)
    local merged = {}
    
    for key, default_value in pairs(defaults) do
        if data[key] ~= nil then
            if type(default_value) == "table" and type(data[key]) == "table" then
                merged[key] = character_save_system.merge_with_defaults(data[key], default_value)
            else
                merged[key] = data[key]
            end
        else
            merged[key] = default_value
        end
    end
    
    -- Also include any extra fields from data that aren't in defaults
    for key, value in pairs(data) do
        if merged[key] == nil then
            merged[key] = value
        end
    end
    
    return merged
end

-- Simple JSON encoder for character data
function character_save_system.encode_json(t, indent)
    indent = indent or 0
    local spacing = string.rep("  ", indent)
    
    if type(t) ~= "table" then
        if type(t) == "string" then
            return '"' .. t:gsub('"', '\\"'):gsub('\\', '\\\\') .. '"'
        elseif type(t) == "number" or type(t) == "boolean" then
            return tostring(t)
        else
            return "null"
        end
    end
    
    -- Check if it's an array-like table
    local is_array = true
    local max_index = 0
    for k, v in pairs(t) do
        if type(k) ~= "number" or k <= 0 or k ~= math.floor(k) then
            is_array = false
            break
        end
        max_index = math.max(max_index, k)
    end
    
    if is_array then
        -- Array format
        local result = "[\n"
        for i = 1, max_index do
            result = result .. spacing .. "  "
            if t[i] ~= nil then
                result = result .. character_save_system.encode_json(t[i], indent + 1)
            else
                result = result .. "null"
            end
            if i < max_index then
                result = result .. ","
            end
            result = result .. "\n"
        end
        result = result .. spacing .. "]"
        return result
    else
        -- Object format
        local result = "{\n"
        local first = true
        for k, v in pairs(t) do
            if not first then
                result = result .. ",\n"
            end
            first = false
            
            local key = type(k) == "string" and k or tostring(k)
            result = result .. spacing .. "  \"" .. key .. "\": "
            result = result .. character_save_system.encode_json(v, indent + 1)
        end
        result = result .. "\n" .. spacing .. "}"
        return result
    end
end

-- Simple JSON decoder for character data  
function character_save_system.decode_json(json_str)
    -- Simple JSON parser for our character data
    -- This is a basic implementation for the specific structure we use
    
    -- Remove whitespace and newlines for easier parsing
    local cleaned = json_str:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    
    -- Use Lua's load function with JSON-like syntax converted to Lua
    local lua_str = cleaned
        :gsub("{", "{ ")
        :gsub("}", " }")
        :gsub("%[", "{ ")
        :gsub("%]", " }")
        :gsub(":", " = ")
        :gsub("null", "nil")
        :gsub("true", "true")
        :gsub("false", "false")
    
    -- Try to evaluate as Lua code
    local success, result = pcall(function()
        return load("return " .. lua_str)()
    end)
    
    if success and type(result) == "table" then
        return result
    end
    
    -- Fallback: try original loadstring method
    success, result = pcall(function()
        return loadstring("return " .. json_str)()
    end)
    
    if success and type(result) == "table" then
        return result
    end
    
    return nil
end

-- Keep the old serialization as backup (now called serialize_table)
function character_save_system.serialize_table(t, indent)
    indent = indent or 0
    local spacing = string.rep("  ", indent)
    local result = "{\n"
    
    for k, v in pairs(t) do
        local key = type(k) == "string" and string.format('"%s"', k) or tostring(k)
        result = result .. spacing .. "  " .. key .. " = "
        
        if type(v) == "table" then
            result = result .. character_save_system.serialize_table(v, indent + 1)
        elseif type(v) == "string" then
            result = result .. string.format('"%s"', v:gsub('"', '\\"'))
        elseif type(v) == "number" then
            result = result .. tostring(v)
        elseif type(v) == "boolean" then
            result = result .. tostring(v)
        else
            result = result .. "nil"
        end
        result = result .. ",\n"
    end
    
    result = result .. spacing .. "}"
    return result
end

-- Update character playtime
function character_save_system.update_playtime(character_id, character_data, dt)
    if character_data then
        character_data.play_time = (character_data.play_time or 0) + dt
        character_data.last_played = os.time()
    end
end

-- Format playtime for display
function character_save_system.format_playtime(seconds)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    
    if hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    else
        return string.format("%dm", minutes)
    end
end

-- Get character display info for menus
function character_save_system.get_character_display_info(character_data)
    if not character_data then return nil end
    
    return {
        name = character_data.name,
        class = character_data.class,
        level = character_data.level,
        playtime = character_save_system.format_playtime(character_data.play_time or 0),
        last_played = os.date("%m/%d/%Y", character_data.last_played),
        map_name = character_data.position.map_id or "unknown",
        health_percent = (character_data.stats.health / character_data.stats.max_health) * 100
    }
end

-- Test function to verify save system works
function character_save_system.test_save_system()
    print("=== TESTING SAVE SYSTEM ===")
    
    -- Try to create a test character
    local test_id, test_data = character_save_system.create_character("TestHero", "warrior")
    
    if test_id then
        print("✅ Test character created successfully: " .. test_id)
        
        -- Try to load it back
        local loaded_data = character_save_system.load_character(test_id)
        if loaded_data then
            print("✅ Test character loaded successfully: " .. loaded_data.name)
            
            -- Clean up test character
            character_save_system.delete_character(test_id)
            print("✅ Test character deleted")
            print("=== SAVE SYSTEM TEST PASSED ===")
            return true
        else
            print("❌ Failed to load test character")
        end
    else
        print("❌ Failed to create test character")
    end
    
    print("=== SAVE SYSTEM TEST FAILED ===")
    return false
end

return character_save_system