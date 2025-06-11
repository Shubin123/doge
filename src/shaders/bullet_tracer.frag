uniform float time;
uniform vec2 bullet_start;
uniform vec2 bullet_end;
uniform float trail_length;
uniform float bullet_speed;
uniform vec3 tracer_color;
uniform float intensity;

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
    vec2 uv = texture_coords;
    
    // Calculate the ray from start to end
    vec2 ray_dir = normalize(bullet_end - bullet_start);
    vec2 ray_perp = vec2(-ray_dir.y, ray_dir.x);
    
    // Current position along the bullet path
    vec2 current_pos = bullet_start + ray_dir * (time * bullet_speed);
    
    // Distance from current fragment to the bullet trail line
    vec2 to_fragment = screen_coords - current_pos;
    float dist_along_ray = dot(to_fragment, ray_dir);
    float dist_perp_ray = abs(dot(to_fragment, ray_perp));
    
    // Create the tracer trail effect
    float trail_fade = 1.0 - clamp(abs(dist_along_ray) / trail_length, 0.0, 1.0);
    float width_fade = 1.0 - clamp(dist_perp_ray / 3.0, 0.0, 1.0);
    
    // Combine fades for the final tracer effect
    float tracer_alpha = trail_fade * width_fade * intensity;
    
    // Add some glow effect
    float glow = exp(-dist_perp_ray * 0.5) * trail_fade * 0.3;
    tracer_alpha += glow;
    
    vec4 tracer = vec4(tracer_color, tracer_alpha);
    
    return mix(color, tracer, tracer_alpha);
}