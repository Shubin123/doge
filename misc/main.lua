-- main.lua - LÖVE Liquid Physics Engine with Wave Propagation and Collision
-- Requires LÖVE (Love2D) engine to run

local lg = love.graphics
local lp = love.physics
local lm = love.math

-- Simulation parameters
local params = {
    viscosity = 0.5,
    density = 2000,
    pressure = 1.3,
    waveSpeed = 300,
    damping = 0.98,
    gridSize = 8,
    particleRadius = 4,
    maxParticles = 2000,
    dt = 1/60
}

-- Grid-based wave propagation system
local WaveGrid = {}
WaveGrid.__index = WaveGrid

function WaveGrid:new(width, height, cellSize)
    local grid = {
        width = width,
        height = height,
        cellSize = cellSize,
        cols = math.ceil(width / cellSize),
        rows = math.ceil(height / cellSize),
        current = {},
        previous = {},
        velocity = {},
        obstacles = {}
    }
    
    -- Initialize grids
    for i = 1, grid.rows do
        grid.current[i] = {}
        grid.previous[i] = {}
        grid.velocity[i] = {}
        grid.obstacles[i] = {}
        for j = 1, grid.cols do
            grid.current[i][j] = 0
            grid.previous[i][j] = 0
            grid.velocity[i][j] = 0
            grid.obstacles[i][j] = false
        end
    end
    
    setmetatable(grid, WaveGrid)
    return grid
end

function WaveGrid:addObstacle(x, y, radius)
    local centerCol = math.floor(x / self.cellSize) + 1
    local centerRow = math.floor(y / self.cellSize) + 1
    local cellRadius = math.ceil(radius / self.cellSize)
    
    for row = math.max(1, centerRow - cellRadius), math.min(self.rows, centerRow + cellRadius) do
        for col = math.max(1, centerCol - cellRadius), math.min(self.cols, centerCol + cellRadius) do
            local dx = (col - 1) * self.cellSize - x
            local dy = (row - 1) * self.cellSize - y
            if dx * dx + dy * dy <= radius * radius then
                self.obstacles[row][col] = true
            end
        end
    end
end

function WaveGrid:update(dt)
    local waveSpeed2 = params.waveSpeed * params.waveSpeed
    local dtSquared = dt * dt
    
    -- Wave equation: ∂²u/∂t² = c²∇²u
    for row = 2, self.rows - 1 do
        for col = 2, self.cols - 1 do
            if not self.obstacles[row][col] then
                -- Calculate Laplacian (∇²u)
                local laplacian = (self.current[row-1][col] + self.current[row+1][col] + 
                                 self.current[row][col-1] + self.current[row][col+1] - 
                                 4 * self.current[row][col]) / (self.cellSize * self.cellSize)
                
                -- Wave propagation with collision reflection
                local newHeight = 2 * self.current[row][col] - self.previous[row][col] + 
                                waveSpeed2 * dtSquared * laplacian
                
                -- Apply damping
                newHeight = newHeight * params.damping
                
                -- Handle obstacle collisions
                local hasObstacleNeighbor = self.obstacles[row-1][col] or self.obstacles[row+1][col] or
                                          self.obstacles[row][col-1] or self.obstacles[row][col+1]
                
                if hasObstacleNeighbor then
                    -- Reflect waves at obstacles
                    newHeight = newHeight * 0.7 -- Energy loss on collision
                end
                
                self.velocity[row][col] = newHeight
            else
                self.velocity[row][col] = 0
            end
        end
    end
    
    -- Update grid states
    for row = 1, self.rows do
        for col = 1, self.cols do
            self.previous[row][col] = self.current[row][col]
            self.current[row][col] = self.velocity[row][col]
        end
    end
end

