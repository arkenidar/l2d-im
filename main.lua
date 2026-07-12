if os.getenv("LOCAL_LUA_DEBUGGER_VSCODE") == "1" then
  require("lldebugger").start()
end

-- print("Hello World! debugger test")

local Viewport = require("viewport")
local Scene = require("scene")
local Shapes = require("shapes")

local image

-- Viewport stack, ordered bottom -> top (list index IS the z position).
-- Drawing walks it forward (painter's algorithm); input walks it
-- backward so the topmost viewport gets first claim on every event.
local viewports = {} -- { { viewport = <Viewport>, scene = <Scene> }, ... }

-- Active pointer captures: once a press is claimed by a viewport, all
-- following move/release events of that pointer go only to it.
-- Each capture is { entry = <stack entry>, tentative = <bool> };
-- tentative means the press landed on a transparent empty area and the
-- click (if it stays a click) will be re-dispatched to layers below.
local mouseCapture = nil
local touchCaptures = {} -- touch id -> capture

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

-- Builds a Viewport + Scene pair and pushes it on top of the stack.
-- opts.blocksInput overrides the input policy explicitly; when nil the
-- policy follows the visuals: a viewport with a background image is
-- input-opaque everywhere, one without lets empty areas fall through.
local function addViewport(x, y, w, h, sceneObjects, useBackground, opts)
  local blocksInput = opts and opts.blocksInput
  if blocksInput == nil then blocksInput = useBackground end
  local scene = Scene.new(sceneObjects, useBackground and drawBackground or nil)
  local viewport = Viewport.new(x, y, w, h, { blocksInput = blocksInput })
  viewport:setOnClick(function(cx, cy)
    scene:onClick(cx, cy)
  end)
  viewport:setHitContent(function(cx, cy)
    return scene:hitTestAt(cx, cy) ~= nil
  end)
  table.insert(viewports, { viewport = viewport, scene = scene })
end

-- Moves a stack entry to the top (end of the list), like a desktop
-- window raised on click.
local function bringToFront(entry)
  for i, e in ipairs(viewports) do
    if e == entry then
      table.remove(viewports, i)
      table.insert(viewports, entry)
      return
    end
  end
end

-- Walks the stack top-down looking for the first viewport that claims
-- a press at (x, y). Handles claim firmly; body presses claim firmly on
-- content or opaque areas and tentatively on transparent empty areas
-- (the drag pans, but a mere click will be forwarded below on release).
-- Returns the capture record, or nil if nothing claimed the press.
local function capturePressAt(x, y)
  for i = #viewports, 1, -1 do
    local entry = viewports[i]
    if entry.viewport.dragMode == nil then
      local kind = entry.viewport:beginDrag(x, y)
      if kind then
        bringToFront(entry)
        return { entry = entry, tentative = (kind == "pan-transparent") }
      end
    end
  end
  return nil
end

-- Ends a captured pointer gesture at (x, y). If the gesture stayed a
-- click on a transparent empty area, forwards the click to the topmost
-- viewport below that actually has something there (content or an
-- input-opaque body), raising it — otherwise fires/ends normally.
local function releaseCapture(capture, x, y)
  local vp = capture.entry.viewport
  if capture.tentative and not vp.dragMoved then
    vp:endDrag()
    for i = #viewports, 1, -1 do
      local entry = viewports[i]
      if entry ~= capture.entry then
        local below = entry.viewport
        if below:hitOrigin(x, y) or below:hitResize(x, y) then
          return -- a handle consumes the click without any action
        end
        local kind = below:bodyInputKind(x, y)
        if kind == "content" or kind == "opaque" then
          bringToFront(entry)
          below:fireClickAt(x, y)
          return
        end
      end
    end
  else
    vp:maybeFireClick(x, y)
    vp:endDrag()
  end
end

function love.load()
  print("Hello World! debugger test")

  image = love.graphics.newImage("assets/highres-photo-4000x3000.png")
  local ww, wh = love.graphics.getDimensions()

  -- Bottom window: opaque photo background, so it blocks all input to
  -- anything below its frame. The two overlapping rects demo scene-level
  -- z: the z = 1 rect draws on top and wins clicks in the overlap.
  addViewport(ww * 0.05, wh * 0.15, ww * 0.45, wh * 0.6, {
    Shapes.newRectButton({ x = 100, y = 100, w = 200, h = 150 }),
    Shapes.newRectButton({ x = 200, y = 170, w = 200, h = 150, z = 1 }),
    Shapes.newCircleButton({ cx = 400, cy = 300 }),
    Shapes.newDecorGroup(),
  }, true)

  -- Top window: no background, overlapping the first one. Its empty
  -- areas are input-transparent — clicks there fall through to the
  -- window below, while drags from the same spot still pan this one.
  addViewport(ww * 0.35, wh * 0.25, ww * 0.45, wh * 0.6, {
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
  if button ~= 1 or mouseCapture then return end
  mouseCapture = capturePressAt(x, y)
end

function love.mousemoved(x, y, dx, dy)
  if mouseCapture then
    mouseCapture.entry.viewport:dragTo(x, y)
  end
end

function love.mousereleased(x, y, button)
  if button ~= 1 or not mouseCapture then return end
  releaseCapture(mouseCapture, x, y)
  mouseCapture = nil
end

-- Wheel goes to the topmost viewport under the cursor that either has
-- something there (content or an input-opaque body) or has overflowing
-- content to scroll. Only a transparent viewport whose content already
-- fits lets the wheel fall through to the layers below.
function love.wheelmoved(dx, dy)
  local mx, my = love.mouse.getPosition()
  for i = #viewports, 1, -1 do
    local vp = viewports[i].viewport
    local kind = vp:bodyInputKind(mx, my)
    if kind == "content" or kind == "opaque" or (kind == "transparent" and vp:canScroll()) then
      vp:wheelmoved(dx, dy)
      return
    end
  end
end

-- Touch mirrors the mouse path, with an independent capture per touch
-- id (a viewport already mid-gesture won't be claimed twice, thanks to
-- the dragMode guard in capturePressAt).
function love.touchpressed(id, x, y)
  touchCaptures[id] = capturePressAt(x, y)
end

function love.touchmoved(id, x, y, dx, dy)
  local capture = touchCaptures[id]
  if capture then
    capture.entry.viewport:dragTo(x, y)
  end
end

function love.touchreleased(id, x, y)
  local capture = touchCaptures[id]
  if capture then
    releaseCapture(capture, x, y)
    touchCaptures[id] = nil
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
