# Roadmap

## Windows, tabs, and nestable viewports

**Goal**: generalize from a single global `Viewport` into a desktop/browser-like UI — multiple
top-level `Window`s (draggable title bar, resizable), where a window can host either one
`Viewport` or a tab strip of several (each tab with independent content, not shared — like
browser tabs). `Viewport` itself becomes nestable: one viewport's content can contain another
viewport, recursively.

**Demo target**: 3 viewports total — Window A with 1 viewport (plus one nested child viewport
inside it, proving nesting works), Window B with a 2-tab strip, one viewport per tab with
independent scenes.

**Known technical gotcha to solve**: LÖVE's `setScissor` / `intersectScissor` rectangles are in
absolute screen pixels, unaffected by the current transform (translate/push). A nested child
viewport's `x, y` are expressed in its *parent's* content-space, not absolute screen space, so
they must be converted via `love.graphics.transformPoint` before clipping. `intersectScissor`
(not `setScissor`) must be used so nested clip regions compose instead of one level clobbering
another's.

This entry is a pointer/summary of a design drafted in an earlier planning pass; the full spec
(new `Window` widget, `Viewport` child-list + chrome-toggle + recursive input routing, per-window
independent scene/canvas ownership, window-level focus/z-order) can be re-derived in a follow-up
planning session before implementation starts.
