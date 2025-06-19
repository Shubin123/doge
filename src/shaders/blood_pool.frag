// Simplified blood shader without arrays - using individual blood drops
uniform sampler2D blood_texture;
uniform vec3 blood_color;
uniform float blood_merge_factor;
uniform vec2 drop_pos1;
uniform float drop_scale1;
uniform vec2 drop_pos2;
uniform float drop_scale2;
uniform vec2 drop_pos3;
uniform float drop_scale3;
uniform vec2 drop_pos4;
uniform float drop_scale4;
uniform vec2 drop_pos5;
uniform float drop_scale5;
uniform highp float time;

const float BLOOD_BLENDING = 0.15;

vec2 scale_from_center(vec2 uv, float s) {
    if(s <= 0.01) return vec2(-10.0, -10.0); // Move offscreen if no scale
    return ((uv - 0.5) * 1.0/s) + 0.5;
}

float sampleBloodDrop(vec2 texture_coords, vec2 drop_pos, float drop_scale) {
    if(drop_scale <= 0.01) return 1.0;
    
    vec2 uv_translated = texture_coords - drop_pos + 0.5;
    vec2 uv_scaled = scale_from_center(uv_translated, drop_scale);
    
    // Only sample if within bounds
    if(uv_scaled.x >= 0.0 && uv_scaled.x <= 1.0 && uv_scaled.y >= 0.0 && uv_scaled.y <= 1.0) {
        return Texel(blood_texture, uv_scaled).r;
    }
    return 1.0;
}

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
    // Sample base texture
    vec4 base_color = Texel(texture, texture_coords);
    
    float blended_pixel = 1.0;
    
    // Sample all blood drops
    blended_pixel *= sampleBloodDrop(texture_coords, drop_pos1, drop_scale1);
    blended_pixel *= sampleBloodDrop(texture_coords, drop_pos2, drop_scale2);
    blended_pixel *= sampleBloodDrop(texture_coords, drop_pos3, drop_scale3);
    blended_pixel *= sampleBloodDrop(texture_coords, drop_pos4, drop_scale4);
    blended_pixel *= sampleBloodDrop(texture_coords, drop_pos5, drop_scale5);
    
    // Apply blood color where drops exist
    if(blended_pixel < blood_merge_factor) {
        vec3 blood_final = mix(blood_color, base_color.rgb, BLOOD_BLENDING);
        
        // Add slight variation based on time for wet blood effect
        float blood_wetness = 1.0 + 0.1 * sin(time * 2.0 + texture_coords.x * 10.0);
        blood_final *= blood_wetness;
        
        return vec4(blood_final, base_color.a);
    }
    
    return base_color;
}