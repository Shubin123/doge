uniform float smoothness;

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec2 nearestPoint = Texel(tex, tc).xy;
    float dist = length(tc - nearestPoint);
    
    // Apply smoothstep for nicer falloff
    dist = smoothstep(0.0, smoothness, dist);
    
    return vec4(dist, 0.0, 0.0, 1.0);
}