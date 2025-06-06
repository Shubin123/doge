-- Grass Rendering Module for LÖVE Engine
-- Features: Animated grass with wind effects using GLSL shaders

local GrassRenderer = {}
GrassRenderer.__index = GrassRenderer


function GrassRenderer.new(grassCount)
    local self = setmetatable({}, GrassRenderer)
    
    self.grassCount = 1000
    self.time = 0
    self.windDirection = {x = 1, y = 2}
    self.windStrength = 3
    self.windSpeed = 4.0
    
    self:initShaders()
    -- self:createGrassData()
    self:createTexture()
    
    return self
end

function GrassRenderer:initShaders()
    -- Grass animation shader - follows LÖVE shader format like your water example
    self.grassShader = love.graphics.newShader([[
        //#pragma language glsl3
        
        
        uniform Image noiseTexture;
        //uniform Image grassTexture;
        uniform float time;
        uniform vec2 windDirection = vec2(1.0, 0.5);
        uniform float windStrength = 0.3;
        uniform float windSpeed = 2.0;
        uniform vec2 screenSize;
        uniform vec3 lightColor = vec3(2.0, 0.95, 0.8);
        uniform vec3 ambientColor = vec3(0.3, 0.4, 0.3);
        
        vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
            // Sample the grass texture
            vec4 texColor = Texel(tex, texture_coords);
            
            // Alpha test - discard transparent pixels
            if (texColor.a < 0.1) {
                discard;
            }
            
            // Calculate wind effect based on screen position
            vec2 grassPos = screen_coords / screenSize;
            float windWave = sin(time * windSpeed + grassPos.x * 10.0 + grassPos.y * 8.0);
            float windNoise = sin(time * windSpeed * 1.7 + grassPos.x * 15.0) * 0.5;
            
            // Create wind displacement effect on color
            float windEffect = windWave * windNoise * windStrength;
            
            // Height-based wind effect (top of grass moves more)
            float heightFactor = texture_coords.y; // 0 at bottom, 1 at top
            windEffect *= heightFactor;
            
            // Sample noise for additional variation
            vec2 noiseCoord = grassPos * 5.0 + vec2(time * 0.1, time * 0.15);
            vec4 noise = Texel(noiseTexture, noiseCoord);
            
            // Apply lighting
            vec3 lighting = ambientColor + lightColor * 0.8;
            
            // Apply grass color with wind effects
            vec3 finalColor = texColor.rgb * color.rgb * lighting;
            
            // Add wind color shift
            float windColorShift = windEffect * 0.3;
            finalColor = mix(finalColor, finalColor * vec3(0.8, 1.2, 0.9), windColorShift);
            
            // Add noise-based color variation
            finalColor += (noise.rgb - 0.5) * 0.1;
            
            // Height-based alpha (grass tips are more transparent)
            float heightAlpha = mix(0.9, 0.6, texture_coords.y);
            
            return vec4(finalColor, texColor.a * heightAlpha * color.a);
        }
    ]])
end

-- function GrassRenderer:createGrassData()
--     -- Create individual grass blades as separate quads
--     self.grassBlades = {}
    
--     local W = love.graphics.getWidth()
--     local H = love.graphics.getHeight()
    
--     for i = 1, self.grassCount do
--         local blade = {}
        
--         -- Random position
--         blade.x = love.math.random(0, W)
--         blade.y = love.math.random(H * 0.4, H)
        
--         -- Random properties
--         blade.width = love.math.random(2, 6)
--         blade.height = love.math.random(3, 10)
--         blade.rotation = love.math.random() * math.pi * 0.2 - math.pi * 0.1 -- Small random rotation
--         blade.scale = 0.8 + love.math.random() * 0.4
        
--         -- Color variation (different shades of green)
--         local greenVariation = 0.8 + love.math.random() * 0.4
--         blade.color = {
--             0.2 + love.math.random() * 0.3,  -- Red
--             greenVariation,                   -- Green
--             0.1 + love.math.random() * 0.2,   -- Blue
--             1.0                               -- Alpha
--         }
        
--         -- Wind properties for individual variation
--         blade.windPhase = love.math.random() * math.pi * 2
--         blade.windIntensity = 0.7 + love.math.random() * 0.6
        
