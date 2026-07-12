# Expected behavior: viewports, nesting, and input routing

This documents the intended behavior of the `Viewport` / `Scene` / stack
system in `viewport.lua`, `scene.lua`, and the router in `main.lua`. It's
a reference for what "correct" looks like — useful when changing the
routing code, since the interactions between z-order, input opacity,
and nesting are easy to get subtly wrong (see the Known regressions
section for real examples from this codebase's history).

## Stacking and z-order

- Viewports live in ordered lists: the root `viewports` list in
  `main.lua`, and each `Viewport`'s own `children` list. In both cases
  the list index **is** the z-order, bottom to top.
- Drawing walks a list forward (painter's algorithm — first entry
  drawn first, last entry drawn on top). Input routing walks a list
  backward (topmost entry gets first claim).
- `bringToFront` moves an entry to the end of *its own* list, like
  raising a window. Clicking or dragging anything inside a viewport —
  its content, an opaque empty area, or one of its own handles —
  raises that viewport within its siblings.
- **A nested capture only reorders the list it actually landed in.**
  Grabbing a deeply nested child's handle must NOT also raise that
  child's ancestors within their own (outer) sibling lists. Ancestors
  keep their existing z-order relative to their own siblings; only the
  level containing the interacted-with entry gets reordered.

## Input opacity (fall-through)

Each viewport body classifies a pointer position as one of:

- `content` — a scene object is under the pointer.
- `opaque` — empty area, but `blocksInput` is true: the viewport still
  claims it.
- `transparent` — empty area, `blocksInput` is false: input should
  fall through to whatever is stacked below.
- (outside the body entirely — not classified)

A press on `content` or `opaque` claims the gesture firmly. A press on
`transparent` claims it *tentatively*: a drag still pans that
viewport, but if the gesture ends as a plain click without having
moved, the click is re-dispatched to the first sibling **below** (in
the same list) that has content or an opaque body there, raising it.
This fall-through search is scoped to the capture's own list — it does
not also search the ancestor's siblings if a nested child's fall-through
search comes up empty.

Wheel events use the same classification, additionally consuming the
event for a `transparent` body that has overflowing content
(`canScroll()`), since a scrollable pane should still catch the wheel
over its own empty margins.

## Handles (move / resize)

- The origin handle (move) is centered *on* the viewport's top-left
  corner; the resize handle is centered on the bottom-right corner.
  Both extend **outside** the body rectangle by their own
  half-size/radius.
- Grabbing a handle must work across its *entire* hit area, including
  the half that sticks out past the body rectangle — a click there is
  outside `hitBody` but must still register as `hitOrigin`/`hitResize`.
- Handles take priority over content/pan: `beginDrag` checks
  `hitOrigin`/`hitResize` before falling back to body classification.
- Consequently, checking a viewport's own handles must never be gated
  on that viewport's own `hitBody` test. (`hitBody` **is** the correct
  gate for deciding whether to descend into a viewport's *children* —
  children only ever live inside the parent's clipped body — but it
  must not also gate the parent's own handle check.)

## Nesting

- A viewport's `children` are drawn and hit-tested inside its own
  content space: a child's `x`/`y` are expressed in the parent's
  content-space (the same space `toContent()` produces), not absolute
  screen coordinates.
- Children are clipped to their parent — including their own handles.
  A child's clip composes with its ancestors' (`intersectScissor`, not
  `setScissor`), so a handle sticking out of the child's own frame is
  still cut off at the parent's frame edge.
- Children pan and scroll with the parent's content, since they're
  drawn after the parent's own scroll translation is applied.
- Input routing descends into a viewport's children **before**
  checking that viewport's own body, so the topmost nested content
  always wins over the parent's own content/opaque body at the same
  screen position.
- A capture on a nested entry must track the chain of ancestor
  viewports whose `toContent` conversion was applied to reach it, so
  that later raw-screen-coordinate events (mouse/touch move and
  release) can be converted into the same coordinate space the capture
  was seeded in before being applied.

## Click vs. drag

- A press that moves less than the click-move threshold before release
  counts as a click, not a drag, regardless of which `dragMode` it
  began in.
- A firm click (content/opaque) fires the viewport's `onClick` in its
  own content-space.
- A tentative click (started on a transparent empty area, stayed a
  click) does *not* fire that viewport's own `onClick` — it searches
  below for something to redirect to instead (see Input opacity above).

## Known regressions (do not reintroduce)

These are real bugs introduced while adding nesting, kept here as
regression notes:

1. **Ancestor z-order leak.** Calling `bringToFront` for every ancestor
   level while unwinding a nested capture raises the whole ancestor
   chain, not just the level that was actually interacted with. This
   visibly reshuffles unrelated sibling windows — e.g. grabbing a
   nested child's handle would raise its parent above an unrelated
   sibling, which looked like the sibling's content had shifted or
   been clipped.
2. **Handles gated on `hitBody`.** Gating a viewport's own
   `beginDrag` call behind its own `hitBody` check breaks grabbing the
   outer half of every handle (parent and nested alike), since handles
   are only half-inside the body rectangle by design.
3. **Mismatched coordinate spaces across a gesture.** Seeding
   `beginDrag` with content-space coordinates (necessary for nested
   hit-testing) but then feeding raw screen coordinates into
   `dragTo`/`endDrag` for the rest of the gesture produces a
   coordinate jump on nested drags. Every event in a captured gesture
   must be converted through the same ancestor chain used at capture
   time.
