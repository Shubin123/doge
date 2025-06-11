vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec4 pixel = Texel(tex, tc);
    // Retro-style edge detection with pixelation
    float edgeThreshold = 0.3;
    float pixelSize = 4.0; // Controls pixelation amount
    
    // Pixelate the coordinates
    vec2 pixelatedTC = floor(tc * pixelSize) / pixelSize;
    
    if (pixel.a > edgeThreshold) {
        // Add some noise for retro effect
        float noise = fract(sin(dot(pixelatedTC, vec2(12.9898, 78.233))) * 43758.5453);
        return vec4(pixelatedTC, noise * 0.1, 1.0);
    }
    return vec4(0.0);
}