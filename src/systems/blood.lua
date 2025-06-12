local blood = {}

-- Blood pool configuration
blood.pool_size = 64  -- Must match TOTAL_BLOOD_DROPS in shader
blood.growing_time = 0.2  -- Time for blood drop to grow
blood.drying_time = 4.0   -- Time for blood drop to dry
blood.delay_until_drying_starts = 0.2  -- Idle time when fully grown

-- Blood pool state
blood.bloody_pool = {}
blood.positions = {}
blood.scales = {}
blood.shader = nil
blood.blood_texture = nil
blood.floor_texture = nil
blood.canvas = nil

-- BloodDrop class
local BloodDrop = {}
BloodDrop.__index = BloodDrop

function BloodDrop.new(index)
    local drop = setmetatable({}, BloodDrop)
    drop.active = false
    drop.index = index
    return drop
end

function BloodDrop:start(pos)
    self.active = true
    blood.positions[self.index] = {pos.x, pos.y}
end

function BloodDrop:animate(value)
    blood.scales[self.index] = value
end

function BloodDrop:stop()
    self.active = false
    blood.scales[self.index] = 0.0
end

-- Blood system functions
function blood.load()
    -- Initialize position and scale arrays
    blood.positions = {}
    blood.scales = {}
    
    for i = 1, blood.pool_size do
        blood.positions[i] = {0, 0}
        blood.scales[i] = 0.0
    end
    
    -- Create blood drop objects
    blood.bloody_pool = {}
    for i = 1, blood.pool_size do
        table.insert(blood.bloody_pool, BloodDrop.new(i))
    end
    
    -- Load shader
    local shader_code = love.filesystem.read("shaders_/blood_pool.frag")
    if shader_code then
        blood.shader = love.graphics.newShader(shader_code)
    else
        print("Warning: Blood shader not found")
    end
    
    -- Create blood texture (radial gradient)
    blood.blood_texture = blood.createBloodTexture()
    
    -- Create canvas for blood effects
    local w, h = love.graphics.getDimensions()
    blood.canvas = love.graphics.newCanvas(w, h)
    
end

function blood.createBloodTexture()
    -- Create a 64x64 radial gradient texture for blood drops
    local size = 64
    local imageData = love.image.newImageData(size, size)
    
    local center = size / 2
    local maxDist = center * 0.8  -- Create soft edge
    
    for x = 0, size - 1 do
        for y = 0, size - 1 do
            local dx = x - center
            local dy = y - center
            local dist = math.sqrt(dx * dx + dy * dy)
            
            -- Create radial gradient with soft falloff
            local alpha = 1.0
            if dist > maxDist then
                alpha = math.max(0, 1.0 - (dist - maxDist) / (center - maxDist))
            end
            
            -- Make it smoother with exponential falloff
            alpha = alpha * alpha
            
            imageData:setPixel(x, y, alpha, alpha, alpha, 1)
        end
    end
    
    local texture = love.graphics.newImage(imageData)
    texture:setFilter("linear", "linear")
    return texture
end

function blood.update(dt)
    -- Update blood drop animations
    for _, drop in ipairs(blood.bloody_pool) do
        if drop.active and drop.startTime then
            local elapsed = love.timer.getTime() - drop.startTime
            
            if drop.phase == "growing" then
                if elapsed < blood.growing_time then
                    local progress = elapsed / blood.growing_time
                    drop:animate(progress)
                else
                    drop.phase = "idle"
                    drop:animate(1.0)
                end
            elseif drop.phase == "idle" then
                if elapsed >= blood.growing_time + blood.delay_until_drying_starts then
                    drop.phase = "drying"
                end
            elseif drop.phase == "drying" then
                local dryStart = blood.growing_time + blood.delay_until_drying_starts
                if elapsed >= dryStart + blood.drying_time then
                    drop:stop()
                    drop.phase = "done"
                else
                    local dryProgress = (elapsed - dryStart) / blood.drying_time
                    drop:animate(1.0 - dryProgress)
                end
            end
        end
    end
    
    -- Note: Shader uniforms are sent in drawBackground() function
end

function blood.dropAt(pos)
    -- Find an inactive blood drop to use
    for i, drop in ipairs(blood.bloody_pool) do
        if not drop.active then
            drop:start(pos)
            
            -- Simple timer-based animation
            drop.startTime = love.timer.getTime()
            drop.phase = "growing"  -- growing, idle, drying, done
            
            break
        end
    end
end


function blood.drawBackground(drawable, x, y)
    -- For now, just draw the normal map - shader implementation coming later
    if drawable and drawable.draw then
        drawable:draw(x or 0, y or 0, 1)
    elseif drawable then
        love.graphics.draw(drawable, x or 0, y or 0)
    end
end

-- Add blood drops to dynamic draw list for proper Z-sorting
function blood.populate()
    if not dynamic_draw_list then
        return
    end
    
    for i = 1, blood.pool_size do
        if blood.scales[i] > 0.01 then
            local x = blood.positions[i][1]
            local y = blood.positions[i][2]
            local radius = blood.scales[i] * 8  -- Scale to visible size
            
            -- Add blood drop to dynamic draw list with very low sort_y (ground level)
            table.insert(dynamic_draw_list, {
                sort_y = y - 1000,  -- Very low priority - render behind everything
                source_object_type = "blood_drop",
                x = x,
                y = y,
                radius = radius,
                scale = blood.scales[i],
                color = {0.6, 0.05, 0.05, 0.8},
                blend_mode = {"alpha"}
            })
        end
    end