--         table.insert(self.grassBlades, blade)
--     end
-- end

function GrassRenderer:createTexture()
    -- Create a simple procedural grass texture
    local width, height = 16, 32
    local imageData = love.image.newImageData("gfx/noise.png")
    --   local imageData = love.graphics.newImage("gfx/noise.png")
    
    imageData:mapPixel(function(x, y, r, g, b, a)
        local normalizedY = y / height
        local normalizedX = x / width
        
        -- Create grass blade shape
        local bladeWidth = math.abs(normalizedX - 0.5) * 2
        local alpha = (1.0 - bladeWidth) * (1.0 - normalizedY * normalizedY)
        
        if alpha > 0.1 then
            return 
                (50 + love.math.random(30)) / 255,   -- R
                (100 + love.math.random(50)) / 255,  -- G
                (30 + love.math.random(20)) / 255,   -- B
                math.min(1, alpha)                   -- A
        else
            return 0, 0, 0, 0  -- Transparent
        end
    end)
    
    self.grassTexture = love.graphics.newImage(imageData)
    self.grassTexture:setWrap("repeat", "repeat")
    self.grassTexture:setFilter("linear", "linear")

    
    -- Create simple noise texture for variation
    local noiseData = love.image.newImageData(64, 64)
    noiseData:mapPixel(function(x, y, r, g, b, a)
        return love.math.random(), love.math.random(), love.math.random(), 1
    end)
    
    self.noiseTexture = noise_texture
    -- self.noiseTexture:setWrap("repeat", "repeat")
    -- self.noiseTexture:setFilter("linear", "linear")
end

function GrassRenderer:update(dt)
    self.time = self.time + dt
    
    -- Get player position
    local playerX = player.body:getX() 
    local playerY = player.body:getY()
    
    -- Update wind with some variation
    self.windDirection.x = math.cos(self.time * 0.5)
    self.windDirection.y = math.sin(self.time * 0.3) * 0.5
    self.windStrength = 0.4 + math.sin(self.time * 0.8) * 0.2
    
    -- Player interaction settings
    local playerRadius = math.max(self.width, self.height) * 0.7  -- Player influence radius
    local maxPlayerEffect = 2.0  -- Maximum displacement from player
    
    -- Update individual grass blade positions based on wind and player interaction
    for _, blade in ipairs(self.grassBlades) do
        -- Calculate wind effect
        local windEffect = math.sin(self.time * self.windSpeed + blade.windPhase) * self.windStrength * blade.windIntensity
        local windOffsetX = self.windDirection.x * windEffect * blade.height * 0.1
        local windOffsetY = self.windDirection.y * windEffect * blade.height * 0.05
        
        -- Calculate player interaction
        local dx = blade.x - playerX
        local dy = blade.y - playerY
        local distance = math.sqrt(dx * dx + dy * dy)
        
        local playerOffsetX = 0
        local playerOffsetY = 0
        
        if distance < playerRadius*0.1  and distance > 0 then
            -- Calculate influence based on distance (closer = stronger effect)
            local influence = 1 - (distance / playerRadius)
            influence = influence * influence  -- Square for more dramatic falloff
            
            -- Calculate direction away from player
            local dirX = dx / distance
            local dirY = dy / distance
            
            -- Apply player displacement
            local displacement = maxPlayerEffect * influence * blade.height * 1.15
            playerOffsetX = dirX * displacement
            playerOffsetY = dirY * displacement * 0.5  -- Less vertical displacement
            
            -- Add some dynamic movement when player is very close
            if distance < playerRadius * 0.5 then
                local dynamicEffect = math.sin(self.time * 8 + blade.windPhase) * influence * 3
                playerOffsetX = playerOffsetX + dynamicEffect * dirX
                playerOffsetY = playerOffsetY + dynamicEffect * dirY * 0.3
            end
        end
        
        -- Combine wind and player effects
        blade.currentWindOffset = {
            x = windOffsetX + playerOffsetX,
            y = windOffsetY + playerOffsetY
        }
        
        -- Store player influence for potential use in rendering (color changes, etc.)
        blade.playerInfluence = distance < playerRadius and (1 - (distance / playerRadius)) or 0
    end
end

-- print(playerX >= 120)
    -- print(playerX <= 280)
    -- print(playerY >= 320)
    -- print(playerY <= 380)