function WaveGrid:addDisturbance(x, y, intensity)
    local col = math.floor(x / self.cellSize) + 1
    local row = math.floor(y / self.cellSize) + 1
    
    if row >= 1 and row <= self.rows and col >= 1 and col <= self.cols then
        if not self.obstacles[row][col] then
            self.current[row][col] = self.current[row][col] + intensity
            
            -- Spread disturbance to neighbors
            local spread = intensity * 0.3
            for dr = -1, 1 do
                for dc = -1, 1 do
                    local nr, nc = row + dr, col + dc
                    if nr >= 1 and nr <= self.rows and nc >= 1 and nc <= self.cols then
                        if not self.obstacles[nr][nc] then
                            self.current[nr][nc] = self.current[nr][nc] + spread
                        end
                    end
                end
            end
        end
    end
end

function WaveGrid:getHeight(x, y)
    local col = math.floor(x / self.cellSize) + 1
    local row = math.floor(y / self.cellSize) + 1
    
    if row >= 1 and row <= self.rows and col >= 1 and col <= self.cols then
        return self.current[row][col]
    end
    return 0
end

-- Fluid Particle class
local FluidParticle = {}
FluidParticle.__index = FluidParticle

function FluidParticle:new(x, y)
    local particle = {
        x = x, y = y,
        vx = 0, vy = 0,
        px = x, py = y, -- Previous position
        density = params.density,
        pressure = 0,
        fx = 0, fy = 0,
        neighbors = {},
        color = {0.2, 0.6, 1.0, 0.8}
    }
    setmetatable(particle, FluidParticle)
    return particle
end

function FluidParticle:update(dt, waveGrid)
    -- Apply wave forces
    local waveHeight = waveGrid:getHeight(self.x, self.y)
    local waveForce = waveHeight * 50
    
    -- Calculate wave gradient for horizontal forces
    local dx = 2
    local leftHeight = waveGrid:getHeight(self.x - dx, self.y)
    local rightHeight = waveGrid:getHeight(self.x + dx, self.y)
    local topHeight = waveGrid:getHeight(self.x, self.y - dx)
    local bottomHeight = waveGrid:getHeight(self.x, self.y + dx)
    
    local gradientX = (rightHeight - leftHeight) / (2 * dx)
    local gradientY = (bottomHeight - topHeight) / (2 * dx)
    
    -- Apply forces
    self.fx = self.fx - gradientX * 100
    self.fy = self.fy - gradientY * 100 + waveForce
    
    -- Add gravity
    self.fy = self.fy + 500
    
    -- Integrate velocity (Verlet integration)
    local ax = self.fx / self.density
    local ay = self.fy / self.density
    
    local newX = 2 * self.x - self.px + ax * dt * dt
    local newY = 2 * self.y - self.py + ay * dt * dt
    
    -- Calculate velocity for rendering
    self.vx = (newX - self.x) / dt
    self.vy = (newY - self.y) / dt
    
    -- Update positions
    self.px, self.py = self.x, self.y
    self.x, self.y = newX, newY
    
    -- Apply damping
    self.vx = self.vx * params.damping
    self.vy = self.vy * params.damping
    
    -- Reset forces
    self.fx, self.fy = 0, 0
    
    -- Update color based on velocity
    local speed = math.sqrt(self.vx * self.vx + self.vy * self.vy)
    local speedNorm = math.min(speed / 200, 1)
    self.color[1] = 0.2 + speedNorm * 0.8  -- Red component
    self.color[2] = 0.6 + speedNorm * 0.4  -- Green component
    self.color[3] = 1.0 - speedNorm * 0.3  -- Blue component
end

