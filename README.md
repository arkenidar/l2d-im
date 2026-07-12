# rules-shape

A LÖVE2D/Lua sandbox for a scrollable, clippable "viewport" widget and click-reactive scene
objects.

## Running

Requires the [LÖVE](https://love2d.org/) engine (tested with `love .`).

```sh
love .
```

## Project layout

- `main.lua` — the demo scene and all `love.*` callbacks.
- `viewport.lua` — the `Viewport` widget.
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

## Roadmap

See [ROADMAP.md](ROADMAP.md) for planned work (windows, tabs, nestable viewports).
