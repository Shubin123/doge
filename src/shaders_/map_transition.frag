#ifdef GL_ES
precision mediump float;
#endif

extern float fade_amount;
extern bool blur;
uniform sampler2D Tex0;

varying vec2 VaryingTexCoord;

void main()
{
    vec4 color;
    
    if (blur) {
        // Simple blur by sampling neighboring pixels
        vec2 texelSize = 1.0 / textureSize(Tex0, 0);
        
        color = texture2D(Tex0, VaryingTexCoord) * 0.25;
        color += texture2D(Tex0, VaryingTexCoord + vec2(texelSize.x, 0.0)) * 0.125;
        color += texture2D(Tex0, VaryingTexCoord - vec2(texelSize.x, 0.0)) * 0.125;
        color += texture2D(Tex0, VaryingTexCoord + vec2(0.0, texelSize.y)) * 0.125;
        color += texture2D(Tex0, VaryingTexCoord - vec2(0.0, texelSize.y)) * 0.125;
        color += texture2D(Tex0, VaryingTexCoord + vec2(texelSize.x, texelSize.y)) * 0.0625;
        color += texture2D(Tex0, VaryingTexCoord - vec2(texelSize.x, texelSize.y)) * 0.0625;
        color += texture2D(Tex0, VaryingTexCoord + vec2(-texelSize.x, texelSize.y)) * 0.0625;
        color += texture2D(Tex0, VaryingTexCoord + vec2(texelSize.x, -texelSize.y)) * 0.0625;
    } else {
        color = texture2D(Tex0, VaryingTexCoord);
    }
    
    // Interpolate toward black based on fade_amount
    color.rgb = mix(color.rgb, vec3(0.0), fade_amount);
    
    gl_FragColor = color;
}