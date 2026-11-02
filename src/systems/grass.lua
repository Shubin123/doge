-- GPU-Optimized Grass Rendering Module for LÖVE Engine
-- Uses instanced rendering and vertex displacement in shaders

local GrassRenderer = {}
GrassRenderer.__index = GrassRenderer

-- Most bodies pushing the grass aside at once (the player, enemies, bosses);
-- must match the vertex shader's array
local MAX_PUSHERS = 32

-- template: an existing renderer whose shader and textures this one shares
function GrassRenderer.new(grassCount, template)
    local self = setmetatable({}, GrassRenderer)
    
    self.grassCount = grassCount or 1000
    self.time = 0
    self.windDirection = {x = 1, y = 2}
    self.windStrength = 3
    self.windSpeed = 4.0
    
    if template then
        self.grassShader = template.grassShader
        self.grassTexture = template.grassTexture
        self.noiseTexture = template.noiseTexture
        self:createMesh()
    else
        self:initShaders()
        self:createMesh()
        self:createTextures()
    end
    
    return self
end

function GrassRenderer:initShaders()
    -- Vertex shader that handles wind displacement
    local vertexShader = [[
        uniform highp float time;
        uniform vec2 windDirection;
        uniform float windStrength;
        uniform float windSpeed;
        #define MAX_PUSHERS 32
        uniform int numPushers;
        uniform vec4 pushers[MAX_PUSHERS]; // x, y, radius of everything walking through
        
        attribute float WindPhase;
        attribute float WindIntensity;
        attribute vec2 BladeCenter;
        
        varying LOVE_HIGHP_OR_MEDIUMP vec2 vTexCoord;
        varying LOVE_HIGHP_OR_MEDIUMP vec4 vColor;
        varying LOVE_HIGHP_OR_MEDIUMP float vPlayerInfluence;
        
        vec4 position(mat4 transform_projection, vec4 vertex_position) {
            vec2 worldPos = vertex_position.xy;
            vec2 bladeCenter = BladeCenter;
            
            // Calculate wind effect
            float windWave = sin(time * windSpeed + bladeCenter.x * 0.01 + bladeCenter.y * 0.008 + WindPhase);
            float windNoise = sin(time * windSpeed * 1.7 + bladeCenter.x * 0.015 + WindPhase) * 0.5;
            float windEffect = windWave * windNoise * windStrength * WindIntensity;
            
            // Height-based wind effect (only affect top vertices)
            vec2 relativePos = worldPos - bladeCenter;
            float heightFactor = max(0.0, -relativePos.y / 20.0); // Assuming max height ~20
            windEffect *= heightFactor * heightFactor;
            
            // Everything walking through pushes the blades aside
            float playerInfluence = 0.0;
            vec2 playerOffset = vec2(0.0);
            for (int i = 0; i < MAX_PUSHERS; i++) {
                if (i >= numPushers) break;
                vec2 toPusher = bladeCenter - pushers[i].xy;
                float dist = length(toPusher);
                float radius = pushers[i].z;
                if (dist >= radius || dist <= 0.0) continue;

                float influence = 1.0 - (dist / radius);
                influence = influence * influence;
                playerInfluence = max(playerInfluence, influence);

                vec2 pushDirection = toPusher / dist;
                playerOffset += pushDirection * 15.0 * influence * heightFactor;

                // Dynamic movement when it's close
                if (dist < radius * 0.5) {
                    float dynamicEffect = sin(time * 8.0 + WindPhase) * influence * 3.0;
                    playerOffset += pushDirection * dynamicEffect * heightFactor;
                }
            }
            // Where several overlap, bend no further than one would
            float bend = length(playerOffset);
            float maxBend = 18.0 * heightFactor;
            if (bend > maxBend) playerOffset *= maxBend / bend;
            
            // Apply wind displacement
            vec2 windOffset = windDirection * windEffect * 8.0;
            
            // Final position
            vec2 finalPos = worldPos + windOffset + playerOffset;
            
            vPlayerInfluence = playerInfluence;
            
            return transform_projection * vec4(finalPos, vertex_position.z, vertex_position.w);
        }
    ]]
    
    -- Fragment shader for grass appearance  
    local fragmentShader = [[
        uniform Image noiseTexture;
        uniform highp float time;
        uniform vec3 lightColor;
        uniform vec3 ambientColor;
        uniform vec2 screenSize;
        
        varying LOVE_HIGHP_OR_MEDIUMP float vPlayerInfluence;
        
        vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
            // Sample grass texture
            vec4 texColor = Texel(tex, texture_coords);
            
            // Alpha test
            if (texColor.a < 0.1) {
                discard;
            }
            
            // Sample noise for variation
            vec2 noiseCoord = screen_coords * 0.01 + vec2(time * 0.1);
            vec4 noise = Texel(noiseTexture, noiseCoord);
            
            // Base lighting
            vec3 lighting = ambientColor + lightColor * 0.8;
            
            // Apply grass color
            vec3 finalColor = texColor.rgb * color.rgb * lighting;
            
            // Player interaction brightness
            if (vPlayerInfluence > 0.0) {
                float brightnessFactor = 1.0 + (vPlayerInfluence * 0.3);
                finalColor *= brightnessFactor;
            }
            
            // Noise variation
            finalColor += (noise.rgb - 0.5) * 0.05;
            
            // Height-based alpha
            float heightAlpha = mix(0.9, 0.6, texture_coords.y);
            
            return vec4(finalColor, texColor.a * heightAlpha * color.a);
        }
    ]]
    
    self.grassShader = love.graphics.newShader(vertexShader, fragmentShader)
