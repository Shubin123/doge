-- src/map_context.lua

local MapDescriptor    = require("map_descriptor")
local MapParser        = require("map_parser")
local ResourceCache    = require("resource_cache")
local TileMapFactory   = require("tilemap_factory")
local EntityFactory    = require("entity_factory")
local PhysicsBuilder   = require("physics_builder")

local MapContext = {}
MapContext.__index = MapContext

--- Create a new MapContext bound to a physics world.
-- @param world love.physics World object
-- @return MapContext instance
function MapContext:new(world)
    assert(world, "MapContext:new requires a physics world")
    local obj = setmetatable({
        world         = world,
        descriptor    = nil,
        definition    = nil,
        tileMap       = nil,
        entities      = nil,
        physicsBodies = nil,
        onEnter       = nil,  -- function(self) optional hook
        onExit        = nil,  -- function(self) optional hook
    }, MapContext)
    return obj
end

--- Load a map by id.
-- Sequences descriptor load, parsing, tilemap creation, entity spawn, physics build.
-- @param id string map identifier (filename without .map)
function MapContext:load(id)
    assert(type(id) == "string" and id ~= "", "MapContext: load requires a non-empty id")
    assert(not self.descriptor, "MapContext: a map is already loaded")

    -- 1) Descriptor
    local desc = MapDescriptor.loadDescriptor(id)
    self.descriptor = desc

    -- 2) Read full content
    local file = io.open(desc.path, "r")
    if not file then error("MapContext: cannot open map file '"..tostring(desc.path).."'") end
    local content = file:read("*a")
    file:close()

    -- 3) Parse full definition
    local def = MapParser.parseMapData(content)
    def.metadata = def.metadata or {}
    -- merge light descriptor metadata (overrides)
    for k, v in pairs(desc.metadata) do
        def.metadata[k] = v
    end
    def.tileset    = desc.tileset
    def.mapWidth   = desc.mapWidth
    def.mapHeight  = desc.mapHeight
    self.definition = def

    -- 4) Determine tile dimensions from metadata
    local m         = def.metadata
    local tileW     = tonumber(m.tile_width)  or 32
    local tileH     = tonumber(m.tile_height) or tileW
    def.tileWidth   = tileW
    def.tileHeight  = tileH

    -- 5) Create tile map
    local tileMapDef = {
        tileset     = def.tileset,
        tileWidth   = tileW,
        tileHeight  = tileH,
        mapWidth    = def.mapWidth,
        mapHeight   = def.mapHeight,
        tileData    = def.tileData,
        worldX      = tonumber(m.world_x) or 0,
        worldY      = tonumber(m.world_y) or 0,
        scale       = tonumber(m.scale)   or 1
    }
    self.tileMap = TileMapFactory.createTileMap(tileMapDef)

    -- 6) Spawn entities
    self.entities = EntityFactory.spawnEntities({
        enemies       = def.enemies,
        collectibles  = def.collectibles,
        interactables = def.interactables,
        playerSpawn   = def.playerSpawn,
    }, { world = self.world })

    -- 7) Build physics bodies
    self.physicsBodies = PhysicsBuilder.buildPhysics(def, self.world)

    -- 8) Enter hook
    if type(self.onEnter) == "function" then
        self.onEnter(self)
    end
end

--- Update entities (if they expose an update(dt) method).
-- @param dt number delta time
function MapContext:update(dt)
    if not self.entities then return end
    for _, e in ipairs(self.entities.enemies      or {}) do
        if type(e.update) == "function" then e:update(dt) end
    end
    for _, c in ipairs(self.entities.collectibles or {}) do
        if type(c.update) == "function" then c:update(dt) end
    end
    for _, i in ipairs(self.entities.interactables or {}) do
        if type(i.update) == "function" then i:update(dt) end
    end
    local p = self.entities.player
    if p and type(p.update) == "function" then p:update(dt) end
end

--- Draw tilemap and entities (if they expose a draw() method).
-- @param camera table camera with view_bounds and isInView()
function MapContext:draw(camera)
    if self.tileMap and camera then
        self.tileMap:draw(camera)
    end
    if not self.entities then return end
    for _, e in ipairs(self.entities.enemies      or {}) do
        if type(e.draw) == "function" then e:draw() end
    end
    for _, c in ipairs(self.entities.collectibles or {}) do
        if type(c.draw) == "function" then c:draw() end
    end
    for _, i in ipairs(self.entities.interactables or {}) do
        if type(i.draw) == "function" then i:draw() end
    end
    local p = self.entities.player
    if p and type(p.draw) == "function" then p:draw() end
end

--- Unload the current map, destroying physics, releasing resources, and calling exit hook.
function MapContext:unload()
    assert(self.descriptor, "MapContext: no map loaded to unload")

    -- Exit hook
    if type(self.onExit) == "function" then
        self.onExit(self)
    end

    -- Destroy physics bodies
    for _, obj in ipairs(self.physicsBodies or {}) do
        if obj.fixture and obj.fixture.destroy then obj.fixture:destroy() end
        if obj.body    and obj.body.destroy    then obj.body:destroy()    end
    end
    self.physicsBodies = nil

    -- Release tilemap resources
    if self.definition and self.definition.tileset then
        ResourceCache.releaseImage(self.definition.tileset)
    end
    self.tileMap = nil

    -- Clear entities & definitions
    self.entities   = nil
    self.definition = nil
    self.descriptor = nil
end

return MapContext