uniform vec2 direction;
uniform float blurSize;

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec2 onePixel = vec2(1.0) / vec2(love_ScreenSize.x, love_ScreenSize.y);
    vec4 result = vec4(0.0);
    float total = 0.0;
    
    // 9-tap Gaussian blur
    float weights[5] = float[](0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);
    
    result += Texel(tex, tc) * weights[0];
    total += weights[0];
    
    for (int i = 1; i < 5; i++) {
        vec2 offset = onePixel * direction * float(i) * blurSize;
        result += Texel(tex, tc + offset) * weights[i];
        result += Texel(tex, tc - offset) * weights[i];
        total += weights[i] * 2.0;
    }
    
    return result / total;
}