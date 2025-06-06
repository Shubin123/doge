vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec4 pixel = Texel(tex, tc);
    // Add edge detection for sprite outlines
    float edgeThreshold = 0.3;
    if (pixel.a > edgeThreshold) {
        return vec4(tc, 0.0, 1.0);
    }
    return vec4(0.0);
}