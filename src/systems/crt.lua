-- needs to be migrated to the new mod system, do not use this in new code.
local crt = {}

function crt.load()

    
-- Shader source code
shaderCode = [[
#if defined(VERTEX) || __VERSION__ > 100 || defined(GL_FRAGMENT_PRECISION_HIGH)
	#define MY_HIGHP_OR_MEDIUMP highp
#else
	#define MY_HIGHP_OR_MEDIUMP mediump
#endif

extern MY_HIGHP_OR_MEDIUMP number time;
extern MY_HIGHP_OR_MEDIUMP vec2 distortion_fac;
extern MY_HIGHP_OR_MEDIUMP vec2 scale_fac;
extern MY_HIGHP_OR_MEDIUMP number feather_fac;
extern MY_HIGHP_OR_MEDIUMP number noise_fac;
extern MY_HIGHP_OR_MEDIUMP number bloom_fac;
extern MY_HIGHP_OR_MEDIUMP number crt_intensity;
extern MY_HIGHP_OR_MEDIUMP number glitch_intensity;
extern MY_HIGHP_OR_MEDIUMP number scanlines;

#define BUFF 0.01
#define BLOOM_AMT 1

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 pc)
{
    //Keep the original texture coords
    MY_HIGHP_OR_MEDIUMP vec2 orig_tc = tc;

    //recenter
    tc = tc*2.0 - vec2(1.0);
    tc *= scale_fac;

    //bulge from middle
    tc += (tc.yx*tc.yx) * tc * (distortion_fac - 1.0);

    //smoothly transition the edge to black
    //buffer for the outer edge, this gets wonky if there is no buffer
    MY_HIGHP_OR_MEDIUMP number mask = (1.0 - smoothstep(1.0-feather_fac,1.0,abs(tc.x) - BUFF))
                * (1.0 - smoothstep(1.0-feather_fac,1.0,abs(tc.y) - BUFF));

    //undo the recenter
    tc = (tc + vec2(1.0))/2.0;

    // Check if we're outside the valid texture coordinates
    if (tc.x < 0.0 || tc.x > 1.0 || tc.y < 0.0 || tc.y > 1.0) {
        return vec4(0.0, 0.0, 0.0, 0.0); // Return transparent black
    }

    //Create the horizontal glitch offset effects
    MY_HIGHP_OR_MEDIUMP number offset_l = 0.;
    MY_HIGHP_OR_MEDIUMP number offset_r = 0.;
    if(glitch_intensity > 0.01){
        MY_HIGHP_OR_MEDIUMP number timefac = 3.0*time;
        offset_l = 50.0*(-3.5+sin(timefac*0.512 + tc.y*40.0)
                + sin(-timefac*0.8233 + tc.y*81.532)
                + sin(timefac*0.333 + tc.y*30.3)
                + sin(-timefac*0.1112331 + tc.y*13.0));
        offset_r = -50.0*(-3.5+sin(timefac*0.6924 + tc.y*29.0)
                + sin(-timefac*0.9661 + tc.y*41.532)
                + sin(timefac*0.4423 + tc.y*40.3)
                + sin(-timefac*0.13321312 + tc.y*11.0));

        if(glitch_intensity > 1.0){
            offset_l = 50.0*(-1.5+sin(timefac*0.512 + tc.y*4.0)
                + sin(-timefac*0.8233 + tc.y*1.532)
                + sin(timefac*0.333 + tc.y*3.3)
                + sin(-timefac*0.1112331 + tc.y*1.0));
            offset_r = -50.0*(-1.5+sin(timefac*0.6924 + tc.y*19.0)
                + sin(-timefac*0.9661 + tc.y*21.532)
                + sin(timefac*0.4423 + tc.y*20.3)
                + sin(-timefac*0.13321312 + tc.y*5.0));
        }  
        tc.x = tc.x + 0.001*glitch_intensity*clamp(offset_l, clamp(offset_r, -1.0, 0.0), 1.0);
    }

    // Sample the main texture - preserving alpha
	MY_HIGHP_OR_MEDIUMP vec4 crt_tex = Texel(tex, tc);
    
    // If the original pixel is transparent, return transparent
    if (crt_tex.a < 0.001) {
        return vec4(0.0, 0.0, 0.0, 0.0);
    }

    //intensity multiplier for any visual artifacts
    MY_HIGHP_OR_MEDIUMP float artifact_amplifier = (abs(clamp(offset_l, clamp(offset_r, -1.0, 0.0), 1.0))*glitch_intensity > 0.9 ? 3. : 1.);

    //Horizontal Chromatic Aberration
	MY_HIGHP_OR_MEDIUMP float crt_amout_adjusted = (max(0., (crt_intensity)/(0.16*0.3)))*artifact_amplifier;
    if(crt_amout_adjusted > 0.0000001) {
        // Sample with chromatic aberration, but check bounds first
        MY_HIGHP_OR_MEDIUMP vec2 r_coord = tc + vec2(0.0005*(1. +10.*(artifact_amplifier - 1.))*1600./love_ScreenSize.x, 0.);
        MY_HIGHP_OR_MEDIUMP vec2 g_coord = tc + vec2(-0.0005*(1. +10.*(artifact_amplifier - 1.))*1600./love_ScreenSize.x, 0.);
        
        MY_HIGHP_OR_MEDIUMP vec4 r_sample = (r_coord.x >= 0.0 && r_coord.x <= 1.0 && r_coord.y >= 0.0 && r_coord.y <= 1.0) ? Texel(tex, r_coord) : vec4(0.0);
        MY_HIGHP_OR_MEDIUMP vec4 g_sample = (g_coord.x >= 0.0 && g_coord.x <= 1.0 && g_coord.y >= 0.0 && g_coord.y <= 1.0) ? Texel(tex, g_coord) : vec4(0.0);
        
        crt_tex.r = crt_tex.r*(1.-crt_amout_adjusted) + crt_amout_adjusted*r_sample.r;
        crt_tex.g = crt_tex.g*(1.-crt_amout_adjusted) + crt_amout_adjusted*g_sample.g;
        // Keep original alpha
    }
    
	MY_HIGHP_OR_MEDIUMP vec3 rgb_result = crt_tex.rgb*(1.0 - (1.0*crt_intensity*artifact_amplifier));

    //post processing on the glitch effect to amplify green or red for a few lines of pixels
    if (sin(time + tc.y*200.0) > 0.85) {
        if (offset_l < 0.99 && offset_l > 0.01) rgb_result.r = rgb_result.g*1.5;
        if (offset_r > -0.99 && offset_r < -0.01) rgb_result.g = rgb_result.r*1.5;
    }

    //Add the pixel scanline overlay
	MY_HIGHP_OR_MEDIUMP vec3 rgb_scanline = 1.0*vec3( 
        clamp(-0.3+2.0*sin( tc.y * scanlines-3.14/4.0) - 0.8*clamp(sin( tc.x*scanlines*4.0), 0.4, 1.0), -1.0, 2.0),
        clamp(-0.3+2.0*cos( tc.y * scanlines) - 0.8*clamp(cos( tc.x*scanlines*4.0), 0.0, 1.0), -1.0, 2.0),
        clamp(-0.3+2.0*cos( tc.y * scanlines -3.14/3.0) - 0.8*clamp(cos( tc.x*scanlines*4.0-3.14/4.0), 0.0, 1.0), -1.0, 2.0));
	
	rgb_result += crt_tex.rgb * rgb_scanline * crt_intensity * artifact_amplifier;
	
    //Add in some noise
    MY_HIGHP_OR_MEDIUMP number x = (tc.x - mod(tc.x, 0.002)) * (tc.y - mod(tc.y, 0.0013)) * time * 1000.0;
	x = mod( x, 13.0 ) * mod( x, 123.0 );
	MY_HIGHP_OR_MEDIUMP number dx = mod( x, 0.11 )/0.11;
	rgb_result = (1.0-clamp( noise_fac*artifact_amplifier, 0.0,1.0 ))*rgb_result + dx * clamp( noise_fac*artifact_amplifier, 0.0,1.0 ) * vec3(1.0,1.0,1.0);

    //contrast and brightness correction for the CRT effect
    rgb_result -= vec3(0.55 - 0.02*(artifact_amplifier - 1. - crt_amout_adjusted*bloom_fac*0.7));
    rgb_result = rgb_result*(1.0 + 0.14 + crt_amout_adjusted*(0.012 - bloom_fac*0.12));
    rgb_result += vec3(0.5);

    //Prepare the final colour to return - preserve original alpha
    MY_HIGHP_OR_MEDIUMP vec4 final_col = vec4(rgb_result, crt_tex.a);

    //Apply bloom if enabled
    MY_HIGHP_OR_MEDIUMP vec4 col = vec4(0.0);
    MY_HIGHP_OR_MEDIUMP float bloom = 0.0;

    if (bloom_fac > 0.00001 && crt_intensity > 0.000001){
        bloom = 0.03*(max(0., (crt_intensity)/(0.16*0.3)));
        MY_HIGHP_OR_MEDIUMP float bloom_dist = 0.0015*float(BLOOM_AMT);
        MY_HIGHP_OR_MEDIUMP vec4 samp;
        MY_HIGHP_OR_MEDIUMP float cutoff = 0.6;

        for (int i = -BLOOM_AMT; i <= BLOOM_AMT; ++i)
            for (int j = -BLOOM_AMT; j <= BLOOM_AMT; ++j){
                MY_HIGHP_OR_MEDIUMP vec2 bloom_coord = tc + (bloom_dist/float(BLOOM_AMT))*vec2(float(i), float(j));
                if (bloom_coord.x >= 0.0 && bloom_coord.x <= 1.0 && bloom_coord.y >= 0.0 && bloom_coord.y <= 1.0) {
                    samp = Texel(tex, bloom_coord);
                    samp.r = max(1./(1.-cutoff)*samp.r - 1./(1.-cutoff) + 1., 0.);
                    samp.g = max(1./(1.-cutoff)*samp.g - 1./(1.-cutoff) + 1., 0.);
                    samp.b = max(1./(1.-cutoff)*samp.b - 1./(1.-cutoff) + 1., 0.);
                    col += min(min(samp.r,samp.g),samp.b) * (2. - float(abs(float(i+j)))/float(BLOOM_AMT+BLOOM_AMT));
                }
        }   

        col /= float(BLOOM_AMT*BLOOM_AMT);
        col.a = crt_tex.a; // Preserve alpha
    }

    // Apply mask and return final result with proper alpha
    MY_HIGHP_OR_MEDIUMP vec4 result = (final_col*(1. -1.*bloom) + bloom*col)*mask;
    result.a = crt_tex.a; // Ensure alpha is preserved
    
    return result;
}
]]



