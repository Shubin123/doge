uniform float time;
uniform vec2 death_position;
uniform float death_progress; // 0.0 to 1.0
uniform vec3 death_color;
uniform float explosion_radius;
uniform vec2 screen_size;
uniform vec2 camera_position;
uniform float camera_zoom;

// Ray marching parameters
#define MAX_STEPS 24
#define MIN_DISTANCE 0.001
#define MAX_DISTANCE 1.5

// Noise function for procedural destruction
float hash(float n) {
    return fract(sin(n) * 43758.5453);
}

float noise3d(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    float n = i.x + i.y * 57.0 + 113.0 * i.z;
    return mix(mix(mix(hash(n + 0.0), hash(n + 1.0), f.x),
                   mix(hash(n + 57.0), hash(n + 58.0), f.x), f.y),
               mix(mix(hash(n + 113.0), hash(n + 114.0), f.x),
                   mix(hash(n + 170.0), hash(n + 171.0), f.x), f.y), f.z);
}

// Fractal noise for complex patterns
float fbm(vec3 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; i++) {
        value += amplitude * noise3d(p);
        p *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

// Distance function for explosion geometry
float map(vec3 pos, float progress) {
    // Central explosion sphere
    float core = length(pos) - 0.2 * progress;
    
    // Expanding energy shockwave
    float shockwave = abs(length(pos) - progress * 0.8) - 0.05;
    
    // Fractal displacement for organic destruction
    float displacement = fbm(pos * 4.0 + time * 2.0) * 0.1 * progress;
    
    // Combine geometries
    float result = min(core, shockwave);
    return result + displacement;
}

// Ray marching with explosion effect
float rayMarch(vec3 ro, vec3 rd, float progress) {
    float depth = 0.0;
    
    for (int i = 0; i < MAX_STEPS; i++) {
        vec3 pos = ro + rd * depth;
        float dist = map(pos, progress);
        
        if (dist < MIN_DISTANCE) {
            return depth;
        }
        
        depth += dist * 0.7;
        
        if (depth > MAX_DISTANCE) {
            break;
        }
    }
    
    return -1.0;
}

// Calculate normal for lighting
vec3 calcNormal(vec3 pos, float progress) {
    vec2 e = vec2(0.001, 0.0);
    return normalize(vec3(
        map(pos + e.xyy, progress) - map(pos - e.xyy, progress),
        map(pos + e.yxy, progress) - map(pos - e.yxy, progress),
        map(pos + e.yyx, progress) - map(pos - e.yyx, progress)
    ));
}

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
    // Convert to world coordinates
    vec2 world_pos = (screen_coords - screen_size * 0.5) / camera_zoom + camera_position;
    
    // Distance from explosion center
    float dist_to_explosion = length(world_pos - death_position);
    
    // Early exit if too far
    if (dist_to_explosion > explosion_radius * 2.0) {
        return texture2D(texture, texture_coords);
    }
    
    // Get original color
    vec4 original = texture2D(texture, texture_coords);
    
    // Setup ray marching coordinates
    vec2 uv = (screen_coords - screen_size * 0.5) / min(screen_size.x, screen_size.y);
    uv *= 2.0; // Zoom in for more detail
    
    vec3 ro = vec3(0.0, 0.0, 1.5);
    vec3 rd = normalize(vec3(uv, -1.0));
    
    // Ray march the explosion
    float depth = rayMarch(ro, rd, death_progress);
    
    if (depth > 0.0 && death_progress > 0.01) {
        vec3 pos = ro + rd * depth;
        vec3 normal = calcNormal(pos, death_progress);
        
        // Dynamic lighting based on explosion progress
        float intensity = 1.0 - death_progress * 0.5;
        
        // Energy patterns
        float energy = fbm(pos * 8.0 + time * 4.0) * intensity;
        
        // Color temperature shift during explosion
        vec3 hot_color = vec3(1.0, 0.8, 0.4); // Orange-white hot
        vec3 cool_color = vec3(0.8, 0.4, 1.0); // Purple cool
        vec3 explosion_color = mix(hot_color, cool_color, death_progress);
        
        // Combine with death_color
        explosion_color = mix(explosion_color, death_color, 0.5);
        
        // Final explosion intensity
        float explosion_intensity = energy * intensity * 2.0;
        
        // Screen space distortion effect
        vec2 distortion = normal.xy * death_progress * 0.1;
        vec4 distorted = texture2D(texture, texture_coords + distortion);
        
        // Blend explosion with distorted background
        vec3 final_color = mix(distorted.rgb, explosion_color, explosion_intensity);
        
        return vec4(final_color, original.a);
    } else {
        // Outer shockwave effect
        float shockwave_dist = abs(dist_to_explosion - death_progress * explosion_radius);
        float shockwave = exp(-shockwave_dist * 10.0) * death_progress;
        
        // Screen shake effect through UV distortion
        vec2 shake = vec2(
            sin(time * 50.0 + dist_to_explosion) * shockwave * 0.02,
            cos(time * 37.0 + dist_to_explosion) * shockwave * 0.02
        );
        
        vec4 shaken = texture2D(texture, texture_coords + shake);
        
        // Add energy flash
        float flash = shockwave * 0.5;
        vec3 flash_color = death_color * flash;
        
        return vec4(shaken.rgb + flash_color, original.a);
    }
}