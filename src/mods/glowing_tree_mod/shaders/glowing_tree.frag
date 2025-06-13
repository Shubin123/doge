// Glowing Tree Mod Shader
// Magical tree effects optimized for the mod system

varying vec4 VaryingTexCoord;
varying vec4 VaryingColor;

uniform sampler2D MainTexture;
uniform float time;
uniform vec3 glow_color;
uniform float glow_intensity;
uniform float health_factor;

// Simple noise function for performance
float noise(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

// Magical sparkle effect
float sparkle(vec2 uv) {
    vec2 sparkle_uv = uv * 6.0 + time * 0.3;
    float n = noise(sparkle_uv);
    float twinkle = sin(n * 8.0 + time * 4.0) * 0.5 + 0.5;
    return pow(twinkle, 6.0) * n;
}

// Energy flow effect
float energyFlow(vec2 uv) {
    float flow = sin(uv.y * 10.0 + time * 2.0) * 0.1;
    float energy = abs(uv.x - 0.5 - flow);
    return 1.0 - smoothstep(0.0, 0.2, energy);
}

// Pulsing aura
float aura(vec2 uv) {
    vec2 center = vec2(0.5, 0.5);
    float dist = distance(uv, center);
    float pulse = sin(time * 3.0 + dist * 6.0) * 0.5 + 0.5;
    float ring = 1.0 - smoothstep(0.0, 0.7, dist);
    return ring * pulse;
}

void main() {
    vec2 uv = VaryingTexCoord.xy;
    
    // Sample base texture
    vec4 tree_color = texture2D(MainTexture, uv);
    
    // Skip if transparent
    if (tree_color.a < 0.1) {
        gl_FragColor = tree_color;
        return;
    }
    
    // Calculate magical effects
    float sparkle_effect = sparkle(uv) * 0.5;
    float energy_lines = energyFlow(uv) * 0.3;
    float aura_effect = aura(uv) * 0.4;
    
    // Combine effects
    float magic_intensity = (sparkle_effect + energy_lines + aura_effect) * glow_intensity * health_factor;
    
    // Apply glow
    vec3 magic_glow = glow_color * magic_intensity;
    
    // Health-based coloring
    vec3 final_color = tree_color.rgb;
    final_color += magic_glow;
    
    // Dying effect
    if (health_factor < 0.5) {
        float dying_factor = 1.0 - health_factor * 2.0;
        final_color = mix(final_color, vec3(0.6, 0.3, 0.1), dying_factor * 0.3);
    }
    
    // Global pulse
    float pulse = (sin(time * 2.0) * 0.1 + 0.9) * health_factor;
    final_color *= pulse;
    
    gl_FragColor = vec4(final_color, tree_color.a * VaryingColor.a);
}