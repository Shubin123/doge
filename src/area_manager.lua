local var = require("var")
local map = require("map") -- Require map module
local fire = require("fire") -- Require fire module
local enemy = require("enemy") -- Require enemy module

local areas = {}
local current_area_id = nil -- This will be the single source of truth for the current area ID

-- Moved from main.lua and modified to accept area data and shapes
local function createCoins(area, coin_shape, n)
    for _ = 1, n do
        local _bod = love.physics.newBody(area.physics_world, math.random(200, var.game_width + 200),
            math.random(50, var.game_height + 50),
            "dynamic")
        table.insert(area.coin_bods, 1, _bod)
        local _fixture = love.physics.newFixture(_bod, coin_shape)
        _fixture:setGroupIndex(69)
    end
end

-- Moved from main.lua and modified to accept area data and shapes
local function createEnemies(area, enemy_shape, n)
    for _ = 1, n do
        local _bod = love.physics.newBody(area.physics_world, math.random(200, var.game_width + 200),
            math.random(50, var.game_height + 50),
            "dynamic")
        table.insert(area.enemies_bods, 1, _bod)
        local _fixture = love.physics.newFixture(_bod, enemy_shape)
        _fixture:setGroupIndex(-777)
    end
end

local function overworld_load(area, coin_shape, enemy_shape)
  print("Overworld loaded")
  -- Create coins and enemies for the overworld
  createCoins(area, coin_shape, var.num_coins) -- Pass area data, shape, and count
  createEnemies(area, enemy_shape, var.num_enemies) -- Pass area data, shape, and count
end

local function overworld_unload()
  print("Overworld unloaded")
  -- Destroy coins and enemies for the overworld
  -- (Need to implement logic to store and destroy these entities)
end

local function shop_load(area, coin_shape, enemy_shape)
  print("Shop loaded")
  -- Create entities for the shop
  -- (Need to implement logic to create entities for the shop)
end

local function shop_unload()
  print("Shop unloaded")
  -- Destroy entities for the shop
  -- (Need to implement logic to destroy entities for the shop)
end

-- Define test_map boundary map data
local test_map_tileset_image = love.graphics.newImage("gfx/TileSet/TX Tileset Wall.png")
local test_map_tiles = map.newTiles(test_map_tileset_image, var.tile_w, var.tile_h)
local map_size_tiles_w = math.floor(700 / var.tile_w) -- Assuming 700x700 box and 16x16 tiles
local map_size_tiles_h = math.floor(700 / var.tile_h)
local map_width_tiles = math.floor(var.game_width / var.tile_w) -- Assuming 800x800 game area
local map_height_tiles = math.floor(var.game_height / var.tile_h)
local test_map_tile_data = {}

-- Initialize tile data with empty tiles
for y = 1, map_height_tiles do
    test_map_tile_data[y] = {}
    for x = 1, map_width_tiles do
        test_map_tile_data[y][x] = 0
    end
end

-- Add tiles for the boundary walls (a 700x700 box centered in 800x800)
local wall_tile_id = 1 -- Assuming tile ID 1 is a wall tile
local offset_tiles_x = math.floor((map_width_tiles - map_size_tiles_w) / 2)
local offset_tiles_y = math.floor((map_height_tiles - map_size_tiles_h) / 2)

-- Top wall
for x = offset_tiles_x + 1, offset_tiles_x + map_size_tiles_w do
    test_map_tile_data[offset_tiles_y + 1][x] = wall_tile_id
end

-- Bottom wall
for x = offset_tiles_x + 1, offset_tiles_x + map_size_tiles_w do
    test_map_tile_data[offset_tiles_y + map_size_tiles_h][x] = wall_tile_id
end

-- Left wall
for y = offset_tiles_y + 1, offset_tiles_y + map_size_tiles_h do
    test_map_tile_data[y][offset_tiles_x + 1] = wall_tile_id
end

-- Right wall
for y = offset_tiles_y + 1, offset_tiles_y + map_size_tiles_h do
    test_map_tile_data[y][offset_tiles_x + map_size_tiles_w] = wall_tile_id
end


local test_map_boundary_map = map.createMap(test_map_tiles, map_width_tiles, map_height_tiles, test_map_tile_data)


areas["overworld"] = {
  area_id = "overworld",
  asset_list = {}, -- Add asset list
  physics_world = nil,
  transition_points = {
    {x = 236, y = 200, target_area_id = "test_map", target_x = 400, target_y = 400} -- Changed to test_map
  },
  spawn_point = {x = 200, y = 200},
  load_function = overworld_load,
  unload_function = overworld_unload,
  saved_position = nil, -- Add saved position
  coin_bods = {}, -- Add coin bodies table
  enemies_bods = {}, -- Add enemy bodies table
  map_layers = {
      map.map, -- Grass layer
      map.map3, -- Structures layer
      map.map4 -- Plants layer
  }
}

areas["shop"] = {
  area_id = "shop",
  asset_list = {}, -- Add asset list
  physics_world = nil,
  transition_points = {
    {x = 50, y = 50, target_area_id = "overworld", target_x = 250, target_y = 250}
  },
  spawn_point = {x = 100, y = 100},
  load_function = shop_load,
  unload_function = shop_unload,
  saved_position = nil, -- Add saved position
  coin_bods = {}, -- Add coin bodies table
  enemies_bods = {}, -- Add enemy bodies table
  map_layers = {
      -- Add shop map layers here
  }
}

