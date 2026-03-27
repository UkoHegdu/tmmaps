# Track Generator V4 — Direction Tracking System

---

## Trackmania Coordinate System

Trackmania uses a **left-handed coordinate system** with Y as the vertical axis.

| Axis | Positive direction | Enum value | `MoveDir` result |
|------|--------------------|------------|------------------|
| X    | West               | `West`     | `int3(1, 0, 0)`  |
| X    | East               | `East`     | `int3(-1, 0, 0)` |
| Y    | Up (elevation)     | —          | —                |
| Z    | North              | `North`    | `int3(0, 0, 1)`  |
| Z    | South              | `South`    | `int3(0, 0, -1)` |

**Key points:**
- East is the *negative* X direction — moving East decreases X.
- West is the *positive* X direction — moving West increases X.
- North increases Z; South decreases Z.
- Elevation increases with Y. Slope blocks sit with their anchor at Y-1 relative to the flat road level.

**Visual vs. enum directions:** The in-game map editor may display the map with a Y-axis flip relative to real-world North/South. A block logged as `dir=N` in the script may visually appear to face South on screen. The enum directions are internally consistent for all calculations; the discrepancy is purely visual.

**Block anchor vs. connection face:** The coordinate stored in the `Blocks` array for a block is its *anchor* position, which is not always the same cell as the road entry or exit. Long blocks (2-cell slopes) have their anchor at one end. `GetConnectResults` returns positions accounting for this; always use its output coords for follow-on placements.

---

## Why direction tracking is needed

Every block has a **facing direction** (`North / East / South / West`). For straight blocks the facing direction and travel direction are the same. For asymmetric blocks — checkpoints, ramps, tilt transitions — the facing direction controls which way the car drives through it, so placing it in the wrong direction makes the car hit it backwards.

`PlaceConnected` calls `GetConnectResults(prevBlock, nextBlockInfo)`, which returns all positions where `nextBlock` can connect to `prevBlock`. This includes both the **forward exit** and the **backward entry** of the previous block — both are free sockets from the API's point of view once the track has grown past them.

Two things make reading direction from the placed block unreliable:

1. **Curves change direction.** A right-turn curve entered from the South is placed facing North, but the track exits going East. Reading `GetBlockDirection(prevBlock)` gives `North`, which is wrong.
2. **Reversed blocks corrupt the chain.** The SlopeDown entry block is placed facing 180° opposite to travel. `GetBlockDirection` would return that reversed direction, causing every subsequent block to chain backward.

The fix: carry direction explicitly as a **global variable** `g_travelDir`, updated on every successful placement.

---

## `g_travelDir` — the global travel direction

```angelscript
CGameEditorPluginMap::ECardinalDirections g_travelDir;
```

- Initialized at generation start from the Start block's facing direction.
- Updated by `PlaceConnected` to `res.Dir` of the chosen connection result after every successful placement.
- Updated by `PlaceReversed` to `reverseDir` after placing a reversed slope block.
- Restored from `placedDirs[]` when a block is popped during fallback.

---

## `PlaceConnected` — two-pass placement

```
preferDir = g_travelDir
backDir   = opposite(g_travelDir)   // (DirToInt(g_travelDir) + 2) % 4

Pass 1 — exact forward match
  For each ConnectResult where CanPlace == true:
    if res.Dir == preferDir AND CanPlaceBlock succeeds:
      place block, set g_travelDir = res.Dir, return new coord

Pass 2 — any direction except directly backward
  For each ConnectResult where CanPlace == true:
    if res.Dir == backDir: skip
    if CanPlaceBlock succeeds:
      place block, set g_travelDir = res.Dir, return new coord
```

**Pass 1** handles straight-going asymmetric blocks (ramps, checkpoints, tilt transitions) — the API returns `res.Dir == preferDir` for the forward connection.

**Pass 2** handles curves. A right-turn curve has no result matching `preferDir` (its exit is perpendicular), so pass 1 falls through. Pass 2 finds the exit connection (`res.Dir = East` for a North-going right turn), skips `backDir`, places the block, and updates `g_travelDir = East`. All blocks after the curve use the new direction.

The `backDir` filter prevents asymmetric blocks from being placed backward when the forward slot is occupied.

**Finding the placed block's coord:** `PlaceBlock()` returns only a bool. To find where the block actually landed (its anchor can differ from the coord passed to `PlaceBlock`), `FindNewlyPlacedBlock` scans only array entries appended after placement:

