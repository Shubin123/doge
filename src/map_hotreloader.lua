local map_hotreloader = {}
local map_manager = require("map_manager")
local map_serializer = require("map_serializer")
local map_loader = require("map_loader")

-- Hot-reload configuration
local hotreload_config = {
    enabled = true,
    watch_directory = "maps",
    check_interval = 1.0, -- Check every second
    auto_reload = true,    -- Automatically reload changed maps
    backup_on_reload = true -- Create backup before reloading
}

-- File watching state
local watched_files = {}
local last_check_time = 0

-- Initialize hot-reloader
function map_hotreloader.initialize()
    -- Ensure maps directory exists
    os.execute("mkdir -p " .. hotreload_config.watch_directory)
    
    -- Scan for existing map files
    map_hotreloader.scan_directory()
    
    print("Map hot-reloader initialized")
    print("Watching directory: " .. hotreload_config.watch_directory)
end

-- Scan directory for map files
function map_hotreloader.scan_directory()
    local new_files = {}
    
    -- Get list of .map files
    local handle = io.popen("find " .. hotreload_config.watch_directory .. " -name '*.map' 2>/dev/null")
    if handle then
        for file_path in handle:lines() do
            local stat_handle = io.popen("stat -c '%Y' '" .. file_path .. "' 2>/dev/null")
            if stat_handle then
                local mtime_str = stat_handle:read("*line")
                local mtime = tonumber(mtime_str)
                stat_handle:close()
                
                if mtime then
                    local file_name = file_path:match(".*/(.+)%.map$") or file_path:match("(.+)%.map$")
                    new_files[file_path] = {
                        name = file_name,
                        path = file_path,
                        last_modified = mtime,
                        loaded = false
                    }
                end
            end
        end
        handle:close()
    end
    
    -- Check for new or modified files
    local changes_detected = false
    for path, file_info in pairs(new_files) do
        local old_info = watched_files[path]
        if not old_info then
            print("New map file detected: " .. file_info.name)
            changes_detected = true
        elseif old_info.last_modified ~= file_info.last_modified then
            print("Map file modified: " .. file_info.name)
            changes_detected = true
            
            if hotreload_config.auto_reload then
                map_hotreloader.reload_map_file(path)
            end
        end
    end
    
    -- Check for deleted files
    for path, file_info in pairs(watched_files) do
        if not new_files[path] then
            print("Map file deleted: " .. file_info.name)
            changes_detected = true
        end
    end
    
    watched_files = new_files
    return changes_detected
end

-- Reload a specific map file
function map_hotreloader.reload_map_file(file_path)
    local file_info = watched_files[file_path]
    if not file_info then
        print("File not being watched: " .. file_path)
        return false
    end
    
    print("Reloading map file: " .. file_info.name)
    
    -- Create backup if enabled
    if hotreload_config.backup_on_reload then
        local backup_path = file_path .. ".backup." .. os.time()
        os.execute("cp '" .. file_path .. "' '" .. backup_path .. "'")
    end
    
    -- Load map data
    local loaded_data = map_serializer.load_map(file_path)
    if not loaded_data then
        print("Failed to reload map: " .. file_path)
        return false
    end
    
    -- Update map loader registry
    map_loader.register_map(loaded_data.definition)
    
    -- If this map is currently active, reload it
    local current_map_id = map_manager.get_current_map_id()
    if current_map_id == loaded_data.definition.id then
        print("Reloading active map: " .. current_map_id)
        
        -- Clear cache to force reload
        map_loader.cache_map(current_map_id, nil)
        
        -- Switch to reloaded map
        local reloaded_map = map_manager.loadMap(current_map_id)
        if reloaded_map then
            print("Successfully hot-reloaded map: " .. current_map_id)
        end
    end
    
    file_info.loaded = true
    return true
end

-- Update hot-reloader (call every frame)
function map_hotreloader.update(dt)
    if not hotreload_config.enabled then return end
    
    last_check_time = last_check_time + dt
    
    if last_check_time >= hotreload_config.check_interval then
        last_check_time = 0
        map_hotreloader.scan_directory()
    end
end

-- Force reload all watched files
function map_hotreloader.reload_all()
    local count = 0
    for path, file_info in pairs(watched_files) do
        if map_hotreloader.reload_map_file(path) then
            count = count + 1
        end
    end
    print("Reloaded " .. count .. " map files")
    return count
end

-- Watch a specific file
function map_hotreloader.watch_file(file_path)
    if not file_path:match("%.map$") then
        print("Only .map files can be watched")
        return false
    end
    
    local stat_handle = io.popen("stat -c '%Y' '" .. file_path .. "' 2>/dev/null")
    if not stat_handle then
        print("Could not stat file: " .. file_path)
        return false
    end
    
    local mtime_str = stat_handle:read("*line")
    local mtime = tonumber(mtime_str)
    stat_handle:close()
    
    if not mtime then
        print("Could not get modification time for: " .. file_path)
        return false
    end
    
    local file_name = file_path:match(".*/(.+)%.map$") or file_path:match("(.+)%.map$")
    watched_files[file_path] = {
        name = file_name,
        path = file_path,
        last_modified = mtime,
        loaded = false
    }
    
    print("Now watching: " .. file_name)
    return true
