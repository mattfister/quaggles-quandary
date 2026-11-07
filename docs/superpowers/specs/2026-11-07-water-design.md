# Water — Design

Date: 2026-11-07

Minecraft-flavoured water for Quaggle's Quandary: sources emit water that
spreads over floors, falls off edges, and fills enclosed pits. Quaggles dam
shallow water and float in deep water. Water is recomputed from scratch after
every move (instant settling) and animated as a ripple.

## Rules

### Water kinds

A new tile, the **source** (`~`), emits water. Every water cell is one of:

- **Flowing** (shallow): spreads across floors, losing one strength per cell.
  A source has strength 4, so flow reaches 3 cells out. It spreads equally in
  all four directions; there is no Minecraft-style pathing toward drops. Where
  two flows meet, a cell takes the higher strength.
- **Falling**: when flowing water reaches a cell with nothing solid beneath
  it, it falls straight down. Where it lands it continues at full strength.
  Falling below floor 0 drains into the void: the water is gone.
- **Pool**: when falling water lands in a region enclosed by terrain, it fills
  that region level by level, up to the lower of (a) the last fully enclosed
  level and (b) the level the water fell from. Above that, it spreads as
  flowing water. Enclosure is judged on terrain only, never on quaggles. Only
  falling water creates pools; a source in a walled room just flows.

**Deep** water is sources and pools. Flowing and falling water are not deep.

### What water occupies

Water can be in air cells and in the cells quaggles stand in: ground, start,
ice, key, crack, goal, fire. Walls, windows, forcefields and lifts block it.
Water is an overlay: it never changes the grid, except that water reaching a
FIRE cell turns it to GROUND permanently.

Changing terrain changes the water: keying a forcefield or crumbling a crack
can release a flood.

### Quaggles and water

- **Dams**: a standing quaggle is solid to flowing and falling water. A
  stack blocks water on every floor it fills. Falling water that lands on a
  quaggle's head spreads from there. Swimmers, and anyone standing on a
  swimmer, do not dam: otherwise a floated stack's rider could cut off the
  stream keeping its pit full, and the water would flicker on and off. Since
  who swims depends on the water, it is worked out starting with no dams and
  adding those the water shows until there are no new ones.
- **Pools ignore quaggles**: a pool fills around quaggles in it.
- **Floating**: a quaggle in deep water rises to the top of the deep water in
  its column, and its stack rides on its head. The riders above the surface
  move normally.
- **Swimming**: deep water holds a swimmer up. A swimmer moves freely unless
  someone stands on its head, in which case it cannot move. A quaggle carrying
  riders cannot step into deep water; a lone quaggle can. A stack may step onto
  a swimmer's head.
- **Wading**: in shallow (flowing) water, quaggles walk, carry and slide on ice
  exactly as without water. A slide that reaches deep water stops there and
  the quaggle floats.
- **Waterfalls**: the base of a falling column (the cell it lands in) cannot be
  entered from the side. Elsewhere, falling water is air to quaggles: they may
  step into it only where the usual landing rule allows, and fall through it.
  A quaggle falling down a column lands in the base cell normally.

### Settling order per move

move → gravity → water → floating → repeat water and floating until nothing
changes → gravity.

Floating only ever moves quaggles up, so the loop ends; it is capped at
`floors * 2` passes, logging an error if the cap is hit.

## Architecture

### `scripts/water.gd` (new)

`class_name Water extends RefCounted`. Pure logic, no nodes, like `Rules`.

`static func compute(r: Rules)` reads the grid, sources and standing quaggle
positions, and returns per-cell water kind and strength, plus each cell's BFS
distance from its source (used for animation). Pools are found by a per-level
flood fill over terrain.

### `scripts/rules.gd`

- `const SOURCE := 126  # '~'`.
- `var water` holds the current water, always derived from state. It is not
  part of `snapshot()`; `restore()` recomputes it, so undo and the solver need
  no changes.
- `try_move` calls a new `_settle_water()` after `_settle()`, implementing the
  settling order above.
- `_holds`: deep water holds a quaggle.
- `_can_enter`: a quaggle with riders cannot enter deep water; no quaggle can
  enter a waterfall base from the side.
- `_step`: a swimmer with a rider refuses to move.
- Extinguished fire uses the existing `cell` event.
- Levels with no source skip all water work, so existing levels and solver
  speed are unaffected.

### Events

- `{type: "water", added: [{pos, kind, level, delay}], removed: [{pos, delay}]}`:
  the diff from the previous water state. `delay` is BFS distance.
- Floating reuses `move` events with `float: true`, played after the water
  reaches the quaggle.

## View

- `scripts/water_view.gd` (new): a node owned by `world.gd` (already ~1000
  lines) that builds and updates water meshes from `rules.water` and plays
  `water` events.
- `shaders/water.gdshader` (new): translucent, matching the toon look,
  scrolling streaks, edge foam.
  - Flowing: a thin sheet on the floor, thinner at lower strength.
  - Pool: fills the cell to the surface, gently moving top.
  - Falling: a vertical sheet scrolling downward, with a splash ring at the
    base. Into the void, the sheet continues past the island base and breaks
    into fading spray.
  - Source: a bubbling spout.
- Ripple: added cells grow in after `delay * ~0.05s`; removed cells drain in
  reverse. Pools rise level by level. `play()` holds float moves until the
  water reaches them and counts water time in its returned duration.
- Undo snaps water to the restored state without animation.

## Editor

- Add `~` to `TILES` in `scripts/editor/level_editor.gd`.
- Draw it in `scripts/editor/editor_grid.gd`.
- The 3D preview gets water through the world.

## Testing

New cases in `tests/test_rules.gd`:

- Flow reaches exactly 3 cells; falls off edges; drains into the void.
- Pool fills to its rim; pool capped by the level the water fell from.
- A quaggle dams flow; moving away releases it.
- A stack in a flooding pit floats up; riders above the surface can move.
- A stack cannot step into deep water; a swimmer with a rider cannot move.
- Waterfall base blocks sideways entry; stepping into a column over nothing
  is refused; a column over the void does not hold a quaggle.
- Water extinguishes fire; keying a forcefield releases a flood.
- Undo restores the water.

## Out of scope

- Designing water levels (after the mechanic works).
- Currents pushing swimmers.
- Freezing water into ice.
