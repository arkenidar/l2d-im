-- Factory functions for demo scene objects. Each one is buildable more
-- than once (unlike a one-off singleton table), so independent scenes
-- can reuse the same shape kinds with their own starting state.
--
-- Every shape exposes the generic per-drawable protocol used by
-- Scene: :draw() and :bounds() (required), plus optional
-- :hitTest(px, py) / :onClick() if it should react to clicks.
local Shapes = {}

-- Single shape, clickable: toggles red/blue.
function Shapes.newRectButton(opts)
  local self = { x = opts.x, y = opts.y, w = opts.w, h = opts.h, isRed = true }

  function self:draw()
    love.graphics.setColor(self.isRed and 1 or 0, 0, self.isRed and 0 or 1)
    love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)
  end

  function self:bounds()
    return self.x + self.w, self.y + self.h
  end

  function self:hitTest(px, py)
    return px >= self.x and px <= self.x + self.w
      and py >= self.y and py <= self.y + self.h
  end

  function self:onClick()
    self.isRed = not self.isRed
  end

  return self
end

-- Single shape, clickable: cycles its own radius on click.
function Shapes.newCircleButton(opts)
  local self = {
    cx = opts.cx,
    cy = opts.cy,
    sizes = opts.sizes or { 30, 50, 70 },
    sizeIndex = opts.sizeIndex or 2,
  }

  function self:radius()
    return self.sizes[self.sizeIndex]
  end

  function self:draw()
    love.graphics.setColor(0, 0, 1)
    love.graphics.circle("fill", self.cx, self.cy, self:radius())
  end

  function self:bounds()
    return self.cx + self:radius(), self.cy + self:radius()
  end

  function self:hitTest(px, py)
    local dx, dy = px - self.cx, py - self.cy
    return (dx * dx + dy * dy) <= (self:radius() ^ 2)
  end

  function self:onClick()
    self.sizeIndex = (self.sizeIndex % #self.sizes) + 1
  end

  return self
end

-- Group of shapes as one object; non-interactive here, but the same
-- protocol supports adding hitTest/onClick to a whole group too.
function Shapes.newDecorGroup()
  local self = {}

  function self:draw()
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Hello, LÖVE!", 150, 200)
    love.graphics.setColor(0, 1, 0)
    love.graphics.line(500, 100, 600, 200)
    love.graphics.setColor(1, 1, 0)
    love.graphics.polygon("fill", 700, 100, 750, 150, 700, 200, 650, 150)
  end

  function self:bounds()
    return 750, 200
  end

  return self
end

return Shapes
