// Glass-aware GI shader - extends ray marching with refraction, Fresnel, and color tinting
// Glass pixels are identified by alpha in [0.2, 0.35] on the surface texture
// When a ray hits glass, it refracts (Snell's law), partially reflects (Schlick Fresnel),
// tints transmitted light by glass color, and continues marching.

uniform sampler2D surfaceTexture;
uniform float maxDistance;
uniform int sampleCount;
uniform highp float time;
uniform vec3 ambientColor;
uniform float glowIntensity;
uniform float colorVibrancy;
uniform float ior; // Index of refraction for glass (default ~1.5)

const float PI = 3.14159265359;
const float GLASS_ALPHA_MIN = 0.2;
const float GLASS_ALPHA_MAX = 0.35;
const int MAX_REFRACTIONS = 2;

float rand(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

// Schlick's Fresnel approximation
float fresnelSchlick(float cosTheta, float n1, float n2) {
    float r0 = (n1 - n2) / (n1 + n2);
    r0 = r0 * r0;
    return r0 + (1.0 - r0) * pow(1.0 - cosTheta, 5.0);
}

// Estimate surface normal from distance field gradient (central differences)
vec2 estimateNormal(Image dfTex, vec2 tc) {
    vec2 texelSize = vec2(1.0) / vec2(love_ScreenSize.x, love_ScreenSize.y);
    float dL = Texel(dfTex, tc - vec2(texelSize.x, 0.0)).r;
    float dR = Texel(dfTex, tc + vec2(texelSize.x, 0.0)).r;
    float dU = Texel(dfTex, tc - vec2(0.0, texelSize.y)).r;
    float dD = Texel(dfTex, tc + vec2(0.0, texelSize.y)).r;
    vec2 grad = vec2(dR - dL, dD - dU);
    float len = length(grad);
    return len > 0.001 ? grad / len : vec2(0.0, 1.0);
}

// 2D refraction: bend ray direction through surface with given IOR ratio
vec2 refract2D(vec2 incident, vec2 normal, float eta) {
    float cosI = -dot(incident, normal);
    // Ensure normal faces against the ray
    if (cosI < 0.0) {
        normal = -normal;
        cosI = -cosI;
    }
    float sinT2 = eta * eta * (1.0 - cosI * cosI);
    // Total internal reflection
    if (sinT2 > 1.0) {
        return reflect(incident, normal);
    }
    float cosT = sqrt(1.0 - sinT2);
    return eta * incident + (eta * cosI - cosT) * normal;
}

bool isGlass(vec4 pixel) {
    return pixel.a >= GLASS_ALPHA_MIN && pixel.a <= GLASS_ALPHA_MAX;
}

vec3 enhanceColor(vec3 color) {
    float luminance = dot(color, vec3(0.299, 0.587, 0.114));
    vec3 saturated = mix(vec3(luminance), color, colorVibrancy);
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

    vec3 radiance = ambientColor * 0.8;
    vec3 glowAccum = vec3(0.0);
    float noise = rand(tc + vec2(time * 0.01));

    vec4 originalPixel = Texel(surfaceTexture, tc);

    for (int i = 0; i < sampleCount; i++) {
        float angle = (0.5 + float(i) + noise) * tauOverRays;
        vec2 rayDirection = vec2(cos(angle), sin(angle));
        vec2 sampleTC = tc;
        float totalDistance = 0.0;

        // Color tint accumulated from glass transmissions
        vec3 tint = vec3(1.0);
        int refractionsLeft = MAX_REFRACTIONS;

        for (int step = 0; step < maxDistance; step += 1) {
            float df = Texel(tex, sampleTC).r;
            sampleTC += rayDirection * df * ratio;
            totalDistance += df;

            if (sampleTC.x < 0.0 || sampleTC.x > 1.0 ||
                sampleTC.y < 0.0 || sampleTC.y > 1.0) break;

            if (df <= minStepSize) {
                vec4 hitPixel = Texel(surfaceTexture, sampleTC);

                // --- GLASS HANDLING ---
                if (isGlass(hitPixel) && refractionsLeft > 0) {
                    refractionsLeft--;

                    // Estimate surface normal from DF gradient
                    vec2 normal = estimateNormal(tex, sampleTC);

                    // Fresnel: determine reflect vs transmit ratio
                    float cosTheta = abs(dot(rayDirection, normal));
                    float reflectance = fresnelSchlick(cosTheta, 1.0, ior);

                    // Tint transmitted light by glass color
                    vec3 glassColor = pow(hitPixel.rgb, vec3(2.2));
                    tint *= mix(glassColor, vec3(1.0), 0.3); // partial tint

                    // Refract the ray direction
                    rayDirection = normalize(refract2D(rayDirection, normal, 1.0 / ior));

                    // Push ray past the glass surface to avoid re-hitting
                    sampleTC += rayDirection * minStepSize * 4.0 * ratio;

                    // Add reflected contribution (attenuated)
                    float reflFalloff = 1.0 - smoothstep(0.0, maxDistance * 0.8, totalDistance);
                    radiance += enhanceColor(glassColor) * reflFalloff * reflectance * 0.5;

                    continue; // keep marching the refracted ray
                }

                // --- NORMAL OPAQUE HIT ---
                vec3 hitColor = pow(hitPixel.rgb, vec3(2.2));
                float falloff = 1.0 - smoothstep(0.0, maxDistance * 0.8, totalDistance);
                falloff = pow(falloff, 0.8);

                vec3 enhancedColor = enhanceColor(hitColor);
                // Apply accumulated glass tint to transmitted light
                radiance += enhancedColor * falloff * tint;

                float brightness = dot(hitColor, vec3(0.299, 0.587, 0.114));
                if (brightness > 0.5) {
                    glowAccum += hitColor * falloff * glowIntensity * tint;
                }

                break;
            }
        }
    }

    vec3 finalColor = radiance * oneOverRays;
    finalColor += glowAccum * oneOverRays * 0.5;

    // Tone mapping
    finalColor = finalColor / (finalColor + vec3(1.0));
    finalColor = pow(finalColor, vec3(1.0 / 2.2));

    // Mix with original for sprites
    if (originalPixel.a > 0.5) {
        finalColor = mix(finalColor, enhanceColor(originalPixel.rgb), 0.3);
    }

    return vec4(finalColor, 1.0);
}
