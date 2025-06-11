uniform float threshold;

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec4 pixel = Texel(tex, tc);
    float brightness = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
    
    if (brightness > threshold) {
        return vec4(pixel.rgb * (brightness - threshold), pixel.a);
    }
    return vec4(0.0, 0.0, 0.0, 0.0);
}