local character_manager = {}

-- Character definitions
local character_definitions = {
    simple_character = {
        id = "simple_character",
        name = "Simple Character",
        description = "A basic rectangle character for testing",
        sprite_sheet = nil, -- Will use procedural rendering
        animations = {
            idle = {
                sheet = nil,
                frame_width = 32,
                frame_height = 32,
                frame_count = 1,
                duration = 1.0,
                color = {0.3, 0.7, 1.0, 1.0} -- Light blue
            },
            walk = {
                sheet = nil,
                frame_width = 32,
                frame_height = 32,
                frame_count = 1,
                duration = 0.5,
                color = {0.5, 0.9, 1.0, 1.0} -- Brighter blue when moving
            },
            dash = {
                sheet = nil,
                frame_width = 40,
                frame_height = 40,
                frame_count = 1,
                duration = 0.3,
                color = {1.0, 0.8, 0.2, 1.0} -- Yellow/orange when dashing
            }
        },
        stats = {
            health = 100,
            speed = 120,
            attack = 15,
            defense = 8
        },
        physics = {
            body_radius = 12,
            scale = 1.0
        },
        special_abilities = {
            dash = {
                speed = 400,
                duration = 0.3,
                cooldown = 1.5
            }
        },
        unlocked = true
    },
    lpc_warrior = {
        id = "lpc_warrior",
        name = "Katana Warrior",
        description = "A skilled warrior wielding a legendary katana",
        sprite_sheet = "gfx/Character1/standard/idle.png",
        animations = {
            idle_up = {
                sheet = "gfx/Character1/standard/idle.png",
                frame_width = 64,
                frame_height = 64,
                frame_count = 2,
                duration = 2.0,
                row = 0
            },
            idle_left = {
                sheet = "gfx/Character1/standard/idle.png",
                frame_width = 64,
                frame_height = 64,
                frame_count = 2,
                duration = 2.0,
                row = 1
            },
            idle_down = {
                sheet = "gfx/Character1/standard/idle.png",
                frame_width = 64,
                frame_height = 64,
                frame_count = 2,
                duration = 2.0,
                row = 2
            },
            idle_right = {
                sheet = "gfx/Character1/standard/idle.png",
                frame_width = 64,
                frame_height = 64,
                frame_count = 2,
                duration = 2.0,
                row = 3
            },
            walk_up = {
                sheet = "gfx/Character1/standard/walk.png",
                frame_width = 64,
                frame_height = 64,
                frame_count = 9,
                duration = 1.0,
                row = 0
            },
            walk_left = {
                sheet = "gfx/Character1/standard/walk.png",
                frame_width = 64,
                frame_height = 64,
                frame_count = 9,
                duration = 1.0,
                row = 1
            },
            walk_down = {
                sheet = "gfx/Character1/standard/walk.png",
                frame_width = 64,
                frame_height = 64,
                frame_count = 9,
                duration = 1.0,
                row = 2
            },
            walk_right = {
                sheet = "gfx/Character1/standard/walk.png",
                frame_width = 64,
                frame_height = 64,
                frame_count = 9,
                duration = 1.0,
                row = 3
            },
            slash_up = {
                sheet = "gfx/Character1/standard/slash.png",
                frame_width = 64,
                frame_height = 64,
                frame_count = 6,
                duration = 0.6,
                row = 0
            },
            slash_left = {
                sheet = "gfx/Character1/standard/slash.png",
                frame_width = 64,
                frame_height = 64,
                frame_count = 6,
                duration = 0.6,
                row = 1
            },
            slash_down = {
                sheet = "gfx/Character1/standard/slash.png",
                frame_width = 64,
                frame_height = 64,
                frame_count = 6,
                duration = 0.6,
                row = 2
            },
            slash_right = {
                sheet = "gfx/Character1/standard/slash.png",
                frame_width = 64,
                frame_height = 64,
                frame_count = 6,
                duration = 0.6,
                row = 3
            },
            dash_up = {
                sheet = "gfx/Character1/custom/walk_128.png",
                frame_width = 128,
                frame_height = 128,
                frame_count = 9,
                duration = 0.3,
                row = 0
            },
            dash_left = {
                sheet = "gfx/Character1/custom/walk_128.png",
                frame_width = 128,
                frame_height = 128,
                frame_count = 9,
                duration = 0.3,
                row = 1
            },
            dash_down = {
                sheet = "gfx/Character1/custom/walk_128.png",
                frame_width = 128,
                frame_height = 128,
                frame_count = 9,
                duration = 0.3,
                row = 2
            },
            dash_right = {
                sheet = "gfx/Character1/custom/walk_128.png",
                frame_width = 128,
                frame_height = 128,
                frame_count = 9,
                duration = 0.3,
                row = 3
            }
        },
        stats = {
            health = 100,
            speed = 120,
            attack = 15,
            defense = 8
        },
        physics = {
            body_radius = 12,
            scale = 0.8
        },
        special_abilities = {
            dash = {
                speed = 400,
                duration = 0.3,
                cooldown = 1.5
            },
            katana_slash = {
                damage = 25,
                range = 80,
                cooldown = 2.0
            }
        },
        unlocked = true
    },
    
    doge = {
        id = "doge",
        name = "Doge (Legacy)",
        description = "The original meme warrior",
        sprite_sheet = "gfx/doge.png",
        animations = {
            idle = {
                sheet = "gfx/testCharacter/idle.png",
                frame_width = 64,
                frame_height = 65,
                frame_count = 10,
                duration = 2.0
            },
            walk = {
                sheet = "gfx/testCharacter/walk.png", 
                frame_width = 64,
                frame_height = 65,
                frame_count = 8,
                duration = 1.0
            },
            jump = {
                sheet = "gfx/testCharacter/jump.png",
                frame_width = 64,
                frame_height = 65,
                frame_count = 10,
                duration = 2.0
            },
            attack = {
                sheet = "gfx/testCharacter/slash.png",
                frame_width = 64,
                frame_height = 65,
                frame_count = 6,
                duration = 0.8
            }
        },
        stats = {
            health = 100,
            speed = 100,
            attack = 10,
            defense = 5
        },
        physics = {
            body_radius = 10,
            scale = 0.8
        },
        special_abilities = {
            dodge = {
                speed = 300,
                duration = 0.2,
                cooldown = 1.0
            }
        },
        unlocked = true
    },
    
    soldier = {
        id = "soldier",
        name = "Soldier",
        description = "Battle-hardened warrior",
        sprite_sheet = "gfx/SoldierSpriteSheets/Soldier.png",
        animations = {
            idle = {
                sheet = "gfx/SoldierSpriteSheets/Soldier_Idle.png",
                frame_width = 100,
                frame_height = 100,
                frame_count = 6,
                duration = 1.5
            },
            walk = {
                sheet = "gfx/SoldierSpriteSheets/Soldier_Walk.png",
                frame_width = 100,
                frame_height = 100,
                frame_count = 8,
                duration = 1.2
            },
            attack = {
                sheet = "gfx/SoldierSpriteSheets/Soldier_Attack01.png",
                frame_width = 100,
                frame_height = 100,
                frame_count = 8,
                duration = 1.0
            }
        },
        stats = {
            health = 120,
            speed = 80,
            attack = 15,
            defense = 8
        },
        physics = {
            body_radius = 12,
            scale = 0.6
        },
        special_abilities = {
            shield_bash = {
                damage = 20,
                cooldown = 3.0,
                stun_duration = 1.0
            }
        },
        unlocked = false,
        unlock_condition = "complete_level1"
    },
    
    warrior = {
        id = "warrior",
        name = "Warrior",
        description = "Mystical fighter with magical abilities",
        sprite_sheet = "gfx/WarriorSpriteSheet/Warrior_SheetnoEffect.png",
        animations = {
            idle = {
                sheet = "gfx/WarriorSpriteSheet/Warrior_SheetnoEffect.png",
                frame_width = 69,
                frame_height = 44,
                frame_count = 6,
                duration = 1.8
            },
            walk = {
                sheet = "gfx/WarriorSpriteSheet/Warrior_SheetnoEffect.png",
                frame_width = 69,
                frame_height = 44,
                frame_count = 8,
                duration = 1.0
            },
            attack = {
                sheet = "gfx/WarriorSpriteSheet/Warrior_Sheet-Effect.png",
                frame_width = 69,
                frame_height = 44,
                frame_count = 6,
                duration = 0.9
            }
        },
        stats = {
            health = 90,
            speed = 110,
            attack = 12,
            defense = 4
        },
        physics = {
            body_radius = 8,
            scale = 1.0
        },
        special_abilities = {
            magic_burst = {
                damage = 25,
                range = 100,
                cooldown = 4.0
            }
        },
        unlocked = false,
        unlock_condition = "complete_level2"
    },
    
    dancer = {
        id = "dancer",
        name = "Dancing Girl",
        description = "Agile performer with rhythm-based combat",
        sprite_sheet = "gfx/DancingGirlSheets/snap.png",
        animations = {
            idle = {
                sheet = "gfx/DancingGirlSheets/balancing.png",
                frame_width = 96,
                frame_height = 96,
                frame_count = 8,
                duration = 2.0
            },
            walk = {
                sheet = "gfx/DancingGirlSheets/skip.png",
                frame_width = 96,
                frame_height = 96,
                frame_count = 8,
                duration = 0.8
            },
            attack = {
                sheet = "gfx/DancingGirlSheets/snap.png",
                frame_width = 96,
                frame_height = 96,
                frame_count = 6,
                duration = 0.6
            },
            special = {
                sheet = "gfx/DancingGirlSheets/slide.png",
                frame_width = 96,
                frame_height = 96,
                frame_count = 8,
                duration = 1.0
            }
        },
        stats = {
            health = 80,
            speed = 130,
            attack = 8,
            defense = 3
        },
        physics = {
            body_radius = 9,
            scale = 0.7
        },
        special_abilities = {
            dance_combo = {
                hits = 3,
                damage_per_hit = 8,
                cooldown = 2.5
            }
        },
        unlocked = false,
        unlock_condition = "complete_level3"
    }
}

