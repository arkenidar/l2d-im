if os.getenv("LOCAL_LUA_DEBUGGER_VSCODE") == "1" then
  require("lldebugger").start()
end

-- print("Hello World! debugger test")

local Viewport = require("viewport")

local image
local vp
local contentCanvas

-- Generous fixed allocation for the content canvas (LÖVE requires an
-- explicit size up front). The *meaningful*, scrollable content size
-- reported to the viewport is the bbox tracked below, not this.
local CANVAS_CAPACITY_W, CANVAS_CAPACITY_H = 2048, 2048

-- Bounding box of everything drawDemoContent actually drew this
-- frame, accumulated via extend() as each shape is drawn. This is
-- what makes the viewport's content size adapt to the real drawing
-- instead of a hand-picked constant.
local contentMaxX, contentMaxY = 0, 0

local function resetContentBounds()
  contentMaxX, contentMaxY = 0, 0
end

local function extend(x2, y2)
  contentMaxX = math.max(contentMaxX, x2)
  contentMaxY = math.max(contentMaxY, y2)
end

-- Generic per-drawable protocol: every entry in sceneObjects exposes
-- :draw() and :bounds() (required), plus optional :hitTest(px, py) /
-- :onClick() if it should react to clicks. Works the same whether the
-- object is a single shape, a group of shapes, or (later) an image.

-- Single shape, clickable.
local RedRectButton = { x = 100, y = 100, w = 200, h = 150, isRed = true }
function RedRectButton:draw()
  love.graphics.setColor(self.isRed and 1 or 0, 0, self.isRed and 0 or 1)
  love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)
end
function RedRectButton:bounds()
  return self.x + self.w, self.y + self.h
end
function RedRectButton:hitTest(px, py)
  return px >= self.x and px <= self.x + self.w
    and py >= self.y and py <= self.y + self.h
end
function RedRectButton:onClick()
  self.isRed = not self.isRed
end

-- Single shape, clickable, cycles its own radius on click.
local BlueCircleButton = { cx = 400, cy = 300, sizes = { 30, 50, 70 }, sizeIndex = 2 }
function BlueCircleButton:radius()
  return self.sizes[self.sizeIndex]
end
function BlueCircleButton:draw()
  love.graphics.setColor(0, 0, 1)
  love.graphics.circle("fill", self.cx, self.cy, self:radius())
end
function BlueCircleButton:bounds()
  return self.cx + self:radius(), self.cy + self:radius()
end
function BlueCircleButton:hitTest(px, py)
  local dx, dy = px - self.cx, py - self.cy
  return (dx * dx + dy * dy) <= (self:radius() ^ 2)