function GrassRenderer:setWind(direction, strength, speed)
    self.windDirection = direction or self.windDirection
    self.windStrength = strength or self.windStrength
    self.windSpeed = speed or self.windSpeed
end

function GrassRenderer:draw()
    -- Save current graphics state
    love.graphics.push()
    
    -- Enable blending for transparency
    love.graphics.setBlendMode("alpha")
    
    -- Use grass shader
    love.graphics.setShader(self.grassShader)
    
    -- Send uniforms to shader
    self.grassShader:send("time", self.time)
    --self.grassShader:send("windDirection", {self.windDirection.x, self.windDirection.y})
    self.grassShader:send("windStrength", self.windStrength)
    self.grassShader:send("windSpeed", self.windSpeed)
    self.grassShader:send("screenSize", {love.graphics.getWidth(), love.graphics.getHeight()})
    self.grassShader:send("noiseTexture", noise_texture)
    
    -- Draw each grass blade with frustum culling
    local rendered_count = 0
    local total_count = #self.grassBlades
    
    for _, blade in ipairs(self.grassBlades) do
        -- Use distance-based culling - default to not rendering if no camera info
        local should_render = false
        
        if camera and camera.x and camera.y and camera.view_radius then
            -- Calculate distance from camera center to grass blade
            local dx = blade.x - camera.x
            local dy = blade.y - camera.y
            local distance = math.sqrt(dx * dx + dy * dy)
            
            -- Only render if within view radius with tight culling
            should_render = distance <= (camera.view_radius * 0.75)  -- Very tight culling
        elseif camera and camera.x and camera.y then
            -- Fallback to basic distance check if view_radius not available
            local dx = blade.x - camera.x
            local dy = blade.y - camera.y
            local distance = math.sqrt(dx * dx + dy * dy)
            should_render = distance <= 300  -- Fixed fallback radius
        end
        
        if should_render then
            rendered_count = rendered_count + 1
            love.graphics.push()
            
            -- Get wind and player offset
            local windX = blade.currentWindOffset and blade.currentWindOffset.x or 0
            local windY = blade.currentWindOffset and blade.currentWindOffset.y or 0
            
            -- Position at the base of the grass (roots stay fixed)
            love.graphics.translate(blade.x, blade.y)
            love.graphics.rotate(blade.rotation)
            love.graphics.scale(blade.scale)
        
            -- Modify color based on player influence (optional enhancement)
            local baseColor = blade.color
            -- if blade.playerInfluence and blade.playerInfluence > 0 then
            --     -- Slightly brighten grass near player
            --     local brightnessFactor = 1 + (blade.playerInfluence * 0.2)
            --     love.graphics.setColor(
            --         math.min(baseColor[1] * brightnessFactor, 1),
            --         math.min(baseColor[2] * brightnessFactor, 1),
            --         math.min(baseColor[3] * brightnessFactor, 1),
            --         baseColor[4]
            --     )
            -- else
                love.graphics.setColor(baseColor)
            -- end
            
            -- Draw grass blade with bend effect
            -- Instead of moving the whole blade, we'll draw it as a curved shape
            local segments = 8  -- Number of segments to create the bend
            local segmentHeight = blade.height / segments
            
            for i = 0, segments - 1 do
                local t = i / segments  -- Progress from 0 (base) to 1 (tip)
                local bendFactor = t * t  -- Quadratic curve - more bend at the tip
                
                -- Calculate offset for this segment
                local segmentOffsetX = windX * bendFactor
                local segmentOffsetY = windY * bendFactor
                
                -- Draw segment as a small rectangle
                love.graphics.push()
                love.graphics.translate(segmentOffsetX, -i * segmentHeight + segmentOffsetY)
                
                -- Taper the width towards the tip
                local widthFactor = 1 - (t * 0.3)  -- 30% narrower at tip
                local segmentWidth = blade.width * widthFactor
                
                love.graphics.rectangle("fill", -segmentWidth/2, -segmentHeight, segmentWidth, segmentHeight)
                love.graphics.pop()
            end
            
            love.graphics.pop()
        end -- Close the should_render if statement
    end
    
    -- Debug output to see if culling is working
    if camera and camera.view_radius then
        -- Uncomment for debugging: print("Grass: rendered " .. rendered_count .. "/" .. total_count .. " (radius: " .. math.floor(camera.view_radius) .. ")")
    end
    
    -- Reset graphics state
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setShader()
    love.graphics.pop()