-- Currently selected character
local selected_character_id = "simple_character"
local loaded_characters = {}

-- Initialize character manager
function character_manager.initialize()
    print("Character Manager initialized")
    -- Preload default character
    character_manager.load_character(selected_character_id)
end

-- Animation creation helper
local function create_animation(anim_data)
    -- Handle procedural (non-sprite sheet) animations
    if not anim_data.sheet then
        local animation = {
            sprite_sheet = nil,
            quads = {},
            frame_width = anim_data.frame_width,
            frame_height = anim_data.frame_height,
            frame_count = anim_data.frame_count,
            duration = anim_data.duration,
            current_time = 0,
            color = anim_data.color or {1, 1, 1, 1},
            is_procedural = true
        }
        
        -- Create a single "quad" for procedural rendering
        table.insert(animation.quads, {procedural = true})
        
        return animation
    end
    
    if not love.filesystem.getInfo(anim_data.sheet) then
        print("Warning: Animation sheet not found: " .. anim_data.sheet)
        return nil
    end
    
    local success, image = pcall(love.graphics.newImage, anim_data.sheet)
    if not success then
        print("Error loading animation sheet: " .. anim_data.sheet)
        return nil
    end
    
    local animation = {
        sprite_sheet = image,
        quads = {},
        frame_width = anim_data.frame_width,
        frame_height = anim_data.frame_height,
        frame_count = anim_data.frame_count,
        duration = anim_data.duration,
        current_time = 0
    }
    
    -- Create quads for animation frames
    local frames_per_row = math.floor(image:getWidth() / anim_data.frame_width)
    local frame_count = 0
    
    -- Check if this is a row-based LPC animation
    if anim_data.row ~= nil then
        -- LPC format: extract frames from specific row
        local y = anim_data.row * anim_data.frame_height
        for x = 0, image:getWidth() - anim_data.frame_width, anim_data.frame_width do
            if frame_count < anim_data.frame_count then
                table.insert(animation.quads, love.graphics.newQuad(
                    x, y,
                    anim_data.frame_width, anim_data.frame_height,
                    image:getDimensions()
                ))
                frame_count = frame_count + 1
            else
                break
            end
        end
    else
        -- Standard format: read frames row by row
        for y = 0, image:getHeight() - anim_data.frame_height, anim_data.frame_height do
            for x = 0, image:getWidth() - anim_data.frame_width, anim_data.frame_width do
                if frame_count < anim_data.frame_count then
                    table.insert(animation.quads, love.graphics.newQuad(
                        x, y, 
                        anim_data.frame_width, anim_data.frame_height,
                        image:getDimensions()
                    ))
                    frame_count = frame_count + 1
                else
                    break
                end
            end
            if frame_count >= anim_data.frame_count then break end
        end
    end
    
    return animation
