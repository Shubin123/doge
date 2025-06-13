// Enemy Damage Shader - Red tint and pulsing effect for low health enemies

uniform float health_percent;
uniform float time;
uniform float damage_flash;

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
    vec4 tex_color = Texel(texture, texture_coords);
    
    // Skip transparent pixels
    if (tex_color.a < 0.01) {
        return tex_color;
    }
    
    // Calculate damage effect intensity based on health
    float damage_intensity = 1.0 - health_percent;
    
    // Add pulsing effect for critical health (below 30%)
    float pulse = 0.0;
    if (health_percent < 0.3) {
        pulse = sin(time * 5.0) * 0.3 + 0.5;
        damage_intensity = mix(damage_intensity, 1.0, pulse * (1.0 - health_percent * 3.33));
    }
    
    // Flash white when recently damaged
    if (damage_flash > 0.0) {
        vec3 flash_color = mix(tex_color.rgb, vec3(1.0), damage_flash);
        tex_color.rgb = flash_color;
    }
    
    // Apply red tint based on damage
    vec3 damaged_color = tex_color.rgb;
    damaged_color.r = mix(tex_color.r, 1.0, damage_intensity * 0.7);
    damaged_color.g = mix(tex_color.g, tex_color.g * 0.3, damage_intensity);
    damaged_color.b = mix(tex_color.b, tex_color.b * 0.3, damage_intensity);
    
    // Add edge glow for critical health
    if (health_percent < 0.15) {
        float edge_detect = 0.0;
        
        // Simple edge detection
        vec4 up = Texel(texture, texture_coords + vec2(0.0, -1.0/256.0));
        vec4 down = Texel(texture, texture_coords + vec2(0.0, 1.0/256.0));
        vec4 left = Texel(texture, texture_coords + vec2(-1.0/256.0, 0.0));
        vec4 right = Texel(texture, texture_coords + vec2(1.0/256.0, 0.0));
        
        if (tex_color.a > 0.5 && (up.a < 0.5 || down.a < 0.5 || left.a < 0.5 || right.a < 0.5)) {
            edge_detect = 1.0;
        }
        
        if (edge_detect > 0.5) {
            damaged_color = mix(damaged_color, vec3(1.0, 0.2, 0.2), pulse);
        }
    }
    
    return vec4(damaged_color, tex_color.a) * color;
}