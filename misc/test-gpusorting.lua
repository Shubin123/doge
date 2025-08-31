-- adapted from https://love2d.org/forums/viewtopic.php?t=94183
-- sorting done on elements of a canvas using gl_FragDepth
-- for drawInstanced calls sorting can be done with attribute bind on mesh
-- as long as gl_FragDepth is supported (es2 needed) sorting can be done.
local canvas1
-- local canvas2
local image
local shader
local depth

function love.load()
    love.window.setMode(1700, 900, { resizable = false, vsync = true, borderless = false })

    canvas1 = love.graphics.newCanvas(700, 700, { format = "rgba8" })
    -- canvas2 = love.graphics.newCanvas(700, 700, { format = "rgba8" })
    depth = love.graphics.newCanvas(700, 700, { format = "depth16" })
    image = love.graphics.newImage("apple.png")

  shader = love.graphics.newShader([[
    extern float z;
    extern float alphaCutoff; // threshold for cutout
    //uniform Image MainTex;

    vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
        vec4 texColor = Texel(tex, uv) * color;

        // Hard alpha test (cutout)
        if (texColor.a < 0.5) {
            discard;
        }

        // Write depth (closer z = smaller value)
        gl_FragDepth = 1.0 - z/10.0;

        // Output final color (opaque where kept)
        return texColor;
    }
]])
end
local t = 0
function love.update(dt)
    t = t + dt
    love.window.setTitle(love.timer.getFPS())
    if love.keyboard.isDown("escape") then
        love.event.quit()
    end
end
function love.draw()
    
    love.graphics.setCanvas({ canvas1, depthstencil = depth })
    love.graphics.clear({ 0,0,0, 0.0 }, { 0.4, 0.2, 0.2, 1.0 })
    love.graphics.setDepthMode("lequal", true)
    -- 'less', 'lequal', 'equal', 'gequal', 'greater', 'notequal', 'always', 'never'

    love.math.setRandomSeed(0)
    love.graphics.setShader(shader)
    -- shader:send("color", { 1.0, 0.8, 0.6 })
    
    for i = 2, 300 do
        local y = love.math.random() * 600
        shader:send("z",y/600)
        love.graphics.draw(image, love.math.random() * 600, y)
    end
    local x,y = love.mouse.getPosition()
    print(y/700)
    shader:send("z",y/600)
    love.graphics.draw(image, x,y)

    love.graphics.setCanvas()
    love.graphics.setShader()
    love.graphics.clear(0.2, 0.2, 0.2, 1.0)
    love.graphics.draw(canvas1, 100, 0)
    -- love.graphics.draw(canvas2, 900, 100)
end