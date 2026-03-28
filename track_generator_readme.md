# Track Generator V4 — How It Works

---

## Overview

Each loop iteration:
1. Compute `phase` from `state + slopeDir + tiltSide`.
2. Pick `targetState` and `targetBlock` from the matching pool (weighted random).
3. Enforce min/max run limits.
4. If `state != targetState`, insert transition blocks (`EnterSlope`, `ExitSlope`, `EnterTilt`, `ExitTilt`).
5. If `BlockSurface(targetBlock) != g_surface`, insert surface transition block(s).
6. Place `targetBlock`. On failure, run the fallback chain.

---

## Direction tracking — `g_travelDir`

Every block has a facing direction (N/E/S/W). This is not always the same as the travel direction (curves change it; reversed slope blocks are placed 180° opposite). Reading the placed block's direction is unreliable, so travel direction is tracked explicitly in a global:

```angelscript
CGameEditorPluginMap::ECardinalDirections g_travelDir;
```

- Set from the Start block at generation start.
- Updated by `PlaceConnected` passes 1 and 2 to `res.Dir` of the chosen socket.
- **Not updated** by `PlaceReversedConnected` or pass 3 — the car's physical direction does not change when blocks are reversed.
- Restored from `placedDirs[]` on every pop.

---

## Placement functions

### `PlaceConnected` (3-pass)

```
Pass 1 — prefer g_travelDir socket → updates g_travelDir
Pass 2 — any socket except backDir → updates g_travelDir
Pass 3 — backDir socket (last resort, e.g. some tilt transitions) → does NOT update g_travelDir
```

Pass 3 logs a warning. If it is reached, it usually means passes 1 and 2 found nothing useful.

### `PlaceReversedConnected`

Specifically picks the `reverseDir` (opposite of `g_travelDir`) socket from `GetConnectResults`. Does **not** update `g_travelDir`. Used for all slope-down blocks because their forward exit faces `reverseDir`.

### `PlaceFlipped`

Places the block at `reverseDir` by calling `CanPlaceBlock`/`PlaceBlock` directly with a ±1 Y offset scan. Does **not** update `g_travelDir`. Used as a fallback when `PlaceConnected` fails for bidirectional blocks (tilt transitions, surface transitions).

---

## Slope-down

All three phases use `PlaceReversedConnected`. `g_travelDir` never changes.

**Why:** slope-down blocks are placed facing `reverseDir`. Their forward exit socket also faces `reverseDir`. `PlaceConnected` pass 1 would instead grab the entry-side sockets (facing `preferDir`) and place the next block behind the previous one.

```
Flat (Y=85, going N)
  └─ SLOPE_END  placed S via PlaceReversedConnected  (g_travelDir=N)
       └─ body blocks         PlaceReversedConnected  (g_travelDir=N, Y decreasing)
            └─ SLOPE_START   placed S via PlaceReversedConnected  (g_travelDir=N)
                 Flat (Y=81, going N)
```

Entry block: `SLOPE_END` reversed (flat face connects to approaching road, slope face faces downhill).
Exit block: `SLOPE_START` reversed (slope face connects to last body block, flat face exits to next flat).

---

## Slope-up

All three phases use normal `PlaceConnected`. `g_travelDir` updated as usual.

```
Flat (going N)
  └─ SLOPE_START  PlaceConnected  (g_travelDir=N)
       └─ body blocks  PlaceConnected  (g_travelDir=N, Y increasing)
            └─ SLOPE_END  PlaceConnected  (g_travelDir=N)
                 Flat (going N, higher elevation)
```

**Exit fallback (jump-landing):** if `SLOPE_END` cannot be placed from the last body block, pop that body block and place a flat block from the previous position instead. The car jumps the height gap going uphill. This is preferable to stopping generation.

---

## Tilt transitions

`EnterTilt` tries both left and right sides. For each side:
1. `PlaceConnected` (normal orientation).
2. If that fails, `PlaceFlipped` (180° rotation, no direction change).

The tilt transition block is bidirectional — one orientation has the flat face connecting to the approaching road. Which one the engine accepts depends on approach geometry.

`ExitTilt` tries the same-side down-transition first, then the opposite-side variant.

Body blocks use side-specific pools (`tiltLeftPool` / `tiltRightPool`) so the banking direction stays consistent through the section.

---

## Surface system

### `g_surface`

```angelscript
Surface g_surface;  // SurfaceTech | SurfaceDirt | SurfaceBump | SurfaceIce
```

