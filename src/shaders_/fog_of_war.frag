uniform vec2 camera_position;
uniform float camera_zoom;
uniform float view_radius;
uniform float fade_distance;
uniform vec3 space_color;
uniform float space_intensity;
uniform vec2 screen_size;
uniform float time;

// Simple noise function for stars
float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

// Smooth noise for space effects
float noise(vec2 st) {
    vec2 i = floor(st);
    vec2 f = fract(st);
    
    float a = random(i);
    float b = random(i + vec2(1.0, 0.0));
    float c = random(i + vec2(0.0, 1.0));
    float d = random(i + vec2(1.0, 1.0));
    
    vec2 u = f * f * (3.0 - 2.0 * f);
    
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// Generate star field
float stars(vec2 world_pos) {
    vec2 star_coord = world_pos * 0.001; // Scale for star density
    
    // Multiple layers of stars at different scales
    float star1 = random(floor(star_coord * 50.0));
    float star2 = random(floor(star_coord * 25.0));
    float star3 = random(floor(star_coord * 10.0));
    
    // Create twinkling effect
    float twinkle = sin(time * 2.0 + star1 * 10.0) * 0.5 + 0.5;
    
    // Combine stars with different intensities
    float stars = 0.0;
    if (star1 > 0.98) stars += (star1 - 0.98) * 50.0 * twinkle;
    if (star2 > 0.95) stars += (star2 - 0.95) * 20.0;
    if (star3 > 0.92) stars += (star3 - 0.92) * 10.0;
    
    return clamp(stars, 0.0, 1.0);
}

// Create nebula-like effects
vec3 nebula(vec2 world_pos) {
    vec2 nebula_coord = world_pos * 0.0005;
    
    float n1 = noise(nebula_coord + time * 0.1);
    float n2 = noise(nebula_coord * 2.0 + time * 0.05);
    float n3 = noise(nebula_coord * 4.0 + time * 0.02);
    
    float nebula_density = (n1 + n2 * 0.5 + n3 * 0.25) / 1.75;
    
    // Color the nebula with purples and blues
    vec3 nebula_color = mix(
        vec3(0.1, 0.05, 0.2),  // Dark purple
        vec3(0.2, 0.1, 0.4),   // Brighter purple
        nebula_density
    );
    
    return nebula_color * nebula_density * 0.3;
}

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec4 pixel = Texel(tex, tc) * color;
    
    // Convert screen coordinates to world coordinates
    // tc ranges from 0-1, so convert to screen pixels first
    vec2 screen_coord = tc * screen_size;
    // camera_position now represents center of view, so offset by screen center
    vec2 world_pos = camera_position + (screen_coord - screen_size * 0.5) / camera_zoom;
    
    // Calculate distance from camera center
    float distance_from_camera = length(world_pos - camera_position);
    
    // Calculate fog factor with smoother, higher resolution transitions
    float fog_start = view_radius - fade_distance;
    float fog_end = view_radius + fade_distance * 0.3;  // Extend slightly beyond for smoother edge
    
    // Use more sophisticated blending for smoother curves
    float fog_factor = smoothstep(fog_start, fog_end, distance_from_camera);
    
    // Apply additional smoothing using a cubic curve for even rounder appearance
    fog_factor = fog_factor * fog_factor * (3.0 - 2.0 * fog_factor);
    
    // Create space background
    vec3 star_field = vec3(stars(world_pos));
    vec3 nebula_field = nebula(world_pos);
    vec3 space_background = space_color * space_intensity + star_field + nebula_field;
    
    // Blend the original pixel with space background based on fog factor
    vec3 final_color = mix(pixel.rgb, space_background, fog_factor);
    float final_alpha = mix(pixel.a, 1.0, fog_factor);
    
    return vec4(final_color, final_alpha);
}