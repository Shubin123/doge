// Instanced neon bullet tracers (bullet.draw). One quad per bullet, stretched
// by the vertex stage from the oldest trail sample (tail) to the bullet (head);
// the pixel stage shades it from the distance to that tail->head spine.
// Drawn additively, both into the bulletNeon glow chain and on top of it.

varying LOVE_HIGHP_OR_MEDIUMP vec2 vLocal;  // (along the spine from the tail, across it), world px
varying LOVE_HIGHP_OR_MEDIUMP float vLen;   // spine length, world px
varying LOVE_HIGHP_OR_MEDIUMP vec4 vCore;   // core colour, intensity
varying LOVE_HIGHP_OR_MEDIUMP vec4 vHalo;   // halo colour, halo radius (world px)
varying LOVE_HIGHP_OR_MEDIUMP float vPhase;

#ifdef VERTEX
attribute vec4 InstSeg;   // tail.xy, head.xy (world)
attribute vec4 InstCore;
attribute vec4 InstHalo;
attribute float InstPhase;

// vertex_position.x is 0 at the tail end of the quad and 1 at the head end,
// vertex_position.y is -1/+1 across it.
vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vec2 tail = InstSeg.xy;
    vec2 seg = InstSeg.zw - tail;
    float len = length(seg);
    vec2 dir = len > 0.001 ? seg / len : vec2(1.0, 0.0);
    vec2 nrm = vec2(-dir.y, dir.x);
    float r = InstHalo.w;

    float along = mix(-r, len + r, vertex_position.x);
    float across = vertex_position.y * r;

    vLocal = vec2(along, across);
    vLen = len;
    vCore = InstCore;
    vHalo = InstHalo;
    vPhase = InstPhase;
    return transform_projection * vec4(tail + dir * along + nrm * across, 0.0, 1.0);
}
#endif

#ifdef PIXEL
uniform float time;
uniform float brightness; // var.tracer_brightness

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    float r = vHalo.w;
    float along = clamp(vLocal.x, 0.0, vLen);
    float d = length(vec2(vLocal.x - along, vLocal.y));   // distance to the spine
    float t = vLen > 0.001 ? along / vLen : 1.0;          // 0 at the tail .. 1 at the head
    float taper = t * t;                                   // the trail fades toward the tail...
    float thin = mix(0.3, 1.0, t);                         // ...and narrows
    float flicker = 0.86 + 0.14 * sin(time * 47.0 + vPhase + t * 9.0);

    float rr = r * r;
    float thread = exp(-d * d / (rr * 0.004 * thin));      // white-hot line
    float body = exp(-d * d / (rr * 0.025 * thin));        // saturated core colour
    float halo = exp(-d / (r * 0.18)) * max(0.0, 1.0 - d / r);  // reaches 0 at the quad edge
    vec2 toHead = vLocal - vec2(vLen, 0.0);
    float flare = exp(-dot(toHead, toHead) / (rr * 0.02)); // bright tip

    // Two-tone: the core colour at the head shades into the halo colour down the trail.
    vec3 tint = mix(vHalo.rgb, vCore.rgb, t);
    vec3 hot = mix(vCore.rgb, vec3(1.0), 0.45);
    vec3 neon = hot * (thread * taper + flare) * 1.1
              + tint * body * taper * 1.05
              + vHalo.rgb * halo * (0.25 + 0.55 * taper);
    float intensity = vCore.a * flicker * brightness;
    // Alpha marks the core as solid, so the GI pass treats a tracer as a light
    // source and its colour spills onto everything around it; dimmer tracers
    // spill less.
    return vec4(neon * intensity, clamp((body * taper + flare) * vCore.a * brightness, 0.0, 1.0));
}
#endif
