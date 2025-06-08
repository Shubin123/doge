#ifdef GL_ES
precision mediump float;
#endif

// Pixelation shader
// Quantizes screen coordinates to a coarse grid based on pixel_size
uniform float pixel_size;
uniform vec2 screen_size;

vec4 effect(vec4 color, sampler2D tex, vec2 uv, vec2 screen_pos) {
    // Compute the center of the block this fragment belongs to
    vec2 block_center = floor(screen_pos / pixel_size) * pixel_size + 0.5 * pixel_size;
    // Normalize back to texture UVs
    vec2 quant_uv = block_center / screen_size;
    // Sample the texture at the quantized UV
    vec4 sampled = Texel(tex, quant_uv);
    // Apply vertex color
    return sampled * color;
}