# Track Generator V4 — Direction Tracking System

## Why direction tracking is needed

Every block in Trackmania has a **facing direction** (North / East / South / West) stored as
`BlockDir`. For a simple straight block the facing direction and the direction the track travels
through the block are the same thing. For asymmetric blocks — ramps, checkpoints, boosts, tilt
transitions — the direction the block *faces* is what determines which way the car drives over
it, so placing it in the wrong direction means the car hits it backwards.

The core placement routine `PlaceConnected` calls `GetConnectResults(prevBlock, nextBlockInfo)`.
The API returns a list of positions and directions where `nextBlock` could connect to `prevBlock`.
The list includes *all* valid connections, both forward (the exit of the previous block) and
backward (the entry of the previous block, which is still a free socket from the API's point of
view once the track has been built far enough that the entry isn't occupied).

Before the refactor, `PlaceConnected` inferred the travel direction by reading
`GetBlockDirection(prevBlock)` — the direction the previous block was placed with. Two things
make this unreliable:

1. **Curves change direction.** A right-turn curve entered from the South is placed facing North,
   but the track exits going East. The next `PlaceConnected` call would read `North` as the
   preferred direction, which is wrong for picking connections off the curve's East exit.

2. **Reversed blocks corrupt the chain.** The SlopeDown entry block is placed with the
   *opposite* of the travel direction. Once placed, `GetBlockDirection` would return that
   reversed direction, causing every subsequent block to chain backward.

The fix is to stop reading direction from the placed block and instead carry it explicitly as a
`travelDir` parameter threaded through every placement call.

---

## The `travelDir` parameter

```angelscript
int3 PlaceConnected(CGameEditorPluginMap@ map, int3 prevPos,
                    const string &in blockName,
                    CGameEditorPluginMap::ECardinalDirections &inout travelDir)
```

`travelDir` is declared `&inout`:
- **In:** the caller provides the current forward direction before placement.
- **Out:** after a successful placement the function writes back the direction that was actually
  used. For straight/slope/special blocks this is the same as the input. For curves it becomes
  the exit direction of the curve — because the chosen connection result will have a `res.Dir`
  that points where the car is heading *after* the curve.

The variable is initialized at generation start from the Start block's own direction and then
passed through every placement call for the entire generation loop.

---

## Pass 1 and Pass 2 inside `PlaceConnected`

```
preferDir = travelDir
backDir   = opposite(travelDir)   // (travelDir + 2) % 4

Pass 1 — exact forward match
  For each ConnectResult:
    if res.Dir == preferDir AND block can be placed:
      place it, set travelDir = res.Dir, return

Pass 2 — any direction except directly backward
  For each ConnectResult:
    if res.Dir == backDir: skip          ← the new filter
    if block can be placed:
      place it, set travelDir = res.Dir, return
```

**Pass 1** handles all straight-going asymmetric blocks (ramps, checkpoints, boosters, tilt
transitions) because the API returns a result with `res.Dir == travelDir` and that result is
the forward connection. Pass 1 picks it, the block faces the right way.

**Pass 2** handles curves. A right-turn curve has no connection result matching `preferDir`
(because its exit is perpendicular), so pass 1 falls through. Pass 2 finds the exit connection
(`res.Dir = East` for a North-going right turn), skips any backward result (`South`), places
the block, and updates `travelDir = East`. All blocks placed after the curve now use the
correct direction.

The `backDir` filter in pass 2 is what prevents asymmetric blocks from being placed backward
when the forward slot is occupied (e.g. when a collision forces a fallback). Before this filter,
pass 2 would accept any direction including directly backward, which caused checkpoints and
ramps to face the wrong way.

---

## Ascending slopes (SlopeUp)

Entry uses `SLOPE_START` placed with `PlaceConnected` in the normal forward direction.
`GetConnectResults` finds the flat-end connection, places the block going upward, and
`travelDir` stays forward (or updates to the same direction for a straight slope).

Exit uses `SLOPE_END` the same way — placed forward, the block descends from slope level back
to flat.

```
Flat ──[SlopeStart]──> Slope body ──[SlopeEnd]──> Flat
         ascends                      descends
         travelDir unchanged throughout
```

---

## Descending slopes (SlopeDown)

### Entry — `PlaceReversed(SLOPE_END, travelDir)`

The key insight the user identified: to start a descent from flat, you place `SLOPE_END`
**rotated 180°** relative to the travel direction. Normally `SLOPE_END` goes from slope-level
(high, entry) to flat (low, exit). Rotated 180°, the flat end faces backward (toward the
previous block) and the slope end faces forward — so the track goes *downward* from the current
flat level into a lower slope level.

`PlaceReversed` computes `reverseDir = opposite(travelDir)` and probes positions 1–4 cells
forward of the previous block, calling `CanPlaceBlock` with `reverseDir` at each offset until
one succeeds. `travelDir` is **not modified** by `PlaceReversed` — the track is still going in
the same forward direction even though the physical block faces backward.

### Why 50% chance?

```angelscript
if (MathRand(0, 1) == 0) {          // 50% chance to attempt descent
    int3 newPos = PlaceReversed(...);
    if (newPos.x >= 0) { ... return descent; }
    // if PlaceReversed fails, fall through to ascending
}
// ascending path always reachable
```

The 50/50 split is simply a variety control. When the generator decides to add a slope section,
it randomly chooses whether to *try* a descent. If the descent placement fails (the API rejects
the reversed block — e.g. there is no room below the current terrain), it falls back to an
ascending slope automatically. The actual rate of descents will be ≤ 50% depending on how often
`PlaceReversed` succeeds at the current track position.

### Mid-slope body blocks

After a reversed `SLOPE_END`, `travelDir` still points forward. The next `PlaceConnected` call
for a body block asks `GetConnectResults(reversedSlopeEnd, bodyBlockInfo)`. Because TM2020's
connectivity system works relative to the block's actual connection sockets (not just its
direction field), it should find the forward-going socket at the slope end of the reversed
block and chain correctly.

