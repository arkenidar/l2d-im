-- Scene: a canvas-backed, click-dispatching collection of drawables.
-- Owns its own offscreen canvas, renders its sceneObjects into it each
-- frame (immediate mode, no dirty-flag caching), tracks the real
-- bounding box of what was drawn, and dispatches clicks to whichever
-- scene object was hit.
local Scene = {}
Scene.__index = Scene

-- Generous fixed allocation for the canvas (LÖVE requires an explicit
-- size up front). The *meaningful*, scrollable content size is the
-- bbox tracked in renderToCanvas, not this.
local CANVAS_CAPACITY_W, CANVAS_CAPACITY_H = 2048, 2048

function Scene.new(sceneObjects, backgroundFn)
  local self = setmetatable({}, Scene)
  self.sceneObjects = sceneObjects
  self.backgroundFn = backgroundFn
  self.canvas = love.graphics.newCanvas(CANVAS_CAPACITY_W, CANVAS_CAPACITY_H)
  self.maxX, self.maxY = 0, 0
  return self
end

-- Re-renders every scene object into the canvas and re-derives the
-- real content bounding box from what was actually drawn.
function Scene:renderToCanvas()
  love.graphics.setCanvas({ self.canvas, stencil = false })
  love.graphics.clear(0, 0, 0, 0)
  self.maxX, self.maxY = 0, 0
  for _, obj in ipairs(self.sceneObjects) do
    obj:draw()
    local x2, y2 = obj:bounds()
    self.maxX = math.max(self.maxX, x2)
    self.maxY = math.max(self.maxY, y2)
  end
  love.graphics.setCanvas()
end

function Scene:contentSize()
  return self.maxX, self.maxY
end

-- Blits the canvas (already holding this frame's fresh render) as
-- viewport content, with transparency.
function Scene:drawContent()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(self.canvas, 0, 0)
end

-- Dispatches a content-space click to the first scene object whose
-- hitTest matches.
function Scene:onClick(cx, cy)
  for _, obj in ipairs(self.sceneObjects) do
    if obj.hitTest and obj:hitTest(cx, cy) then
      obj:onClick()
      break
    end
  end
end

return Scene
