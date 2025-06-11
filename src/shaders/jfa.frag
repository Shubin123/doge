uniform float stepSize;

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec2 offset = stepSize / vec2(love_ScreenSize.x, love_ScreenSize.y);
    vec2 bestPoint = vec2(-2.0);
    float bestDist = 1e9;
    
    // Enhanced 3x3 sampling with slight jitter for smoother results
    for(float y = -1.0; y <= 1.0; y += 1.0) {
        for(float x = -1.0; x <= 1.0; x += 1.0) {
            vec2 sampleTC = tc + vec2(x, y) * offset;
            if(sampleTC.x < 0.0 || sampleTC.x > 1.0 ||
               sampleTC.y < 0.0 || sampleTC.y > 1.0) continue;
            
            vec2 data = Texel(tex, sampleTC).xy;
            if(data.x > 0.0 || data.y > 0.0) {
                float dist = length(tc - data);
                if(dist < bestDist) {
                    bestDist = dist;
                    bestPoint = data;
                }
            }
        }
    }
    return vec4(bestPoint, 0.0, 1.0);
}