end

-- Load character assets
function character_manager.load_character(character_id)
    local char_def = character_definitions[character_id]
    if not char_def then
        print("Character definition not found: " .. character_id)
        return nil
    end
    
    if loaded_characters[character_id] then
        return loaded_characters[character_id]
    end
    
    print("Loading character: " .. char_def.name)
    
    local character = {
        id = character_id,
        definition = char_def,
        animations = {},
        current_animation = "idle",
        stats = {},
        physics = {},
        special_abilities = {}
    }
    
    -- Copy stats
    for key, value in pairs(char_def.stats) do
        character.stats[key] = value
    end
    
    -- Copy physics properties
    for key, value in pairs(char_def.physics) do
        character.physics[key] = value
    end
    
    -- Copy special abilities
    for key, value in pairs(char_def.special_abilities) do
        character.special_abilities[key] = {}
        for k, v in pairs(value) do
            character.special_abilities[key][k] = v
        end
    end
    
    -- Load animations
    for anim_name, anim_data in pairs(char_def.animations) do
        local animation = create_animation(anim_data)
        if animation then
            character.animations[anim_name] = animation
        else
            print("Failed to load animation: " .. anim_name .. " for character: " .. character_id)
        end
    end
    
    -- Load character portrait/icon
    if char_def.sprite_sheet and love.filesystem.getInfo(char_def.sprite_sheet) then
        local success, image = pcall(love.graphics.newImage, char_def.sprite_sheet)
        if success then
            character.portrait = image
        end
    end
    
    loaded_characters[character_id] = character
    return character
