# Stadium Mode Requirements

## Overview

Stadium mode is a constrained generation mode for the Stadium environment, which uses a
much smaller play area (~48×48 blocks) compared to the normal 255×255×255 map.
The generator must avoid placing blocks outside the valid area by turning when it
approaches a wall, rather than continuing straight into it.

## UI

- Add a **"Stadium Mode"** checkbox in the Track Generator tab (in `ui.as`).
- Stored as `bool st_stadiumMode` in `settings.as`.
- When checked, the behavior described below applies during generation.

## Boundary Definition

The user placed marker blocks at all 8 corners of the stadium. Their coordinates from the logs:

```
<47,  9,  0>    <0,  9,  0>
<47, 39,  0>    <0, 39,  0>
<47,  9, 47>    <0,  9, 47>
<47, 39, 47>    <0, 39, 47>
```

This gives:
- **X walls**: at X=0 (West wall) and X=47 (East wall)
- **Z walls**: at Z=0 (South wall) and Z=47 (North wall)
- **Y range**: Y=9 (floor) to Y=39 (ceiling) — not relevant for horizontal wall avoidance

The hard wall coordinates are therefore fixed: `WALL_MIN_X = 0`, `WALL_MAX_X = 47`,
`WALL_MIN_Z = 0`, `WALL_MAX_Z = 47`.

These are **not** derived from `MAX_X`/`MAX_Z` at runtime — the stadium size is a known
constant. Define them as named constants in the code.

A 2-block safety margin is kept so blocks don't clip into the wall:

```
Safe X: [2 .. 45]
Safe Z: [2 .. 45]
```

The Y axis is not constrained by walls — only X and Z matter for horizontal wall avoidance.

## Wall Avoidance Logic

### When to trigger

Before placing each flat block, compute the distance from `prevPos` to the wall
ahead in `g_travelDir`:

- North (Z+): `distAhead = 45 - prevPos.z`
- South (Z-): `distAhead = prevPos.z - 2`
- East  (X-): `distAhead = prevPos.x - 2`
- West  (X+): `distAhead = 45 - prevPos.x`

If `distAhead <= STADIUM_TURN_THRESHOLD` (suggested: **4 blocks**), a turn is **forced**.

### Turn block

Always use **Curve2** for wall-avoidance turns. Curve2 takes 2 blocks in the forward
direction before exiting 90°, so it fits as long as `distAhead >= 2`.
- If `distAhead < 2`, use **Curve1** as last-resort fallback (1 block radius).

No Curve3/4/5 should be used for forced wall turns — they may not fit near the wall.

### Turn direction

- Check both perpendicular directions (left and right of `g_travelDir`) for available
  space. Prefer the direction with more room (larger `distAhead` on the new axis).
- If both sides have equal room, choose randomly (50/50).
- After the turn, `g_travelDir` is updated by `PlaceConnected` automatically (as it
  already does for any curve block).

### Interaction with slopes/tilts

Wall avoidance only triggers when `state == SurfaceState::Flat`.
If the generator is in a Slope or Tilt state when approaching a wall:
- Exit the slope/tilt first (same as the existing forced-exit logic at end-of-track).
- Then apply the wall-avoidance turn on the next flat block.

## Curve5 Exclusion

In stadium mode, `RoadTechCurve5` (and equivalent for other surfaces) must not be
placed — it is too large for a small arena and produces uninteresting layouts.

Options:
- A) Filter Curve5 out of the flat pool at `LoadPools()` time when `st_stadiumMode` is true.
- B) Skip the picked block and re-roll if it is Curve5 and stadium mode is on.

Option A is cleaner (pool is filtered once upfront).

## Block Count

Stadium tracks are naturally shorter. A sensible default when stadium mode is on
could be **20–35 blocks**, but this is still controlled by the existing `st_maxBlocks`
slider — no forced override needed.

## Notes / Open Questions

- Should the generator also avoid previously placed blocks (self-intersection)?
  Currently it relies on `CanPlaceBlock` returning false for occupied cells. This
  should already prevent overlap; verify that it works inside the small arena.
- Wall coordinates (X=0, X=47, Z=0, Z=47) are from the corner markers the user placed
  (see Boundary Definition section). They are stadium-specific constants, not derived
  from `MAX_X`/`MAX_Z` at runtime.
- Curve5 is already removed from all platform pool `.txt` files (done separately).