end

-- Stop watching a file
function map_hotreloader.unwatch_file(file_path)
    if watched_files[file_path] then
        local file_name = watched_files[file_path].name
        watched_files[file_path] = nil
        print("Stopped watching: " .. file_name)
        return true
    end
    return false
end

-- Auto-save current map to watched location
function map_hotreloader.auto_save_current_map()
    local current_map = map_manager.get_current_map()
    if not current_map then
        print("No current map to auto-save")
        return false
    end
    
    local save_path = hotreload_config.watch_directory .. "/" .. current_map.id .. ".map"
    local success = map_serializer.save_map(current_map, save_path, "binary")
    
    if success then
        -- Add to watched files immediately
        map_hotreloader.watch_file(save_path)
        print("Auto-saved current map to: " .. save_path)
    end
    
    return success
end

-- Export current map for external editing
function map_hotreloader.export_for_external_edit(format)
    format = format or "json"
    local current_map = map_manager.get_current_map()
    if not current_map then
        print("No current map to export")
        return false
    end
    
    local export_path = hotreload_config.watch_directory .. "/" .. current_map.id .. "_external." .. format
    local success
    
    if format == "json" then
        success = map_serializer.save_map(current_map, export_path, "json")
    elseif format == "lua" then
        success = map_serializer.export_as_lua(current_map, hotreload_config.watch_directory .. "/" .. current_map.id .. "_external.lua")
    else
        print("Unsupported export format: " .. format)
        return false
    end
    
    if success then
        print("Exported map for external editing: " .. export_path)
        print("Edit the file and it will be auto-reloaded when saved")
        
        -- Watch the exported file
        if format ~= "lua" then
            map_hotreloader.watch_file(export_path)
        end
    end
    
    return success
end

-- Get list of watched files
function map_hotreloader.get_watched_files()
    local files = {}
    for path, info in pairs(watched_files) do
        table.insert(files, {
            name = info.name,
            path = path,
            last_modified = info.last_modified,
            loaded = info.loaded
        })
    end
    
    -- Sort by name
    table.sort(files, function(a, b) return a.name < b.name end)
    return files
end

-- Configuration functions
function map_hotreloader.set_enabled(enabled)
    hotreload_config.enabled = enabled
    print("Hot-reload " .. (enabled and "enabled" or "disabled"))
end

function map_hotreloader.set_auto_reload(auto_reload)
    hotreload_config.auto_reload = auto_reload
    print("Auto-reload " .. (auto_reload and "enabled" or "disabled"))
end

function map_hotreloader.set_check_interval(interval)
    hotreload_config.check_interval = math.max(0.1, interval)
    print("Check interval set to: " .. hotreload_config.check_interval .. "s")
end

function map_hotreloader.set_watch_directory(directory)
    hotreload_config.watch_directory = directory
    os.execute("mkdir -p " .. directory)
    
    -- Clear current watches and rescan
    watched_files = {}
    map_hotreloader.scan_directory()
    
    print("Watch directory changed to: " .. directory)
end

-- Debug information
function map_hotreloader.get_debug_info()
    local file_count = 0
    for _ in pairs(watched_files) do file_count = file_count + 1 end
    
    return {
        enabled = hotreload_config.enabled,
        auto_reload = hotreload_config.auto_reload,
        watch_directory = hotreload_config.watch_directory,
        check_interval = hotreload_config.check_interval,
        watched_file_count = file_count,
        last_check_time = last_check_time
    }
end

-- Create development map template
function map_hotreloader.create_dev_template(map_id, name)
    local template = map_serializer.create_template(map_id, name or "Dev Map", 30, 30)
    
    -- Add some sample entities for testing
    template.enemies = {
        {x = 200, y = 200, type = "basic"},
        {x = 300, y = 300, type = "basic"}
    }
    template.collectibles = {
        {x = 150, y = 150, type = "coin"},
        {x = 250, y = 250, type = "coin"}
    }
    
    -- Save to watched directory
    local dev_path = hotreload_config.watch_directory .. "/" .. map_id .. "_dev.map"
    
    -- Create a mock map object for saving
    local mock_map = {
        id = map_id,
        definition = template,
        tile_data = {},
        width = template.map_width,
        height = template.map_height
    }
    
    -- Generate simple tile pattern
    for y = 1, template.map_height do
        mock_map.tile_data[y] = {}
        for x = 1, template.map_width do
            -- Create a simple border pattern
            if x == 1 or x == template.map_width or y == 1 or y == template.map_height then
                mock_map.tile_data[y][x] = 50 -- Border tiles
            elseif (x + y) % 3 == 0 then
                mock_map.tile_data[y][x] = 25 -- Pattern tiles
            else
                mock_map.tile_data[y][x] = 1  -- Default tiles
            end
        end
    end
    
    local success = map_serializer.save_map(mock_map, dev_path, "json")
    if success then
        map_hotreloader.watch_file(dev_path)
        print("Created development template: " .. dev_path)
        return dev_path
    end
    
    return nil
end

return map_hotreloader