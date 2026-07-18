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
  self:rebuildDrawOrder()
  return self
end

-- Painter's-algorithm ordering: objects sorted by ascending z (default
-- 0), insertion order breaking ties (table.sort alone is not stable).
-- Drawing walks this list forward; hit testing walks it backward, so
-- the object painted on top is also the one that receives input.
function Scene:rebuildDrawOrder()
  local order = {}
  for i, obj in ipairs(self.sceneObjects) do
    order[i] = obj
    obj.__sceneIndex = i
  end
  table.sort(order, function(a, b)
    local za, zb = a.z or 0, b.z or 0
    if za ~= zb then return za < zb end
    return a.__sceneIndex < b.__sceneIndex
  end)
  self.drawOrder = order
end

-- Re-renders every scene object into the canvas (bottom to top by z)
-- and re-derives the real content bounding box from what was actually
-- drawn. Rebuilds the z-ordering each frame so dynamic z changes and
-- added/removed objects just work (object counts are tiny).
function Scene:renderToCanvas()
  self:rebuildDrawOrder()
  -- Render in a clean coordinate space: setCanvas does NOT reset the
  -- current transform or scissor, so a nested scene rendered mid-frame
  -- (inside its parent's translated, scissored content pass) would
  -- otherwise bake the parent's offset into the canvas and clip
  -- against the parent's screen-space scissor.
  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setScissor()
  love.graphics.setCanvas({ self.canvas, stencil = false })
  love.graphics.clear(0, 0, 0, 0)
  self.maxX, self.maxY = 0, 0
  for _, obj in ipairs(self.drawOrder) do
    obj:draw()
    local x2, y2 = obj:bounds()
    self.maxX = math.max(self.maxX, x2)
    self.maxY = math.max(self.maxY, y2)
  end
  love.graphics.setCanvas()
  love.graphics.pop()
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

-- First-hit test in top-down z order. Returns the topmost object whose
-- hitTest matches, or nil for an empty spot. Any hitTest match counts
-- as "content here" — including cover shapes with no onClick — so it
-- doubles as the input-opacity probe the viewport router uses.
function Scene:hitTestAt(cx, cy)
  for i = #self.drawOrder, 1, -1 do
    local obj = self.drawOrder[i]
    if obj.hitTest and obj:hitTest(cx, cy) then
      return obj
    end
  end
  return nil
end

-- Dispatches a content-space click to the topmost scene object whose
-- hitTest matches. Returns true when an object consumed the click
-- (even a cover shape without an onClick handler).
function Scene:onClick(cx, cy)
  local obj = self:hitTestAt(cx, cy)
  if obj then
    if obj.onClick then obj:onClick() end
    return true
  end
  return false
end

return Scene
