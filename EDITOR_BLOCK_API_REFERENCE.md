# Block-related editor API reference (OpenPlanet / Trackmania)

Summary of what the game exposes for blocks and the editor. Source: OpenPlanet API docs (mp4.openplanet.dev) and this plugin’s usage. Use this to see what already exists before building new features.

---

## 1. Map / editor access

- **GetApp()** → `CGameCtnApp@`
- **app.Editor** → cast to **CGameCtnEditorFree**
- **editor.PluginMapType** → cast to **CGameEditorPluginMap** (or **CTmEditorPluginMapType** for TM)
- **GetApp().RootMap** → `CGameCtnChallenge@` (the map); **RootMap.Blocks** = array of placed blocks

---

## 2. Block placement and removal

| Method | Purpose |
|--------|--------|
| **GetBlockModelFromName(wstring)** | Get `CGameCtnBlockInfo@` from block IdName (e.g. `"RoadTechStraight"`). |
| **CanPlaceBlock(BlockModel, int3 Coord, ECardinalDirections Dir, bool OnGround, uint VariantIndex)** | Can this block be placed at Coord with Dir? |
| **PlaceBlock(BlockModel, int3 Coord, Dir)** | Place block (may destroy existing). |
| **CanPlaceBlock_NoDestruction(...)** / **PlaceBlock_NoDestruction(...)** | Same but do not destroy existing blocks. |
| **RemoveBlock(int3 Coord)** | Remove block at Coord. |
| **RemoveBlockSafe(BlockModel, int3 Coord, Dir)** | Remove knowing block type/dir. |
| **RemoveAllBlocks()** | Clear all blocks. |
| **PreloadAllBlocks()** | Preload block set (e.g. before generation). |

So: the game already gives you **test-before-place** (CanPlaceBlock) and **place / remove** at any coord + direction.

---

## 3. Connectivity (what fits after a block)

| Method | Purpose |
|--------|--------|
| **GetConnectResults(CGameCtnBlock@ ExistingBlock, CGameCtnBlockInfo@ NewBlock)** | Ask game: where can NewBlock attach to ExistingBlock? Fills **ConnectResults** array. |
| **GetConnectResultsBlockToMacroBlock(...)** | Block → macroblock. |
| **GetConnectResultsMacroBlockToBlock(...)** | Macroblock → block. |
| **GetConnectResultsMacroBlockToMacroBlock(...)** | Macroblock → macroblock. |

**ConnectResults** (array of **CGameEditorPluginMapConnectResults**):

- **CanPlace** (bool)
- **Coord** (int3)
- **Dir** (ECardinalDirections)

So: the game already answers “what can connect here?” and “at which position and rotation?” for blocks and macroblocks, including multi-cell and L-shaped blocks.

---

## 4. Reading placed blocks

| Source | What you get |
|--------|----------------|
| **map.GetBlock(int3 Coord)** | `CGameCtnBlock@` at that cell (null if none). For multi-cell blocks, one position often returns the same block. |
| **GetApp().RootMap.Blocks** | Array of all placed blocks on the map. |
| **map.Blocks** | Editor’s buffer of blocks (CGameEditorPluginMap member). |
| **map.ClassicBlocks** / **map.TerrainBlocks** | Subsets by type. |

**CGameCtnBlock** (one placed block):

- **CoordX, CoordY, CoordZ** (uint) – position (also **Coord** as nat3).
- **BlockDir** / **Dir** / **Direction** (ECardinalDirections) – orientation.
- **BlockModel** / **BlockInfo** – `CGameCtnBlockInfo@` (the block type).
- **BlockUnits** / **BlockUnitsE** – units/cells of the block.
- **Skin** – skin; **SetBlockSkin(Block, wstring)** to change.
- **WaypointSpecialProperty**, **CharPhySpecialProperty** – gameplay props.
- **Editable**, **IsGround**, **BlockInfoVariantIndex**, etc.

So: you can enumerate blocks, get position/direction/type, and change skin; the game handles multi-cell geometry.

---

## 5. Block catalog (models)

| Member / method | Purpose |
|------------------|--------|
| **map.BlockModels** | All block *types* (CGameCtnBlockInfo) available in the editor. |
| **map.TerrainBlockModels** | Terrain block types. |
| **map.MacroblockModels** | Macroblock types. |
| **GetBlockModelFromName(wstring)** | Look up by IdName. |
| **GetTerrainBlockModelFromName(wstring)** | Terrain by name. |
| **GetMacroblockModelFromName(wstring)** | Macroblock by name. |

