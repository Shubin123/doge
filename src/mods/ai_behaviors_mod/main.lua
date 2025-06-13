-- AI Behaviors Mod - Main Entry Point
-- This mod provides reusable AI behavior patterns and state machines

local aiBehaviorsMod = {}

-- Mod state
local active_ai = {}
local behavior_patterns = {}
local state_machines = {}
local ai_counter = 0
local mod_config = {}

-- Predefined behavior patterns
local BEHAVIOR_PATTERNS = {
    -- Aggressive: Always moves toward target
    aggressive = {
        name = "aggressive",
        description = "Always pursues target aggressively",
        update = function(entity, target, dt, api)
            if not target then return end
            
            local distance = api.utils.math.distance(entity.x, entity.y, target.x, target.y)
            
            if distance > entity.min_distance or 50 then
                -- Move towards target
                local dx = target.x - entity.x
                local dy = target.y - entity.y
                local length = math.sqrt(dx * dx + dy * dy)
                
                if length > 0 then
                    entity.velocity_x = (dx / length) * entity.speed
                    entity.velocity_y = (dy / length) * entity.speed
                end
            else
                -- Back off if too close
                local dx = entity.x - target.x
                local dy = entity.y - target.y
                local length = math.sqrt(dx * dx + dy * dy)
                
                if length > 0 then
                    entity.velocity_x = (dx / length) * entity.speed * 0.3
                    entity.velocity_y = (dy / length) * entity.speed * 0.3
                end
            end
            
            return "pursuing"
        end
    },
    
    -- Tactical: Uses cover and positioning
    tactical = {
        name = "tactical",
        description = "Uses tactical movement and positioning",
        update = function(entity, target, dt, api)
            if not target then return end
            
            local distance = api.utils.math.distance(entity.x, entity.y, target.x, target.y)
            entity.ai_timer = (entity.ai_timer or 0) + dt
            
            -- Decision making every 2 seconds
            if entity.ai_timer >= 2.0 then
                entity.ai_timer = 0
                
                if distance < 150 then
                    entity.ai_state = "retreat"
                elseif distance > 350 then
                    entity.ai_state = "advance"
                else
                    entity.ai_state = math.random() < 0.7 and "strafe" or "hold"
                end
            end
            
            if entity.ai_state == "advance" then
                local dx = target.x - entity.x
                local dy = target.y - entity.y
                local length = math.sqrt(dx * dx + dy * dy)
                if length > 0 then
                    entity.velocity_x = (dx / length) * entity.speed
                    entity.velocity_y = (dy / length) * entity.speed
                end
            elseif entity.ai_state == "retreat" then
                local dx = entity.x - target.x
                local dy = entity.y - target.y
                local length = math.sqrt(dx * dx + dy * dy)
                if length > 0 then
                    entity.velocity_x = (dx / length) * entity.speed
                    entity.velocity_y = (dy / length) * entity.speed
                end
            elseif entity.ai_state == "strafe" then
                local angle = math.atan2(target.y - entity.y, target.x - entity.x) + math.pi/2
                entity.velocity_x = math.cos(angle) * entity.speed * 0.7
                entity.velocity_y = math.sin(angle) * entity.speed * 0.7
            else -- hold
                entity.velocity_x = entity.velocity_x * 0.8
                entity.velocity_y = entity.velocity_y * 0.8
            end
            
            return entity.ai_state or "tactical"
        end
    },
    
    -- Cautious: Keeps distance, avoids danger
    cautious = {
        name = "cautious",
        description = "Maintains safe distance from threats",
        update = function(entity, target, dt, api)
            if not target then return end
            
            local distance = api.utils.math.distance(entity.x, entity.y, target.x, target.y)
            local optimal_distance = entity.optimal_distance or 300
            
            if distance < optimal_distance then
                -- Move away
                local dx = entity.x - target.x
                local dy = entity.y - target.y
                local length = math.sqrt(dx * dx + dy * dy)
                if length > 0 then
                    entity.velocity_x = (dx / length) * entity.speed
                    entity.velocity_y = (dy / length) * entity.speed
                end
                return "retreating"
            elseif distance > optimal_distance + 100 then
                -- Move closer but carefully
                local dx = target.x - entity.x
                local dy = target.y - entity.y
                local length = math.sqrt(dx * dx + dy * dy)
                if length > 0 then
                    entity.velocity_x = (dx / length) * entity.speed * 0.6
                    entity.velocity_y = (dy / length) * entity.speed * 0.6
                end
                return "positioning"
            else
                -- Stay in position
                entity.velocity_x = entity.velocity_x * 0.9
                entity.velocity_y = entity.velocity_y * 0.9
                return "holding"
            end
        end
    },
    
    -- Patrol: Moves between waypoints
    patrol = {
        name = "patrol",
        description = "Patrols between predefined waypoints",
        update = function(entity, target, dt, api)
            entity.waypoints = entity.waypoints or {
                {x = entity.x + 100, y = entity.y},
                {x = entity.x - 100, y = entity.y},
                {x = entity.x, y = entity.y + 100},
                {x = entity.x, y = entity.y - 100}
            }
            entity.current_waypoint = entity.current_waypoint or 1
            entity.waypoint_timer = (entity.waypoint_timer or 0) + dt
            
            local waypoint = entity.waypoints[entity.current_waypoint]
            local distance = api.utils.math.distance(entity.x, entity.y, waypoint.x, waypoint.y)
            
            if distance < 20 or entity.waypoint_timer > 5.0 then
                -- Move to next waypoint
                entity.current_waypoint = (entity.current_waypoint % #entity.waypoints) + 1
                entity.waypoint_timer = 0
                waypoint = entity.waypoints[entity.current_waypoint]
            end
            
            -- Move toward current waypoint
            local dx = waypoint.x - entity.x
            local dy = waypoint.y - entity.y
            local length = math.sqrt(dx * dx + dy * dy)
            if length > 0 then
                entity.velocity_x = (dx / length) * entity.speed * 0.5
                entity.velocity_y = (dy / length) * entity.speed * 0.5
            end
            
            -- Check for target interruption
            if target then
                local target_distance = api.utils.math.distance(entity.x, entity.y, target.x, target.y)
                if target_distance < (entity.detection_range or 200) then
                    return "target_detected"
                end
            end
            
            return "patrolling"
        end
    },
    
    -- Guard: Protects a specific area or entity
    guard = {
        name = "guard",
        description = "Guards a specific location or entity",
        update = function(entity, target, dt, api)
            entity.guard_position = entity.guard_position or {x = entity.x, y = entity.y}
            entity.guard_radius = entity.guard_radius or 100
            
            local guard_distance = api.utils.math.distance(entity.x, entity.y, entity.guard_position.x, entity.guard_position.y)
            
            -- Return to guard position if too far
            if guard_distance > entity.guard_radius then
                local dx = entity.guard_position.x - entity.x
                local dy = entity.guard_position.y - entity.y
                local length = math.sqrt(dx * dx + dy * dy)
                if length > 0 then
                    entity.velocity_x = (dx / length) * entity.speed
                    entity.velocity_y = (dy / length) * entity.speed
                end
                return "returning_to_post"
            end
            
            -- Check for threats
            if target then
                local threat_distance = api.utils.math.distance(entity.x, entity.y, target.x, target.y)
                local guard_to_threat = api.utils.math.distance(entity.guard_position.x, entity.guard_position.y, target.x, target.y)
                
                if threat_distance < (entity.detection_range or 150) and guard_to_threat < entity.guard_radius * 2 then
                    -- Face the threat
                    local dx = target.x - entity.x
                    local dy = target.y - entity.y
                    local length = math.sqrt(dx * dx + dy * dy)
                    if length > 0 and threat_distance > 50 then
                        entity.velocity_x = (dx / length) * entity.speed * 0.3
                        entity.velocity_y = (dy / length) * entity.speed * 0.3
                    end
                    return "guarding_against_threat"
                end
            end
            
            -- Idle at guard position
            entity.velocity_x = entity.velocity_x * 0.95
            entity.velocity_y = entity.velocity_y * 0.95
            return "on_guard"
        end
    }
}

-- State machine templates
local STATE_MACHINE_TEMPLATES = {
    basic_combat = {
        initial_state = "idle",
        states = {
            idle = {
                enter = function(entity, api) end,
                update = function(entity, dt, api) 
                    -- Check for targets
                    return "idle"
                end,
                exit = function(entity, api) end,
                transitions = {
                    target_detected = "pursue",
                    damaged = "combat"
                }
            },
            pursue = {
                enter = function(entity, api) 
                    entity.pursue_timer = 0
                end,
                update = function(entity, dt, api)
                    entity.pursue_timer = entity.pursue_timer + dt
                    -- Pursuit logic here
                    return entity.pursue_timer > 10 and "idle" or "pursue"
                end,
                exit = function(entity, api) end,
                transitions = {
                    target_lost = "idle",
                    target_in_range = "combat",
                    timeout = "idle"
                }
            },
            combat = {
                enter = function(entity, api) 
                    entity.combat_timer = 0
                end,
                update = function(entity, dt, api)
                    entity.combat_timer = entity.combat_timer + dt
                    -- Combat logic here
                    return "combat"
                end,
                exit = function(entity, api) end,
                transitions = {
                    target_lost = "pursue",
                    low_health = "flee",
                    target_dead = "idle"
                }
            },
            flee = {
                enter = function(entity, api) 
                    entity.flee_timer = 0
                end,
                update = function(entity, dt, api)
                    entity.flee_timer = entity.flee_timer + dt
                    -- Flee logic here
                    return entity.flee_timer > 5 and "idle" or "flee"
                end,
                exit = function(entity, api) end,
                transitions = {
                    safe = "idle",
                    timeout = "idle"
                }
            }
        }
    }
}

-- Initialize the mod
function aiBehaviorsMod.init(api)
    print("[AI_BEHAVIORS_MOD] Initializing AI Behaviors Mod v1.0.0")
    
    -- Store API reference
    aiBehaviorsMod.api = api
    
    -- Load configuration
    mod_config = {
        debug_ai = false,
        ai_update_rate = 60,
        pathfinding_enabled = true,
        behavior_trees_enabled = true
    }
    
    -- Initialize behavior patterns
    for name, pattern in pairs(BEHAVIOR_PATTERNS) do
        behavior_patterns[name] = pattern
    end
    
    print("[AI_BEHAVIORS_MOD] Loaded " .. #behavior_patterns .. " behavior patterns")
    print("[AI_BEHAVIORS_MOD] Initialization complete!")
end

-- Create AI behavior for an entity
function aiBehaviorsMod.createAIBehavior(entity, behavior_type, options)
    options = options or {}
    
    local pattern = behavior_patterns[behavior_type]
    if not pattern then
        print("[AI_BEHAVIORS_MOD] Unknown behavior type: " .. behavior_type)
        return nil
    end
    
    ai_counter = ai_counter + 1
    
    local ai_instance = {
        id = ai_counter,
        entity = entity,
        behavior_type = behavior_type,
        pattern = pattern,
        options = options,
        active = true,
        last_update = 0,
        state = "idle",
        state_data = {}
    }
    
    -- Set entity AI properties
    entity.ai_id = ai_counter
    entity.behavior_type = behavior_type
    entity.speed = options.speed or entity.speed or 100
    entity.detection_range = options.detection_range or entity.detection_range or 200
    entity.min_distance = options.min_distance or entity.min_distance or 50
    entity.optimal_distance = options.optimal_distance or entity.optimal_distance or 300
    entity.velocity_x = entity.velocity_x or 0
    entity.velocity_y = entity.velocity_y or 0
    
    table.insert(active_ai, ai_instance)
    
    if mod_config.debug_ai then
        print("[AI_BEHAVIORS_MOD] Created " .. behavior_type .. " AI for entity " .. (entity.id or "unknown"))
    end
    
    return ai_instance
end

-- Update AI behavior
function aiBehaviorsMod.updateAIBehavior(ai_instance, target, dt)
    if not ai_instance or not ai_instance.active or not ai_instance.entity then
        return
    end
    
    local api = aiBehaviorsMod.api
    local entity = ai_instance.entity
    local pattern = ai_instance.pattern
    
    -- Update entity position if it has a physics body
    if entity.body and not entity.body:isDestroyed() then
        entity.x = entity.body:getX()
        entity.y = entity.body:getY()
    end
    
    -- Run behavior pattern update
    local new_state = pattern.update(entity, target, dt, api)
    if new_state and new_state ~= ai_instance.state then
        ai_instance.state = new_state
        
        if mod_config.debug_ai then
            print("[AI_BEHAVIORS_MOD] Entity " .. (entity.id or "unknown") .. " state: " .. new_state)
        end
    end
    
    -- Apply velocity to physics body if available
    if entity.body and not entity.body:isDestroyed() then
        entity.body:setLinearVelocity(entity.velocity_x or 0, entity.velocity_y or 0)
    end
    
    ai_instance.last_update = aiBehaviorsMod.api.utils.getTime()
end

-- Update all active AI
function aiBehaviorsMod.update(dt)
    for i = #active_ai, 1, -1 do
        local ai_instance = active_ai[i]
        
        if ai_instance.active and ai_instance.entity then
            -- Get target (could be player or other entity)
            local target = aiBehaviorsMod.getTarget(ai_instance.entity)
            aiBehaviorsMod.updateAIBehavior(ai_instance, target, dt)
        else
            table.remove(active_ai, i)
        end
    end
end

-- Get target for an entity (default: nearest player)
function aiBehaviorsMod.getTarget(entity)
    local api = aiBehaviorsMod.api
    local player_x, player_y = api.game.getPlayerPosition()
    
    if player_x and player_y then
        return {x = player_x, y = player_y, type = "player"}
    end
    
    return nil
end

-- Create state machine
function aiBehaviorsMod.createStateMachine(entity, template_name, custom_states)
    local template = STATE_MACHINE_TEMPLATES[template_name]
    if not template and not custom_states then
        print("[AI_BEHAVIORS_MOD] Unknown state machine template: " .. template_name)
        return nil
    end
    
    local states = custom_states or template.states
    local initial_state = template and template.initial_state or "idle"
    
    local state_machine = {
        entity = entity,
        current_state = initial_state,
        states = states,
        state_data = {},
        active = true
    }
    
    -- Enter initial state
    if states[initial_state] and states[initial_state].enter then
        states[initial_state].enter(entity, aiBehaviorsMod.api)
    end
    
    table.insert(state_machines, state_machine)
    entity.state_machine = state_machine
    
    return state_machine
end

-- Transition state
function aiBehaviorsMod.transitionState(state_machine, new_state, force)
    if not state_machine or not state_machine.active then return false end
    
    local current_state = state_machine.current_state
    local states = state_machine.states
    
    -- Check if transition is valid
    if not force and states[current_state] and states[current_state].transitions then
        local valid_transitions = states[current_state].transitions
        if not valid_transitions[new_state] then
            if mod_config.debug_ai then
                print("[AI_BEHAVIORS_MOD] Invalid transition from " .. current_state .. " to " .. new_state)
            end
            return false
        end
    end
    
    -- Exit current state
    if states[current_state] and states[current_state].exit then
        states[current_state].exit(state_machine.entity, aiBehaviorsMod.api)
    end
    
    -- Enter new state
    state_machine.current_state = new_state
    if states[new_state] and states[new_state].enter then
        states[new_state].enter(state_machine.entity, aiBehaviorsMod.api)
    end
    
    if mod_config.debug_ai then
        print("[AI_BEHAVIORS_MOD] State transition: " .. current_state .. " -> " .. new_state)
    end
    
    return true
end

-- Update state machines
function aiBehaviorsMod.updateStateMachines(dt)
    for i = #state_machines, 1, -1 do
        local sm = state_machines[i]
        
        if sm.active and sm.entity then
            local current_state = sm.current_state
            local states = sm.states
            
            if states[current_state] and states[current_state].update then
                local result = states[current_state].update(sm.entity, dt, aiBehaviorsMod.api)
                
                -- Check for automatic state transitions
                if result and result ~= current_state then
                    aiBehaviorsMod.transitionState(sm, result)
                end
            end
        else
            table.remove(state_machines, i)
        end
    end
end

-- Remove AI from entity
function aiBehaviorsMod.removeAI(entity)
    -- Remove from active AI
    for i = #active_ai, 1, -1 do
        if active_ai[i].entity == entity then
            table.remove(active_ai, i)
        end
    end
    
    -- Remove from state machines
    for i = #state_machines, 1, -1 do
        if state_machines[i].entity == entity then
            table.remove(state_machines, i)
        end
    end
    
    entity.ai_id = nil
    entity.state_machine = nil
end

-- Get AI statistics
function aiBehaviorsMod.getStats()
    local stats = {
        active_ai_count = #active_ai,
        state_machines_count = #state_machines,
        behavior_types = {},
        state_distribution = {}
    }
    
    for _, ai in ipairs(active_ai) do
        stats.behavior_types[ai.behavior_type] = (stats.behavior_types[ai.behavior_type] or 0) + 1
    end
    
    for _, sm in ipairs(state_machines) do
        stats.state_distribution[sm.current_state] = (stats.state_distribution[sm.current_state] or 0) + 1
    end
    
    return stats
end

-- Debug visualization
function aiBehaviorsMod.debugDraw()
    if not mod_config.debug_ai then return end
    
    local api = aiBehaviorsMod.api
    
    for _, ai in ipairs(active_ai) do
        local entity = ai.entity
        if entity and entity.x and entity.y then
            -- Draw AI state
            api.renderer.addToQueue("ui", {
                type = "text",
                text = ai.behavior_type .. ":" .. ai.state,
                x = entity.x,
                y = entity.y - 40,
                font = "default",
                sort_y = 10003,
                active = true,
                color = {1, 1, 0, 0.8}
            })
            
            -- Draw detection range
            api.renderer.addToQueue("ui", {
                type = "circle",
                mode = "line",
                x = entity.x,
                y = entity.y,
                radius = entity.detection_range or 200,
                sort_y = 10000,
                active = true,
                color = {0, 1, 0, 0.3}
            })
        end
    end
end

-- Cleanup
function aiBehaviorsMod.cleanup()
    active_ai = {}
    state_machines = {}
    ai_counter = 0
    print("[AI_BEHAVIORS_MOD] Cleanup complete")
end

-- Mod interface - exports for other mods
aiBehaviorsMod.exports = {
    createAIBehavior = aiBehaviorsMod.createAIBehavior,
    updateAIBehavior = aiBehaviorsMod.updateAIBehavior,
    createStateMachine = aiBehaviorsMod.createStateMachine,
    transitionState = aiBehaviorsMod.transitionState,
    removeAI = aiBehaviorsMod.removeAI,
    getStats = aiBehaviorsMod.getStats
}

return aiBehaviorsMod