crtShader = crt:new({
    crt_intensity = 0.06,
    glitch_intensity = 0.2,
    bloom_fac = 0.4
})

end

-- Default parameters
local defaultParams = {
    time = 0,
    distortion_fac = {1.02, 1.065},
    scale_fac = {1, 1},
    feather_fac = 0.02,
    noise_fac = 0.03,
    bloom_fac = 0.3,
    crt_intensity = 0.48,
    glitch_intensity = 0.1,
    scanlines = 800
}

function crt:new(params)
    local shader = {}
    setmetatable(shader, {__index = self})
    
    -- Create the shader
    shader.shader = love.graphics.newShader(shaderCode)
    shader.params = {}
    
    -- Initialize parameters
    for k, v in pairs(defaultParams) do
        shader.params[k] = v
    end
    
    -- Override with provided parameters
    if params then
        for k, v in pairs(params) do
            shader.params[k] = v
        end
    end
    
    -- Create canvas for full-screen post-processing
    shader:updateCanvas()
    
    -- Set initial shader parameters
    shader:updateParams()
    
    return shader
end

function crt:updateCanvas()
    local w, h = love.graphics.getDimensions()
    if not self.canvas or self.canvas:getWidth() ~= w or self.canvas:getHeight() ~= h then
        if self.canvas then
            self.canvas:release()
        end
        self.canvas = love.graphics.newCanvas(w, h)
    end
