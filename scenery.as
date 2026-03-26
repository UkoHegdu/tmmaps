// Scenery Generator V1.
// Pass 1 (close): places DecoHillSlope / DecoHillDeadendSlope blocks on both sides of each
//   track block, at a random height offset of -2..+2 relative to the track block.
// Pass 2 (far): places DecoCliff10Straight 10 cells to both sides of each track block,
//   at the same Y level used for close scenery (or track Y if close placement failed).
//
// Tracks placed coords in lastSceneryCoords so CancelScenery can remove them selectively.
//
// Safety limits:
//   - Skips entirely if the track has more than MAX_SCENERY_BLOCKS blocks.
//   - Each IsEditorReadyForRequest wait is capped at MAX_WAIT_YIELDS iterations.
//   - Each placement attempt is wrapped in try/catch so a bad block never freezes.

const int MAX_SCENERY_BLOCKS = 50;
const int MAX_WAIT_YIELDS    = 2000;  // ~2 s at 1 ms/yield before giving up

array<int3> lastSceneryCoords;

// ── Block name pools ──────────────────────────────────────────────────────────

array<string> CLOSE_SCENERY_BLOCKS = {
	"DecoHillSlope2Straight",
	"DecoHillSlope2StraightX2",
	"DecoHillDeadendSlope2StraightLeft",
	"DecoHillDeadendSlope2StraightRight"
};

const string FAR_SCENERY_BLOCK = "DecoCliff10Straight";

// ── Helpers ───────────────────────────────────────────────────────────────────

// Returns true if a block name belongs to the background (should not get scenery placed next to it).
bool IsSceneryOrGrass(const string &in name)
{
	return name.StartsWith("Deco") || name == "Grass" || name.StartsWith("TrackWall");
}

// Safe IsEditorReadyForRequest wait with a yield cap.
// Returns false if the cap was hit (editor unresponsive).
bool WaitEditorReady(CGameEditorPluginMap@ map)
{
	int n = 0;
	while (!map.IsEditorReadyForRequest) {
		yield();
		if (++n >= MAX_WAIT_YIELDS) {
			TGprint("\\$f00Scenery: editor unresponsive after " + tostring(MAX_WAIT_YIELDS) + " yields — skipping.");
			return false;
		}
	}
	return true;
}

// Try to place blockName at pos in each of the 4 directions.
// Returns the direction used, or -1 on failure/error.
// Appends pos to the given coord list on success.
int TryPlaceScenery(CGameEditorPluginMap@ map, const string &in blockName, int3 pos, array<int3>@ placed)
{
	// Validate block model exists before attempting anything.
	auto info = map.GetBlockModelFromName(blockName);
	if (info is null) {
		TGprint("\\$f00Scenery: block model not found: " + blockName);
		return -1;
	}

	for (int d = 0; d < 4; d++) {
		try {
			auto dir = IntToDir(d);
			if (!WaitEditorReady(map)) return -1;
			if (map.CanPlaceBlock(info, pos, dir, true, 0)) {
				if (!WaitEditorReady(map)) return -1;
				if (map.PlaceBlock(info, pos, dir)) {
					placed.InsertLast(pos);
					return d;
				}
			}
		} catch {
			TGprint("\\$f00Scenery: exception placing " + blockName + " at " + tostring(pos) + " dir " + tostring(d) + " — skipping.");
		}
	}
	return -1;
}

// ── Main ──────────────────────────────────────────────────────────────────────

