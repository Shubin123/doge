-- Faithful transliteration of the UV-rect portion of
-- calculateFrameOffsetsFromMetadata (src/game/characterAnimator.lua).
-- Usage: lua5.4 uv_map.lua <spritesPerRow> <uniformWidth> <uniformHeight> <textureWidth> <textureHeight> <totalSprites>
-- Prints "u,v,uSize,vSize" per global sprite index.
local spritesPerRow = tonumber(arg[1])
local uniformWidth = tonumber(arg[2])
local uniformHeight = tonumber(arg[3])
local textureWidth = tonumber(arg[4])
local textureHeight = tonumber(arg[5])
local totalSprites = tonumber(arg[6])

for globalIndex = 0, totalSprites - 1 do
    local row = math.floor(globalIndex / spritesPerRow)
    local col = globalIndex % spritesPerRow
    local u = (col * uniformWidth) / textureWidth
    local v = (row * uniformHeight) / textureHeight
    local uSize = uniformWidth / textureWidth
    local vSize = uniformHeight / textureHeight
    print(string.format("%.17g,%.17g,%.17g,%.17g", u, v, uSize, vSize))
end
