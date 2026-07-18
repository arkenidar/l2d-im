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
-- Each capture is { entry = <stack entry>, list = <the stack entry
-- belongs to>, tentative = <bool> }; tentative means the press landed
-- on a transparent empty area and the click (if it stays a click) will
-- be re-dispatched to sibling layers below.
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

-- Builds a Viewport + Scene pair and pushes it on top of a stack —
-- either the root `viewports` list, or (when opts.parent is given) that
-- viewport's `children`, nesting it inside. A nested child's x, y are
-- in the parent's content-space, same as everything else drawn there.
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
  local entry = { viewport = viewport, scene = scene }
  local list = (opts and opts.parent and opts.parent.children) or viewports
  table.insert(list, entry)
  return entry
end

-- Moves a stack entry to the top (end of its own list — root or a
-- parent's children), like a desktop window raised on click.
local function bringToFront(list, entry)
  for i, e in ipairs(list) do
    if e == entry then
      table.remove(list, i)
      table.insert(list, entry)
      return
    end
  end
end

-- Converts a raw screen (x, y) into the coordinate space capture.list
-- and capture.entry operate in, by applying each ancestor viewport's
-- toContent in outer-to-inner order. Needed because love.mousemoved /
-- love.touchmoved always report raw screen coordinates, but a nested
-- capture's beginDrag/dragTo/etc. were seeded with coordinates already
-- converted into its parent's (and its parent's parent's, ...)
-- content-space during capturePressAt's descent.
local function toLocal(chain, x, y)
  for _, vp in ipairs(chain) do
    x, y = vp:toContent(x, y)
  end
  return x, y
end

-- Walks a stack (root or a nested children list) top-down looking for
-- the first viewport that claims a press at (x, y), descending into a
-- viewport's own children first so the topmost nested content wins.
-- Handles claim firmly; body presses claim firmly on content or opaque
-- areas and tentatively on transparent empty areas (the drag pans, but
-- a mere click will be forwarded below on release). Returns a capture
-- record { entry, list, chain, tentative }, or nil if nothing claimed
-- the press. chain is the list of ancestor viewports (outer to inner)
-- toLocal must apply to convert future raw screen coordinates into the
-- space capture.list/capture.entry operate in.
--
-- Only the list the capture actually landed in gets reordered — a
-- nested capture does NOT also raise its ancestors' entries in their
-- own (outer) lists. Otherwise grabbing a deeply nested child's handle
-- would raise the whole ancestor chain to the front of the root stack,
-- swapping which unrelated sibling window paints on top of which.
-- Note: descending into children is gated on hitBody (children only
-- ever live, visually and interactively, inside the parent's clipped
-- body), but the parent's own beginDrag is NOT gated on its own
-- hitBody — the move/resize handles are centered on the frame corners
-- and half of each sticks out past the body rectangle, exactly like
-- the original single-level router relied on.
--
-- A viewport's own handles are drawn on top of its children (draw()
-- paints them after the clipped body), so a press on one of its own
-- handles must NOT descend into children — otherwise a child handle
-- underneath would steal the press from the parent handle covering it.
local function capturePressAt(list, x, y)
  for i = #list, 1, -1 do
    local entry = list[i]
    local vp = entry.viewport
    if vp.dragMode == nil then
      local onOwnHandle = vp:hitOrigin(x, y) or vp:hitResize(x, y)
      if not onOwnHandle and vp:hitBody(x, y) then
        local cx, cy = vp:toContent(x, y)
        local childCapture = capturePressAt(vp.children, cx, cy)
        if childCapture then
          table.insert(childCapture.chain, 1, vp)
          return childCapture
        end
      end
      local kind = vp:beginDrag(x, y)
      if kind then
        bringToFront(list, entry)
        return { entry = entry, list = list, chain = {}, tentative = (kind == "pan-transparent") }
      end
    end
  end
  return nil
end

-- Ends a captured pointer gesture at (x, y). If the gesture stayed a
-- click on a transparent empty area, forwards the click to the topmost
-- sibling below (in the same list the capture came from) that actually
-- has something there (content or an input-opaque body), raising it —
-- otherwise fires/ends normally. A click that falls through every
-- sibling of a nested child is not re-tried against the parent's own
-- siblings; nesting only one level of fall-through keeps this simple.
local function releaseCapture(capture, x, y)
  local vp = capture.entry.viewport
  if capture.tentative and not vp.dragMoved then
    vp:endDrag()
    for i = #capture.list, 1, -1 do
      local entry = capture.list[i]
      if entry ~= capture.entry then
        local below = entry.viewport
        if below:hitOrigin(x, y) or below:hitResize(x, y) then
          return -- a handle consumes the click without any action
        end
        local kind = below:bodyInputKind(x, y)
        if kind == "content" or kind == "opaque" then
          bringToFront(capture.list, entry)
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

