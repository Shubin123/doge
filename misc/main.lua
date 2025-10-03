local canvas, depth
local image, mesh, instanceMesh, shader,shader2
local image2, mesh2, instanceMesh2
local instanceCount = 10
local instanceData = {}
local instanceData2 = {}

function love.load()
    love.window.setMode(1000, 1000, { resizable=false, vsync=true, depth=16 })
    -- we can just sort on the default canvas or screen, and across shaders!
    -- canvas = love.graphics.newCanvas(1000, 1000, {format="rgba4"}) 
    -- depth  = love.graphics.newCanvas(1000, 1000, {format="depth16"})

    image  = love.graphics.newImage("apple.png")

    image2  = love.graphics.newImage("coin.png")

    -- Base sprite quad
    mesh = love.graphics.newMesh({
        {0, 0, 0, 0},
        {image:getWidth(), 0, 1, 0},
        {image:getWidth(), image:getHeight(), 1, 1},
        {0, image:getHeight(), 0, 1},
    }, "fan", "static")
    mesh:setTexture(image)
    -- Base sprite quad
    mesh2 = love.graphics.newMesh({
        {0, 0, 0, 0},
        {image:getWidth(), 0, 1, 0},
        {image:getWidth(), image:getHeight(), 1, 1},
        {0, image:getHeight(), 0, 1},
    }, "fan", "static")
    mesh2:setTexture(image2)

    -- Instance mesh: x, y, z per instance
    instanceMesh = love.graphics.newMesh({{"InstanceData", "float", 3}}, instanceCount, "points", "stream")
    instanceMesh2 = love.graphics.newMesh({{"InstanceData", "float", 3}}, instanceCount, "points", "stream")

    -- Fill instance data
    love.math.setRandomSeed(0)
    for i=1,instanceCount do
        local x = love.math.random() * 600
        local y = love.math.random() * 600
        local z = y / 600
        instanceData[i] = {x, y, z}
    end
    for i=1,instanceCount do
        local x = love.math.random() * 600
        local y = love.math.random() * 600
        local z = y / 600
        instanceData2[i] = {x, y, z}
    end
    instanceMesh:setVertices(instanceData)
    instanceMesh2:setVertices(instanceData2)

    -- Attach instance mesh
    mesh:attachAttribute("InstanceData", instanceMesh, "perinstance")
    mesh2:attachAttribute("InstanceData", instanceMesh2, "perinstance")

    -- Shader: cutout + per-instance depth
    shader = love.graphics.newShader([[
    #pragma language glsl3
    varying float VZ;

    #ifdef VERTEX
        attribute vec3 InstanceData;
    vec4 position(mat4 transform_projection, vec4 vertex_position) {
        vec4 pos = vertex_position;
        pos.xy += InstanceData.xy;
        VZ = InstanceData.y/love_ScreenSize.y;
        return transform_projection * pos;
    }
    #endif

    #ifdef PIXEL
    //extern Image MainTex;
    vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
        vec4 texColor = Texel(MainTex, uv) * color;

        // cutout alpha test
        if (texColor.a < 0.5) discard;

        // write depth per instance
        gl_FragDepth = 1.0 - VZ;

        return vec4(gl_FragDepth,gl_FragDepth,gl_FragDepth,1);
    }
    #endif
]])

shader2 = love.graphics.newShader([[
#pragma language glsl3
    varying float VZ;

    #ifdef VERTEX
        attribute vec3 InstanceData;
    vec4 position(mat4 transform_projection, vec4 vertex_position) {
        vec4 pos = vertex_position;
        pos.xy += InstanceData.xy;
        VZ = InstanceData.y/love_ScreenSize.y;
        return transform_projection * pos;
    }
    #endif

    #ifdef PIXEL
    //extern Image MainTex;
    vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
        vec4 texColor = Texel(MainTex, uv) * color;

        // cutout alpha test
        if (texColor.a < 0.5) discard;

        // write depth per instance
        gl_FragDepth = 1.0 - VZ;

        return texColor;
    }
    #endif
]])

love.graphics.setDepthMode("lequal", true)
end
local t = 0
function love.update(dt)
    t = t + dt
    -- make first instance follow mouse
    local mx,my = love.mouse.getPosition()
    if mx and my then
        instanceData[1][1] = mx - image:getWidth()/2
        instanceData[1][2] = my - image:getHeight()/2
        instanceData[1][3] = (my)/1000 -- z
        instanceMesh:setVertices(instanceData)
    end
end
-- both batches of drawns can be sorted on GPU!!!
function love.draw()
    -- love.graphics.setCanvas({canvas, depthstencil=depth})
    -- love.graphics.clear(0,0,0,0,true,true)
    -- love.graphics.setDepthMode("lequal", true)
    love.graphics.setShader(shader)
    -- draw all instances
    love.graphics.drawInstanced(mesh, instanceCount)
    -- love.graphics.setShader()

    love.graphics.setShader(shader)
    -- draw all instances
    love.graphics.drawInstanced(mesh2, instanceCount)
    love.graphics.setShader()
    
    
    -- love.graphics.setDepthMode()
    -- love.graphics.setCanvas()

    -- love.graphics.clear(0.2,0.2,0.2,1)
    -- love.graphics.draw(canvas, 0, 0)
end
