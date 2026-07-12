-- Viewport: a movable, resizable, scrollable, clipping widget frame.
--
-- A Viewport no longer listens to raw LÖVE input itself: the router in
-- main.lua walks the viewport stack top-down, uses beginDrag /
-- bodyInputKind to find the first viewport that consumes an event, and
-- then forwards the rest of that gesture (dragTo / endDrag /
-- maybeFireClick / wheelmoved) only to the capturing viewport.
local Viewport = {}
Viewport.__index = Viewport

local HANDLE_SIZE = 14 * 3 -- square origin handle side length
local HANDLE_RADIUS = 8 * 3 -- resize circle handle radius
local CLICK_MOVE_THRESHOLD = 6 -- max pointer movement (px) still counted as a click, not a drag

-- opts.blocksInput: when true, the whole body consumes input even where
-- no content was hit (an input-opaque window); when false, empty areas
-- let input fall through to whatever is stacked below.
function Viewport.new(x, y, w, h, opts)
  local self = setmetatable({}, Viewport)
  self.x, self.y, self.w, self.h = x, y, w, h
  self.scrollX, self.scrollY = 0, 0
  self.minW, self.minH = 60, 60
  self.blocksInput = opts and opts.blocksInput or false
  self.hitContent = nil -- fn(contentX, contentY) -> bool, "is there content here?"
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

-- fn(contentX, contentY) -> truthy is asked at press/wheel time to know
-- whether real content sits under the pointer. Together with
-- self.blocksInput it decides whether this viewport consumes the event
-- or lets it fall through to viewports below (see bodyInputKind).
function Viewport:setHitContent(fn)
  self.hitContent = fn
end

function Viewport:toContent(x, y)
  return x - self.x + self.scrollX, y - self.y + self.scrollY
end

-- Classifies a pointer position against the viewport body for input
-- routing: nil (outside body), "content" (a scene object is under the
-- pointer), "opaque" (empty area but the viewport blocks input), or
-- "transparent" (empty area that lets input fall through).
function Viewport:bodyInputKind(x, y)
  if not self:hitBody(x, y) then return nil end
  if self.hitContent then
    local cx, cy = self:toContent(x, y)
    if self.hitContent(cx, cy) then return "content" end
  end
  if self.blocksInput then return "opaque" end
  return "transparent"
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

-- Returns the press hit kind so the router can decide capture policy:
-- "move" / "resize" (handles), "pan-content" / "pan-opaque" (firm body
-- grabs), "pan-transparent" (tentative grab on an empty see-through
-- area), or nil (missed entirely).
function Viewport:beginDrag(x, y)
  local kind
  if self:hitOrigin(x, y) then
    self.dragMode, kind = "move", "move"
  elseif self:hitResize(x, y) then
    self.dragMode, kind = "resize", "resize"
  else
    local bodyKind = self:bodyInputKind(x, y)
    if bodyKind then
      self.dragMode, kind = "pan", "pan-" .. bodyKind
    else
      self.dragMode = nil
    end
  end
  self.lastX, self.lastY = x, y
  self.dragStartX, self.dragStartY = x, y
  self.dragMoved = false
  return kind
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

-- Fires self.onClick at a screen position translated into
-- content-space, if the position is inside the body. Used both for a
-- viewport's own click and for clicks re-dispatched from a transparent
-- viewport stacked above it. Returns whether a click was fired.
function Viewport:fireClickAt(x, y)
  if self.onClick and self:hitBody(x, y) then
    self.onClick(self:toContent(x, y))
    return true
  end
  return false
end

-- If the just-finished drag was actually a click (started as body-pan,
-- released within the frame, moved less than CLICK_MOVE_THRESHOLD),
-- invoke self.onClick with the release position translated into
-- content-space.
function Viewport:maybeFireClick(x, y)
  if self.dragMode == "pan" and not self.dragMoved then
    self:fireClickAt(x, y)
  end
end

-- True when the content is larger than the frame, i.e. there is
-- somewhere to scroll to. Used by the wheel router: a transparent
-- viewport with overflowing content still catches the wheel over its
-- empty areas, since it is visibly a scrollable pane.
function Viewport:canScroll()
  return self.contentW > self.w or self.contentH > self.h
end

-- Scrolls in response to a wheel event the router already decided this
-- viewport should consume. Shift forces horizontal; otherwise
-- vertical, falling back to horizontal when that is the only
-- overflowing axis.
function Viewport:wheelmoved(dx, dy)
  local horizontal = love.keyboard.isDown("lshift", "rshift")
    or (self.contentH <= self.h and self.contentW > self.w)
  if horizontal then
    self.scrollX = self.scrollX - dy * 30
  else
    self.scrollY = self.scrollY - dy * 30
  end
  self:clampScroll()
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
