// Additive neon treatment for the geometry drawn by bullet.drawSingleTracer.
// Keeping it pixel-stage only avoids WebGL's cross-stage precision mismatch.
#ifdef PIXEL
extern vec3 tracer_color;
extern number intensity;
extern number pulse;

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
    number flicker = 0.82 + 0.18 * sin(pulse + screen_coords.x * 0.075);
    vec3 hot_core = mix(tracer_color, vec3(1.0), 0.46);
    vec3 neon = hot_core * (1.25 + intensity * 1.75) * flicker;
    return vec4(neon * color.rgb, color.a * intensity);
}
#endif
