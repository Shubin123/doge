uniform sampler2D surfaceTexture;
uniform float maxDistance;
uniform int sampleCount;
uniform float time;
uniform vec3 ambientColor;
uniform float glowIntensity;
uniform float colorVibrancy;
uniform vec2 camera_position;
uniform float camera_zoom;
uniform mat4 view_matrix;

const float PI = 3.14159265359;

float rand(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

// Color enhancement function
vec3 enhanceColor(vec3 color) {
    // Increase saturation for arcade feel
    float luminance = dot(color, vec3(0.299, 0.587, 0.114));
    vec3 saturated = mix(vec3(luminance), color, colorVibrancy);
    
    // Apply slight color grading
    saturated.r = pow(saturated.r, 0.95);
    saturated.g = pow(saturated.g, 1.0);
    saturated.b = pow(saturated.b, 1.05);
    
    return saturated;
}

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    float oneOverRays = 1.0 / float(sampleCount);
    float tauOverRays = 2.0 * PI * oneOverRays;
    vec2 oneOverSize = vec2(1.0) / vec2(love_ScreenSize.x, love_ScreenSize.y);
    vec2 ratio = normalize(oneOverSize);
    float minStepSize = min(oneOverSize.x, oneOverSize.y) * 0.5;
    
    vec3 radiance = ambientColor * 0.8; // Bright ambient for gameplay visibility
    vec3 glowAccum = vec3(0.0);
    float noise = rand(tc + vec2(time * 0.01));
    
    // Get original pixel for glow calculation
    vec4 originalPixel = Texel(surfaceTexture, tc);
    
    for(int i = 0; i < sampleCount; i++) {
        float angle = (0.5 + float(i) + noise) * tauOverRays;
        vec2 rayDirection = vec2(cos(angle), sin(angle));
        vec2 sampleTC = tc;
        
        float totalDistance = 0.0;
        
        for (int step = 0; step < maxDistance; step += 1) {
            float df = Texel(tex, sampleTC).r;
            sampleTC += rayDirection * df * ratio;
            totalDistance += df;
            
            if(sampleTC.x < 0.0 || sampleTC.x > 1.0 ||
               sampleTC.y < 0.0 || sampleTC.y > 1.0) break;
            
            if (df <= minStepSize) {
                vec3 hitColor = Texel(surfaceTexture, sampleTC).rgb;
                hitColor = pow(hitColor, vec3(2.2)); // From sRGB
                
                // Distance-based falloff with glow
                float falloff = 1.0 - smoothstep(0.0, maxDistance * 0.8, totalDistance);
                falloff = pow(falloff, 0.8); // Softer falloff for arcade feel
                
                // Add color bleeding for vibrant arcade look
                vec3 enhancedColor = enhanceColor(hitColor);
                radiance += enhancedColor * falloff;
                
                // Accumulate glow from bright objects
                float brightness = dot(hitColor, vec3(0.299, 0.587, 0.114));
                if (brightness > 0.5) {
                    glowAccum += hitColor * falloff * glowIntensity;
                }
                
                break;
            }
        }
    }
    
    // Average and apply enhancements
    vec3 finalColor = radiance * oneOverRays;
    finalColor += glowAccum * oneOverRays * 0.5; // Add glow contribution
    
    // Apply tone mapping for arcade style
    finalColor = finalColor / (finalColor + vec3(1.0));
    finalColor = pow(finalColor, vec3(1.0 / 2.2)); // To sRGB
    
    // Mix with original for sprites
    if (originalPixel.a > 0.5) {
        finalColor = mix(finalColor, enhanceColor(originalPixel.rgb), 0.3);
    }
    
    return vec4(finalColor, 1.0);
}