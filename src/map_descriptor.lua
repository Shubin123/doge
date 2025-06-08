-- c:/Users/admin/Desktop/JAMUBC_Cloned_repos/doge/src/map_descriptor.lua

local MapDescriptor = {}

-- Directory where .map files are stored (relative to working directory)
local MAP_DIR = "maps"

-- Determine path separator from package.config
local PATH_SEP = package.config:sub(1,1)

-- Utility to join path components
local function joinPath(...)
    local parts = {...}
    return table.concat(parts, PATH_SEP)
end

-- Internal helper: parse only header, version, [metadata], [tileset], [dimensions]
local function parseLightDescriptor(filePath)
    local file, err = io.open(filePath, "r")
    if not file then
        return nil, ("Could not open map file '%s': %s"):format(filePath, err or "unknown")
    end

    local descriptor = {}
    -- Read and verify header
    local header = file:read("*l")
    if header ~= "DOGE_MAP" then
        file:close()
        return nil, ("Invalid map header in '%s' (got '%s')"):format(filePath, tostring(header))
    end

    -- Read version
    descriptor.version = file:read("*l")

    -- skip blank line (after version)
    file:read("*l")

    local mode
    descriptor.metadata = {}

    for line in file:lines() do
        -- Section headers
        if line:match("^%[metadata%]") then
            mode = "metadata"
        elseif line:match("^%[tileset%]") then
            mode = "tileset"
        elseif line:match("^%[dimensions%]") then
            mode = "dimensions"
        elseif line:match("^%[.+%]") then
            -- other sections we don't care about here
            mode = nil
        elseif line ~= "" then
            -- Content lines
            if mode == "metadata" then
                local k, v = line:match("^(%w+)=(.+)$")
                if k and v then
                    descriptor.metadata[k] = v
                end
            elseif mode == "tileset" then
                descriptor.tileset = line
            elseif mode == "dimensions" then
                local w, h = line:match("^(%d+)x(%d+)$")
                if w and h then
                    descriptor.mapWidth  = tonumber(w)
                    descriptor.mapHeight = tonumber(h)
                    -- we've got everything we need: break early
                    break
                end
            end
        end
    end

    file:close()
    return descriptor
end

--- Returns a list of all available map descriptors (metadata-only).
-- Each entry has fields: id, path, version, metadata table, tileset, mapWidth, mapHeight.
function MapDescriptor.getAvailableDescriptors()
    local list = {}

    local files = love.filesystem.getDirectoryItems(MAP_DIR)
    for _, entry in ipairs(files) do
        if entry:match("%.map$") then
            local id       = entry:sub(1, -5) -- strip ".map"
            local filePath = joinPath(MAP_DIR, entry)
            local desc, err = parseLightDescriptor(filePath)
            if desc then
                desc.id   = id
                desc.path = filePath
                table.insert(list, desc)
            else
                -- skip invalid map files
                -- could log err if desired
            end
        end
    end

    return list
end

--- Loads a single map descriptor by id.
-- Reads header, version, [metadata], [tileset], [dimensions] only.
-- @param id The map id (filename without .map extension)
-- @return descriptor table or throws error on failure
function MapDescriptor.loadDescriptor(id)
    if type(id) ~= "string" or id == "" then
        error("MapDescriptor.loadDescriptor: invalid id")
    end

    local fileName = id .. ".map"
    local filePath = joinPath(MAP_DIR, fileName)
    local desc, err = parseLightDescriptor(filePath)
    if not desc then
        error(("MapDescriptor.loadDescriptor: failed to load '%s': %s"):format(id, err))
    end

    desc.id   = id
    desc.path = filePath
    return desc
end

return MapDescriptor