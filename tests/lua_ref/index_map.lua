-- Faithful transliteration of the per-axis nearest-neighbor index math from
-- characterAnimator.createAndSaveAtlas (src/game/characterAnimator.lua).
-- Usage: lua5.4 index_map.lua <uniformDim> <spriteDim>
-- Prints one clamped source index per line, one per destination pixel.
local uniformDim = tonumber(arg[1])
local spriteDim = tonumber(arg[2])

for d = 0, uniformDim - 1 do
    local src = math.floor(d * spriteDim / uniformDim)
    src = math.max(0, math.min(src, spriteDim - 1))
    print(src)
end
