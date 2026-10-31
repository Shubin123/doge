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
extern MY_HIGHP_OR_MEDIUMP number noise_fac;
extern MY_HIGHP_OR_MEDIUMP number bloom_fac;
extern MY_HIGHP_OR_MEDIUMP number crt_intensity;
extern MY_HIGHP_OR_MEDIUMP number glitch_intensity;
extern MY_HIGHP_OR_MEDIUMP number scanlines;
extern MY_HIGHP_OR_MEDIUMP number contrast_pivot;

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

    //undo the recenter. The bulge pushes the corners a little past the
    //picture's edge; mirror back in there so the whole screen stays covered
    //(no black or see-through border, and nothing cropped at the edges)
    tc = (tc + vec2(1.0))/2.0;
    tc = vec2(1.0) - abs(vec2(1.0) - abs(tc));

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

    // Sample the finished frame (opaque: scene, GI, water and HUD)
	MY_HIGHP_OR_MEDIUMP vec4 crt_tex = Texel(tex, tc);

    //intensity multiplier for any visual artifacts
    MY_HIGHP_OR_MEDIUMP float artifact_amplifier = (abs(clamp(offset_l, clamp(offset_r, -1.0, 0.0), 1.0))*glitch_intensity > 0.9 ? 3. : 1.);

    //Horizontal Chromatic Aberration
	MY_HIGHP_OR_MEDIUMP float crt_amout_adjusted = (max(0., (crt_intensity)/(0.16*0.3)))*artifact_amplifier;
    if(crt_amout_adjusted > 0.0000001) {
        // Sample with chromatic aberration (off-screen samples clamp to the edge)
        MY_HIGHP_OR_MEDIUMP vec2 r_coord = tc + vec2(0.0005*(1. +10.*(artifact_amplifier - 1.))*1600./love_ScreenSize.x, 0.);
        MY_HIGHP_OR_MEDIUMP vec2 g_coord = tc + vec2(-0.0005*(1. +10.*(artifact_amplifier - 1.))*1600./love_ScreenSize.x, 0.);
        
        crt_tex.r = crt_tex.r*(1.-crt_amout_adjusted) + crt_amout_adjusted*Texel(tex, r_coord).r;
        crt_tex.g = crt_tex.g*(1.-crt_amout_adjusted) + crt_amout_adjusted*Texel(tex, g_coord).g;
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

    //contrast and brightness correction for the CRT effect. It pivots near
    //black (contrast_pivot): this pass covers the whole frame, which is
    //mostly dark, and a mid-grey pivot crushed it to black
    rgb_result -= vec3(contrast_pivot + 0.02 - 0.02*(artifact_amplifier - 1. - crt_amout_adjusted*bloom_fac*0.7));
    rgb_result = rgb_result*(1.0 + 0.14 + crt_amout_adjusted*(0.012 - bloom_fac*0.12));
    rgb_result += vec3(contrast_pivot);

    //Prepare the final colour to return
    MY_HIGHP_OR_MEDIUMP vec4 final_col = vec4(rgb_result, 1.0);

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
                samp = Texel(tex, tc + (bloom_dist/float(BLOOM_AMT))*vec2(float(i), float(j)));
                samp.r = max(1./(1.-cutoff)*samp.r - 1./(1.-cutoff) + 1., 0.);
                samp.g = max(1./(1.-cutoff)*samp.g - 1./(1.-cutoff) + 1., 0.);
                samp.b = max(1./(1.-cutoff)*samp.b - 1./(1.-cutoff) + 1., 0.);
                col += min(min(samp.r,samp.g),samp.b) * (2. - float(abs(float(i+j)))/float(BLOOM_AMT+BLOOM_AMT));
        }   

        col /= float(BLOOM_AMT*BLOOM_AMT);
    }

    // Opaque: this pass is the whole screen
    MY_HIGHP_OR_MEDIUMP vec4 result = final_col*(1. -1.*bloom) + bloom*col;
    result.a = 1.0;
    
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
    noise_fac = 0.03,
    bloom_fac = 0.3,
    crt_intensity = 0.48,
    glitch_intensity = 0.1,
    scanlines = 800,
    contrast_pivot = 0.05
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

-- The canvas the finished frame is drawn into -- scene composite, water and
-- HUD -- so the CRT pass can then cover the whole screen with it. It follows
-- the window's size.
function crt:target()
    self:updateCanvas()
    return self.canvas
end

-- Put the captured frame on screen through the CRT shader, every pixel. The
-- shader's output is opaque, so "replace" changes nothing but lets the GPU
-- skip reading the screen back.
function crt:present()
    local blend_mode, alpha_mode = love.graphics.getBlendMode()
    love.graphics.setCanvas()
    love.graphics.setBlendMode("replace", "premultiplied")
    love.graphics.setShader(self.shader)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.canvas)
    love.graphics.setShader()
    love.graphics.setBlendMode(blend_mode, alpha_mode)
end

-- Screen point -> the point of the captured frame shown there (the shader's
-- own mapping). The bulge moves the picture away from the OS cursor, most
-- near the edges; aim and clicks go through this so they hit what is drawn
-- under the cursor.
function crt.toImage(x, y)
    if not (var.graphics_high and crtShader) then return x, y end
    local w, h = love.graphics.getDimensions()
    local p = crtShader.params
    local u = (x / w * 2 - 1) * p.scale_fac[1]
    local v = (y / h * 2 - 1) * p.scale_fac[2]
    u, v = u + v * v * u * (p.distortion_fac[1] - 1), v + u * u * v * (p.distortion_fac[2] - 1)
    u, v = (u + 1) / 2, (v + 1) / 2
    u, v = 1 - math.abs(1 - math.abs(u)), 1 - math.abs(1 - math.abs(v)) -- the shader's mirror
    return u * w, v * h
end

-- love.mouse.getPosition() through crt.toImage.
function crt.mouse()
    return crt.toImage(love.mouse.getPosition())
end

return crt