end

-- Simple visual blood effects using basic drawing (backup)
function blood.drawBloodDrops()
    love.graphics.push()
    love.graphics.setColor(0.6, 0.05, 0.05, 0.8)
    
    for i = 1, blood.pool_size do
        if blood.scales[i] > 0.01 then
            local x = blood.positions[i][1]
            local y = blood.positions[i][2]
            local radius = blood.scales[i] * 8  -- Scale to visible size
            
            -- Draw blood drop as a circle
            love.graphics.circle("fill", x, y, radius)
            
            -- Add darker center
            love.graphics.setColor(0.4, 0.02, 0.02, 1.0)
            love.graphics.circle("fill", x, y, radius * 0.6)
            love.graphics.setColor(0.6, 0.05, 0.05, 0.8)
        end
    end
    
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.pop()
end

-- Individual blood drop drawing function for renderer
function blood.drawSingleBloodDrop(blood_data)
    love.graphics.push()
    love.graphics.setColor(blood_data.color[1], blood_data.color[2], blood_data.color[3], blood_data.color[4])
    
    -- Draw blood drop as a circle
    love.graphics.circle("fill", blood_data.x, blood_data.y, blood_data.radius)
    
    -- Add darker center for depth
    love.graphics.setColor(0.4, 0.02, 0.02, blood_data.color[4])
    love.graphics.circle("fill", blood_data.x, blood_data.y, blood_data.radius * 0.6)
    
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.pop()
end

-- Helper function to add blood at enemy damage location
function blood.onEnemyDamage(enemyX, enemyY, damage, direction)
    -- Scale blood effects based on damage (weapon type impact)
    local baseDrops = math.min(12, math.max(1, math.floor(damage * 1.5))) -- More drops for higher damage
    local spreadFactor = math.min(40, 10 + damage * 3) -- Wider spread for higher damage
    local sizeFactor = math.min(1.5, 0.5 + damage * 0.1) -- Larger drops for higher damage
    
    -- Entry wound effect at impact point (smaller, concentrated)
    local entryDrops = math.ceil(baseDrops * 0.3) -- Fewer drops for entry wound
    for i = 1, entryDrops do
        -- Smaller spread for entry wound
        local offsetX = (math.random() - 0.5) * (spreadFactor * 0.5)
        local offsetY = (math.random() - 0.5) * (spreadFactor * 0.5)
        
        -- Smaller scale for entry drops
        local variedScale = sizeFactor * (0.5 + math.random() * 0.4)
        blood.dropAt(vec2.new(enemyX + offsetX, enemyY + offsetY))
        
        -- Update scale directly for this drop
        blood.scales[#blood.positions] = variedScale
    end
    
    -- Exit wound effect with directional splatter if direction is provided
    if direction then
        local exitDrops = math.ceil(baseDrops * 0.7) -- More drops for exit wound
        local exitSpreadFactor = spreadFactor * 1.2 -- Wider spread for exit
        local exitDistance = 20 + damage * 5 -- Distance beyond enemy for exit splatter
        
        for i = 1, exitDrops do
            -- Project blood along bullet direction for "through-and-through" effect
            local projDistance = exitDistance + math.random() * (exitDistance * 0.5)
            local offsetX = direction.x * projDistance + (math.random() - 0.5) * exitSpreadFactor
            local offsetY = direction.y * projDistance + (math.random() - 0.5) * exitSpreadFactor
            
            -- Larger scale for exit drops
            local variedScale = sizeFactor * (0.8 + math.random() * 0.7)
            blood.dropAt(vec2.new(enemyX + offsetX, enemyY + offsetY))
            
            -- Update scale directly for this drop
            blood.scales[#blood.positions] = variedScale
        end
    end
    
    -- Add gore particles for very high damage (e.g., rocket launcher)
    if damage > 5 then
        -- Simulate gore mist or additional splatter
        local goreDrops = math.floor(damage / 2)
        for i = 1, goreDrops do
            local offsetX = (math.random() - 0.5) * (spreadFactor * 1.5)
            local offsetY = (math.random() - 0.5) * (spreadFactor * 1.5)
            blood.dropAt(vec2.new(enemyX + offsetX, enemyY + offsetY))
            blood.scales[#blood.positions] = sizeFactor * 0.3 * (0.5 + math.random() * 0.5)
        end
    end
end

-- Helper function to add blood trail when enemy moves while bleeding
function blood.onEnemyMove(oldX, oldY, newX, newY, isWounded)
    if not isWounded then return end
    
    -- Calculate distance moved
    local dx = newX - oldX
    local dy = newY - oldY
    local distance = math.sqrt(dx * dx + dy * dy)
    
    -- Add blood drops along the path
    if distance > 10 then  -- Only if moved significant distance
        local numDrops = math.floor(distance / 15)  -- One drop every 15 pixels
        
        for i = 1, numDrops do
            local t = i / numDrops
            local x = oldX + dx * t
            local y = oldY + dy * t
            
            -- Random chance to drop blood
            if math.random() < 0.3 then  -- 30% chance per position
                blood.dropAt(vec2.new(x, y))
            end
        end
    end
end

return blood