- Reset to `SurfaceTech` at generation start.
- Updated when a surface transition block is successfully placed.
- Restored from `placedSurfaces[]` on every pop.
- Controls which slope/tilt transition block names are used (`GetSlopeStart()`, `GetTiltUpLeft()`, etc.) and filters all pool picks via `PickFromPool()`, which strips blocks whose name prefix doesn't match `SURF_PREFIX[g_surface]` before the random draw.

### Data tables (indexed by `Surface` enum value)

```
SURF_PREFIX          — block name prefix, used by BlockSurface() to detect surface
SURF_SLOPE_START/END — slope entry/exit blocks per surface
SURF_TILT_UP/DOWN_LEFT/RIGHT — tilt transition blocks per surface (empty = no tilt)
SURF_HAS_SLOPE/TILT  — capability flags; gate wSlope/wTilt weights in the pick loop
SURF_TRANS_TABLE     — flat array [surf * 5 + phase], Tech↔surface transition block names
```

Adding a new surface: add an enum value, extend each table, create a block list file, add settings + UI.

### Surface transition placement

Surface transition blocks are bidirectional by rotation. The placement order:

1. **`PlaceConnected`** — try the normal orientation.
2. **`PlaceFlipped`** — try 180° rotation if step 1 fails; no direction change.

Same principle as tilt transitions.

### Crossing two non-Tech surfaces (e.g. Dirt → Bump)

No direct Dirt↔Bump block exists. Two transitions are inserted:

```
...RoadDirtBody → RoadTechToRoadDirt (Dirt side back) → RoadTechToRoadBump (Bump side forward) → RoadBumpBody...
```

Step 1: current surface → Tech (`SurfTransBlock(g_surface, phase)`, `PlaceConnected` or `PlaceFlipped`).
Step 2: Tech → target surface (`SurfTransBlock(targetSurface, phase)`, `PlaceConnected` or `PlaceFlipped`).

If either step fails, the target block is skipped (`continue`) and the generator picks a new block next iteration. `g_surface` stays wherever it got to — if step 1 succeeded but step 2 failed, the road is now on Tech at the step-1 block.

### Surface capability constraints

`wSlope` and `wTilt` in the pick-weight calculation are gated by `SURF_HAS_SLOPE[g_surface]` and `SURF_HAS_TILT[g_surface]`. This prevents the generator from attempting state transitions that have no transition block for the current surface (e.g. Ice has no tilt).

---

## Fallback chain (target block placement failure)

All fallbacks use surface-aware helpers (`GetStraight()`, `GetSlopeEnd()`, `GetSlopeStart()`, `PickFromPool()`) so the correct blocks are used regardless of the current `g_surface`.

0. **Undo transition** — if `stateRun == 0` (transition was just placed): remove it, reset to Flat, try a flat block from the pre-transition position.
1. **Mirror** — if the failed block name contains `Left` or `Right`, try the same block with the opposite side. Uses the same placement path (reversed for SlopeDown, normal otherwise), so `stateRun` is incremented and the state section continues uninterrupted.
2. **Flat straight** — try `GetStraight()` (surface-correct straight block) from the current position without popping.
3. **Slope escape** — pop 1 block, try: `GetSlopeEnd()` reversed → `GetSlopeStart()` forward → `PickFromPool(flatPool)`. Remove partial escape blocks if any step fails.
4. **Slope escape again** — pop 1 more block, retry escape from the new tail.
5. **Stop** — all fallbacks exhausted; keep what was placed.

---

## Parallel tracking arrays

Three arrays are maintained in sync throughout the loop. On every successful placement (including transition blocks): `InsertLast`. On every pop: `RemoveLast` + restore the global from the new last entry.

| Array | Tracks | Restored global |
|---|---|---|
| `placedCoords[]` | Block anchor coords | `prevPos` |
| `placedDirs[]` | `g_travelDir` at placement | `g_travelDir` |
| `placedSurfaces[]` | `g_surface` at placement | `g_surface` |

---

## Coordinate notes

- Trackmania uses a **left-handed** system with Y vertical.
- East = negative X, West = positive X, North = positive Z, South = negative Z.
- Slope block anchors sit at Y-1 relative to flat road level.
- `FindNewlyPlacedBlock` scans only entries appended after `PlaceBlock` (O(1)) to find the actual anchor coord, since `PlaceBlock` returns only bool.