end
function BlueCircleButton:onClick()
  self.sizeIndex = (self.sizeIndex % #self.sizes) + 1
end

-- Group of shapes as one object; non-interactive here, but the same
-- protocol supports adding hitTest/onClick to a whole group too.
local DecorGroup = {}
function DecorGroup:draw()
  love.graphics.setColor(1, 1, 1)
  love.graphics.print("Hello, LÖVE!", 150, 200)
  love.graphics.setColor(0, 1, 0)
  love.graphics.line(500, 100, 600, 200)
  love.graphics.setColor(1, 1, 0)
  love.graphics.polygon("fill", 700, 100, 750, 150, 700, 200, 650, 150)
end
function DecorGroup:bounds()
  return 750, 200
end

local sceneObjects = { RedRectButton, BlueCircleButton, DecorGroup }

-- Background image, dynamically fit to the viewport's current size
-- (w, h). Drawn fixed relative to the viewport's origin, unaffected
-- by scrolling.
local function drawBackground(w, h)
  local iw, ih = image:getDimensions()
  local scale = math.min(w / iw, h / ih)
  local ix = (w - iw * scale) / 2
  local iy = (h - ih * scale) / 2
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(image, ix, iy, 0, scale, scale)
end

-- Draws every scene object in fixed content-space coordinates, onto
-- whatever canvas is currently active (contentCanvas), reporting each
-- object's own extent so the real content bounding box can be tracked.
local function drawDemoContent()
  for _, obj in ipairs(sceneObjects) do
    obj:draw()
    extend(obj:bounds())
  end
end

-- Draws the content canvas as the viewport's scrollable content: the
-- canvas already holds this frame's fresh render of drawDemoContent,
-- so this just blits it (with transparency) over the background.
local function drawContentCanvas()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(contentCanvas, 0, 0)
end

function love.load()
  print("Hello World! debugger test")

  image = love.graphics.newImage("assets/highres-photo-4000x3000.png")
  contentCanvas = love.graphics.newCanvas(CANVAS_CAPACITY_W, CANVAS_CAPACITY_H)

  local ww, wh = love.graphics.getDimensions()
  vp = Viewport.new(ww * 0.15, wh * 0.15, ww * 0.6, wh * 0.6)

  vp:setOnClick(function(cx, cy)
    for _, obj in ipairs(sceneObjects) do
      if obj.hitTest and obj:hitTest(cx, cy) then
        obj:onClick()
        break
      end
    end
  end)
end

function love.update(dt)
  -- Update logic here
end

function love.draw()
  -- Re-render the content into its buffer every frame (immediate
  -- mode, no dirty-flag caching), then let the viewport scroll/clip
  -- the resulting buffer image over the background.
  love.graphics.setCanvas({ contentCanvas, stencil = false })
  love.graphics.clear(0, 0, 0, 0)
  resetContentBounds()
  drawDemoContent()
  love.graphics.setCanvas()

  vp:setContentSize(contentMaxX, contentMaxY)
  vp:draw(drawContentCanvas, drawBackground)
end

function love.keypressed(key)
  if key == "escape" then
    love.event.quit()
  end
end

function love.quit()
  print("Exiting the game...")
end

function love.errorhandler(msg)
  print("An error occurred: " .. msg)
  return msg
end

function love.focus(focused)
  if focused then
    print("Window gained focus")
  else
    print("Window lost focus")
  end
end

function love.mousepressed(x, y, button)
  print("Mouse pressed at: (" .. x .. ", " .. y .. ") with button: " .. button)
  vp:mousepressed(x, y, button)
end

function love.mousereleased(x, y, button)
  print("Mouse released at: (" .. x .. ", " .. y .. ") with button: " .. button)
  vp:mousereleased(x, y, button)
end

function love.mousemoved(x, y, dx, dy)
  print("Mouse moved to: (" .. x .. ", " .. y .. ") with delta: (" .. dx .. ", " .. dy .. ")")
  vp:mousemoved(x, y, dx, dy)
end

function love.wheelmoved(x, y)
  print("Mouse wheel moved: (" .. x .. ", " .. y .. ")")
  vp:wheelmoved(x, y)
end

function love.touchpressed(id, x, y)
  vp:touchpressed(id, x, y)
end

function love.touchmoved(id, x, y, dx, dy)
  vp:touchmoved(id, x, y, dx, dy)
end

function love.touchreleased(id, x, y)
  vp:touchreleased(id, x, y)
end

function love.resize(w, h)
  print("Window resized to: (" .. w .. ", " .. h .. ")")
end

function love.textinput(text)
  print("Text input: " .. text)
end

function love.joystickadded(joystick)
  print("Joystick added: " .. joystick:getName())
end

function love.joystickremoved(joystick)
  print("Joystick removed: " .. joystick:getName())
end

function love.joystickaxis(joystick, axis, value)
  print("Joystick axis moved: " .. joystick:getName() .. ", Axis: " .. axis .. ", Value: " .. value)
end

function love.joystickhat(joystick, hat, direction)
  print("Joystick hat moved: " .. joystick:getName() .. ", Hat: " .. hat .. ", Direction: " .. direction)
end

function love.joystickpressed(joystick, button)
  print("Joystick button pressed: " .. joystick:getName() .. ", Button: " .. button)
end

function love.joystickreleased(joystick, button)
  print("Joystick button released: " .. joystick:getName() .. ", Button: " .. button)
end

function love.threaderror(thread, errorstr)
  print("Thread error in thread: " .. thread:getName() .. ", Error: " .. errorstr)
end

function love.lowmemory()
  print("Low memory warning received")
end

function love.directorydropped(path)
  print("Directory dropped: " .. path)
end

function love.filedropped(file)
  print("File dropped: " .. file:getFilename())
end

function love.visible(visible)
  if visible then
    print("Window is now visible")
  else
    print("Window is now hidden")
  end
end
