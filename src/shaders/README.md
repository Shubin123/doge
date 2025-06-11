# Game Shaders

This folder contains all the fragment shaders used in the game's rendering pipeline.

## Shader Files

### `seed.frag`
- **Purpose**: Edge detection and UV coordinate seeding
- **Usage**: Identifies sprite outlines and returns UV coordinates for surfaces above alpha threshold
- **Uniforms**: None
- **Features**: Alpha threshold-based edge detection

### `jfa.frag` 
- **Purpose**: Jump Flood Algorithm implementation
- **Usage**: Calculates distance fields using iterative sampling
- **Uniforms**: `stepSize` - controls sampling distance
- **Features**: 3x3 sampling pattern with boundary checking

### `distance_field.frag`
- **Purpose**: Distance field generation with smooth falloff
- **Usage**: Converts JFA output to smooth distance field
- **Uniforms**: `smoothness` - controls falloff smoothness
- **Features**: Smoothstep-based distance calculation

### `global_illumination.frag`
- **Purpose**: Advanced global illumination with arcade-style effects
- **Usage**: Ray-marched lighting with color enhancement and glow
- **Uniforms**: 
  - `surfaceTexture` - main scene texture
  - `maxDistance` - ray marching distance
  - `sampleCount` - number of light rays
  - `time` - animation time
  - `ambientColor` - base lighting color
  - `glowIntensity` - brightness glow strength
  - `colorVibrancy` - color saturation enhancement
  - `camera_position` - camera world position
  - `camera_zoom` - camera zoom level
  - `view_matrix` - camera transformation matrix
- **Features**: 
  - Ray-marched global illumination
  - Color enhancement for arcade feel
  - Glow accumulation from bright objects
  - Tone mapping and sRGB conversion

### `bloom_extract.frag`
- **Purpose**: Bright pixel extraction for bloom effect
- **Usage**: Identifies and extracts pixels above brightness threshold
- **Uniforms**: `threshold` - brightness cutoff value
- **Features**: Luminance-based extraction with threshold scaling

### `blur.frag`
- **Purpose**: Gaussian blur for bloom effect
- **Usage**: Multi-tap directional blur for smooth light diffusion
- **Uniforms**: 
  - `direction` - blur direction (horizontal/vertical)
  - `blurSize` - blur intensity multiplier
- **Features**: 9-tap Gaussian kernel with weighted sampling

### `composite.frag`
- **Purpose**: Final scene composition and post-processing
- **Usage**: Combines all render passes into final output
- **Uniforms**:
  - `bloomTexture` - bloom effect texture
  - `giTexture` - global illumination texture
  - `bloomStrength` - bloom blend intensity
  - `giStrength` - GI blend intensity  
  - `contrast` - contrast adjustment
  - `saturation` - color saturation
  - `tintColor` - color tint overlay
- **Features**:
  - Multi-pass texture blending
  - Contrast and saturation adjustment
  - Color tinting
  - Vignette effect

## Rendering Pipeline

1. **Seed Pass**: `seed.frag` → Generates UV coordinates for visible surfaces
2. **JFA Passes**: `jfa.frag` → Multiple iterations to build distance field
3. **Distance Field**: `distance_field.frag` → Smooth distance field generation
4. **Global Illumination**: `global_illumination.frag` → Ray-marched lighting
5. **Bloom Extract**: `bloom_extract.frag` → Extract bright pixels
6. **Bloom Blur**: `blur.frag` → Horizontal and vertical blur passes
7. **Final Composite**: `composite.frag` → Combine all effects

## Loading

All shaders are loaded in `src/shader.lua` using:
```lua
shader_name = love.graphics.newShader("shaders_/filename.frag")
```

Note: Paths are relative to the `src/` directory since Love2D is launched with `love ./src`.

## Camera Integration

The `global_illumination.frag` shader includes camera-aware uniforms for performance optimization and visual consistency with the camera system.