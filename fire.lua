-- Fire Shader System
FireRenderer = {}
FireRenderer.__index = FireRenderer

function FireRenderer:new(x, y, width, height)
    local fire = setmetatable({}, FireRenderer)
    
    fire.x = x or 0
    fire.y = y or 0
    fire.width = width or 200
    fire.height = height or 300
    fire.time = 0
    
    -- Create fire shader
    fire.fireShader = love.graphics.newShader([[
        uniform float time;
        uniform vec2 resolution;
        uniform float intensity;
        uniform vec2 windDirection;
        uniform Image noiseTexture;
        
        // Simple noise function
        float noise(vec2 p) {
            return Texel(noiseTexture, p * 0.1).r;
        }
        
        // Fractal noise
        float fbm(vec2 p) {
            float value = 0.0;
            float amplitude = 0.5;
            for (int i = 0; i < 4; i++) {
                value += amplitude * noise(p);
                p *= 2.0;
                amplitude *= 0.5;
            }
            return value;
        }
        
        vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
            vec2 uv = texture_coords;
            vec2 p = uv * 2.0 - 1.0;
            p.x *= resolution.x / resolution.y;
            
            // Add time-based movement
            p.y += time * 0.3;
            p.x += sin(time * 0.5 + p.y * 3.0) * 0.1;
            
            // Add wind effect
            p.x += windDirection.x * 0.2;
            p.y += windDirection.y * 0.1;
            
            // Create flame shape - wider at bottom, narrower at top
            float flameWidth = (1.0 - uv.y) * 0.8 + 0.2;
            float flameMask = 1.0 - smoothstep(0.0, flameWidth, abs(p.x));
            
            // Generate fire noise
            float noise1 = fbm(p * 3.0 + vec2(0.0, time * 2.0));
            float noise2 = fbm(p * 6.0 + vec2(time * 1.5, 0.0));
            float noise3 = fbm(p * 12.0 - vec2(0.0, time * 3.0));
            
            // Combine noises
            float fireNoise = noise1 * 0.5 + noise2 * 0.3 + noise3 * 0.2;
            
            // Create fire gradient (hot at bottom, cooler at top)
            float gradient = 1.0 - uv.y;
            
            // Combine everything
            float fireStrength = flameMask * fireNoise * gradient * intensity;
            fireStrength = smoothstep(0.1, 0.8, fireStrength);
            
            // Fire colors - from white/yellow at core to red/orange at edges
            vec3 fireColor;
            if (fireStrength > 0.7) {
                // Hot core - white to yellow
                fireColor = mix(vec3(1.0, 1.0, 0.8), vec3(1.0, 1.0, 1.0), (fireStrength - 0.7) / 0.3);
            } else if (fireStrength > 0.4) {
                // Middle - yellow to orange
                fireColor = mix(vec3(1.0, 0.5, 0.0), vec3(1.0, 1.0, 0.8), (fireStrength - 0.4) / 0.3);
            } else if (fireStrength > 0.1) {
                // Edges - red to orange
                fireColor = mix(vec3(0.8, 0.1, 0.0), vec3(1.0, 0.5, 0.0), (fireStrength - 0.1) / 0.3);
            } else {
                fireColor = vec3(0.0);
            }
            
            // Add some flickering
            float flicker = sin(time * 8.0 + p.x * 10.0) * 0.1 + 0.9;
            fireColor *= flicker;
            
            return vec4(fireColor, fireStrength);
        }
    ]])
    
    -- Create noise texture for the shader
    fire.noiseTexture = fire:createNoiseTexture(256, 256)
    
    -- Fire properties
    fire.intensity = 1.0
    fire.windDirection = {x = 0, y = 0}
    
    -- Create particle system for sparks and embers
    fire.sparkTexture = fire:createSparkTexture()
    fire.particleSystem = love.graphics.newParticleSystem(fire.sparkTexture, 100)
    
    -- Configure particle system
    fire.particleSystem:setParticleLifetime(1.0, 3.0)
    fire.particleSystem:setEmissionRate(30)
    fire.particleSystem:setSizeVariation(0.5)
    fire.particleSystem:setLinearAcceleration(-20, -100, 20, -200)
    fire.particleSystem:setColors(
        1.0, 1.0, 0.8, 1.0,  -- Start: bright yellow
        1.0, 0.5, 0.0, 0.8,  -- Middle: orange
        0.8, 0.1, 0.0, 0.5,  -- End: red
        0.2, 0.0, 0.0, 0.0   -- Fade: dark red
    )
    fire.particleSystem:setSizes(0.5, 1.0, 0.8, 0.2)
    fire.particleSystem:setRotation(0, 2 * math.pi)
    fire.particleSystem:setSpinVariation(1)
    fire.particleSystem:setRadialAcceleration(-50, 50)
    fire.particleSystem:setTangentialAcceleration(-10, 10)
    
    return fire
