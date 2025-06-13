// Glowing Tree Fragment Shader
// Advanced magical tree effects with glow, wind sway, and pulsing energy

varying vec4 VaryingTexCoord;
varying vec4 VaryingColor;

uniform sampler2D MainTexture;
uniform float time;
uniform vec3 glow_color;
uniform float glow_intensity;
uniform float wind_strength;
uniform float sway_amplitude;
uniform float pulse_speed;
uniform float health_factor;

// Noise functions for magical effects
float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

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

// Fractal noise for more complex patterns
float fbm(vec2 st) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    
    for (int i = 0; i < 4; i++) {
        value += amplitude * noise(st * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    
    return value;
}

// Create magical sparkle effect
float sparkle(vec2 uv, float time_offset) {
    vec2 sparkle_uv = uv * 8.0 + time_offset;
    float sparkle_noise = fbm(sparkle_uv + time * 0.5);
    
    // Create twinkling stars effect
    float twinkle = sin(sparkle_noise * 10.0 + time * 3.0) * 0.5 + 0.5;
    twinkle = pow(twinkle, 8.0); // Make sparkles more distinct
    
    return twinkle * sparkle_noise;
}

// Create energy flow lines
float energyFlow(vec2 uv) {
    vec2 flow_uv = uv;
    
    // Vertical energy streams
    float stream1 = sin((flow_uv.x + time * 0.3) * 15.0) * 0.1;
    float stream2 = sin((flow_uv.x + time * -0.2) * 20.0) * 0.05;
    
    // Horizontal waves for magical energy
    float wave = sin(flow_uv.y * 8.0 + time * 2.0) * 0.1;
    
    // Combine streams
    float energy = abs(flow_uv.y - 0.5 - stream1 - stream2 - wave);
    energy = 1.0 - smoothstep(0.0, 0.1, energy);
    
    return energy;
}

// Create pulsing aura effect
float aura(vec2 uv, vec2 center) {
    float dist = distance(uv, center);
    
    // Pulsing rings
    float pulse = sin(time * pulse_speed + dist * 8.0) * 0.5 + 0.5;
    float ring = 1.0 - smoothstep(0.0, 0.6, dist);
    
    // Add some variation with noise
    float aura_noise = fbm(uv * 4.0 + time * 0.3);
    ring *= (0.8 + aura_noise * 0.4);
    
    return ring * pulse;
}

// Wind displacement effect
vec2 windEffect(vec2 uv) {
    // Create wind patterns
    float wind_wave1 = sin(time * 1.5 + uv.y * 5.0) * sway_amplitude * wind_strength;
    float wind_wave2 = sin(time * 2.3 + uv.y * 3.0) * sway_amplitude * wind_strength * 0.5;
    
    // Add some turbulence
    float turbulence = fbm(uv * 2.0 + time * 0.8) * 0.02 * wind_strength;
    
    vec2 wind_offset = vec2(wind_wave1 + wind_wave2 + turbulence, 0.0);
    
    // Make wind effect stronger at the top (leaves)
    float height_factor = smoothstep(0.2, 0.8, 1.0 - uv.y);
    wind_offset *= height_factor;
    
    return wind_offset;
}

void main() {
    vec2 uv = VaryingTexCoord.xy;
    
    // Apply wind displacement
    vec2 wind_displaced_uv = uv + windEffect(uv);
    
    // Sample the base tree texture with wind displacement
    vec4 tree_color = texture2D(MainTexture, wind_displaced_uv);
    
    // Skip processing if pixel is transparent
    if (tree_color.a < 0.1) {
        gl_FragColor = tree_color;
        return;
    }
    
    // Calculate magical effects
    float sparkle_effect = sparkle(uv, time * 0.7);
    float energy_lines = energyFlow(uv);
    float aura_effect = aura(uv, vec2(0.5, 0.5));
    
    // Health-based intensity modification
    float health_mod = mix(0.3, 1.0, health_factor);
    
    // Combine magical effects
    float magic_intensity = (sparkle_effect * 0.4 + energy_lines * 0.3 + aura_effect * 0.3) * glow_intensity * health_mod;
    
    // Create magical glow color
    vec3 magic_glow = glow_color * magic_intensity;
    
    // Pulsing effect for the entire tree
    float global_pulse = (sin(time * pulse_speed) * 0.1 + 0.9) * health_factor;
    
    // Edge glow effect
    vec2 edge_uv = abs(uv - 0.5) * 2.0;
    float edge_dist = max(edge_uv.x, edge_uv.y);
    float edge_glow = (1.0 - smoothstep(0.7, 1.0, edge_dist)) * glow_intensity * 0.3;
    
    // Combine all effects
    vec3 final_color = tree_color.rgb;
    
    // Add magical glow
    final_color += magic_glow;
    
    // Add edge glow
    final_color += glow_color * edge_glow;
    
    // Apply global pulse
    final_color *= global_pulse;
    
    // Add some color variation based on health
    if (health_factor < 0.5) {
        // Dying tree - add red/brown tint
        float dying_factor = 1.0 - health_factor * 2.0;
        final_color = mix(final_color, vec3(0.8, 0.4, 0.2), dying_factor * 0.3);
    }
    
    // Energy particle overlay
    float particle_effect = sparkle(uv * 3.0, time * 1.2) * glow_intensity * 0.2;
    final_color += glow_color * particle_effect;
    
    // Atmospheric effects (heat shimmer for magical energy)
    vec2 shimmer_uv = uv + vec2(
        sin(time * 4.0 + uv.y * 10.0) * 0.005,
        cos(time * 3.0 + uv.x * 8.0) * 0.005
    ) * glow_intensity;
    
    // Final color output
    gl_FragColor = vec4(final_color, tree_color.a * VaryingColor.a);
}