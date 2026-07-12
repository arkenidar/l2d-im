# rules-shape

A LÖVE2D/Lua sandbox for a scrollable, clippable "viewport" widget and click-reactive scene
objects.

## Running

Requires the [LÖVE](https://love2d.org/) engine (tested with `love .`).

```sh
love .
```

## Project layout

- `main.lua` — the demo scene, the viewport stack, the input router, and all `love.*` callbacks.
- `viewport.lua` — the `Viewport` widget.
- `scene.lua` — the `Scene`: canvas-backed, z-ordered, click-dispatching drawable collection.
- `shapes.lua` — factory functions for demo scene objects (shapes).
- `conf.lua` — LÖVE window configuration.
- `assets/` — background image.

## The `Viewport` widget (`viewport.lua`)

- Movable via the origin (square) handle, resizable via the corner (circle) handle.
- Clips its content to its own bounds (scissor-based).
- Scrollable via mouse wheel, body drag-to-pan, and touch drag. Scroll range is derived from a
  caller-reported content size (`setContentSize` / `getContentSize`), so it adapts to content
  that's larger than the viewport frame.
- Two draw layers: `backgroundFn` (fixed relative to the viewport's origin, unaffected by
  scroll) and `contentFn` (scrolls with the viewport).
- Click detection distinguishes a click (press+release under a small movement threshold) from a
  pan-drag, and reports it in content-space coordinates via `setOnClick`.

## The demo scene (`main.lua`)

Interactive shapes follow a generic `sceneObjects` protocol — each object exposes `:draw()` and
`:bounds()` (required), plus optional `:hitTest()` / `:onClick()` if it should react to clicks.
The demo includes:

- A rectangle that toggles red/blue on click.
- A circle that cycles its radius (small/medium/big) on click.
- A non-interactive group (text, line, polygon).
- A background image dynamically fit to the viewport's current size.

Each frame, the scene is rendered into an offscreen canvas and a bounding-box accumulator
(`extend`) derives the viewport's scrollable content size from what was actually drawn, instead
of a hand-picked constant.

## Event routing, input consumption, and z-order

This section is written for the three main kinds of users of this code:

### 1. If you *use* the demo (end user)

- **Move** a window by dragging its orange square handle; **resize** it by dragging its cyan
  circle handle; **pan** its content by dragging its body; **scroll** with the mouse wheel
  (shift = horizontal; if only the horizontal axis overflows, plain wheel scrolls that instead).
- Windows stack like desktop windows: **pressing any part of a window raises it to the top**,
  and whichever window is on top under the pointer receives the event — nothing "bleeds" into
  windows underneath.
- A window with an opaque background blocks all input to whatever is below its frame. A window
  *without* a background is see-through to input in its empty areas: a **click** on empty space
  falls through to the window below (e.g. toggling a square that is visible through the gap),
  while a **drag** from the same empty spot still pans the transparent window itself.

### 2. If you *build scenes and windows* with these widgets (app programmer)

**Stacking (z-order of viewports).** The `viewports` list in `main.lua` is ordered bottom → top:
list position *is* the z position. Drawing walks it forward (painter's algorithm), input walks
it backward (topmost first). `addViewport(...)` pushes on top; `bringToFront(entry)` raises a
window (also done automatically on press).

**Input opacity of a viewport (does it stop events, or let them through?).** Pass
`opts.blocksInput` to `addViewport` / `Viewport.new`:

- `true` — the whole body consumes clicks/drags/wheel, even empty areas (a solid window).
- `false` — empty areas let events fall through to viewports below; only spots where a scene
  object's `hitTest` matches consume input.
- `nil` (default) — **follows the visuals**: a viewport given a background is opaque, one
  without is transparent in its empty areas.

**Z-order *inside* a scene.** Give any scene object a numeric `z` (default `0`, e.g.
`Shapes.newRectButton({ ..., z = 1 })`). Higher `z` draws on top and is hit-tested first, so
the shape you see on top is the one that gets the click. Ties draw in insertion order.

**Stopping fall-through without a background image.** Add a cover object that hit-tests its
area — `Shapes.newCoverRect({ x = 0, y = 0, w = ..., h = ..., z = -1 })` draws a translucent
panel *under* your interactive shapes and makes that whole region count as content, so clicks,
drags, and wheel stop at your scene instead of reaching windows below. Any object with a
`hitTest` behaves this way; `onClick` is optional.

**The scene-object protocol** (`shapes.lua` has examples): `:draw()` and `:bounds()` required;
optional `:hitTest(px, py)` (makes the object input-consuming), `:onClick()` (reaction), and
`z` (paint/hit order).

### 3. If you *change the routing itself* (contributor)

All routing lives in `main.lua`; `Viewport` and `Scene` only answer questions about themselves.

- **Press** (`capturePressAt`): walk viewports top → bottom; the first one whose
  `Viewport:beginDrag` reports a hit claims the press and is raised. The hit kind decides the
  capture: handles (`"move"`/`"resize"`) and body presses on content or opaque areas
  (`"pan-content"`/`"pan-opaque"`) capture *firmly*; a body press on a transparent empty area
  (`"pan-transparent"`) captures *tentatively*.
- **Pointer capture**: once claimed, all `mousemoved`/`mousereleased` (and per-id
  `touchmoved`/`touchreleased`) go only to the capturing viewport — events are never broadcast.
- **Release** (`releaseCapture`): a firm capture ends normally (`maybeFireClick` + `endDrag`).
  A *tentative* capture that stayed under the click-vs-drag movement threshold is re-dispatched:
  the walk resumes below the transparent viewport and the click fires on the topmost viewport
  with content or an opaque body at that point (which is also raised). If the pointer *did*
  move, the tentative capturer simply panned and nothing is forwarded.
- **Wheel**: goes to the topmost viewport under the cursor that has content there, is
  input-opaque, or has overflowing content to scroll (`Viewport:canScroll`); otherwise it falls
  through.
- **Opacity probe**: `Viewport:bodyInputKind(x, y)` classifies a point as
  `nil | "content" | "opaque" | "transparent"`, using the `setHitContent` predicate (wired to
  `Scene:hitTestAt`, a descending-z first-hit test) plus the `blocksInput` flag.

## Roadmap

See [ROADMAP.md](ROADMAP.md) for planned work (windows, tabs, nestable viewports).