-- Walks a stack top-down for the topmost viewport under (mx, my) that
-- should consume a wheel event, descending into children first: either
-- it has something there (content or an input-opaque body), or it has
-- overflowing content to scroll. Only a transparent viewport whose
-- content already fits lets the wheel fall through. Returns true once
-- consumed.
local function wheelRoute(list, mx, my, dx, dy)
  for i = #list, 1, -1 do
    local vp = list[i].viewport
    if vp:hitBody(mx, my) then
      local cx, cy = vp:toContent(mx, my)
      if wheelRoute(vp.children, cx, cy, dx, dy) then return true end
      local kind = vp:bodyInputKind(mx, my)
      if kind == "content" or kind == "opaque" or (kind == "transparent" and vp:canScroll()) then
        vp:wheelmoved(dx, dy)
        return true
      end
    end
  end
  return false
end

function love.load()
  print("Hello World! debugger test")

  image = love.graphics.newImage("assets/highres-photo-4000x3000.png")
  local ww, wh = love.graphics.getDimensions()

  -- Bottom window: opaque photo background, so it blocks all input to
  -- anything below its frame. The two overlapping rects demo scene-level
  -- z: the z = 1 rect draws on top and wins clicks in the overlap.
  local bottom = addViewport(ww * 0.05, wh * 0.15, ww * 0.45, wh * 0.6, {
    Shapes.newRectButton({ x = 100, y = 100, w = 200, h = 150 }),
    Shapes.newRectButton({ x = 200, y = 170, w = 200, h = 150, z = 1 }),
    Shapes.newCircleButton({ cx = 400, cy = 300 }),
    Shapes.newDecorGroup(),
  }, true)

  -- Nested demo: a child viewport living inside the bottom window's
  -- content space, proving a viewport can host another viewport,
  -- recursively — it scrolls/clips with its parent and still handles
  -- its own drag, resize, and input independently.
  addViewport(10, 10, 150, 110, {
    Shapes.newRectButton({ x = 15, y = 15, w = 60, h = 40 }),
    Shapes.newCircleButton({ cx = 100, cy = 60, sizeIndex = 1 }),
  }, false, { blocksInput = true, parent = bottom.viewport })

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
  -- Re-renders each scene into its own buffer every frame (immediate
  -- mode, no dirty-flag caching), then lets its viewport scroll/clip
  -- the resulting buffer image over its own background — recursing
  -- into any nested children the same way. Shared with Viewport:draw,
  -- which uses it for a viewport's own children.
  Viewport.drawStack(viewports)
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
  mouseCapture = capturePressAt(viewports, x, y)
end

function love.mousemoved(x, y, dx, dy)
  if mouseCapture then
    local lx, ly = toLocal(mouseCapture.chain, x, y)
    mouseCapture.entry.viewport:dragTo(lx, ly)
  end
end

function love.mousereleased(x, y, button)
  if button ~= 1 or not mouseCapture then return end
  local lx, ly = toLocal(mouseCapture.chain, x, y)
  -- Sync one last time at the release position before ending the
  -- gesture: mousemoved isn't guaranteed to have delivered an event at
  -- this exact spot (a fast flick can release before/without a
  -- matching motion sample), which would otherwise leave the drag
  -- visibly frozen short of where the pointer actually ended up.
  mouseCapture.entry.viewport:dragTo(lx, ly)
  releaseCapture(mouseCapture, lx, ly)
  mouseCapture = nil
end

-- Wheel goes to the topmost viewport under the cursor that either has
-- something there (content or an input-opaque body) or has overflowing
-- content to scroll. Only a transparent viewport whose content already
-- fits lets the wheel fall through to the layers below.
function love.wheelmoved(dx, dy)
  local mx, my = love.mouse.getPosition()
  wheelRoute(viewports, mx, my, dx, dy)
end

-- Touch mirrors the mouse path, with an independent capture per touch
-- id (a viewport already mid-gesture won't be claimed twice, thanks to
-- the dragMode guard in capturePressAt).
function love.touchpressed(id, x, y)
  touchCaptures[id] = capturePressAt(viewports, x, y)
end

function love.touchmoved(id, x, y, dx, dy)
  local capture = touchCaptures[id]
  if capture then
    local lx, ly = toLocal(capture.chain, x, y)
    capture.entry.viewport:dragTo(lx, ly)
  end
end

function love.touchreleased(id, x, y)
  local capture = touchCaptures[id]
  if capture then
    local lx, ly = toLocal(capture.chain, x, y)
    -- See love.mousereleased: sync at the release position first, in
    -- case no touchmoved landed exactly there.
    capture.entry.viewport:dragTo(lx, ly)
    releaseCapture(capture, lx, ly)
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
