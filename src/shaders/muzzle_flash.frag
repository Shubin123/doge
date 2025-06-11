uniform vec2 flash_pos;      // Position of the muzzle flash in screen coordinates
uniform vec2 flash_dir;      // Direction the gun is pointing (normalized)
uniform float flash_intensity; // Intensity/brightness of the flash (0-1)
uniform float cone_angle;    // Half angle of the cone in radians (e.g., 0.5 for ~30 degrees)
uniform float cone_length;   // Maximum length of the light cone
uniform vec3 flash_color;    // Color of the muzzle flash
uniform float time;          // Time since flash started for animation

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
    // Get the original pixel color
    vec4 pixel = Texel(texture, texture_coords);
    
    // Calculate vector from flash position to current pixel
    vec2 to_pixel = screen_coords - flash_pos;
    float distance = length(to_pixel);
    
    // Early exit if pixel is too far from flash
    if (distance > cone_length) {
        return pixel;
    }
    
    // Normalize the vector to pixel
    vec2 to_pixel_norm = normalize(to_pixel);
    
    // Calculate the angle between flash direction and pixel direction
    float dot_product = dot(flash_dir, to_pixel_norm);
    float angle = acos(clamp(dot_product, -1.0, 1.0));
    
    // Check if pixel is within the cone
    if (angle > cone_angle) {
        return pixel;
    }
    
    // Calculate cone falloff based on angle
    float angle_falloff = 1.0 - (angle / cone_angle);
    angle_falloff = pow(angle_falloff, 2.0); // Sharper falloff at edges
    
    // Calculate distance falloff
    float distance_falloff = 1.0 - (distance / cone_length);
    distance_falloff = pow(distance_falloff, 1.5); // Non-linear falloff
    
    // Add some noise for more realistic effect
    float noise = sin(distance * 0.1 + time * 50.0) * 0.1 + 0.9;
    
    // Calculate the intensity at this pixel
    float pixel_intensity = flash_intensity * angle_falloff * distance_falloff * noise;
    
    // Add some inner core brightness
    float core_distance = 20.0;
    if (distance < core_distance) {
        float core_intensity = 1.0 - (distance / core_distance);
        core_intensity = pow(core_intensity, 3.0);
        pixel_intensity += core_intensity * flash_intensity * 0.5;
    }
    
    // Apply the flash color with additive blending
    vec3 flash_contribution = flash_color * pixel_intensity;
    
    // Mix the flash with the original pixel using additive blending
    vec3 final_color = pixel.rgb + flash_contribution;
    
    // Add slight bloom effect for very bright areas
    float brightness = dot(final_color, vec3(0.299, 0.587, 0.114));
    if (brightness > 0.8) {
        float bloom_intensity = (brightness - 0.8) * 2.0;
        final_color += vec3(bloom_intensity * 0.3);
    }
    
    return vec4(final_color, pixel.a);
}