function FluidParticle:checkCollision(obstacles)
    for _, obstacle in ipairs(obstacles) do
        local dx = self.x - obstacle.x
        local dy = self.y - obstacle.y
        local dist = math.sqrt(dx * dx + dy * dy)
        
        if dist < obstacle.radius + params.particleRadius then
            -- Collision detected
            local overlap = obstacle.radius + params.particleRadius - dist
            local nx, ny = dx / dist, dy / dist
            
            -- Separate particles
            self.x = self.x + nx * overlap * 0.5
            self.y = self.y + ny * overlap * 0.5
            
            -- Reflect velocity with energy loss
            local dot = self.vx * nx + self.vy * ny
            self.vx = self.vx - 2 * dot * nx * 0.8
            self.vy = self.vy - 2 * dot * ny * 0.8
            
            return true
        end
    end
    
    -- Boundary collisions
    local bounced = false
    if self.x < params.particleRadius then
        self.x = params.particleRadius
        self.vx = math.abs(self.vx) * 0.7
        bounced = true
    elseif self.x > love.graphics.getWidth() - params.particleRadius then
        self.x = love.graphics.getWidth() - params.particleRadius
        self.vx = -math.abs(self.vx) * 0.7
        bounced = true
    end
    
    if self.y < params.particleRadius then
        self.y = params.particleRadius
        self.vy = math.abs(self.vy) * 0.7
        bounced = true
    elseif self.y > love.graphics.getHeight() - params.particleRadius then
        self.y = love.graphics.getHeight() - params.particleRadius
        self.vy = -math.abs(self.vy) * 0.7
        bounced = true
    end
    
    return bounced
end

-- Obstacle class
local Obstacle = {}
Obstacle.__index = Obstacle

function Obstacle:new(x, y, radius)
    local obstacle = {
        x = x, y = y,
        radius = radius,
        color = {0.8, 0.3, 0.3, 0.3}
    }
    setmetatable(obstacle, Obstacle)
    return obstacle
end

function Obstacle:render()
    lg.setColor(self.color)
    lg.circle("fill", self.x, self.y, self.radius)
    lg.setColor(1, 1, 1, 0.2)
    lg.circle("line", self.x, self.y, self.radius)
end

-- Main simulation state
local simulation = {
    particles = {},
    obstacles = {},
    waveGrid = nil,
    paused = false,
    showWaves = true,
    mousePressed = false
}

function love.load()
    love.window.setTitle("LÖVE Liquid Physics Engine - Wave Propagation & Collision")
    
    -- Initialize wave grid
    simulation.waveGrid = WaveGrid:new(love.graphics.getWidth(), love.graphics.getHeight(), params.gridSize)
    
    -- Create obstacles
    table.insert(simulation.obstacles, Obstacle:new(200, 300, 50))
    table.insert(simulation.obstacles, Obstacle:new(600, 200, 40))
    table.insert(simulation.obstacles, Obstacle:new(400, 500, 60))
    
    -- Add obstacles to wave grid
    for _, obstacle in ipairs(simulation.obstacles) do
        simulation.waveGrid:addObstacle(obstacle.x, obstacle.y, obstacle.radius)
    end
    
    -- Create initial particles
    for i = 1, 800 do
        local x = love.math.random(100, love.graphics.getWidth() - 100)
        local y = love.math.random(100, 300)
        table.insert(simulation.particles, FluidParticle:new(x, y))
    end
    
    -- Set up graphics
    lg.setBackgroundColor(0.05, 0.05, 0.1)
    lg.setLineWidth(1)
end

function love.update(dt)
    if simulation.paused then return end
    
    dt = math.min(dt, params.dt) -- Cap dt for stability
    
    -- Update wave grid
    simulation.waveGrid:update(dt)
    for k,v in ipairs(simulation.obstacles) do
            v.x = v.x + 100
    end
    -- Update particles
    for i, particle in ipairs(simulation.particles) do
        particle:update(dt, simulation.waveGrid)
        
        -- Check collisions
        -- print(simulation.obstacles.x = simulation.obstacles.x + 1 )
        
        
        -- local collided = particle:checkCollision(simulation.obstacles)
        
        -- Add wave disturbance when particle moves quickly or collides
        local speed = math.sqrt(particle.vx * particle.vx + particle.vy * particle.vy)
        if speed > 50 or collided then
            simulation.waveGrid:addDisturbance(particle.x, particle.y, speed * 0.001)
        end
    end
    
    -- Mouse interaction
    if simulation.mousePressed then
        local mx, my = love.mouse.getPosition()
        simulation.waveGrid:addDisturbance(mx, my, 0.5)
        
        -- Attract nearby particles
        for _, particle in ipairs(simulation.particles) do
            local dx = mx - particle.x
            local dy = my - particle.y
            local dist = math.sqrt(dx * dx + dy * dy)
            
            if dist < 100 and dist > 0 then
                local force = (100 - dist) / 100 * 200
                particle.fx = particle.fx + (dx / dist) * force
                particle.fy = particle.fy + (dy / dist) * force
            end
        end
    end
