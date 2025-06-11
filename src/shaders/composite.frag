uniform sampler2D bloomTexture;
uniform sampler2D giTexture;
uniform float bloomStrength;
uniform float giStrength;
uniform float contrast;
uniform float saturation;
uniform vec3 tintColor;

vec3 adjustContrast(vec3 color, float contrast) {
    return (color - 0.5) * contrast + 0.5;
}

vec3 adjustSaturation(vec3 color, float saturation) {
    float gray = dot(color, vec3(0.299, 0.587, 0.114));
    return mix(vec3(gray), color, saturation);
}

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec4 base = Texel(tex, tc);
    vec4 bloom = Texel(bloomTexture, tc);
    vec4 gi = Texel(giTexture, tc);
    
    // Blend GI with original scene
    vec3 result = mix(base.rgb, gi.rgb, giStrength);
    
    // Add bloom on top
    result = result + bloom.rgb * bloomStrength;
    
    // Apply post-processing
    result = adjustContrast(result, contrast);
    result = adjustSaturation(result, saturation);
    
    // Apply subtle color tint
    result = mix(result, result * tintColor, 0.1);
    
    // Vignette effect
    float vignette = 1.0 - length(tc - vec2(0.5)) * 0.5;
    vignette = smoothstep(0.3, 1.0, vignette);
    result *= vignette;
    
    return vec4(result, base.a);
}