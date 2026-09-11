// Hot, animated muzzle-flash colour pass. The cone geometry is produced in
// Lua; this shader gives every layer a saturated neon core for additive blend.
#ifdef PIXEL
extern vec3 flash_color;
extern number intensity;
extern number pulse;

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
    number shimmer = 0.90 + 0.10 * sin(pulse * 2.0 + screen_coords.y * 0.12);
    vec3 core = mix(flash_color, vec3(1.0, 0.95, 0.76), 0.58);
    return vec4(core * color.rgb * (1.4 + intensity * 1.8) * shimmer, color.a * intensity);
}
#endif