end

function love.draw()
    -- Render wave grid
    if simulation.showWaves then
        for row = 1, simulation.waveGrid.rows do
            for col = 1, simulation.waveGrid.cols do
                local height = simulation.waveGrid.current[row][col]
                if math.abs(height) > 0.01 then
                    local x = (col - 1) * params.gridSize
                    local y = (row - 1) * params.gridSize
                    local intensity = math.min(math.abs(height) * 10, 1)
                    
                    if height > 0 then
                        lg.setColor(0.3, 0.7, 1.0, intensity * 0.3)
                    else
                        lg.setColor(0.2, 0.3, 0.7, intensity * 0.3)
                    end
                    
                    lg.rectangle("fill", x, y, params.gridSize, params.gridSize)
                end
            end
        end
    end
    
    -- Render obstacles
    for _, obstacle in ipairs(simulation.obstacles) do
        obstacle:render()
    end
    
    -- Render particles with metaball effect
    lg.setBlendMode("add")
    for _, particle in ipairs(simulation.particles) do
        -- lg.setColor(particle.color)
        -- lg.circle("fill", particle.x, particle.y, params.particleRadius)
    end
    lg.setBlendMode("alpha")
    
    -- Render UI
    lg.setColor(1, 1, 1)
    lg.print("FPS: " .. love.timer.getFPS(), 10, 10)
    lg.print("Particles: " .. #simulation.particles, 10, 30)
    lg.print("Wave Speed: " .. params.waveSpeed, 10, 50)
    lg.print("Controls:", 10, 80)
    lg.print("SPACE: Pause/Resume", 10, 100)
    lg.print("W: Toggle wave visualization", 10, 120)
    lg.print("R: Reset simulation", 10, 140)
    lg.print("Mouse: Click and drag to interact", 10, 160)
    lg.print("Arrow keys: Adjust wave speed", 10, 180)
    
    if simulation.paused then
        lg.setColor(1, 1, 0)
        lg.print("PAUSED", love.graphics.getWidth() / 2 - 30, 20)
    end
end

function love.mousepressed(x, y, button)
    if button == 1 then
        simulation.mousePressed = true
        -- Add major wave disturbance
        simulation.waveGrid:addDisturbance(x, y, 2.0)
    elseif button == 2 then
        -- Add new particle at mouse position
        if #simulation.particles < params.maxParticles then
            table.insert(simulation.particles, FluidParticle:new(x, y))
        end
    end
end

function love.mousereleased(x, y, button)
    if button == 1 then
        simulation.mousePressed = false
    end
end

function love.keypressed(key)
    if key == "space" then
        simulation.paused = not simulation.paused
    elseif key == "w" then
        simulation.showWaves = not simulation.showWaves
    elseif key == "r" then
        -- Reset simulation
        simulation.particles = {}
        for i = 1, 800 do
            local x = love.math.random(100, love.graphics.getWidth() - 100)
            local y = love.math.random(100, 300)
            table.insert(simulation.particles, FluidParticle:new(x, y))
        end
        
        -- Reset wave grid
        for row = 1, simulation.waveGrid.rows do
            for col = 1, simulation.waveGrid.cols do
                simulation.waveGrid.current[row][col] = 0
                simulation.waveGrid.previous[row][col] = 0
                simulation.waveGrid.velocity[row][col] = 0
            end
        end
    elseif key == "up" then
        params.waveSpeed = math.min(params.waveSpeed + 50, 1000)
    elseif key == "down" then
        params.waveSpeed = math.max(params.waveSpeed - 50, 50)
    elseif key == "escape" then
        love.event.quit()
    end
end