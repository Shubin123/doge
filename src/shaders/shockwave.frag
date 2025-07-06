/* Shockwave distortion effect for explosions */
extern vec2 center; // Center of the shockwave (in screen coordinates)
extern float radius; // Current radius of the shockwave
extern float maxRadius; // Maximum radius the shockwave will reach
extern float time; // Time since the explosion started

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
{
    // Calculate distance from the center of the shockwave
    float dist = distance(screen_coords, center);
    
    // Only apply distortion within the current shockwave radius
    if (dist < radius)
    {
        // Calculate a ripple effect that cascades outward
        float ripple = sin(dist * 10.0 - time * 5.0) * 0.05;
        float distortion = (radius - dist) / radius * 0.1 + ripple;
        
        // Offset the texture coordinates to create a distortion effect
        vec2 offset = normalize(screen_coords - center) * distortion;
        vec2 distorted_coords = texture_coords + offset;
        
        // Sample the texture at the distorted coordinates
        return Texel(texture, distorted_coords) * color;
    }
    
    // Outside the shockwave radius, return the original texture
    return Texel(texture, texture_coords) * color;
}
