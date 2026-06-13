local border = {}

-- Current border body and fixtures for management
border.fence_body = nil
border.fence_fixture = nil

-- Create world border with specified dimensions
function border.create(world, width, height, offset_x, offset_y)
    offset_x = offset_x or 200
    offset_y = offset_y or 50
    
    -- Clean up existing border if it exists
    border.destroy()
    
    -- Create new border
    border.fence_body = love.physics.newBody(world, 0, 0, "static")
    border.fence_shape = love.physics.newChainShape(true, 
        offset_x, offset_y,                    -- Top-left
        width + offset_x, offset_y,            -- Top-right
        width + offset_x, height + offset_y,   -- Bottom-right
        offset_x, height + offset_y            -- Bottom-left
    )
    border.fence_fixture = love.physics.newFixture(border.fence_body, border.fence_shape)
    
    return border.fence_body, border.fence_fixture
end

-- Destroy current border
function border.destroy()
    if border.fence_fixture and not border.fence_fixture:isDestroyed() then
        border.fence_fixture:destroy()
        border.fence_fixture = nil
    end
    
    if border.fence_body and not border.fence_body:isDestroyed() then
        border.fence_body:destroy()
        border.fence_body = nil
    end
end

-- Update border dimensions (recreates the border)
function border.resize(world, width, height, offset_x, offset_y)
    return border.create(world, width, height, offset_x, offset_y)
end

-- Get current border info
function border.getInfo()
    if not border.fence_body or border.fence_body:isDestroyed() then
        return nil
    end
    
    return {
        body = border.fence_body,
        fixture = border.fence_fixture,
        active = true
    }
end

return border