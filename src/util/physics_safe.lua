-- physics_safe.lua
-- Utility module for safe physics operations that check body validity before acting
-- Prevents crashes from nil bodies or destroyed physics bodies

local physSafe = {}

-- Check if a physics body is valid and not destroyed
-- @param body: physics body to check
-- @return boolean: true if body exists and is not destroyed
function physSafe.isValidBody(body)
    return body and not body:isDestroyed()
end

-- Safely apply linear impulse to a physics body
-- @param body: physics body to apply impulse to
-- @param ix: impulse x component
-- @param iy: impulse y component
-- @return boolean: true if impulse was applied, false if body invalid
function physSafe.safeApplyImpulse(body, ix, iy)
    if not physSafe.isValidBody(body) then
        return false
    end
    
    body:applyLinearImpulse(ix, iy)
    return true
end

-- Safely get position from a physics body
-- @param body: physics body to get position from
-- @return x, y: position coordinates, or nil, nil if body invalid
function physSafe.safeGetPosition(body)
    if not physSafe.isValidBody(body) then
        return nil, nil
    end
    
    return body:getPosition()
end

return physSafe