```angelscript
uint preLen = GetApp().RootMap.Blocks.Length;
PlaceBlock(map, blockName, dir, coord);
// scan only newly appended entries — O(1-2) instead of O(all blocks)
for (uint ak = preLen; ak < allB.Length; ak++) {
    if (allB[ak].BlockModel.IdName == blockName)
        return int3(allB[ak].CoordX, allB[ak].CoordY, allB[ak].CoordZ);
}
```

---

## Slope geometry — shared facts

**`g_travelDir` does not change during a slope section.** The car travels in the same physical direction through entry, body, and exit blocks. The slope creates an elevation change, not a direction change.

| What we call | Entry block | Body Y trend | Direction change | Exit block |
|---|---|---|---|---|
| SlopeDown | SLOPE_END reversed | decreases | None — `g_travelDir` unchanged | SLOPE_START forward |
| SlopeUp   | SLOPE_START forward | decreases | None — `g_travelDir` unchanged | SLOPE_END forward |

After the slope, flat road continues in the same direction at a different elevation level.

---

## SlopeDown — detailed implementation

### Why the entry reverses direction

SlopeDown begins by placing `SLOPE_END` facing **opposite** to the current travel direction. This is the only way to connect `SLOPE_END`'s flat face to the approaching road: the block physically acts as a ramp entry — the flat face faces the incoming car, and the slope face faces the direction the car will travel down the hill.

After the entry block `g_travelDir` is set to `reverseDir`. The car now physically travels in the opposite direction through the slope. This is a genuine switch-back: if the car was going West, it enters the slope going East, descends East, and exits East at a lower level. The rest of the track continues East.

### Entry — `PlaceReversedConnected(SLOPE_END)`

`SLOPE_END` is a **2×1 block**: its anchor coord is offset from the flat road's forward socket. Earlier code used `PlaceReversed` (raw Y±1 brute force), which could not find the correct anchor and failed consistently with `CanPlaceBlock = NO` for both Y offsets.

The fix was `PlaceReversedConnected`:

1. Call `GetConnectResults(prevBlock, SLOPE_END_info)` — the engine computes all valid snap positions.
2. Scan results for `res.Dir == reverseDir` (the "backward" connection: SLOPE_END placed facing toward us, connecting its flat face to the approaching road).
3. The engine returns exactly one such result with the correct anchor coord, one cell below flat level and offset horizontally to account for the block's length.
4. Call `CanPlaceBlock` at that coord, then `PlaceBlock`.
5. **Do NOT update `g_travelDir`.** The car's physical direction does not change.

```angelscript
auto reverseDir = IntToDir((DirToInt(g_travelDir) + 2) % 4);
map.GetConnectResults(prevBlock, SLOPE_END_info);
for each res in ConnectResults:
    if ConvertDir(res.Dir) == reverseDir and res.CanPlace:
        if CanPlaceBlock(map, SLOPE_END, reverseDir, res.Coord):
            PlaceBlock(map, SLOPE_END, reverseDir, res.Coord)
            // g_travelDir intentionally NOT updated — direction unchanged
            return FindNewlyPlacedBlock(...)
```

**Why not update `g_travelDir`:** Setting `g_travelDir = reverseDir` after this call was a critical bug. The slope does not physically reverse the car's travel direction. Flipping g_travelDir to reverseDir (e.g., W→E) would cause every subsequent block placement and curve turn decision to use the wrong direction, cascading a full East/West flip across the entire rest of the track.

Example from logs (car traveling West):
```
travelDir=W  reverseDir=E
backDir result: coord=<142, 84, 120>  dir=E    ← anchor one below flat, offset east
SLOPE_END placed facing E at <142, 84, 120>
g_travelDir stays W                            ← direction unchanged
```

### Slope body blocks

Because `g_travelDir` is unchanged (W), `PlaceConnected` uses `preferDir=W`. The body blocks' connection results from SLOPE_END report `dir=E` (backDir). They are placed by **pass 3** of `PlaceConnected`, which tries backDir results without updating `g_travelDir`:

```
body blocks: Y=83, 82, 81 going physically West  ← pass 3 places them, g_travelDir=W throughout
```

### Exit — `PlaceConnected(SLOPE_START)`

