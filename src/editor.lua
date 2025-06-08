local editor = {}

-- Initialize the editor module
function editor.load(world)
    editor.world = world
    editor.selectedBody = nil
    editor.tempBody = nil
    editor.tempFixture = nil
    editor.collisions = {}
    editor.mouseX = 0
    editor.mouseY = 0
    editor.isPressed = false
end

-- Create a temporary collision detector at mouse position
function editor.createTempCollider(x, y, radius)
    radius = radius or 10 -- Default radius for detection
    
    -- Clean up existing temp collider
    if editor.tempBody then
        editor.tempBody:destroy()
        editor.tempBody = nil
        editor.tempFixture = nil
    end
    
    -- Clear previous collisions
    editor.collisions = {}
    
    -- Create temporary body for collision detection
    editor.tempBody = love.physics.newBody(world, x, y, "dynamic")
    local shape = love.physics.newCircleShape(radius)
    editor.tempFixture = love.physics.newFixture(editor.tempBody, shape)
    
    -- Make it a sensor so it doesn't physically interact
    editor.tempFixture:setSensor(true)
    editor.tempFixture:setUserData("temp_collider")
    
    return editor.tempBody, editor.tempFixture
end

-- Collision callback function (called from main beginContact)
function editor.collision(fixtureA, fixtureB, contact)
    -- Only process if we have a temp fixture active
    if not editor.tempFixture then
        return
    end
    
    local mouseFixture, otherFixture = nil, nil
    
    if fixtureA == editor.tempFixture then
        mouseFixture = fixtureA
        otherFixture = fixtureB
    elseif fixtureB == editor.tempFixture then
        mouseFixture = fixtureB
        otherFixture = fixtureA
    end
    
    if mouseFixture and otherFixture then
        local otherBody = otherFixture:getBody()
        
        -- Don't add static bodies or bodies that are already in the list
        if otherBody:getType() == "dynamic" then
            local alreadyExists = false
            for _, collision in ipairs(editor.collisions) do
                if collision.body == otherBody then
                    alreadyExists = true
                    break
                end
            end
            
            if not alreadyExists then
                table.insert(editor.collisions, {
                    body = otherBody,
                    fixture = otherFixture
                })
            end
        end
    end
    
    return editor.collisions
end

-- Handle mouse press events
function editor.mousepressed(x, y, button)
    print("wow")
    if button == 1 then -- Left mouse button
        editor.mouseX = x
        editor.mouseY = y
        editor.isPressed = true
        
        -- Create temp collider at mouse position to detect what we're clicking on
        editor.createTempCollider(x, y)
    end
end

-- Handle mouse movement
function editor.mousemoved(x, y, dx, dy)
    editor.mouseX = x
    editor.mouseY = y
end

-- Handle mouse release
function editor.mousereleased(x, y, button)
    if button == 1 then
        editor.isPressed = false
        
        -- Clean up temp collider
        if editor.tempBody then
            editor.tempBody:destroy()
            editor.tempBody = nil
            editor.tempFixture = nil
        end
        
        editor.selectedBody = nil
        editor.collisions = {}
    end
end

-- Get currently selected body
function editor.getSelectedBody()
    return editor.selectedBody
end

-- Get current collisions
function editor.getCollisions()
    return editor.collisions
end

-- Update function (call this in love.update)
function editor.update(dt)
    -- Always keep temp collider active and following mouse
    if not editor.tempBody then
        editor.createTempCollider(editor.mouseX, editor.mouseY)
    else
        editor.tempBody:setPosition(editor.mouseX, editor.mouseY)
    end
    
    -- If mouse is pressed and we have collisions, select and move the first body
    if editor.isPressed and #editor.collisions > 0 then
        if not editor.selectedBody then
            editor.selectedBody = editor.collisions[1].body
        end
        
        -- Directly move the selected body to mouse position
        if editor.selectedBody and editor.selectedBody:getType() == "dynamic" then
            editor.selectedBody:setPosition(editor.mouseX, editor.mouseY)
            -- Reset velocity to prevent physics from interfering
            editor.selectedBody:setLinearVelocity(0, 0)
            editor.selectedBody:setAngularVelocity(0)
        end
    end
end

-- Clean up resources
function editor.cleanup()
    if editor.tempBody then
        editor.tempBody:destroy()
        editor.tempBody = nil
        editor.tempFixture = nil
    end
    
    editor.selectedBody = nil
    editor.collisions = {}
end

return editor