void BeginScenery()
{
	uint64 before = Time::get_Now();

	auto app = cast<CTrackMania>(GetApp());
	if (app is null) return;
	auto editor = cast<CGameCtnEditorFree>(app.Editor);
	if (editor is null) { UI::ShowNotification("Editor not open!"); return; }
	auto map = cast<CGameEditorPluginMap>(editor.PluginMapType);
	if (map is null) return;

	// ── Use the last V4 run coords as the track block list ───────────────────
	// Iterating RootMap.Blocks counts terrain/ground blocks (~65k) which
	// swamps the 50-block limit and the IsSceneryOrGrass filter misses them.
	// Using lastRunCoords gives exactly the blocks we just generated.

	array<int3> trackCoords;
	array<CGameEditorPluginMap::ECardinalDirections> trackDirs;

	for (uint i = 0; i < v4::lastRunCoords.Length; i++) {
		int3 coord = v4::lastRunCoords[i];
		auto block = GetBlockAt(map, coord);
		if (block is null) continue;
		string name = block.BlockModel.IdName;
		if (IsSceneryOrGrass(name)) continue;
		trackCoords.InsertLast(coord);
		trackDirs.InsertLast(GetBlockDirection(block));
	}

	if (trackCoords.Length == 0) {
		UI::ShowNotification("Scenery: no track blocks from last run. Generate a track first.");
		return;
	}

	// ── Block-count safety limit ──────────────────────────────────────────────

	if (int(trackCoords.Length) > MAX_SCENERY_BLOCKS) {
		TGprint("\\$f00Scenery: skipping — track has " + tostring(trackCoords.Length)
			+ " blocks (limit " + tostring(MAX_SCENERY_BLOCKS) + ").");
		UI::ShowNotification("Scenery skipped: track has " + tostring(trackCoords.Length)
			+ " blocks (max " + tostring(MAX_SCENERY_BLOCKS) + ").");
		return;
	}

	TGprint("\\$0f0\\$sScenery: generating for " + tostring(trackCoords.Length) + " track blocks...");

	lastSceneryCoords.Resize(0);
	array<int3>@ placed = lastSceneryCoords;

	// Per-block: Y used for the close scenery on each side (-1 = not placed, use track Y).
	// Index i*2+0 = left side, i*2+1 = right side.
	array<int> closePlacedY;
	closePlacedY.Resize(trackCoords.Length * 2);
	for (uint i = 0; i < closePlacedY.Length; i++) closePlacedY[i] = -9999;

	// ── Pass 1: close scenery ─────────────────────────────────────────────────

	for (uint ti = 0; ti < trackCoords.Length; ti++) {
		int3 tPos = trackCoords[ti];
		auto tDir = trackDirs[ti];

		// Perpendicular offsets (one cell to each side of the travel direction).
		int3 leftOff  = MoveDir(TurnDirLeft(tDir));
		int3 rightOff = MoveDir(TurnDirRight(tDir));

		for (int side = 0; side < 2; side++) {
			int3 sideOff = (side == 0) ? leftOff : rightOff;
			int hOff = Math::Rand(-2, 2);
			int3 pos = tPos.opAdd(sideOff).opAdd(int3(0, hOff, 0));

			string blockName = CLOSE_SCENERY_BLOCKS[Math::Rand(0, int(CLOSE_SCENERY_BLOCKS.Length) - 1)];
			if (TryPlaceScenery(map, blockName, pos, placed) >= 0) {
				closePlacedY[ti * 2 + side] = pos.y;
			}
		}

		if (!WaitEditorReady(map)) {
			TGprint("\\$f00Scenery: aborting pass 1 at block " + tostring(ti) + " — editor unresponsive.");
			UI::ShowNotification("Scenery aborted (editor unresponsive).");
			return;
		}
	}

	// ── Pass 2: far scenery ───────────────────────────────────────────────────

	for (uint ti = 0; ti < trackCoords.Length; ti++) {
		int3 tPos = trackCoords[ti];
		auto tDir = trackDirs[ti];

		int3 leftOff  = MoveDir(TurnDirLeft(tDir));
		int3 rightOff = MoveDir(TurnDirRight(tDir));

		for (int side = 0; side < 2; side++) {
			int3 sideOff = (side == 0) ? leftOff : rightOff;

			// 10 cells out from the track block.
			int3 farOff = int3(sideOff.x * 10, 0, sideOff.z * 10);

			// Y: use the close-scenery Y if it was placed, otherwise track Y.
			int closeY = closePlacedY[ti * 2 + side];
			int farY = (closeY == -9999) ? tPos.y : closeY;

			int3 pos = int3(tPos.x + farOff.x, farY, tPos.z + farOff.z);
			TryPlaceScenery(map, FAR_SCENERY_BLOCK, pos, placed);
		}

		if (!WaitEditorReady(map)) {
			TGprint("\\$f00Scenery: aborting pass 2 at block " + tostring(ti) + " — editor unresponsive.");
			UI::ShowNotification("Scenery aborted (editor unresponsive).");
			return;
		}
	}

	TGprint("\\$0f0\\$sScenery done: placed " + tostring(placed.Length) + " blocks in "
		+ tostring(Time::get_Now() - before) + " ms.");
	UI::ShowNotification("Scenery: " + tostring(placed.Length) + " blocks placed.");
}

// ── Cancel ────────────────────────────────────────────────────────────────────

void CancelScenery()
{
	if (lastSceneryCoords.Length == 0) {
		UI::ShowNotification("Scenery: nothing to undo.");
		return;
	}

	auto app = cast<CTrackMania>(GetApp());
	if (app is null) return;
	auto editor = cast<CGameCtnEditorFree>(app.Editor);
	if (editor is null) { UI::ShowNotification("Editor not open!"); return; }
	auto map = cast<CGameEditorPluginMap>(editor.PluginMapType);
	if (map is null) return;

	for (uint i = 0; i < lastSceneryCoords.Length; i++) {
		if (!WaitEditorReady(map)) {
			TGprint("\\$f00Scenery cancel: editor unresponsive at block " + tostring(i) + ", stopping.");
			break;
		}
		map.RemoveBlock(lastSceneryCoords[i]);
	}

	TGprint("Scenery: cleared " + tostring(lastSceneryCoords.Length) + " blocks.");
	UI::ShowNotification("Scenery cleared.");
	lastSceneryCoords.Resize(0);
}