`PlaceConnected(SLOPE_START)` with `preferDir=W`. The last body block's forward socket connects to SLOPE_START. `g_travelDir` remains W throughout.

```
body at Y=81  travelDir=W
SLOPE_START placed, Y=80  dir=W
flat road resumes at lower Y, still going W
```

### Full shape

```
Flat (Y=85, going W)
  └──[SLOPE_END reversed, facing E, g_travelDir=W]──>
       slope body: Y=83, 82, 81, placed via pass 3, g_travelDir=W
       └──[SLOPE_START forward, g_travelDir=W]──>
            Flat (Y=80, going W)    ← same direction, lower elevation
```

---

## SlopeUp — implementation

### Entry — `PlaceConnected(SLOPE_START)`

`SLOPE_START` is placed in the normal forward direction via `PlaceConnected`. `g_travelDir` is unchanged — same direction throughout.

### Exit — `PlaceConnected(SLOPE_END)`

`PlaceConnected(SLOPE_END)` from the last body block. `g_travelDir` unchanged.

### Full shape

```
Flat (going W)
  └──[SLOPE_START forward, g_travelDir=W]──>
       slope body: going W, g_travelDir=W
       └──[SLOPE_END forward, g_travelDir=W]──>
            Flat (going W, different elevation)
```

---

## Slope-escape direction fix

In the slope-escape fallback, `PlaceReversedConnected(SLOPE_END)` does not change `g_travelDir`. `PlaceConnected(SLOPE_START)` may update `g_travelDir` to its result direction. The `afterSlopeEndDir` save/restore ensures the road continues in the correct direction after the escape sequence:

```angelscript
int3 p1 = PlaceReversedConnected(map, prevPos, SLOPE_END);
auto afterSlopeEndDir = g_travelDir;   // saves current direction (unchanged by PlaceReversedConnected)

int3 p2 = PlaceConnected(map, p1, SLOPE_START);
g_travelDir = afterSlopeEndDir;        // restore in case PlaceConnected changed it

int3 p3 = PlaceConnected(map, p2, escFlat);   // flat block placed in correct direction
```

---

## Tilt transitions

`EnterTilt` / `ExitTilt` use `PlaceConnected` in the normal forward direction. `g_travelDir` updates to the transition block's direction (same heading, changed banking). Side-specific pools (`tiltLeftPool`, `tiltRightPool`) ensure body blocks stay consistent with the entry banking side.

---

## Fallback chain

When a block cannot be placed:

1. **Fallback 0** — if a transition block was just placed (state changed, `stateRun == 0`): undo it, reset to Flat, try a flat block from the pre-transition position.
2. **Fallback 1** — try `RoadTechStraight` from the current position (no popping).
3. **Fallback 2** — pop 1 block, try slope-down escape: `SLOPE_END` reversed → `SLOPE_START` reversed → flat block. If any step fails, the partial slope blocks are removed.
4. **Fallback 3** — pop 1 more block (2nd-to-last), retry slope-down escape from the new tail. Same sequence; partial slope blocks are cleaned up on failure.
5. **Stop** — if all fallbacks fail, stop generation at the current block count. The partial track remains on the map for inspection.

`placedCoords[]` and `placedDirs[]` are parallel arrays tracking every placed block's position and the `g_travelDir` value at placement time. When a block is popped, `g_travelDir` is restored from `placedDirs` so the next placement attempt uses the correct direction.

---

## Variable reference

| Variable | Type | Role |
|----------|------|------|
| `g_travelDir` | `ECardinalDirections` (global) | Current physical forward direction; updated after every placement |
| `preferDir` | local in `PlaceConnected` | Pass 1 target; copy of `g_travelDir` at call time |
| `backDir` | local in `PlaceConnected` | Opposite of `preferDir`; filtered out in pass 2 |
| `reverseDir` | local in `PlaceReversed` | Opposite of `g_travelDir`; used as the block's facing direction |
| `afterSlopeEndDir` | local in slope-escape | `g_travelDir` saved after `SLOPE_END` to prevent double-flip from `SLOPE_START` |
| `slopeDir` | `SlopeDir` enum | `SlopeUp` or `SlopeDown`; controls pool selection and exit block |
| `tiltSide` | `TiltSide` enum | `TiltLeft` or `TiltRight`; controls transition block and pool |
| `placedDirs[]` | `array<ECardinalDirections>` | `g_travelDir` at time of each placement; used to restore direction on pop |
