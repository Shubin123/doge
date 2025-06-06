uniform float time;
uniform vec2 enemy_position;
uniform vec3 aura_color;
uniform float aura_intensity;
uniform float aura_radius;
uniform vec2 screen_size;
uniform vec2 camera_position;
uniform float camera_zoom;

// Ray marching parameters
#define MAX_STEPS 32
#define MIN_DISTANCE 0.001
#define MAX_DISTANCE 2.0

// Smooth minimum function for blending shapes
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Distance function for a sphere
float sdSphere(vec3 p, float r) {
    return length(p) - r;
}

// Distance function for a torus
float sdTorus(vec3 p, vec2 t) {
    vec2 q = vec2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

// Noise function for organic movement
float noise(vec3 p) {
    return sin(p.x) * sin(p.y) * sin(p.z) * 0.5 + 0.5;
}

// Main distance function for enemy aura
float map(vec3 pos) {
    // Animated time for dynamic effects
    float t = time * 2.0;
    
    // Core sphere with pulsing
    float core = sdSphere(pos, 0.3 + sin(t * 1.5) * 0.1);
    
    // Rotating energy rings
    vec3 ring_pos = pos;
    ring_pos.xz = mat2(cos(t), -sin(t), sin(t), cos(t)) * ring_pos.xz;
    float ring1 = sdTorus(ring_pos, vec2(0.5, 0.05));
    
    ring_pos.xy = mat2(cos(t * 0.7), -sin(t * 0.7), sin(t * 0.7), cos(t * 0.7)) * ring_pos.xy;
    float ring2 = sdTorus(ring_pos, vec2(0.4, 0.03));
    
    // Combine with smooth minimum for organic blending
    float combined = smin(core, ring1, 0.2);
    combined = smin(combined, ring2, 0.15);
    
    // Add noise for organic distortion
    float n = noise(pos * 3.0 + t) * 0.1;
    
    return combined + n;
}

// Ray marching function
float rayMarch(vec3 ro, vec3 rd) {
    float depth = 0.0;
    
    for (int i = 0; i < MAX_STEPS; i++) {
        vec3 pos = ro + rd * depth;
        float dist = map(pos);
        
        if (dist < MIN_DISTANCE) {
            return depth;
        }
        
        depth += dist * 0.8; // Slightly conservative step
        
        if (depth > MAX_DISTANCE) {
            break;
        }
    }
    
    return -1.0; // Miss
}

// Calculate normal using finite differences
vec3 calcNormal(vec3 pos) {
    vec2 e = vec2(0.001, 0.0);
    return normalize(vec3(
        map(pos + e.xyy) - map(pos - e.xyy),
        map(pos + e.yxy) - map(pos - e.yxy),
        map(pos + e.yyx) - map(pos - e.yyx)
    ));
}

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
    // Convert screen coordinates to world coordinates
    vec2 world_pos = (screen_coords - screen_size * 0.5) / camera_zoom + camera_position;
    
    // Calculate distance from enemy
    float dist_to_enemy = length(world_pos - enemy_position);
    
    // Early exit if too far from enemy
    if (dist_to_enemy > aura_radius * 2.0) {
        return texture2D(texture, texture_coords);
    }
    
    // Setup ray marching
    vec2 uv = (screen_coords - screen_size * 0.5) / min(screen_size.x, screen_size.y);
    
    // Camera setup for 3D effect
    vec3 ro = vec3(0.0, 0.0, 2.0); // Ray origin
    vec3 rd = normalize(vec3(uv, -1.0)); // Ray direction
    
    // Ray march the scene
    float depth = rayMarch(ro, rd);
    
    // Get original texture color
    vec4 original = texture2D(texture, texture_coords);
    
    if (depth > 0.0) {
        // Hit the aura geometry
        vec3 pos = ro + rd * depth;
        vec3 normal = calcNormal(pos);
        
        // Lighting calculation
        vec3 light_dir = normalize(vec3(0.5, 1.0, 0.8));
        float ndotl = max(0.0, dot(normal, light_dir));
        
        // Fresnel effect for energy-like appearance
        float fresnel = pow(1.0 - abs(dot(normal, rd)), 2.0);
        
        // Animated glow intensity
        float glow = sin(time * 3.0 + pos.x * 5.0) * 0.3 + 0.7;
        
        // Calculate final aura color
        vec3 aura = aura_color * (ndotl * 0.5 + 0.5) * fresnel * glow * aura_intensity;
        
        // Blend with original
        return vec4(mix(original.rgb, aura, 0.8), original.a);
    } else {
        // Add subtle outer glow
        float outer_glow = 1.0 - smoothstep(0.0, aura_radius, dist_to_enemy);
        outer_glow = pow(outer_glow, 3.0) * aura_intensity * 0.3;
        
        vec3 glow_color = aura_color * outer_glow;
        return vec4(original.rgb + glow_color, original.a);
    }
}