end

-- Alternative method: Draw grass using a canvas for better performance
function GrassRenderer:drawToCanvas(canvas)
    love.graphics.setCanvas(canvas)
    love.graphics.clear()
    
    self:draw()
    
    love.graphics.setCanvas()
end

-- Method to create grass in specific areas (like your water.setWaterArea)
function GrassRenderer:setGrassArea(x, y, width, height, density)
    density = density or 1.0
    
    -- Clear existing grass
    self.grassBlades = {}
    
    -- Calculate grass count based on area and density
    local areaGrassCount = math.floor((width * height * density) / 1000)
    areaGrassCount = math.min(areaGrassCount, 2000) -- Limit for performance
    
    -- Generate grass within the specified area
    for i = 1, areaGrassCount do
        local blade = {}
        
        -- Position within the specified area
        blade.x = x + love.math.random() * width
        blade.y = y + love.math.random() * height
        
        -- Random properties
        blade.width = love.math.random(0.1, 1)
        blade.height = love.math.random(1, 7)
        blade.rotation = love.math.random() * math.pi * 0.2 - math.pi * 0.1
        blade.scale = 0.8 + love.math.random()
        
        -- Color variation
        local greenVariation = 0.8 + love.math.random() * 0.4
        blade.color = {
            0.2 + love.math.random() * 0.3,
            greenVariation,
            0.1 + love.math.random() * 0.2,
            0.30
        }
        
        -- Wind properties
        blade.windPhase = love.math.random() * math.pi * 2
        blade.windIntensity = 0.7 + love.math.random() * 0.6
        
        table.insert(self.grassBlades, blade)
    end
    self.x = x
    self.y = y
    self.width = width
    self.height = height
    self.grassCount = #self.grassBlades
end

-- Usage example and demo scene
-- local function createGrassDemo()
    local grass = GrassRenderer.new(800)
    
    local demo = {}
    
    function demo.load()
        -- Set grass to cover entire game area with minimal padding since we now have culling
        local padding = 100 -- Reduced padding since culling handles off-screen grass
        grass:setGrassArea(
            -padding, 
            -padding, 
            var.game_width + padding * 2, 
            var.game_height + padding * 2, 
            1500  -- Reduced density for better performance
        )
    end
    
    function demo.update(dt)
        grass:update(dt)
        
        -- Interactive wind control
        if love.keyboard.isDown("left") then
            grass:setWind({x = -1, y = 0}, 0.6, 3.0)
        elseif love.keyboard.isDown("right") then
            grass:setWind({x = 1, y = 0}, 0.6, 3.0)
        elseif love.keyboard.isDown("up") then
            grass:setWind({x = 0, y = -1}, 0.8, 2.5)
        elseif love.keyboard.isDown("down") then
            grass:setWind({x = 0, y = 1}, 0.4, 2.0)
        end
    end
    
    function demo.draw()
        -- Draw background
        -- love.graphics.setColor(0.6, 0.8, 1.0)  -- Sky blue
        -- love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
        
        -- Draw ground
        -- love.graphics.setColor(0.4, 0.3, 0.2)  -- Brown
        -- love.graphics.rectangle("fill", 0, love.graphics.getHeight() * 0.7, 
        --                        love.graphics.getWidth(), love.graphics.getHeight() * 0.3)
        
        
        
        -- Draw grass
        -- love.graphics.setColor(1, 1, 1, 0.001)  -- Reset color
        grass:draw()
        -- grass:drawToCanvas()
        -- love.graphics.setColor(1, 1, 1, 1)  -- Reset color
        
        -- Draw instructions
        -- love.graphics.setColor(0, 0, 0,0.1)
        -- love.graphics.print("Use arrow keys to control wind", 10, 10)
        -- print("Grass count: " .. grass.grassCount)
        -- love.graphics.print("Wind: " .. string.format("%.2f, %.2f", grass.windDirection.x, grass.windDirection.y), 10, 50)


        
    end
    
    -- return demo
-- end

return {
    GrassRenderer = GrassRenderer,
    demo = demo
}