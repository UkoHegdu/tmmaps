# blocks.txt → Plugin Block List: Integration Proposal

## Principle

Use **Kind** and **Type** from blocks.txt to assign blocks to plugin categories. No need to name every block; use rules and name patterns.

---

## 1. Categories (from Type)

Map **Type** from blocks.txt to the plugin’s block-style categories:

| Type in blocks.txt | Plugin category / usage |
|--------------------|--------------------------|
| **Tech**           | Tech road, Platform Tech, Open Tech |
| **Dirt**           | Dirt road, Platform Dirt, Open Dirt |
| **Ice**             | Ice road, Ice Wall, Platform Ice, Open Ice |
| **Water**          | Water road |
| **Plastic**        | Plastic platform |
| **Grass**          | Grass platform, Open Grass |
| **Snow**           | Snow (if added) |
| **Rally**          | Rally (if added) |
| **Bump**           | Sausage / Bump road |
| **Scenery**        | Scenery generator pool (Deco, Obstacle, Structure, etc.) |
| **Other**          | Ignore or separate “misc” pool |

So: **all blocks with Type = Tech go under Tech**, Type = Dirt under Dirt, Type = Scenery under Scenery, etc.

---

## 2. Roles (from IdName)

Within each category, assign a **role** from the block’s **IdName** (and optionally Kind):

| Name pattern (in IdName) | Role | Used as |
|---------------------------|------|---------|
| `Start`                  | Start | RD_START |
| `Finish`                 | Finish | RD_FINISH |
| `Straight`, `Base` (road) | Straight | RD_STRAIGHT |
| `Curve1`..`Curve5`       | Turn | RD_TURN1..5 |
| `SlopeBase`, `Slope2Base`| Slope | RD_UP1, RD_UP2 |
| `Slope2Start`            | Slope2 start | RD_COOL2 (where used) |
| `Checkpoint`             | Checkpoint | RD_CP |
| `SpecialTurbo`, `SpecialBoost`, … | Special | RD_TURBO1, RD_BOOSTER1, etc. |
| `ToRoad`, `ToDecoWall`, `ToTrackWall` | Connector / end | RD_END, RD_CONNECT |
| `Deco*`, `Obstacle*`, `Structure*` (Kind = Scenery) | Scenery | SCENERY_BLOCKS |

So: **all blocks with “Tech” in Type go to Tech category**; within that, **role is decided by name** (Start, Straight, Curve, Slope, Special, …).

---

## 3. Where each block goes

- **Track blocks (Kind = Track)**  
  - Take **Type** → choose plugin **category** (Tech, Dirt, Ice, …).  
  - Take **IdName** → choose **role** (Start, Finish, Straight, Turn, Slope, Special, Connector).  
  - Add to that category’s pool for that role (e.g. all Tech + Straight → Tech RD_STRAIGHT pool).

- **Scenery blocks (Kind = Scenery)**  
  - Take **Type** (e.g. Scenery, or Dirt/Ice for themed deco).  
  - Add to **SCENERY_BLOCKS** (or a type-specific scenery pool if you split later).

- **Other (Kind = Other)**  
  - Ignore, or put in a “misc” list for future use.

No need to list every block by name: **category = Type**, **role = pattern in IdName**.

---

## 4. Implementation options

1. **Parse blocks.txt at load**  
   Build arrays per (Category, Role) from the file; use them instead of (or in addition to) hardcoded RD_*.

2. **Keep current RD_* and add “extra” from blocks.txt**  
   For each category/role, optionally extend the pool with matching blocks from blocks.txt (e.g. extra Tech straights).

3. **blocks.txt as single source of truth**  
   Replace hardcoded block names with names loaded from blocks.txt by (Type → category, IdName → role). Requires a one-time mapping from “role” to RD_START, RD_STRAIGHT, etc.

Recommendation: start with (2) so existing behaviour stays the same, and only add blocks that match Type + role from blocks.txt.
