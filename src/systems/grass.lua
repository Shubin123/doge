-- GPU-Optimized Grass Rendering Module for LÖVE Engine
-- Uses instanced rendering and vertex displacement in shaders

local GrassRenderer = {}
GrassRenderer.__index = GrassRenderer

function GrassRenderer.new(grassCount)
    local self = setmetatable({}, GrassRenderer)
    
    self.grassCount = grassCount or 1000
    self.time = 0
    self.windDirection = {x = 1, y = 2}
    self.windStrength = 3
    self.windSpeed = 4.0
    
    self:initShaders()
    self:createMesh()
    self:createTextures()
    
    return self
end

function GrassRenderer:initShaders()
    -- Vertex shader that handles wind displacement
    local vertexShader = [[
        uniform highp float time;
        uniform vec2 windDirection;
        uniform float windStrength;
        uniform float windSpeed;
        uniform vec2 playerPos;
        uniform float playerRadius;
        
        attribute float WindPhase;
        attribute float WindIntensity;
        attribute vec2 BladeCenter;
        
        varying vec2 vTexCoord;
        varying vec4 vColor;
        varying float vPlayerInfluence;
        
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
            
            // Calculate player interaction
            vec2 toPlayer = bladeCenter - playerPos;
            float distToPlayer = length(toPlayer);
            float playerInfluence = 0.0;
            vec2 playerOffset = vec2(0.0);
            
            if (distToPlayer < playerRadius && distToPlayer > 0.0) {
                playerInfluence = 1.0 - (distToPlayer / playerRadius);
                playerInfluence = playerInfluence * playerInfluence;
                
                vec2 pushDirection = normalize(toPlayer);
                float maxDisplacement = 15.0 * playerInfluence * heightFactor;
                playerOffset = pushDirection * maxDisplacement;
                
                // Dynamic movement when player is close
                if (distToPlayer < playerRadius * 0.5) {
                    float dynamicEffect = sin(time * 8.0 + WindPhase) * playerInfluence * 3.0;
                    playerOffset += pushDirection * dynamicEffect * heightFactor;
                }
            }
            
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
        
        varying float vPlayerInfluence;
        
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
    self.grassBlades = {}
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

function GrassRenderer:setGrassArea(x, y, width, height, density)
    density = density or 1.0
    
    -- Calculate grass count
    local areaGrassCount = math.floor((width * height * density) / 1000)
    areaGrassCount = math.min(areaGrassCount, var and var.max_grass or 2000)
    
    -- Clear existing data
    self.grassBlades = {}
    
    -- Create vertices for all grass blades in one mesh
    local vertices = {}
    local vertexIndex = 1
    
    for i = 1, areaGrassCount do
        local bladeX = x + love.math.random() * width
        local bladeY = y + love.math.random() * height
        local bladeWidth = 0.5 + love.math.random() * 1.5
        local bladeHeight = 8 + love.math.random() * 15
        local rotation = love.math.random() * math.pi * 0.2 - math.pi * 0.1
        
        -- Color variation
        local r = 0.2 + love.math.random() * 0.3
        local g = 0.8 + love.math.random() * 0.4
        local b = 0.1 + love.math.random() * 0.2
        -- local a = 0.8 
        local a = mymath.realRandom(0,0.1) + mymath.realRandom(0,0.2) + mymath.realRandom(0,0.3) - mymath.realRandom(0,0.05)
        
        -- Wind properties (stored in texture coordinates for shader access)
        local windPhase = love.math.random() * math.pi * 2
        local windIntensity = 0.7 + love.math.random() * 0.6
        
        -- Calculate rotated and scaled vertices
        local cos_r = math.cos(rotation)
        local sin_r = math.sin(rotation)
        
        -- Base quad vertices (relative to center)
        local baseVerts = {
            {-0.5, 0},   -- Bottom left
            { 0.5, 0},   -- Bottom right  
            { 0.5, -1},  -- Top right
            {-0.5, -1}   -- Top left
        }
        
        -- Transform and add vertices for this blade
        for j = 1, 4 do
            local localX = baseVerts[j][1] * bladeWidth
            local localY = baseVerts[j][2] * bladeHeight
            
            -- Apply rotation
            local rotatedX = localX * cos_r - localY * sin_r
            local rotatedY = localX * sin_r + localY * cos_r
            
            -- World position
            local worldX = bladeX + rotatedX
            local worldY = bladeY + rotatedY
            
            -- Texture coordinates
            local u = (j == 2 or j == 3) and 1 or 0
            local v = (j == 3 or j == 4) and 0 or 1
            
            -- Store grass properties in unused vertex attributes
            -- We'll use the vertex color to pass per-blade data
            vertices[vertexIndex] = {
                worldX, worldY,  -- Position
                u, v,            -- Texture coordinates
                r, g, b, a,      -- Color
                -- Store additional data in extra attributes if needed
                windPhase,       -- Custom attribute 1
                windIntensity,   -- Custom attribute 2
                bladeX, bladeY   -- Original blade center for shader calculations
            }
            vertexIndex = vertexIndex + 1
        end
        
        -- Store blade info for reference
        table.insert(self.grassBlades, {
            x = bladeX, y = bladeY,
            width = bladeWidth, height = bladeHeight,
            rotation = rotation, windPhase = windPhase, windIntensity = windIntensity
        })
    end
    
    -- Create mesh with all vertices
    local vertexFormat = {
        {"VertexPosition", "float", 2},
        {"VertexTexCoord", "float", 2}, 
        {"VertexColor", "byte", 4},
        {"WindPhase", "float", 1},
        {"WindIntensity", "float", 1},
        {"BladeCenter", "float", 2}
    }
    
    self.grassMesh = love.graphics.newMesh(vertexFormat, vertices, "triangles", "static")
    
    -- Set up indices for triangulated quads
    local indices = {}
    for i = 0, areaGrassCount - 1 do
        local base = i * 4 + 1
        -- First triangle
        table.insert(indices, base)     -- 0
        table.insert(indices, base + 1) -- 1  
        table.insert(indices, base + 2) -- 2
        -- Second triangle  
        table.insert(indices, base)     -- 0
        table.insert(indices, base + 2) -- 2
        table.insert(indices, base + 3) -- 3
    end
    
    self.grassMesh:setVertexMap(indices)
    self.grassMesh:setTexture(self.grassTexture)
    
    self.x = x
    self.y = y
    self.width = width
    self.height = height
    self.grassCount = areaGrassCount
end

function GrassRenderer:update(dt)
    self.time = self.time + dt
    
    -- Simple wind variation (minimal CPU work)
    self.windDirection.x = math.cos(self.time * 0.5)
    self.windDirection.y = math.sin(self.time * 0.3) * 0.5
    self.windStrength = 0.4 + math.sin(self.time * 0.8) * 0.2
end

function GrassRenderer:draw()
    if not self.grassMesh then return end
    
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
    self.grassShader:send("playerPos", {playerX, playerY})
    self.grassShader:send("playerRadius", playerRadius)
    -- self.grassShader:send("screenSize", {love.graphics.getWidth(), love.graphics.getHeight()})
    self.grassShader:send("noiseTexture", self.noiseTexture)
    self.grassShader:send("lightColor", {2.0, 0.95, 0.8})
    self.grassShader:send("ambientColor", {0.3, 0.4, 0.3})
    
    -- Single draw call for all grass!
    -- love.graphics.setBlendMode("subrract", "premultiplied")
    love.graphics.setColor(1, 1, 1, 1)
    -- love.graphics.setBlendMode("add")
    
    love.graphics.draw(self.grassMesh)
    
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

function GrassRenderer:drawToCanvas(canvas)
    love.graphics.setCanvas(canvas)
    love.graphics.clear()
    self:draw()
    love.graphics.setCanvas()
end

-- Create demo instance
local grass = GrassRenderer.new(800)
local demo = {}

function demo.load()
    grass:setGrassArea(var.game_width/2, 50, var.game_width, var.game_height/4, 100)
end

function demo.update(dt)
    grass:update(dt)
    -- grass:setGrassArea(var.game_width/2, 50, var.game_width*math.sin(fire.t) + 1, var.game_height/4, 100)

end

function demo.draw()
    grass:draw()
end

return {
    GrassRenderer = GrassRenderer,
    public = demo
}