**CGameCtnBlockInfo** (one block type):

- **IdName** (string) – e.g. `"RoadTechStraight"`.
- **Name**, **Description**, **IsRoad**, **IsTerrain**, **IsPodium**, **IsClip**.
- **WayPointType** / **EdWaypointType** – Start, Finish, Checkpoint, None, etc.
- **VariantGround** / **VariantBaseGround**, **AdditionalVariantsGround** – variants.
- **IsPillar**, **PillarShapeMultiDir**, **SymmetricalBlockInfoConnected** – geometry/symmetry.
- **CharPhySpecialProperty** – physics/special behaviour.

So: you can list all block types and read metadata (road/terrain, waypoint type, variants) without building your own list.

---

## 6. Ghost blocks (preview)

- **CanPlaceGhostBlock(BlockModel, int3 Coord, Dir)** – can a ghost be shown here?
- **PlaceGhostBlock(BlockModel, int3 Coord, Dir)** – show ghost (preview) at Coord.

Useful for “show where the next block would go” without placing.

---

## 7. Road / terrain in a range

- **CanPlaceRoadBlocks(BlockModel, int3 StartCoord, int3 EndCoord)**  
- **PlaceRoadBlocks(BlockModel, StartCoord, EndCoord)**  
- **CanPlaceTerrainBlocks(...)** / **PlaceTerrainBlocks(...)** / **PlaceTerrainBlocks_NoDestruction(...)**  
- **RemoveTerrainBlocks(int3 StartCoord, int3 EndCoord)**

Useful for filling a rectangle of road or terrain.

---

## 8. Macroblocks

- **CanPlaceMacroblock(MacroblockModel, int3 Coord, Dir)** / **PlaceMacroblock(...)**  
- **CanPlaceMacroblock_NoDestruction** / **PlaceMacroblock_NoDestruction**  
- **CanPlaceMacroblock_NoTerrain** / **PlaceMacroblock_NoTerrain**  
- **RemoveMacroblock(...)**  
- **GetMacroblockModelFromName(wstring)**  
- **CreateMacroblockInstance(...)** / **CreateMacroblockInstanceWithUserData(...)**  
- **GetMacroblockInstanceFromOrder(uint)** / **GetMacroblockInstanceFromUnitCoord(int3)**  
- **GetLatestMacroblockInstance()** / **GetLatestMacroblockInstanceWithOffset(uint)**  
- **GetMacroblockInstanceConnectedToClip(Clip)**  
- **RemoveMacroblockInstance(...)** / **RemoveMacroblockInstancesByUserData(int)**  
- **ResetAllMacroblockInstances()**  
- **map.MacroblockInstances** – all macroblock instances.

So: full support for placing, removing, and resolving macroblocks by coord or order; connectivity APIs exist for block↔macroblock and macroblock↔macroblock.

---

## 9. Skins and appearance

- **IsBlockModelSkinnable(BlockModel)**  
- **GetNbBlockModelSkins(BlockModel)**  
- **GetBlockModelSkin(BlockModel, uint SkinIndex)**  
- **GetBlockSkin(Block)** / **SetBlockSkin(Block, wstring SkinFileName)**  
- **GetSkinDisplayName(wstring)**  
- **OpenBlockSkinDialog(Block)**  
- **NextMapElemColor** – set next placed block color (e.g. **CGameEditorPluginMap::EMapElemColor**).

So: list skins for a type, get/set skin on a placed block, and set default color for next placement.

---

## 10. Cursor and selection (editor state)

- **map.CursorCoord** (nat3) – cursor cell.  
- **map.CursorDir** (ECardinalDirections) – cursor direction.  
- **map.CursorBlockModel** / **CursorTerrainBlockModel** / **CursorMacroblockModel** – current block in cursor.  
- **GetMouseCoordOnGround()** / **GetMouseCoordAtHeight(uint CoordY)** – mouse → coord.  
- **map.PlaceMode** – Block, Macroblock, GhostBlock, CopyPaste, etc.  
- **map.EditMode** – Place, Erase, Pick, SelectionAdd, SelectionRemove, etc.  
- **CopyPaste_Copy()** / **CopyPaste_Cut()** / **CopyPaste_Remove()** / **CopyPaste_SelectAll()** / **CopyPaste_ResetSelection()**  
- **CopyPaste_AddOrSubSelection(int3 StartCoord, int3 EndCoord)**  
- **CopyPaste_Symmetrize()**  
- **map.CustomSelectionCoords** – custom selection list.  
- **ShowCustomSelection()** / **HideCustomSelection()**  

