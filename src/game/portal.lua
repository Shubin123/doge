local portal = {}

local skin = require("ui.skin")

-- Stepping into a portal opens a selector of every region (game/regions.lua);
-- picking one teleports the player in front of that region's portal.
local W, H = 35, 50     -- the portal's rect, from its top left
local FLASH_TIME = 0.45 -- seconds the screen glows after a jump

portal.selecting = false -- the selector is open
portal.from = nil        -- the region whose portal the player is standing in
local armed = true       -- false after Esc, until the player steps out
local choice = 1         -- highlighted destination, an index into regions.list
local flash = 0
local font
local mouseX, mouseY     -- where the mouse was last frame; moving it picks
local layout

function portal.load()
    
    -- Initialize shader test
    portal.SHADERS = {}
    portal.current_time = 0
    portal.spin_time = 0
    
    -- Load shaders from directory (your method)
    local shader_files = love.filesystem.getDirectoryItems("resources/shaders")
    for k, filename in ipairs(shader_files) do
        local extension = string.sub(filename, -3)
        if extension == '.fs' then
            local shader_name = string.sub(filename, 1, -4)
            portal.SHADERS[shader_name] = love.graphics.newShader("resources/shaders/"..filename)
        end
    end
    portal.SHADERS["portal"] = love.graphics.newShader([[
    
    #if defined(VERTEX) || __VERSION__ > 100 || defined(GL_FRAGMENT_PRECISION_HIGH)
	#define MY_HIGHP_OR_MEDIUMP highp
#else
	#define MY_HIGHP_OR_MEDIUMP mediump
#endif

extern MY_HIGHP_OR_MEDIUMP number time;
extern MY_HIGHP_OR_MEDIUMP number spin_time;
extern MY_HIGHP_OR_MEDIUMP vec4 colour_1;
extern MY_HIGHP_OR_MEDIUMP vec4 colour_2;
extern MY_HIGHP_OR_MEDIUMP vec4 colour_3;
extern MY_HIGHP_OR_MEDIUMP number contrast;
extern MY_HIGHP_OR_MEDIUMP number spin_amount;

#define PIXEL_SIZE_FAC 700.
#define SPIN_EASE 0.5

vec4 effect( vec4 colour, Image texture, vec2 texture_coords, vec2 screen_coords )
{
    //Convert to UV coords (0-1) and floor for pixel effect
    MY_HIGHP_OR_MEDIUMP number pixel_size = length(love_ScreenSize.xy)/PIXEL_SIZE_FAC;
    MY_HIGHP_OR_MEDIUMP vec2 uv = (floor(screen_coords.xy*(1./pixel_size))*pixel_size - 0.5*love_ScreenSize.xy)/length(love_ScreenSize.xy) - vec2(0.12, 0.);
    MY_HIGHP_OR_MEDIUMP number uv_len = length(uv);

    //Adding in a center swirl, changes with time. Only applies meaningfully if the 'spin amount' is a non-zero number
    MY_HIGHP_OR_MEDIUMP number speed = (spin_time*SPIN_EASE*0.2) + 302.2;
    MY_HIGHP_OR_MEDIUMP number new_pixel_angle = (atan(uv.y, uv.x)) + speed - SPIN_EASE*20.*(1.*spin_amount*uv_len + (1. - 1.*spin_amount));
    MY_HIGHP_OR_MEDIUMP vec2 mid = (love_ScreenSize.xy/length(love_ScreenSize.xy))/2.;
    uv = (vec2((uv_len * cos(new_pixel_angle) + mid.x), (uv_len * sin(new_pixel_angle) + mid.y)) - mid);

	//Now add the paint effect to the swirled UV
    uv *= 30.;
    speed = time*(2.);
	MY_HIGHP_OR_MEDIUMP vec2 uv2 = vec2(uv.x+uv.y);

    for(int i=0; i < 5; i++) {
		uv2 += sin(max(uv.x, uv.y)) + uv;
		uv  += 0.5*vec2(cos(5.1123314 + 0.353*uv2.y + speed*0.131121),sin(uv2.x - 0.113*speed));
		uv  -= 1.0*cos(uv.x + uv.y) - 1.0*sin(uv.x*0.711 - uv.y);
	}

    //Make the paint amount range from 0 - 2
    MY_HIGHP_OR_MEDIUMP number contrast_mod = (0.25*contrast + 0.5*spin_amount + 1.2);
	MY_HIGHP_OR_MEDIUMP number paint_res =min(2., max(0.,length(uv)*(0.035)*contrast_mod));
    MY_HIGHP_OR_MEDIUMP number c1p = max(0.,1. - contrast_mod*abs(1.-paint_res));
    MY_HIGHP_OR_MEDIUMP number c2p = max(0.,1. - contrast_mod*abs(paint_res));
    MY_HIGHP_OR_MEDIUMP number c3p = 1. - min(1., c1p + c2p);

    MY_HIGHP_OR_MEDIUMP vec4 ret_col = (0.3/contrast)*colour_1 + (1. - 0.3/contrast)*(colour_1*c1p + colour_2*c2p + vec4(c3p*colour_3.rgb, c3p*colour_1.a));

    return ret_col;
}

]])

    
    -- Alternative: Load shader directly (for testing if file loading doesn't work)
    -- You would save your shader code to "resources/shaders/paint_effect.fs"
    -- if not portal.SHADERS["paint_effect"] then
    --     print("Shader not found in directory, attempting direct load...")
    --     -- This assumes you have the shader saved as paint_effect.fs
    --     local success, shader = pcall(love.graphics.newShader, "resources/shaders/paint_effect.fs")
    --     if success then
    --         portal.SHADERS["paint_effect"] = shader
    --         print("Shader loaded successfully!")
    --     else
    --         print("Failed to load shader:", shader)
    --     end
    -- end
    
    -- Shader parameters (adjustable)
    portal.params = {
        time = 0,
        spin_time = 0,
        colour_1 = {1.0, 0.2, 0.3, 1.0},  -- Red-ish
        colour_2 = {0.2, 0.8, 0.3, 1.0},  -- Green-ish
        colour_3 = {0.3, 0.2, 1.0, 1.0},  -- Blue-ish
        contrast = 2.0,
        spin_amount = 5
    }
    
    -- Create a simple texture to render with the shader
    portal.canvas = love.graphics.newCanvas(love.graphics.getWidth(), love.graphics.getHeight())

    font = love.graphics.newFont("gfx/menu/Px437_IBM_VGA_8x16.ttf", 16)
    font:setFilter("nearest", "nearest")
    portal.selecting, portal.from, armed, flash = false, nil, true, 0
    
    -- print("Available shaders:")
    -- for name, shader in pairs(portal.SHADERS) do
    --     print("  - " .. name)
    -- end
end

function portal.update(dt)
    -- Update time parameters
    portal.current_time = portal.current_time + dt
    portal.spin_time = portal.spin_time + dt * 0.5  -- Slower spin time
    
    portal.params.time = portal.current_time
    portal.params.spin_time = portal.spin_time
    
    -- Optional: Add some parameter animation
    portal.params.contrast = 2.0 + math.sin(portal.current_time * 0.3) * 0.5
    portal.params.spin_amount = 0.5 + math.sin(portal.current_time * 0.2) * 0.3

    flash = math.max(0, flash - dt)
    if var.State == "menu" or not (player and player.body) then return end

    -- Standing in a portal opens the selector; walking out closes it
    local px, py = player.body:getPosition()
    local inside
    for _, r in ipairs(regions.list) do
        local p = r.portal
        if p and px > p.x - 8 and px < p.x + W + 8 and py > p.y + 10 and py < p.y + H + 14 then
            inside = r
        end
    end
    if not inside then
        portal.selecting, portal.from, armed = false, nil, true
    elseif armed and not portal.selecting then
        portal.selecting, portal.from = true, inside
        choice = inside == regions.list[1] and 2 or 1
    end

    -- Moving the mouse over a destination highlights it, like the arrow keys
    local mx, my = crt.mouse()
    if portal.selecting and (mx ~= mouseX or my ~= mouseY) then
        local buttons, u = layout()
        for i, b in ipairs(buttons) do
            if b.enabled and skin.contains(b, mx / u, my / u) then choice = i end
        end
    end
    mouseX, mouseY = mx, my
end

--- Add every portal on screen to the dynamic draw list.
function portal.populate()
    local x0, y0, x1, y1 = regions.view(W)
    for _, r in ipairs(regions.list) do
        local p = r.portal
        if p and p.x < x1 and p.x + W > x0 and p.y < y1 and p.y + H > y0 then
            table.insert(dynamic_draw_list, {
                sort_y = p.y + 165, -- with a character standing just behind it
                shader = portal.SHADERS["portal"],
                shader_params = portal.params,
                x = p.x,
                y = p.y,
                width = W,
                height = H,
                color = { 1, 1, 1, 1 },
                blend_mode = { "alpha" },
                source_object_type = "portal_shader"
            })
        end
    end
end

--- Teleport to regions.list[i] (not the one the player is standing in).
function portal.travel(i)
    local r = regions.list[i]
    if not r or r == portal.from then return end
    -- the arrival point is outside the far portal, so it doesn't open again
    portal.selecting, portal.from, armed = false, nil, true
    regions.teleport(r)
    flash = FLASH_TIME
    camera.shake(3, 0.25)
end

local function step(d)
    local n = #regions.list
    repeat
        choice = (choice - 1 + d) % n + 1
    until regions.list[choice] ~= portal.from
end

-- Destination buttons, in GUI units (see ui/skin.lua), centred on screen
function layout()
    local u = skin.guiScale()
    local sw, sh = love.graphics.getDimensions()
    local bw, n = 150, #regions.list
    local top = math.floor((sh / u - (n * 24 + 34)) / 2)
    local buttons = {}
    for i, r in ipairs(regions.list) do
        buttons[i] = {
            x = math.floor((sw / u - bw) / 2),
            y = top + 22 + (i - 1) * 24,
            w = bw,
            label = i .. "  " .. r.name .. (r == portal.from and "  (here)" or ""),
            enabled = r ~= portal.from,
        }
    end
    return buttons, u, top
end

--- Keys while the selector is open: Up/Down, Enter or E to go, 1-9 to go
--- straight there, Esc to close it until the player steps out and back in.
--- Returns true when it used the key.
function portal.keypressed(key)
    if not portal.selecting or var.State == "menu" or command.isOpen() or cmdn.isOpen() then
        return false
    end
    if key == "escape" then
        portal.selecting, armed = false, false
    elseif key == "up" then
        step(-1)
    elseif key == "down" then
        step(1)
    elseif key == "return" or key == "kpenter" or key == "e" then
        portal.travel(choice)
    elseif tonumber(key) and regions.list[tonumber(key)] then
        portal.travel(tonumber(key))
    else
        return false
    end
    return true
end

--- Clicks on a destination (x, y in CRT image space). Returns true when used.
function portal.mousepressed(x, y, button)
    if not portal.selecting or button ~= 1 then return false end
    local buttons, u = layout()
    for i, b in ipairs(buttons) do
        if b.enabled and skin.contains(b, x / u, y / u) then
            portal.travel(i)
            return true
        end
    end
    return false
end

function portal.wheelmoved(x, y)
    if not portal.selecting or y == 0 then return false end
    step(y > 0 and -1 or 1)
    return true
end

--- The jump's flash and the selector, in screen space under the CRT.
function portal.drawUI()
    if var.State == "menu" then return end
    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setShader()
    if flash > 0 then
        local sw, sh = love.graphics.getDimensions()
        love.graphics.setColor(0.75, 0.55, 1.0, (flash / FLASH_TIME) ^ 2 * 0.85)
        love.graphics.rectangle("fill", 0, 0, sw, sh)
    end
    if portal.selecting then
        local buttons, u, top = layout()
        local ts = skin.textScale(u)
        love.graphics.setFont(font)
        love.graphics.scale(u)
        local b1 = buttons[1]
        love.graphics.setColor(0.06, 0.06, 0.06, 0.7)
        love.graphics.rectangle("fill", b1.x - 8, top, b1.w + 16, #buttons * 24 + 34)
        skin.printCentered("Travel to", b1.x + b1.w / 2, top + 6, ts, skin.WHITE)
        for i, b in ipairs(buttons) do
            skin.button(b, ts, b.enabled and i == choice)
        end
        skin.printCentered("Up/Down  Enter  Esc", b1.x + b1.w / 2, top + 26 + #buttons * 24, ts, skin.GRAY)
    end
    love.graphics.pop()
end

function portal.draw()
    local shader = portal.SHADERS["portal"]
    -- local shader = portal.SHADERS["polychrome"]
    
    
    if shader then
        -- Set shader parameters
        shader:send("time", portal.params.time)
        shader:send("spin_time", portal.params.spin_time)
        shader:send("colour_1", portal.params.colour_1)
        shader:send("colour_2", portal.params.colour_2)
        shader:send("colour_3", portal.params.colour_3)
        shader:send("contrast", portal.params.contrast)
        shader:send("spin_amount", portal.params.spin_amount)
    
        -- Apply shader and draw a fullscreen quad
        love.graphics.setShader(shader)
        love.graphics.rectangle("fill", 300, 200, 35, 50)
        
    

        -- love.graphics.setBlendMode("lighten","premultiplied")
        love.graphics.setShader()  -- Reset shader
        
        -- Draw UI info
        -- love.graphics.setColor(1, 1, 1, 0.8)
        -- love.graphics.print("Paint Effect Shader Test", 10, 10)
        -- love.graphics.print("Time: " .. string.format("%.2f", portal.params.time), 10, 30)
        -- love.graphics.print("Spin Time: " .. string.format("%.2f", portal.params.spin_time), 10, 50)
        -- love.graphics.print("Contrast: " .. string.format("%.2f", portal.params.contrast), 10, 70)
        -- love.graphics.print("Spin Amount: " .. string.format("%.2f", portal.params.spin_amount), 10, 90)
        -- love.graphics.print("Press SPACE to reset time, R to randomize colors", 10, 120)
        -- love.graphics.setColor(1, 1, 1, 1)
    else
        -- Shader not loaded, show error
        love.graphics.setColor(1, 0.5, 0.5, 1)
        love.graphics.print("Shader 'paint_effect' not found!", 10, 10)
        love.graphics.print("Make sure 'paint_effect.fs' exists in 'resources/shaders/' directory", 10, 30)
        love.graphics.print("Available shaders:", 10, 60)
        local y = 80
        for name, _ in pairs(portal.SHADERS) do
            love.graphics.print("  - " .. name, 10, y)
            y = y + 20
        end
        love.graphics.setColor(1, 1, 1, 1)
    end
end





return portal