end

function FireRenderer:createNoiseTexture(width, height)
    local imageData = love.image.newImageData(width, height)
    
    for x = 0, width - 1 do
        for y = 0, height - 1 do
            -- Generate Perlin-like noise
            local noise = 0
            local amplitude = 1
            local frequency = 0.01
            
            for i = 1, 4 do
                noise = noise + amplitude * (love.math.noise(x * frequency, y * frequency) * 2 - 1)
                amplitude = amplitude * 0.5
                frequency = frequency * 2
            end
            
            noise = (noise + 1) * 0.5  -- Normalize to 0-1
            imageData:setPixel(x, y, noise, noise, noise, 1)
        end
    end
    
    return love.graphics.newImage(imageData)
end

function FireRenderer:createSparkTexture()
    local size = 8
    local imageData = love.image.newImageData(size, size)
    local center = size / 2
    
    for x = 0, size - 1 do
        for y = 0, size - 1 do
            local dx = x - center + 0.5
            local dy = y - center + 0.5
            local distance = math.sqrt(dx * dx + dy * dy)
            local alpha = math.max(0, 1 - distance / center)
            imageData:setPixel(x, y, 1, 1, 1, alpha)
        end
    end
    
    return love.graphics.newImage(imageData)
end

function FireRenderer:update(dt)
    self.time = self.time + dt
    
    -- Update particle system
    self.particleSystem:update(dt)
    
    -- Emit particles from the base of the fire
    local emitX = self.x + self.width * 0.5 + (love.math.random() - 0.5) * self.width * 0.3
    local emitY = self.y + self.height * 0.9
    self.particleSystem:setPosition(emitX, emitY)
    
    -- Add some wind variation
    self.windDirection.x = math.sin(self.time * 0.3) * 0.5
    self.windDirection.y = math.cos(self.time * 0.2) * 0.2
    
    -- Vary intensity slightly
    self.intensity = 0.8 + math.sin(self.time * 2.0) * 0.2
end

function FireRenderer:setWind(x, y)
    self.windDirection.x = x or 0
    self.windDirection.y = y or 0
end

function FireRenderer:setIntensity(intensity)
    self.intensity = intensity or 1.0
end

function FireRenderer:draw()
    -- Save graphics state
    love.graphics.push()
    
    -- Set additive blending for fire effect
    love.graphics.setBlendMode("add")
    
    -- Use fire shader
    love.graphics.setShader(self.fireShader)
    
    -- Send uniforms to shader
    self.fireShader:send("time", self.time)
    self.fireShader:send("resolution", {self.width, self.height})
    self.fireShader:send("intensity", self.intensity)
    self.fireShader:send("windDirection", {self.windDirection.x, self.windDirection.y})
    self.fireShader:send("noiseTexture", self.noiseTexture)
    
    -- Draw fire quad
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", self.x, self.y, self.width, self.height)
    
    -- Reset shader
    love.graphics.setShader()
    
    -- Draw particle system on top
    love.graphics.setBlendMode("alpha")
    love.graphics.draw(self.particleSystem)
    
    -- Restore graphics state
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode("alpha")
    love.graphics.pop()
end

-- Usage example:
--[[
function love.load()
    fire = FireRenderer:new(300, 200, 150, 250)
end

function love.update(dt)
    fire:update(dt)
    
    -- Optional: control fire with mouse
    local mx, my = love.mouse.getPosition()
    local windX = (mx - 400) / 400  -- Assuming 800px wide screen
    fire:setWind(windX, 0)
end

function love.draw()
    fire:draw()
end
--]]