So: you can read “block under cursor” and cursor coord/dir, and use copy/paste and custom selection.

---

## 11. Ground and height

- **GetBlockGroundHeight(BlockModel, int CoordX, int CoordZ, Dir)** – ground height for that block type at that cell.  
- **GetGroundHeight(int CoordX, int CoordZ)** – current ground height.  

Useful for placing blocks “on ground” or at a given height.

---

## 12. Map / gameplay counts

- **GetStartBlockCount(bool IncludeMultilaps)**  
- **GetFinishBlockCount(bool IncludeMultilaps)**  
- **GetMultilapBlockCount()**  
- **GetCheckpointBlockCount()**  
- **GetStartLineBlock()** – get start block.  
- **map.Map** – CGameCtnChallenge (map root).  
- **map.MapName** / **map.MapFileName**  

So: you can count starts/finishes/checkpoints/multilaps and get the start block without scanning.

---

## 13. Testing and saving

- **TestMapFromStart()** / **TestMapFromCoord(int3 Coord, Dir)** – test drive from start or from a coord.  
- **TestMapWithMode(wstring RulesModeName)** / **TestMapWithMode2(..., string SettingsXml)**  
- **SaveMap(wstring FileName)** / **SaveMapCompat(FileName, Path)**  
- **AutoSave()**  
- **Undo()** / **Redo()**  

Useful for “generate then test” or “save variant” workflows.

---

## 14. Other editor state

- **map.IsEditorReadyForRequest** – wait before async placement/removal.  
- **map.BlockStockMode**, **map.UndergroundMode**  
- **map.Inventory** – block inventory.  
- **map.Items** – anchored objects (e.g. items).  
- **RemoveItem(Item)**  
- **ComputeShadows()** / **ComputeShadows1(EShadowsQuality)**  
- **SetMapType(wstring)** / **GetMapType()**  
- **SetMapStyle(wstring)** / **GetMapStyle()**  

---

## What you don’t have to build yourself

- **“What can connect after this block?”** → **GetConnectResults** + **ConnectResults** (position + rotation).  
- **“Can I place this block here?”** → **CanPlaceBlock** / **CanPlaceGhostBlock**.  
- **“List all block types”** → **BlockModels** (and TerrainBlockModels, MacroblockModels).  
- **“List all placed blocks”** → **RootMap.Blocks** or **map.Blocks**.  
- **“Block under cursor”** → **CursorCoord** + **GetBlock(CursorCoord)** (and **CursorBlockModel** for current tool).  
- **“Where would the next block go?”** → **GetConnectResults** or **CanPlaceBlock** at candidate coords.  
- **“Multi-cell / L-shaped / 6-cell block”** → same APIs; game handles geometry and returns valid connection results.  
- **“Rotations that fit”** → **ConnectResults** array contains one result per valid placement (each with Dir).  

---

## Possible features to build on top

1. **Connectivity table** – For each block type (or each “role”), call GetConnectResults with every other track block and store results → “suitable next blocks” per block type.  
2. **“Block under cursor” actions** – Use CursorCoord + GetBlock to run “find suitable blocks” or “log block info” on the cell under the cursor.  
3. **Ghost preview** – Use PlaceGhostBlock / CanPlaceGhostBlock to show where the next block would go before placing.  
4. **Symmetry / copy-paste** – Use CopyPaste_* and CustomSelectionCoords to duplicate or mirror segments.  
5. **Start/finish/CP stats** – Use GetStartBlockCount, GetFinishBlockCount, GetCheckpointBlockCount in validators or UI.  
6. **Skin/color automation** – Use SetBlockSkin and NextMapElemColor for themed or random styling.  
7. **Macroblock scripts** – Use macroblock instance APIs to place or replace large prefabs by coord or order.  
8. **Test from position** – Use TestMapFromCoord to test from a specific block (e.g. after a slope/turn).  

Reference: [OpenPlanet API – CGameEditorPluginMap / CTmEditorPluginMapType](https://mp4.openplanet.dev/TrackMania/CTmEditorPluginMapType) and linked types (CGameCtnBlock, CGameCtnBlockInfo, CGameEditorPluginMapConnectResults).