### Exit — `PlaceReversed(SLOPE_START, travelDir)` with fallback

To end a descent, `SLOPE_START` is placed reversed. Normally `SLOPE_START` goes from flat
upward to slope-level. Reversed, its flat end faces backward and the slope end faces forward,
so the track goes from the current (lower) slope level forward and downward to a new lower flat
level.

**Fallback:** if `PlaceReversed(SLOPE_START)` fails, `ExitSlope` falls back to
`PlaceConnected(SLOPE_END)`. From the lowered slope position, a normal `SLOPE_END` going
forward will bring the track *back upward* toward the original flat level — a V-shaped valley
instead of a clean descent to a new lower flat. The geometry is not ideal but the `Slope` state
is exited cleanly and generation can continue.

```
Flat ──[SlopeEnd reversed]──> Slope body ──[SlopeStart reversed]──> lower Flat
          descends                                exits down
                                    OR on fallback:
                              ──[SlopeEnd normal]──> original Flat
                                    ascends back up (V-shape)
```

---

## Tilt transitions

Tilt blocks (`TiltTransition1UpLeft/Right`, `TiltTransition1DownLeft/Right`) follow the same
`PlaceConnected` path with `travelDir &inout`. `travelDir` updates to the direction of the
placed transition block, which for tilt is the same as the forward travel direction (tilt
changes banking, not compass heading). The side-specific pools (`tiltLeftPool`, `tiltRightPool`)
ensure the body blocks match the banking side chosen at entry.

---

## Summary of variables and their roles

| Variable | Type | Meaning |
|---|---|---|
| `travelDir` | `ECardinalDirections &inout` | Explicit forward travel direction; updated after every `PlaceConnected` success |
| `preferDir` | local copy of `travelDir` | What direction pass 1 tries to match |
| `backDir` | `opposite(preferDir)` | Direction that pass 2 refuses to use |
| `slopeDir` | `SlopeDir` enum | Whether current slope section is ascending or descending; controls which pool and which exit block |
| `tiltSide` | `TiltSide` enum | Left or right banking; controls which transition block and pool |

---

## What `travelDir` does NOT change

- **`PlaceReversed`** does not take `travelDir` as `&inout`. The block is placed backward but
  the track's forward direction is unchanged. This is intentional: the reversed block is a
  physical detail of the slope geometry; the generator's conceptual direction of travel remains
  forward throughout.

- **After a curve**, `travelDir` updates to the curve's *exit* direction via the `res.Dir` of
  the chosen pass 2 result. From that point all subsequent blocks use the post-curve direction
  as their `preferDir`, which is why ramps and checkpoints placed immediately after curves now
  face correctly.
