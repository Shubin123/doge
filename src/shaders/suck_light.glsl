// A dead enemy's light being pulled into the player (systems/suckLight.lua).
// Instanced like the bullet tracers: one quad per mote, stretched from the
// oldest trail sample (tail) to the mote (head); the pixel stage draws a
// bright orb at the head trailing a twisting ribbon of light. A flare at the
// player is the same instance with no length (tail == head).

varying LOVE_HIGHP_OR_MEDIUMP vec2 vLocal;   // (along the spine from the tail, across it), world px
varying LOVE_HIGHP_OR_MEDIUMP float vLen;    // spine length, world px
varying LOVE_HIGHP_OR_MEDIUMP vec4 vColor;   // rgb, intensity
varying LOVE_HIGHP_OR_MEDIUMP vec2 vParams;  // glow radius (world px), phase

#ifdef VERTEX
attribute vec4 InstSeg;    // tail.xy, head.xy (world)
attribute vec4 InstColor;
attribute vec2 InstParams;

vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vec2 tail = InstSeg.xy;
    vec2 seg = InstSeg.zw - tail;
    float len = length(seg);
    vec2 dir = len > 0.001 ? seg / len : vec2(1.0, 0.0);
    vec2 nrm = vec2(-dir.y, dir.x);
    float r = InstParams.x;

    float along = mix(-r, len + r, vertex_position.x);
    float across = vertex_position.y * r;

    vLocal = vec2(along, across);
    vLen = len;
    vColor = InstColor;
    vParams = InstParams;
    return transform_projection * vec4(tail + dir * along + nrm * across, 0.0, 1.0);
}
#endif

#ifdef PIXEL
uniform float time;
uniform float brightness; // var.tracer_brightness

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    float r = vParams.x;
    float along = clamp(vLocal.x, 0.0, vLen);
    float t = vLen > 0.001 ? along / vLen : 1.0;           // 0 at the tail .. 1 at the mote

    // The trail writhes like a ribbon being pulled taut: a travelling wave
    // across the spine, calm at the mote, widest at the far end.
    float wave = sin(vLocal.x * 0.3 - time * 18.0 + vParams.y) * r * 0.25 * (1.0 - t);
    float d = length(vec2(vLocal.x - along, vLocal.y - wave));
    float taper = t * sqrt(t);

    float rr = r * r;
    float ribbon = exp(-d * d / (rr * 0.022));
    float glow = exp(-d / (r * 0.3)) * max(0.0, 1.0 - d / r);
    vec2 toHead = vLocal - vec2(vLen, 0.0);
    float orb = exp(-dot(toHead, toHead) / (rr * 0.06));
    float pulse = 0.8 + 0.2 * sin(time * 22.0 + vParams.y);

    vec3 hot = mix(vColor.rgb, vec3(1.0), 0.6);
    vec3 light = hot * (ribbon * taper + orb) * 1.2
               + vColor.rgb * glow * (0.2 + 0.8 * taper);
    float k = vColor.a * pulse * brightness;
    // Alpha marks the orb and ribbon as solid, so the GI pass treats them as
    // light sources.
    return vec4(light * k, clamp((ribbon * taper + orb) * vColor.a * brightness, 0.0, 1.0));
}
#endif
