local sampleScreen = {}
sampleScreen.shader = nil
sampleScreen.brightness = 0
sampleScreen.x = 0
sampleScreen.y = 0


imageData = nil
function sampleScreen.load()
    sampleScreen.canvas = love.graphics.newCanvas(1,1)
    sampleScreen.shader = love.graphics.newShader([[
    uniform sampler2D lightingTex;
    uniform vec2 sampleUV;
    vec4 effect(vec4 color, Image text, vec2 textCoord, vec2 screenCoord){
        //sample a region instead
        //float uregion = mix(sampleUV.x,sampleUV.z,textCoord.x);
        //float vregion = mix(sampleUV.y,sampleUV.w,textCoord.y);
        return Texel(lightingTex,sampleUV.xy); // single pixel of sample works and cheapish
    }
    ]])
end

function sampleScreen.pass()
    sampleScreen.shader:send("lightingTex",gi_canvas)
    -- sampleScreen.shader:send("sampleUV",{sampleScreen.x/var.screen_width,sampleScreen.y/var.screen_height,(sampleScreen.x+10)/var.screen_width,(sampleScreen.y+10)/var.screen_height})
    sampleScreen.shader:send("sampleUV",{sampleScreen.x/var.screen_width,sampleScreen.y/var.screen_height})
    love.graphics.setCanvas(sampleScreen.canvas)
    love.graphics.setShader(sampleScreen.shader)
    love.graphics.rectangle("fill",0,0,1,1)
    love.graphics.setShader()
    love.graphics.setCanvas()
    -- imageData = sampleScreen.canvas:newImageData()
    -- imageData = scene_canvas:newImageData()
end

-- function sampleScreen.sample()
--     sample = coroutine.create(function()
--         coroutine.yield()
--         local imageData = sampleScreen.canvas:newImageData()
--         coroutine.yield()
--         local r,g,b = imageData:getPixel(0,0)
--         sampleScreen.brightness = 0.2126*r+0.7152*g+0.07722*b
--         coroutine.yield()
--         -- coroutine.yield()
--     end)
-- end


return sampleScreen