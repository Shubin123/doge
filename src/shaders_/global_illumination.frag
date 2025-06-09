uniform sampler2D surfaceTexture;
uniform float maxDistance;
uniform int sampleCount;
uniform float time;
uniform vec3 ambientColor;
uniform float glowIntensity;
uniform float colorVibrancy;

// Dynamic lighting system - struct array format
uniform int numLights;

struct Light {
    vec2 pos;
    vec3 color;
    float intensity;
    float size;
    vec2 dir;    // new: direction for flares
    float seed;  // new: per-light noise seed
};

uniform Light lights[16];

const float PI = 3.14159265359;

float rand(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

float saturate(float x) {
    return clamp(x, 0.0, 1.0);
}

// Color enhancement function
vec3 enhanceColor(vec3 color) {
    float luminance = dot(color, vec3(0.299, 0.587, 0.114));
    vec3 saturated = mix(vec3(luminance), color, colorVibrancy);
    
    saturated.r = pow(saturated.r, 0.95);
    saturated.g = pow(saturated.g, 1.0);
    saturated.b = pow(saturated.b, 1.05);
    
    return saturated;
}

// Access light data from struct array
vec2 getLightPos(int index) {
    return lights[index].pos;
}

vec3 getLightColor(int index) {
    return lights[index].color;
}

float getLightIntensity(int index) {
    return lights[index].intensity;
}

float getLightSize(int index) {
    return lights[index].size;
}

vec2 getLightDir(int index) {
    return lights[index].dir;
}

float getLightSeed(int index) {
    return lights[index].seed;
}

// Realistic dynamic lighting calculation
vec3 calculateDynamicLighting(vec2 tc) {
    vec3 totalLight = vec3(0.0);
    
    for(int i = 0; i < numLights && i < 16; i++) {
        vec2 lightPos = getLightPos(i);
        vec3 lightColor = getLightColor(i);
        float lightIntensity = getLightIntensity(i);
        float lightSize = getLightSize(i);
        vec2 lightDir = getLightDir(i);
        float lightSeed = getLightSeed(i);
        
        if(lightIntensity <= 0.0) continue;
        
        // New physics-based attenuation calculation
        vec2 L = tc - lightPos;
        float d = length(L);
        vec2 N = L / max(d, 0.0001);
        float phys = pow(saturate(1.0 - pow(d / lightSize, 4.0)), 2.0) / (d * d + 1.0);
        float align = max(dot(N, -lightDir), 0.0);
        float dirFalloff = pow(align, 8.0);
        float ellipse = 1.0 - smoothstep(0.0, 1.0, length(vec2(L.x / (lightSize * 1.2), L.y / (lightSize * 0.6))));
        float n = fract(sin(dot(lightPos * lightSeed, vec2(12.989, 78.233))) * 43758.5453);
        float noiseMod = mix(0.8, 1.2, n);
        float attenuation = phys * mix(ellipse, dirFalloff, step(0.5, align)) * noiseMod;
        
        // Realistic light shape variations
        float shapeVariation = 1.0;
        if(lightIntensity > 2.5) { // Explosions - irregular shape
            float angle = atan(N.y, N.x);
            shapeVariation = 0.8 + 0.3 * sin(angle * 6.0 + time * 15.0) * sin(angle * 4.0 + time * 8.0);
        } else if(lightIntensity > 1.5) { // Muzzle flashes - directional
            float angle = atan(N.y, N.x);
            shapeVariation = 0.9 + 0.2 * cos(angle * 2.0);
        } else if(lightIntensity > 0.5) { // Fire - organic flicker
            float angle = atan(N.y, N.x);
            shapeVariation = 0.85 + 0.25 * sin(angle * 3.0 + time * 12.0) * cos(angle * 5.0 + time * 6.0);
        }
        
        // Realistic flickering patterns
        float flicker = 1.0;
        if(lightIntensity > 2.5) { // Explosions - violent flicker
            flicker = 0.7 + 0.3 * abs(sin(time * 80.0 + float(i) * 3.7)) * 
                     abs(cos(time * 120.0 + float(i) * 2.3));
        } else if(lightIntensity > 1.5) { // Muzzle flashes - sharp decay
            flicker = 0.9 + 0.1 * sin(time * 45.0 + float(i) * 4.1);
        } else if(lightIntensity > 0.5) { // Fire - organic flicker
            flicker = 0.85 + 0.15 * sin(time * 18.0 + float(i)) * 
                     sin(time * 22.0 + float(i) * 1.7);
        }
        
        // Realistic color temperature shifts
        vec3 tempVariation = vec3(1.0);
        if(lightIntensity > 2.0) { // Hot explosions shift toward white/blue
            tempVariation = vec3(
                1.0 + 0.2 * sin(time * 30.0 + float(i)),
                1.0 + 0.15 * sin(time * 25.0 + float(i) * 1.3),
                1.0 + 0.3 * sin(time * 35.0 + float(i) * 0.7)
            );
        } else if(lightIntensity > 1.0) { // Fire shifts orange/red
            tempVariation = vec3(
                1.0 + 0.1 * sin(time * 15.0 + float(i)),
                1.0 - 0.05 * sin(time * 12.0 + float(i) * 1.2),
                1.0 - 0.15 * sin(time * 18.0 + float(i) * 0.8)
            );
        }
        
        totalLight += lightColor * tempVariation * lightIntensity * attenuation * flicker * shapeVariation;
    }
    
    return totalLight;
}

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    float oneOverRays = 1.0 / float(sampleCount);
    float tauOverRays = 2.0 * PI * oneOverRays;
    vec2 oneOverSize = vec2(1.0) / vec2(love_ScreenSize.x, love_ScreenSize.y);
    vec2 ratio = normalize(oneOverSize);
    float minStepSize = min(oneOverSize.x, oneOverSize.y) * 0.5;
    
    // Complex ambient + dynamic lighting
    vec3 radiance = ambientColor * 0.6;
    vec3 dynamicContribution = calculateDynamicLighting(tc);
    radiance += dynamicContribution * 0.8;
    
    vec3 glowAccum = vec3(0.0);
    float noise = rand(tc + vec2(time * 0.01));
    
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
                
                vec3 enhancedColor = enhanceColor(hitColor);
                radiance += enhancedColor * falloff;
                
                // Complex glow system with dynamic light interaction
                float brightness = dot(hitColor, vec3(0.299, 0.587, 0.114));
                if (brightness > 0.2) {
                    vec3 baseGlow = hitColor * falloff * glowIntensity;
                    vec3 colorBleed = enhancedColor * falloff * glowIntensity * 0.7;
                    
                    // Multi-frequency pulsing
                    float pulse1 = 0.8 + 0.4 * sin(time * 8.0 + totalDistance);
                    float pulse2 = 0.9 + 0.2 * sin(time * 15.0 + totalDistance * 1.3);
                    float combinedPulse = (pulse1 + pulse2) * 0.5;
                    
                    glowAccum += (baseGlow + colorBleed) * combinedPulse;
                    
                    // Dynamic light influence on glow
                    for(int i = 0; i < numLights && i < 16; i++) {
                        vec2 lightPos = getLightPos(i);
                        vec3 lightColor = getLightColor(i);
                        float lightIntensity = getLightIntensity(i);
                        float lightSize = getLightSize(i);
                        
                        if(lightIntensity <= 0.0) continue;
                        
                        float lightDist = length(sampleTC - lightPos);
                        if(lightDist < lightSize * 2.0) {
                            float influence = (1.0 - lightDist / (lightSize * 2.0));
                            glowAccum += lightColor * lightIntensity * influence * 0.4 * brightness;
                        }
                    }
                    
                    // Ultra-bright object special effects
                    if(brightness > 0.7) {
                        glowAccum += hitColor * 3.0 * falloff * sin(time * 20.0) * 0.2;
                        glowAccum += vec3(1.0, 0.9, 0.8) * falloff * sin(time * 35.0) * 0.15;
                    }
                }
                
                break;
            }
        }
    }
    
    // Average and apply enhancements
    vec3 finalColor = radiance * oneOverRays;
    finalColor += glowAccum * oneOverRays * 0.5; // Add glow contribution
    
    // Complex tone mapping with dynamic range
    finalColor = finalColor / (finalColor + vec3(0.5));
    finalColor = pow(finalColor, vec3(1.0 / 2.1));
    
    // Dynamic sprite enhancement with light interaction
    if (originalPixel.a > 0.5) {
        vec3 spriteColor = enhanceColor(originalPixel.rgb);
        
        // Calculate local dynamic lighting influence
        vec3 localDynamicLighting = calculateDynamicLighting(tc) * 0.6;
        spriteColor += localDynamicLighting;
        
        // Distance-based sprite lighting
        for(int i = 0; i < numLights && i < 16; i++) {
            vec2 lightPos = getLightPos(i);
            vec3 lightColor = getLightColor(i);
            float lightIntensity = getLightIntensity(i);
            float lightSize = getLightSize(i);
            
            if(lightIntensity <= 0.0) continue;
            
            float dist = length(tc - lightPos);
            if(dist < lightSize * 1.5) {
                float influence = (1.0 - dist / (lightSize * 1.5));
                spriteColor += lightColor * lightIntensity * influence * 0.3;
            }
        }
        
        finalColor = mix(finalColor, spriteColor, 0.4);
    }
    
    // Complex edge lighting effects
    for(int i = 0; i < numLights && i < 16; i++) {
        vec2 lightPos = getLightPos(i);
        vec3 lightColor = getLightColor(i);
        float lightIntensity = getLightIntensity(i);
        float lightSize = getLightSize(i);
        
        if(lightIntensity <= 0.0) continue;
        
        float dist = length(tc - lightPos);
        
        // Realistic light scattering and bloom
        vec2 lightDir = tc - lightPos;
        float lightDist = length(lightDir);
        
        // Soft atmospheric scattering
        if(lightDist < lightSize * 1.5) {
            float scatterFalloff = exp(-lightDist * 2.0);
            float scatterIntensity = lightIntensity * scatterFalloff * 0.1;
            finalColor += lightColor * scatterIntensity;
        }
        
        // Realistic bloom with directional bias
        if(lightDist < lightSize * 0.8) {
            vec2 normalizedDir = lightDist > 0.0 ? lightDir / lightDist : vec2(0.0);
            float angle = atan(normalizedDir.y, normalizedDir.x);
            
            // Create realistic lens flare effect
            float bloomShape = 1.0;
            if(lightIntensity > 2.0) {
                bloomShape = 0.7 + 0.3 * abs(cos(angle * 4.0));
            }
            
            float bloomFalloff = (1.0 - lightDist / (lightSize * 0.8));
            bloomFalloff = pow(bloomFalloff, 1.5); // More natural falloff
            
            finalColor += lightColor * lightIntensity * bloomFalloff * bloomShape * 0.2;
        }
    }
    
    // Clamp to prevent over-brightening
    finalColor = min(finalColor, vec3(1.2));
    
    return vec4(finalColor, 1.0);
}