-- Define test_map area
local function test_map_load(area, coin_shape, enemy_shape)
  print("AreaManager: test_map_load called for area: " .. area.area_id)
  -- Create boundaries for the test map (a 700x700 box centered in 800x800)
  -- Static bodies are now created via the map data, no need to create them here
  print("AreaManager: test_map_load - Boundary walls created via map data.")
end

local function test_map_unload()
  print("AreaManager: test_map_unload called")
  -- Static bodies are part of the world, world:destroy() should handle them.
end

areas["test_map"] = {
  area_id = "test_map",
  asset_list = {},
  physics_world = nil,
  transition_points = {
    {x = 400, y = 730, target_area_id = "overworld", target_x = 236, target_y = 220} -- Portal back to overworld
  },
  spawn_point = {x = 400, y = 400}, -- Center of the 800x800 game area, inside the 700x700 box
  load_function = test_map_load,
  unload_function = test_map_unload,
  saved_position = nil,
  coin_bods = {},
  enemies_bods = {},
  map_layers = {
      test_map_boundary_map -- Test map boundary layer
  }
}

function loadArea(area_id)
  if areas[area_id] then
    print("AreaManager loadArea: Start loading area: " .. area_id)
    local area = areas[area_id]
    area.physics_world = love.physics.newWorld(0, 0)
    print("AreaManager loadArea: Physics world created for " .. area_id .. ": " .. tostring(area.physics_world))
    area.physics_world:setCallbacks(beginContact, endContact, preSolve, postSolve) -- Assuming these functions are globally available or accessible

    -- Create shapes for entities within this area's physics world
    local coin_shape = love.physics.newCircleShape(5)
    local enemy_shape = love.physics.newCircleShape(10)

    if area.load_function then
      area.load_function(area, coin_shape, enemy_shape) -- Pass area data and shapes
    end

    -- Populate fire and enemies for the new area's physics world
    fire.populate(area.physics_world)
    enemy.populate(area.physics_world)

    local start_x, start_y
    if area.saved_position then
      start_x, start_y = area.saved_position.x, area.saved_position.y
    else
      start_x, start_y = area.spawn_point.x, area.spawn_point.y
      print("AreaManager loadArea: Using spawn point for " .. area_id .. ": " .. start_x .. ", " .. start_y)
    end
    print("AreaManager loadArea: Calling player.load for " .. area_id .. " with world " .. tostring(area.physics_world) .. " at " .. start_x .. ", " .. start_y)
    player.load(area.physics_world, start_x, start_y)
    current_area_id = area_id -- Set the current area ID
    
    -- Sync global variables with area-specific data
    enemies_bods = area.enemies_bods
    coin_bods = area.coin_bods
    
    print("AreaManager loadArea: player.load completed and current_area_id set to: " .. current_area_id .. " for area " .. area_id)
  else
    print("AreaManager loadArea: Area ID not found: " .. area_id)
  end
end

function unloadArea(area_id)
  if areas[area_id] then
    print("AreaManager unloadArea: Start unloading area: " .. area_id)
    local px, py = player.getPosition()
    areas[area_id].saved_position = {x = px, y = py}
    print("AreaManager unloadArea: Saved player position for " .. area_id .. ": " .. px .. ", " .. py)
    player.unload()
    print("AreaManager unloadArea: player.unload completed for " .. area_id)
    if areas[area_id].unload_function then
      areas[area_id].unload_function()
    end
    -- Call unload functions for fire and enemies
    fire.unload()
    enemy.unload() -- Call enemy.unload

    if areas[area_id].physics_world then
      print("AreaManager unloadArea: Destroying physics world for " .. area_id .. ": " .. tostring(areas[area_id].physics_world))
      areas[area_id].physics_world:destroy()
      areas[area_id].physics_world = nil
      print("AreaManager unloadArea: Physics world destroyed for " .. area_id)
    end
  else
    print("AreaManager unloadArea: Area ID not found: " .. area_id)
  end
end

function transitionArea(target_area_id, target_x, target_y)
  print("AreaManager transitionArea: Starting transition from " .. (current_area_id or "nil") .. " to " .. target_area_id .. " at " .. target_x .. ", " .. target_y)
  if current_area_id ~= nil then
    print("AreaManager transitionArea: Unloading current area: " .. current_area_id)
    -- unloadArea(current_area_id)
    print("AreaManager transitionArea: Current area " .. current_area_id .. " unloaded.")
  end
  print("AreaManager transitionArea: Loading target area: " .. target_area_id)
  loadArea(target_area_id)
  print("AreaManager transitionArea: Target area " .. target_area_id .. " loaded.")
  -- Set player position directly. The delay was a precaution.
  print("AreaManager transitionArea: Calling player.moveTo " .. target_x .. ", " .. target_y .. " for area " .. target_area_id)
  player.moveTo(target_x, target_y)
  print("AreaManager transitionArea: player.moveTo completed for " .. target_area_id)
  current_area_id = target_area_id
  print("AreaManager transitionArea: current_area_id set to " .. current_area_id)
end

function getCurrentArea()
  return areas[current_area_id]
end

return {
  areas = areas,
  loadArea = loadArea,
  unloadArea = unloadArea,
  transitionArea = transitionArea,
  getCurrentArea = getCurrentArea,
  current_area_id = current_area_id -- Expose for initial load in main.lua
}