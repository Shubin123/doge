/* Shockwave distortion effect for explosions - Debugged version */
extern vec2 center; // Center of the shockwave (in screen coordinates) - ignored for testing
extern float radius; // Current radius of the shockwave - ignored for testing
extern float maxRadius; // Maximum radius the shockwave will reach - ignored for testing
extern float time; // Time since the explosion started

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
    // Use the approach that worked - modify the working sine wave version
    vec2 uv = screen_coords / vec2(love_ScreenSize.x, love_ScreenSize.y);
    
    // Shockwave center
    vec2 shockCenter = vec2(0.5, 0.5);
    float dist = distance(uv, shockCenter);
    
    // Animated shockwave radius
    float shockRadius = mod(time * 0.3, 1.0);
    
    // Create a simple radial distortion like the sine wave
    vec2 direction = normalize(uv - shockCenter);
    float distortionAmount = 10.0;
    
    // Only distort near the shockwave radius
    if (abs(dist - shockRadius) < 0.1) {
        distortionAmount = 5 * (1.0 - abs(dist - shockRadius) / 0.1);
    }
    
    // Apply distortion to texture_coords (same way as the sine wave)
    vec2 distortedCoords = texture_coords + direction * distortionAmount;
    
    // Sample with distorted coordinates
    vec4 distortedColor = Texel(texture, distortedCoords);
    
    // Add highlight at shockwave
    if (abs(dist - shockRadius) < 0.02) {
        distortedColor = mix(distortedColor, vec4(1.0, 0.8, 0.6, 1.0), 0.5);
    }
    
    return distortedColor;
}