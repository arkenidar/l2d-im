-- Viewport: a movable, resizable, scrollable, clipping widget frame.
local Viewport = {}
Viewport.__index = Viewport

local HANDLE_SIZE = 14 * 3 -- square origin handle side length
local HANDLE_RADIUS = 8 * 3 -- resize circle handle radius
local CLICK_MOVE_THRESHOLD = 6 -- max pointer movement (px) still counted as a click, not a drag

function Viewport.new(x, y, w, h)
  local self = setmetatable({}, Viewport)
  self.x, self.y, self.w, self.h = x, y, w, h
  self.scrollX, self.scrollY = 0, 0
  self.minW, self.minH = 60, 60
  -- Bounding size of the actual content drawn inside this viewport.
  -- Distinct from self.w/self.h (the viewport frame size) and may be
  -- larger (or change over time, e.g. if the content is dynamic) --
  -- call setContentSize whenever it changes so scroll clamping and the
  -- scrollable range stay correct. Defaults to the frame size, i.e. no
  -- overscroll until the caller reports otherwise.
  self.contentW, self.contentH = w, h
  self.dragMode = nil -- nil | "move" | "resize" | "pan"
  self.lastX, self.lastY = 0, 0
  self.dragStartX, self.dragStartY = 0, 0
  self.dragMoved = false
  self.activeTouch = nil
  self.onClick = nil -- fn(contentX, contentY), called on a body click (no drag)
  return self
end

function Viewport:getDimensions()
  return self.w, self.h
end

function Viewport:getContentSize()
  return self.contentW, self.contentH
end

-- fn(contentX, contentY) is called when the viewport body is clicked
-- (pressed and released with negligible movement) inside its bounds,
-- with coordinates translated into the same content-space used by
-- the draw() content callback.
function Viewport:setOnClick(fn)
  self.onClick = fn
end

-- Reports the current bounding size of the content drawn inside this
-- viewport, so h/v scrolling can reach every part of it. Safe to call
-- every frame if the content's size can change.
function Viewport:setContentSize(contentW, contentH)
  self.contentW, self.contentH = contentW, contentH
  self:clampScroll()
end

function Viewport:hitOrigin(mx, my)
  local half = HANDLE_SIZE / 2
  return mx >= self.x - half and mx <= self.x + half
    and my >= self.y - half and my <= self.y + half
end

function Viewport:hitResize(mx, my)
  local cx, cy = self.x + self.w, self.y + self.h
  local dx, dy = mx - cx, my - cy
  return (dx * dx + dy * dy) <= (HANDLE_RADIUS * HANDLE_RADIUS)
end

function Viewport:hitBody(mx, my)
  return mx >= self.x and mx <= self.x + self.w
    and my >= self.y and my <= self.y + self.h
end

function Viewport:clampScroll()
  local maxScrollX = math.max(0, self.contentW - self.w)
  local maxScrollY = math.max(0, self.contentH - self.h)
  self.scrollX = math.max(0, math.min(self.scrollX, maxScrollX))
  self.scrollY = math.max(0, math.min(self.scrollY, maxScrollY))
end

function Viewport:beginDrag(x, y)
  if self:hitOrigin(x, y) then
    self.dragMode = "move"
  elseif self:hitResize(x, y) then
    self.dragMode = "resize"
  elseif self:hitBody(x, y) then
    self.dragMode = "pan"
  else
    self.dragMode = nil
  end
  self.lastX, self.lastY = x, y
  self.dragStartX, self.dragStartY = x, y
  self.dragMoved = false
  return self.dragMode ~= nil
end

function Viewport:dragTo(x, y)
  if not self.dragMode then return end
  local dx, dy = x - self.lastX, y - self.lastY
  self.lastX, self.lastY = x, y

  if not self.dragMoved then
    local sdx, sdy = x - self.dragStartX, y - self.dragStartY
    if (sdx * sdx + sdy * sdy) > (CLICK_MOVE_THRESHOLD * CLICK_MOVE_THRESHOLD) then
      self.dragMoved = true
    end
  end

  if self.dragMode == "move" then
    self.x = self.x + dx
    self.y = self.y + dy
  elseif self.dragMode == "resize" then
    self.w = math.max(self.minW, self.w + dx)
    self.h = math.max(self.minH, self.h + dy)
    self:clampScroll()
  elseif self.dragMode == "pan" then
    self.scrollX = self.scrollX - dx
    self.scrollY = self.scrollY - dy
    self:clampScroll()
  end
end

function Viewport:endDrag()
  self.dragMode = nil
end

-- If the just-finished drag was actually a click (started as body-pan,
-- released within the frame, moved less than CLICK_MOVE_THRESHOLD),
-- invoke self.onClick with the release position translated into
-- content-space.
function Viewport:maybeFireClick(x, y)
  if self.dragMode == "pan" and not self.dragMoved and self.onClick and self:hitBody(x, y) then
    local contentX = x - self.x + self.scrollX
    local contentY = y - self.y + self.scrollY
    self.onClick(contentX, contentY)
  end
end

-- Mouse input
function Viewport:mousepressed(x, y, button)
  if button ~= 1 then return end
  self:beginDrag(x, y)
end

function Viewport:mousemoved(x, y, dx, dy)
  self:dragTo(x, y)
end

function Viewport:mousereleased(x, y, button)
  if button ~= 1 then return end
  self:maybeFireClick(x, y)
  self:endDrag()
end

function Viewport:wheelmoved(dx, dy)
  local mx, my = love.mouse.getPosition()
  if not self:hitBody(mx, my) then return end

  if love.keyboard.isDown("lshift", "rshift") then
    self.scrollX = self.scrollX - dy * 30
  else
    self.scrollY = self.scrollY - dy * 30
  end
  self:clampScroll()
end

-- Touch input (mirrors body-grab panning)
function Viewport:touchpressed(id, x, y)
  if self.activeTouch ~= nil then return end
  if self:beginDrag(x, y) then
    self.activeTouch = id
  end
end

function Viewport:touchmoved(id, x, y, dx, dy)
  if id ~= self.activeTouch then return end
  self:dragTo(x, y)
end

function Viewport:touchreleased(id, x, y)
  if id ~= self.activeTouch then return end
  self:maybeFireClick(x, y)
  self:endDrag()
  self.activeTouch = nil
end

-- contentFn(w, h) is clipped to the viewport and scrolls with it.
-- backgroundFn(w, h), if given, is clipped to the viewport but stays
-- fixed relative to its origin regardless of scroll.
function Viewport:draw(contentFn, backgroundFn)
  love.graphics.push()
  love.graphics.setScissor(self.x, self.y, self.w, self.h)
  love.graphics.translate(self.x, self.y)

  if backgroundFn then
    backgroundFn(self.w, self.h)
  end

  love.graphics.translate(-self.scrollX, -self.scrollY)
  contentFn(self.w, self.h)

  love.graphics.pop()
  love.graphics.setScissor()

  -- Frame border.
  love.graphics.setColor(1, 1, 1)
  love.graphics.rectangle("line", self.x, self.y, self.w, self.h)

  -- Origin square handle.
  local half = HANDLE_SIZE / 2
  love.graphics.setColor(0.9, 0.6, 0.1)
  love.graphics.rectangle("fill", self.x - half, self.y - half, HANDLE_SIZE, HANDLE_SIZE)

  -- Resize circle handle.
  love.graphics.setColor(0.1, 0.7, 0.9)
  love.graphics.circle("fill", self.x + self.w, self.y + self.h, HANDLE_RADIUS)

  love.graphics.setColor(1, 1, 1)
end

return Viewport