end

-- Get all available characters
function character_manager.get_all_characters()
    return character_definitions
end

-- Get character definition
function character_manager.get_character_definition(character_id)
    return character_definitions[character_id]
end

-- Get loaded character
function character_manager.get_loaded_character(character_id)
    return loaded_characters[character_id]
end

-- Set selected character
function character_manager.set_selected_character(character_id)
    if character_definitions[character_id] then
        selected_character_id = character_id
        print("Selected character: " .. character_definitions[character_id].name)
        return true
    end
    return false
end

-- Get selected character
function character_manager.get_selected_character()
    return selected_character_id
end

-- Get selected character data
function character_manager.get_selected_character_data()
    return loaded_characters[selected_character_id] or character_manager.load_character(selected_character_id)
end

-- Check if character is unlocked
function character_manager.is_character_unlocked(character_id)
    local char_def = character_definitions[character_id]
    if not char_def then return false end
    
    if char_def.unlocked then return true end
    
    -- Check unlock conditions
    if char_def.unlock_condition then
        -- This would integrate with a progression system
        -- For now, just return false
        return character_manager.check_unlock_condition(char_def.unlock_condition)
    end
    
    return false
end

-- Check unlock condition (placeholder for progression system)
function character_manager.check_unlock_condition(condition)
    -- This would check against saved game progress
    -- For demo purposes, unlock all characters
    return true
end

-- Unlock character
function character_manager.unlock_character(character_id)
    local char_def = character_definitions[character_id]
    if char_def then
        char_def.unlocked = true
        print("Unlocked character: " .. char_def.name)
        return true
    end
    return false
end

-- Get unlocked characters
function character_manager.get_unlocked_characters()
    local unlocked = {}
    for id, char_def in pairs(character_definitions) do
        if character_manager.is_character_unlocked(id) then
            table.insert(unlocked, {
                id = id,
                definition = char_def,
                loaded_data = loaded_characters[id]
            })
        end
    end
    
    -- Sort by unlock order (or name)
    table.sort(unlocked, function(a, b)
        return a.definition.name < b.definition.name
    end)
    
    return unlocked
