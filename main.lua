if os.getenv("LOCAL_LUA_DEBUGGER_VSCODE") == "1" then
  require("lldebugger").start()
end

-- print("Hello World! debugger test")

local Viewport = require("viewport")
local Scene = require("scene")
local Shapes = require("shapes")

local image
local viewports = {} -- { { viewport = <Viewport>, scene = <Scene> }, ... }

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

-- Builds a Viewport + Scene pair and adds it to the top-level list.
local function addViewport(x, y, w, h, sceneObjects, useBackground)
  local scene = Scene.new(sceneObjects, useBackground and drawBackground or nil)
  local viewport = Viewport.new(x, y, w, h)
  viewport:setOnClick(function(cx, cy)
    scene:onClick(cx, cy)
  end)
  table.insert(viewports, { viewport = viewport, scene = scene })
end

function love.load()
  print("Hello World! debugger test")

  image = love.graphics.newImage("assets/highres-photo-4000x3000.png")
  local ww, wh = love.graphics.getDimensions()

  addViewport(ww * 0.05, wh * 0.15, ww * 0.42, wh * 0.6, {
    Shapes.newRectButton({ x = 100, y = 100, w = 200, h = 150 }),
    Shapes.newCircleButton({ cx = 400, cy = 300 }),
    Shapes.newDecorGroup(),
  }, true)

  addViewport(ww * 0.53, wh * 0.15, ww * 0.42, wh * 0.6, {
    Shapes.newCircleButton({ cx = 150, cy = 150, sizeIndex = 1 }),
    Shapes.newRectButton({ x = 50, y = 250, w = 150, h = 100 }),
  }, false)
end

function love.update(dt)
  -- Update logic here
end

function love.draw()
  for _, entry in ipairs(viewports) do
    -- Re-render each scene into its own buffer every frame (immediate
    -- mode, no dirty-flag caching), then let its viewport scroll/clip
    -- the resulting buffer image over its own background.
    entry.scene:renderToCanvas()
    entry.viewport:setContentSize(entry.scene:contentSize())
    entry.viewport:draw(function()
      entry.scene:drawContent()
    end, entry.scene.backgroundFn)
  end
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
  for _, entry in ipairs(viewports) do
    entry.viewport:mousepressed(x, y, button)
  end
end

function love.mousereleased(x, y, button)
  print("Mouse released at: (" .. x .. ", " .. y .. ") with button: " .. button)
  for _, entry in ipairs(viewports) do
    entry.viewport:mousereleased(x, y, button)
  end
end

function love.mousemoved(x, y, dx, dy)
  print("Mouse moved to: (" .. x .. ", " .. y .. ") with delta: (" .. dx .. ", " .. dy .. ")")
  for _, entry in ipairs(viewports) do
    entry.viewport:mousemoved(x, y, dx, dy)
  end
end

function love.wheelmoved(x, y)
  print("Mouse wheel moved: (" .. x .. ", " .. y .. ")")
  for _, entry in ipairs(viewports) do
    entry.viewport:wheelmoved(x, y)
  end
end

function love.touchpressed(id, x, y)
  for _, entry in ipairs(viewports) do
    entry.viewport:touchpressed(id, x, y)
  end
end

function love.touchmoved(id, x, y, dx, dy)
  for _, entry in ipairs(viewports) do
    entry.viewport:touchmoved(id, x, y, dx, dy)
  end
end

function love.touchreleased(id, x, y)
  for _, entry in ipairs(viewports) do
    entry.viewport:touchreleased(id, x, y)
  end
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
