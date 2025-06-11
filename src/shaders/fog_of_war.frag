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

// Generate Star Wars-like star field
float stars(vec2 world_pos) {
    vec2 star_coord = world_pos * 0.0008; // Reduced scale for smaller, denser field
    
    // Multiple layers of stars at different scales for depth
    float star1 = random(floor(star_coord * 80.0));  // Small distant stars
    float star2 = random(floor(star_coord * 40.0));  // Medium stars
    float star3 = random(floor(star_coord * 15.0));  // Larger foreground stars
    
    // Very subtle twinkling - Star Wars stars don't twinkle much
    float twinkle1 = sin(time * 0.8 + star1 * 6.28) * 0.1 + 0.9;
    float twinkle2 = sin(time * 0.5 + star2 * 6.28) * 0.15 + 0.85;
    
    // Create more realistic star distribution with smaller, punchier stars
    float stars = 0.0;
    if (star1 > 0.992) stars += (star1 - 0.992) * 125.0 * twinkle1;  // Tiny bright stars
    if (star2 > 0.988) stars += (star2 - 0.988) * 83.0 * twinkle2;   // Small medium stars
    if (star3 > 0.98) stars += (star3 - 0.98) * 50.0;               // Larger dim stars
    
    return clamp(stars, 0.0, 1.0);
}

// Create subtle distant nebula effects (more Star Wars-like)
vec3 nebula(vec2 world_pos) {
    vec2 nebula_coord = world_pos * 0.0003;  // Larger scale for distant nebulae
    
    float n1 = noise(nebula_coord + time * 0.02);
    float n2 = noise(nebula_coord * 1.5 + time * 0.01);
    float n3 = noise(nebula_coord * 3.0);
    
    float nebula_density = (n1 + n2 * 0.3 + n3 * 0.1) / 1.4;
    
    // More muted colors like Star Wars space backgrounds
    vec3 nebula_color = mix(
        vec3(0.03, 0.02, 0.08),  // Very dark blue-purple
        vec3(0.08, 0.05, 0.15),  // Slightly brighter purple
        nebula_density
    );
    
    return nebula_color * nebula_density * 0.15;  // Much more subtle
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
    
    // Create more gradual fade with multiple transition zones
    float inner_radius = view_radius * 0.6;      // Full visibility zone
    float fade_start = view_radius * 0.8;        // Start gentle fade
    float fog_start = view_radius - fade_distance * 0.3;  // More aggressive fade
    float fog_end = view_radius + fade_distance * 0.5;    // Complete fade to space
    
    // Multi-stage fog calculation for smoother transition
    float fog_factor = 0.0;
    
    if (distance_from_camera < inner_radius) {
        fog_factor = 0.0;  // No fog in inner area
    } else if (distance_from_camera < fade_start) {
        // Very gentle initial fade
        float t = (distance_from_camera - inner_radius) / (fade_start - inner_radius);
        fog_factor = t * t * 0.1;  // Start with 10% max fog
    } else if (distance_from_camera < fog_start) {
        // Gentle transition zone
        float t = (distance_from_camera - fade_start) / (fog_start - fade_start);
        fog_factor = 0.1 + t * t * 0.3;  // 10% to 40% fog
    } else {
        // Final fade to space
        float t = smoothstep(fog_start, fog_end, distance_from_camera);
        fog_factor = 0.4 + t * 0.6;  // 40% to 100% fog
    }
    
    // Apply smoothing for natural curve
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