end

-- Create player instance from character
function character_manager.create_player_instance(world, character_id, spawn_x, spawn_y)
    character_id = character_id or selected_character_id
    local character = character_manager.get_loaded_character(character_id)
    
    if not character then
        character = character_manager.load_character(character_id)
    end
    
    if not character then
        print("Failed to create player instance for character: " .. character_id)
        return nil
    end
    
    spawn_x = spawn_x or 400
    spawn_y = spawn_y or 300
    
    -- Create physics body
    local body = love.physics.newBody(world, spawn_x, spawn_y, "dynamic")
    local shape = love.physics.newCircleShape(character.physics.body_radius)
    local fixture = love.physics.newFixture(body, shape)
    fixture:setGroupIndex(-1)
    
    -- Create player instance
    local player_instance = {
        character_id = character_id,
        character = character,
        body = body,
        shape = shape,
        fixture = fixture,
        scale = character.physics.scale,
        
        -- Stats (can be modified during gameplay)
        health = character.stats.health,
        max_health = character.stats.health,
        speed = character.stats.speed,
        attack = character.stats.attack,
        defense = character.stats.defense,
        
        -- Animation state
        current_animation = "idle",
        animation_time = 0,
        facing_direction = 0,
        
        -- Movement state
        velocity = {x = 0, y = 0},
        is_moving = false,
        
        -- Special abilities state
        ability_cooldowns = {},
        
        -- Combat state
        is_attacking = false,
        attack_timer = 0
    }
    
    -- Initialize ability cooldowns
    for ability_name, ability_data in pairs(character.special_abilities) do
        player_instance.ability_cooldowns[ability_name] = 0
    end
    
    return player_instance
end

-- Update character animation
function character_manager.update_character_animation(character, dt)
    if not character.animations[character.current_animation] then
        character.current_animation = "idle"
    end
    
    local animation = character.animations[character.current_animation]
    if animation then
        animation.current_time = animation.current_time + dt
        if animation.current_time >= animation.duration then
            animation.current_time = animation.current_time - animation.duration
        end
    end
end

-- Get character animation frame
function character_manager.get_character_frame(character)
    if not character.animations[character.current_animation] then
        return nil, nil
    end
    
    local animation = character.animations[character.current_animation]
    if not animation or #animation.quads == 0 then
        return nil, nil
    end
    
    local frame_index = math.floor(animation.current_time / animation.duration * #animation.quads) + 1
    frame_index = math.max(1, math.min(#animation.quads, frame_index))
    
    return animation.sprite_sheet, animation.quads[frame_index]
end

-- Preload all available characters
function character_manager.preload_all_characters()
    print("Preloading all characters...")
    local loaded_count = 0
    
    for character_id, char_def in pairs(character_definitions) do
        if character_manager.is_character_unlocked(character_id) then
            if character_manager.load_character(character_id) then
                loaded_count = loaded_count + 1
            end
        end
    end
    
    print("Preloaded " .. loaded_count .. " characters")
    return loaded_count
end

-- Cleanup loaded characters
function character_manager.cleanup()
    loaded_characters = {}
    collectgarbage()
    print("Character manager cleaned up")
end

-- Get character stats summary
function character_manager.get_character_stats_summary(character_id)
    local char_def = character_definitions[character_id]
    if not char_def then return nil end
    
    local total_stats = char_def.stats.health + char_def.stats.speed + char_def.stats.attack + char_def.stats.defense
    
    return {
        name = char_def.name,
        description = char_def.description,
        stats = char_def.stats,
        total_rating = total_stats,
        special_ability_count = 0,
        unlocked = character_manager.is_character_unlocked(character_id)
    }
end

-- Debug information
function character_manager.get_debug_info()
    local loaded_count = 0
    for _ in pairs(loaded_characters) do loaded_count = loaded_count + 1 end
    
    return {
        total_characters = 0,
        loaded_characters = loaded_count,
        selected_character = selected_character_id,
        memory_usage = collectgarbage("count")
    }
end

return character_manager