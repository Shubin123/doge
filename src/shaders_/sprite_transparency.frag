// Shader to handle sprite transparency - makes white backgrounds transparent

uniform float threshold = 0.9; // How close to white should be transparent
uniform float smoothness = 0.1; // Smoothness of the transparency transition

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
    vec4 texel = Texel(texture, texture_coords);
    
    // Calculate how close this pixel is to white
    float whiteness = min(min(texel.r, texel.g), texel.b);
    float white_amount = (texel.r + texel.g + texel.b) / 3.0;
    
    // Make pixels close to pure white transparent
    float alpha_factor = 1.0 - smoothstep(threshold - smoothness, threshold, white_amount);
    
    // Also reduce alpha for very bright pixels
    if (texel.r > 0.95 && texel.g > 0.95 && texel.b > 0.95) {
        alpha_factor *= 0.1;
    }
    
    // Apply the color and computed alpha
    return vec4(texel.rgb * color.rgb, texel.a * color.a * alpha_factor);
}