end

function crt:updateParams(newParams)
    if newParams then
        for k, v in pairs(newParams) do
            self.params[k] = v
        end
    end
    
    -- Send parameters to shader
    for k, v in pairs(self.params) do
        if self.shader:hasUniform(k) then
            self.shader:send(k, v)
        end
    end
end

-- function crt:setTime(time)
--     self.params.time = time
--     if self.shader:hasUniform("time") then
--         self.shader:send("time", time)
--     end
-- end

-- function crt:setGlitchIntensity(intensity)
--     self.params.glitch_intensity = intensity
--     if self.shader:hasUniform("glitch_intensity") then
--         self.shader:send("glitch_intensity", intensity)
--     end
-- end

-- function crt:setCRTIntensity(intensity)
--     self.params.crt_intensity = intensity
--     if self.shader:hasUniform("crt_intensity") then
--         self.shader:send("crt_intensity", intensity)
--     end
-- end

-- -- Begin capturing the screen for post-processing
-- function crt:beginCapture()
--     -- self:updateCanvas() -- Ensure canvas matches current screen size
--     -- love.graphics.setCanvas(self.canvas)
--     -- love.graphics.clear(0, 0, 0, 0) -- Clear with transparent black

--     -- handled by main prepass

-- end

-- End capture and apply the CRT effect to the entire screen
function crt.endCapture()
    -- love.graphics.setCanvas()
    
    -- Store current graphics state
    -- local currentShader = love.graphics.getShader()
    -- local currentBlendMode = love.graphics.getBlendMode()
    
    -- Get screen dimensions to ensure full coverage
    -- local screenWidth, screenHeight = love.graphics.getDimensions()
    
    -- Apply the CRT shader to the entire screen
    love.graphics.setShader(crtShader.shader)
    -- love.graphics.setBlendMode("add", "premultiplied")
    love.graphics.draw(scene_canvas, 0, 0, 0, 1, 1)
    
    -- Restore previous graphics state
    love.graphics.setShader()
    -- love.graphics.setBlendMode(currentBlendMode)
end



return crt