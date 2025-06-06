local sprite = {}
sprite.__index = sprite

function sprite:new(spriteImg, numRows, numColumns)
    local self          = setmetatable({}, sprite)
    self.spriteImg    = spriteImg
    self.numRows        = numRows
    self.numColumns     = numColumns
    return self
end

function sprite:constructsprite(spriteImg, numRows, numColumns)
    self.spriteImg    = spriteImg
    self.numRows        = numRows
    self.numColumns     = numColumns

    local spriteW, spriteH = self.spriteImg:getWidth(), self.spriteImg:getHeight()
    local TileW, TileH = spriteW/self.numRows, spriteH/self.numColumns
    local Quads = {}
    local index = 0

    for row=0,self.numRows-1 do
        for column=0,self.numColumns-1 do
            Quads[index] = love.graphics.newQuad(column*TileW, row*TileH, TileW, TileH, spriteW, spriteH)
            index = index + 1
        end
    end

    return Quads
end

function sprite:getTileSize()
    local spriteW, spriteH = self.spriteImg:getWidth(), self.spriteImg:getHeight()
    local TileW, TileH = spriteW/self.numRows, spriteH/self.numColumns

    return TileW/2, TileH/2
end

return sprite