end

function GrassRenderer:createMesh()
    -- We'll create the mesh when we have grass data
    self.grassMesh = nil
end

function GrassRenderer:createTextures()
    -- Create grass texture (keep your existing logic but simplified)
    local width, height = 16, 32
    local imageData = love.image.newImageData(width, height)
    
    imageData:mapPixel(function(x, y, r, g, b, a)
        local normalizedY = y / height
        local normalizedX = x / width
        
        local bladeWidth = math.abs(normalizedX - 0.5) * 2
        local alpha = (1.0 - bladeWidth) * (1.0 - normalizedY * normalizedY)
        
        if alpha > 0.1 then
            return 
                (50 + love.math.random(30)) / 255,
                (100 + love.math.random(50)) / 255,
                (30 + love.math.random(20)) / 255,
                math.min(1, alpha)
        else
            return 0, 0, 0, 0
        end
    end)
    
    self.grassTexture = love.graphics.newImage(imageData)
    self.grassTexture:setWrap("repeat", "repeat")
    self.grassTexture:setFilter("linear", "linear")
    
    -- Use existing noise texture or create simple one
    if noise_texture then
        self.noiseTexture = noise_texture
    else
        local noiseData = love.image.newImageData(64, 64)
        noiseData:mapPixel(function(x, y, r, g, b, a)
            return love.math.random(), love.math.random(), love.math.random(), 1
        end)
        self.noiseTexture = love.graphics.newImage(noiseData)
        self.noiseTexture:setWrap("repeat", "repeat")
    end
end

-- A blade's corners: across and up (times its width and height), and the
-- texture coordinate there
local CORNERS = {
    { -0.5, 0, 0, 1 },  -- bottom left
    { 0.5, 0, 1, 1 },   -- bottom right
    { 0.5, -1, 1, 0 },  -- top right
    { -0.5, -1, 0, 0 }, -- top left
}

local VERTEX_FORMAT = {
    {"VertexPosition", "float", 2},
    {"VertexTexCoord", "float", 2},
    {"VertexColor", "byte", 4},
    {"WindPhase", "float", 1},
    {"WindIntensity", "float", 1},
    {"BladeCenter", "float", 2}
}

-- With LuaJIT's FFI and its compiler running, blades are written straight
-- into the mesh's vertex data, laid out as VERTEX_FORMAT, instead of a table
-- per vertex for LÖVE to read back: ten times quicker. Interpreted (LÖVE
-- turns the JIT off on Apple Silicon) FFI writes are slower than the tables,
-- and the browser build's Lua has no FFI, so those hand LÖVE the tables.
-- Same mesh either way.
local ffi
do
    local ok, lib = pcall(require, "ffi")
    if ok and (pcall(lib.typeof, "grass_vertex") or pcall(lib.cdef, [[
        typedef struct {
            float x, y, u, v;
            uint8_t r, g, b, a;
            float windPhase, windIntensity, cx, cy;
        } grass_vertex;
    ]])) then
        ffi = lib
    end
end

-- A colour component as LÖVE stores a "byte" one given a number
local function unorm8(v)
    return math.floor(math.min(math.max(v, 0), 1) * 255)
end

-- The vertex map for `count` blades as uint32 data: two triangles per
-- blade's quad. Every mesh takes the start of one shared list, built once
-- (and again only for a field bigger than any before), instead of a table of
-- six numbers a blade each time.
local sharedIndices, sharedBlades = nil, 0
local function indexData(count)
    if count > sharedBlades then
        local n = math.max(count, var and var.max_grass or 2000)
        local data = love.data.newByteData(n * 6 * 4)
        local p = ffi.cast("uint32_t *", data:getFFIPointer())
        for i = 0, n - 1 do
            local base, k = i * 4, i * 6
            p[k], p[k + 1], p[k + 2] = base, base + 1, base + 2
            p[k + 3], p[k + 4], p[k + 5] = base, base + 2, base + 3
        end
        sharedIndices, sharedBlades = data, n
    end
    return love.data.newDataView(sharedIndices, 0, count * 6 * 4)
end

-- accept(x, y), if given, says where blades may grow (each gets a few tries
-- to land somewhere it's true); tint multiplies their colour. random, if
-- given, is where every number comes from (a function giving 0 <= n < 1),
-- for the same blades every time, and then they're kept as vertex data
-- (self.vertexData, VERTEX_FORMAT) wherever there's the FFI, to be cached.
function GrassRenderer:setGrassArea(x, y, width, height, density, accept, tint, random)
    density = density or 1.0
    local seeded = random ~= nil
    random = random or love.math.random
    local realRandom = mymath.realRandom
    if seeded then
        realRandom = function(low, high) return random() * (high - low) + low end
    end
    self.vertexData = nil

    -- Calculate grass count
    local areaGrassCount = math.floor((width * height * density) / 1000)
    areaGrassCount = math.min(areaGrassCount, var and var.max_grass or 2000)

    local spotX, spotY = {}, {}
    for _ = 1, areaGrassCount do
        for _ = 1, accept and 8 or 1 do
            local bx, by = x + random() * width, y + random() * height
            if not accept or accept(bx, by) then
                spotX[#spotX + 1], spotY[#spotY + 1] = bx, by
                break
            end
        end
    end
    areaGrassCount = #spotX
    if areaGrassCount == 0 then
        self.grassMesh = nil
        return
    end

    -- Every blade's four corners in one mesh: into vertexData (FFI) or vertices
    local vertexData, out, vertices
    if ffi and (jit.status() or seeded) then
        vertexData = love.data.newByteData(areaGrassCount * 4 * ffi.sizeof("grass_vertex"))
        out = ffi.cast("grass_vertex *", vertexData:getFFIPointer())
    else
        vertices = {}
    end

    for i = 1, areaGrassCount do
        local bladeX = spotX[i]
        local bladeY = spotY[i]
        local bladeWidth = 0.5 + random() * 1.5
        local bladeHeight = 8 + random() * 15
        local rotation = random() * math.pi * 0.2 - math.pi * 0.1

        -- Color variation
        local r = 0.2 + random() * 0.3
        local g = 0.8 + random() * 0.4
        local b = 0.1 + random() * 0.2
        if tint then
            r, g, b = r * tint[1], g * tint[2], b * tint[3]
        end
        local a = realRandom(0,0.1) + realRandom(0,0.2) + realRandom(0,0.3) - realRandom(0,0.05)

        -- Wind properties (per-vertex attributes for the shader)
        local windPhase = random() * math.pi * 2
        local windIntensity = 0.7 + random() * 0.6

        local cos_r = math.cos(rotation)
        local sin_r = math.sin(rotation)
        local r8, g8, b8, a8 = unorm8(r), unorm8(g), unorm8(b), unorm8(a)

        for j = 1, 4 do
            local corner = CORNERS[j]
            local localX = corner[1] * bladeWidth
            local localY = corner[2] * bladeHeight

            -- Rotated, then placed at the blade
            local worldX = bladeX + (localX * cos_r - localY * sin_r)
            local worldY = bladeY + (localX * sin_r + localY * cos_r)

            if out then
                local v = out[(i - 1) * 4 + j - 1]
                v.x, v.y, v.u, v.v = worldX, worldY, corner[3], corner[4]
                v.r, v.g, v.b, v.a = r8, g8, b8, a8
                v.windPhase, v.windIntensity, v.cx, v.cy = windPhase, windIntensity, bladeX, bladeY
            else
                vertices[(i - 1) * 4 + j] = {
                    worldX, worldY,              -- Position
                    corner[3], corner[4],        -- Texture coordinates
                    r, g, b, a,                  -- Color
                    windPhase, windIntensity,    -- Wind
                    bladeX, bladeY               -- Blade center for the shader
                }
            end
        end
    end

    self:setMesh(x, y, width, height, areaGrassCount, vertexData or vertices)
    if seeded then self.vertexData = vertexData end
end

--- The mesh for `count` blades over the rect, from their vertices: vertex
--- data laid out as VERTEX_FORMAT (as a seeded setGrassArea keeps, or the
--- cache gives back), or a table per vertex.
function GrassRenderer:setMesh(x, y, width, height, count, vertices)
    self.x = x
    self.y = y
    self.width = width
    self.height = height
    self.grassCount = count
    if count == 0 then
        self.grassMesh = nil
        return
    end

    if type(vertices) == "table" then
        self.grassMesh = love.graphics.newMesh(VERTEX_FORMAT, vertices, "triangles", "static")
    else
        self.grassMesh = love.graphics.newMesh(VERTEX_FORMAT, count * 4, "triangles", "static")
        self.grassMesh:setVertices(vertices)
    end

    -- Two triangles per blade's quad
    if ffi then
        self.grassMesh:setVertexMap(indexData(count), "uint32")
    else
        local indices = {}
        for i = 0, count - 1 do
            local base, k = i * 4 + 1, i * 6
            indices[k + 1], indices[k + 2], indices[k + 3] = base, base + 1, base + 2
            indices[k + 4], indices[k + 5], indices[k + 6] = base, base + 2, base + 3
        end
        self.grassMesh:setVertexMap(indices)
    end
    self.grassMesh:setTexture(self.grassTexture)
end

function GrassRenderer:update(dt)
    self.time = self.time + dt
    
    -- Simple wind variation (minimal CPU work)
    self.windDirection.x = math.cos(self.time * 0.5)
    self.windDirection.y = math.sin(self.time * 0.3) * 0.5
    self.windStrength = 0.4 + math.sin(self.time * 0.8) * 0.2
end

-- Scratch tables for the pushers uploaded each frame (reused, no garbage)
local pushers, pusherDist, sorted = {}, {}, {}
local function byDistance(a, b) return pusherDist[a] < pusherDist[b] end

-- Collect the bodies bending this patch: the player first, then enemies and
-- bosses inside it, nearest the player first when there are too many.
function GrassRenderer:gatherPushers(playerX, playerY, playerRadius)
    local n = 0
    local function add(x, y, radius)
        if x + radius < self.x or x - radius > self.x + self.width or
           y + radius < self.y or y - radius > self.y + self.height then
            return
        end
        n = n + 1
        local p = pushers[n]
        if not p then p = {}; pushers[n] = p end
        p[1], p[2], p[3], p[4] = x, y, radius, 0
        pusherDist[p] = (x - playerX) ^ 2 + (y - playerY) ^ 2
    end

    if player and player.body then add(playerX, playerY, playerRadius) end
    if enemy and enemy.enemies then
        for _, e in ipairs(enemy.enemies) do
            if not e.dead and e.body and not e.body:isDestroyed() then
                local x, y = e.body:getPosition()
                add(x, y, (e.scale or 0.6) * 50)
            end
        end
    end
    if boss and boss.bosses then
        for _, b in pairs(boss.bosses) do
            if b.body and not b.body:isDestroyed() then
                local x, y = b.body:getPosition()
                add(x, y, 60)
            end
        end
    end

    if n > MAX_PUSHERS then
        -- The player is nearest itself (distance 0), so it always stays
        for i = 1, n do sorted[i] = pushers[i] end
        for i = #sorted, n + 1, -1 do sorted[i] = nil end
        table.sort(sorted, byDistance)
        for i = 1, n do pushers[i] = sorted[i] end
        n = MAX_PUSHERS
    end
    return n
end

-- Whether any of the patch is on screen (blades sway a little past its edges)
function GrassRenderer:onScreen()
    local zoom = camera.zoom
    local x0, y0 = -camera.x / zoom, -camera.y / zoom
    local x1, y1 = x0 + love.graphics.getWidth() / zoom, y0 + love.graphics.getHeight() / zoom
    return self.x < x1 + 30 and self.x + self.width > x0 - 30
        and self.y < y1 + 30 and self.y + self.height > y0 - 30
end

function GrassRenderer:draw()
    if not self.grassMesh or not self:onScreen() then return end
    
    love.graphics.push()
    love.graphics.setBlendMode("alpha")
    love.graphics.setShader(self.grassShader)
    
    -- Get player position
    local playerX = player and player.body and player.body:getX() or 0
    local playerY = player and player.body and player.body:getY() or 0
    local playerRadius = player.scale*50
    
    -- Send uniforms once
    self.grassShader:send("time", self.time)
    -- self.grassShader:send("windDirection", {self.windDirection.x, self.windDirection.y})
    self.grassShader:send("windStrength", self.windStrength)
    self.grassShader:send("windSpeed", self.windSpeed)
    local n = self:gatherPushers(playerX, playerY, playerRadius)
    self.grassShader:send("numPushers", n)
    if n > 0 then
        self.grassShader:send("pushers", unpack(pushers, 1, n))
    end
    -- self.grassShader:send("screenSize", {love.graphics.getWidth(), love.graphics.getHeight()})
    self.grassShader:send("noiseTexture", self.noiseTexture)
    self.grassShader:send("lightColor", {2.0, 0.95, 0.8})
    self.grassShader:send("ambientColor", {0.3, 0.4, 0.3})
    
    -- Single draw call for all grass!
    -- love.graphics.setBlendMode("subrract", "premultiplied")
    love.graphics.setColor(1, 1, 1, 1)
    -- love.graphics.setBlendMode("add")
    
    -- occludes == false: leave the scene's alpha be, so GI doesn't see a wall
    if self.occludes == false then love.graphics.setColorMask(true, true, true, false) end
    love.graphics.draw(self.grassMesh)
    if self.occludes == false then love.graphics.setColorMask() end
    
    -- Reset state
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setShader()
    -- love.graphics.setBlendMode("alpha") -- reset

    love.graphics.pop()
end

-- Keep your existing methods
function GrassRenderer:setWind(direction, strength, speed)
    self.windDirection = direction or self.windDirection
    self.windStrength = strength or self.windStrength
    self.windSpeed = speed or self.windSpeed
end

-- function GrassRenderer:drawToCanvas(canvas)
--     love.graphics.setCanvas(canvas)
--     love.graphics.clear()
--     self:draw()
--     love.graphics.setCanvas()
-- end

-- Create demo instance
local grass = GrassRenderer.new(800)
local demo = {}

-- Further patches other systems lay out (the regions), each drawn only while
-- it's on screen
local fields = {}

function demo.load()
    grass:setGrassArea(var.game_width/2, 50, var.game_width, var.game_height/4, 100)
    fields = {}
end

--- A patch of about `count` blades over the rect, growing only where
--- accept(x, y) is true, coloured by tint ({ r, g, b } multipliers). With
--- random (see setGrassArea) the same blades every time, kept in
--- field.vertexData where the FFI is.
function demo.addField(x, y, width, height, count, accept, tint, random)
    local field = GrassRenderer.new(count, grass)
    field:setGrassArea(x, y, width, height, count * 1000 / (width * height), accept, tint, random)
    fields[#fields + 1] = field
    return field
end

--- A patch of `count` blades over the rect from the vertex data a seeded
--- addField kept (field.vertexData), say from the cache.
function demo.addFieldFrom(x, y, width, height, count, vertexData)
    local field = GrassRenderer.new(count, grass)
    field:setMesh(x, y, width, height, count, vertexData)
    fields[#fields + 1] = field
    return field
end

--- The patches addField and addFieldFrom made, in order.
function demo.fields()
    return fields
end

-- Bytes a vertex takes in vertex data; nil without the FFI (the browser),
-- where fields keep no vertex data to cache
demo.VERTEX_SIZE = ffi and ffi.sizeof("grass_vertex")

function demo.update(dt)
    grass:update(dt)
    for _, field in ipairs(fields) do
        field:update(dt)
    end
    -- grass:setGrassArea(var.game_width/2, 50, var.game_width*math.sin(fire.t) + 1, var.game_height/4, 100)

end

function demo.draw()
    grass:draw()
    for _, field in ipairs(fields) do
        field:draw()
    end
end

return {
    GrassRenderer = GrassRenderer,
    public = demo
}