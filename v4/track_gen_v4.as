// Track Generator V4: RoadTech-only, surface state machine.
// Surface states: Flat, Slope, Tilt.
// Block pool loaded from block_data/roadtech_v4_blocks.txt.
// Transition blocks (SlopeStart/End, TiltTransition) are inserted automatically.
// Place a RoadTechStart block first, then generate.

namespace v4 {

enum SurfaceState { Flat, Slope, Tilt }
enum TiltSide { TiltNone, TiltLeft, TiltRight }
enum SlopeDir { SlopeUp, SlopeDown }

const int MAX_SLOPE_RUN = 8;
const int MAX_TILT_RUN  = 12;
const int MIN_FLAT_RUN  = 3;
const int MIN_SLOPE_RUN = 3;
const int MIN_TILT_RUN  = 3;
const int MAX_ATTEMPTS  = 1;  // single attempt — clear and fail on hard failure

// Transition block names
const string SLOPE_START    = "RoadTechSlopeStart2x1";
const string SLOPE_END      = "RoadTechSlopeEnd2x1";
const string TILT_UP_LEFT   = "RoadTechTiltTransition1UpLeft";
const string TILT_UP_RIGHT  = "RoadTechTiltTransition1UpRight";
const string TILT_DOWN_LEFT = "RoadTechTiltTransition1DownLeft";
const string TILT_DOWN_RIGHT= "RoadTechTiltTransition1DownRight";
const string RAMP_ESCAPE    = "RoadTechRampLow";

// Coords of the last successful V4 generation (used by ClearLastRun).
array<int3> lastRunCoords;

// Block pools (populated by LoadPools)
array<string> flatPool;
array<string> slopePool;     // all slope blocks (for logging)
array<string> slopeUpPool;   // SlopeUp + neutral slope blocks (ascending sections)
array<string> slopeDownPool; // SlopeDown + neutral slope blocks (descending sections)
array<string> tiltPool;
// Side-specific tilt pools — built from tiltPool at load time.
// TiltSwitch blocks are excluded (they change bank direction mid-section,
// which breaks side tracking and makes ExitTilt pick the wrong transition).
array<string> tiltLeftPool;
array<string> tiltRightPool;

// Current forward travel direction — set at generation start, updated by PlaceConnected.
CGameEditorPluginMap::ECardinalDirections g_travelDir;

// ── Pool loading ─────────────────────────────────────────────────────────────

string GetBlockDataPath()
{
	string storage = IO::FromStorageFolder("block_data/");
	try {
		IO::File f(storage + "roadtech_v4_blocks.txt", IO::FileMode::Read);
		f.Close();
		return storage;
	} catch {}
	return "d:\\REPO\\tmmaps\\block_data\\";
}

string DirStr(CGameEditorPluginMap::ECardinalDirections d)
{
	switch(d) {
		case CGameEditorPluginMap::ECardinalDirections::North: return "N";
		case CGameEditorPluginMap::ECardinalDirections::East:  return "E";
		case CGameEditorPluginMap::ECardinalDirections::South: return "S";
		case CGameEditorPluginMap::ECardinalDirections::West:  return "W";
	}
	return "?";
}

bool IsTiltDirectedCurve(const string &in blockName)
{
	if (blockName.IndexOf("TiltCurve") < 0) return false;
	string lower = blockName.ToLower();
	return lower.IndexOf("downleft")  >= 0 || lower.IndexOf("upleft")  >= 0 ||
	       lower.IndexOf("downright") >= 0 || lower.IndexOf("upright") >= 0;
}

void LoadPools()
{
	flatPool.Resize(0);
	slopePool.Resize(0);
	slopeUpPool.Resize(0);
	slopeDownPool.Resize(0);
	tiltPool.Resize(0);

	string path = GetBlockDataPath() + "roadtech_v4_blocks.txt";
	string section = "";

	try {
		IO::File f(path, IO::FileMode::Read);
		while (!f.EOF()) {
			string line = f.ReadLine().Trim();

			if (line.StartsWith("## ")) {
				string h = line.ToUpper();
				if      (h.IndexOf("EXCLUDED")        >= 0) section = "EXCLUDED";
				else if (h.IndexOf("SLOPE TRANSITION") >= 0) section = "SLOPE_TRANS";
				else if (h.IndexOf("TILT TRANSITION")  >= 0) section = "TILT_TRANS";
				else if (h.IndexOf("SLOPE")            >= 0) section = "SLOPE";
				else if (h.IndexOf("TILT")             >= 0) section = "TILT";
				else if (h.IndexOf("FLAT")             >= 0) section = "FLAT";
				continue;
			}

			if (line.Length == 0 || line.SubStr(0, 1) == "#") continue;
			if (section == "EXCLUDED" || section == "SLOPE_TRANS" || section == "TILT_TRANS") continue;

			// Respect the special blocks toggle
			if (!st_v4Special && line.IndexOf("Special") >= 0) continue;

			// Respect the ramp blocks toggle
			if (!st_v4Ramps && line.IndexOf("Ramp") >= 0) continue;

			if (section == "FLAT") {
				flatPool.InsertLast(line);
			} else if (section == "SLOPE") {
				slopePool.InsertLast(line);
				bool isDown = line.IndexOf("SlopeDown") >= 0;
				bool isUp   = line.IndexOf("SlopeUp")   >= 0;
				// Neutral blocks (no SlopeDown/SlopeUp suffix) go into both pools.
				if (!isDown) slopeUpPool.InsertLast(line);
				if (!isUp)   slopeDownPool.InsertLast(line);
			} else if (section == "TILT" && !IsTiltDirectedCurve(line)) {
				tiltPool.InsertLast(line);
			}
		}
		f.Close();
	} catch {
		TGprint("\\$f00V4: failed to load roadtech_v4_blocks.txt");
		return;
	}

	// Build side-specific tilt pools.
	// Neutral blocks (no TiltLeft/TiltRight in name) go into both.
	// TiltSwitch blocks are dropped — they change the bank direction mid-section.
	tiltLeftPool.Resize(0);
	tiltRightPool.Resize(0);
	for (uint i = 0; i < tiltPool.Length; i++) {
		string name = tiltPool[i];
		if (name.IndexOf("TiltSwitch") >= 0) continue;
		bool hasLeft  = name.IndexOf("TiltLeft")  >= 0;
		bool hasRight = name.IndexOf("TiltRight") >= 0;
		if (!hasLeft && !hasRight) {
			tiltLeftPool.InsertLast(name);
			tiltRightPool.InsertLast(name);
		} else if (hasLeft) {
			tiltLeftPool.InsertLast(name);
		} else {
			tiltRightPool.InsertLast(name);
		}
	}

	TGprint("V4 pools loaded — flat: " + tostring(flatPool.Length)
		+ "  slopeUp: " + tostring(slopeUpPool.Length)
		+ "  slopeDown: " + tostring(slopeDownPool.Length)
		+ "  tiltL: " + tostring(tiltLeftPool.Length)
		+ "  tiltR: " + tostring(tiltRightPool.Length));
}

// ── Placement helpers ────────────────────────────────────────────────────────────────────────────

// Find the newly placed block by scanning only entries appended after preLen.
// Relies on TM appending new blocks to the end of the Blocks array.
int3 FindNewlyPlacedBlock(const string &in blockName, uint preLen, int3 fallback)
{
	auto allB = GetApp().RootMap.Blocks;
	for (uint ak = preLen; ak < allB.Length; ak++) {
		if (allB[ak].BlockModel.IdName == blockName)
			return int3(allB[ak].CoordX, allB[ak].CoordY, allB[ak].CoordZ);
	}
	return fallback;
}

// Dump every connect result the game returned for blockName from prevPos.
// Called automatically when PlaceConnected falls through to pass 3 (backDir),
// which signals pass 1 and 2 found nothing usable — useful for diagnosing
// broken slope/tilt chains.
void LogConnectResults(CGameEditorPluginMap@ map, int3 prevPos, const string &in blockName, const string &in prevBlockName)
{
	auto preferDir = g_travelDir;
	auto backDir   = IntToDir((DirToInt(preferDir) + 2) % 4);
	TGprint("    [ConnectResults] " + blockName + " from " + prevBlockName + " @ " + tostring(prevPos)
		+ "  prefer=" + DirStr(preferDir) + "  back=" + DirStr(backDir)
		+ "  total=" + tostring(map.ConnectResults.Length));
	for (uint r = 0; r < map.ConnectResults.Length; r++) {
		auto res = map.ConnectResults[r];
		if (res is null) { TGprint("      [" + tostring(r) + "] null"); continue; }
		auto dir = ConvertDir(res.Dir);
		string canConn  = res.CanPlace ? "canConn" : "noConn";
		string canPlace = res.CanPlace ? (CanPlaceBlock(map, blockName, dir, res.Coord) ? "canPlace" : "BLOCKED") : "—";
		string tag = (dir == preferDir) ? " <prefer" : (dir == backDir ? " <back" : "");
		TGprint("      [" + tostring(r) + "] dir=" + DirStr(dir) + "  coord=" + tostring(res.Coord)
			+ "  " + canConn + "  " + canPlace + tag);
	}
}

// Place blockName connected to prevPos. travelDir is the intended forward direction;
// it is updated to the direction of the placed block after success.
// Pass 1: exact match — asymmetric blocks (ramps, CPs) always face correctly.
// Pass 2: any direction except directly backward — handles curves naturally while
//         preventing backward placement when the forward slot is occupied.
int3 PlaceConnected(CGameEditorPluginMap@ map, int3 prevPos, const string &in blockName)
{
	auto prevBlock = GetBlockAt(map, prevPos);
	if (prevBlock is null) {
		TGprint("\\$f00V4: no block at " + tostring(prevPos));
		return int3(-1, -1, -1);
	}

	auto info = map.GetBlockModelFromName(blockName);
	if (info is null) {
		TGprint("\\$f00V4: block model not found: " + blockName);
		return int3(-1, -1, -1);
	}

	while (!map.IsEditorReadyForRequest) { yield(); }
	map.GetConnectResults(prevBlock, info);
	while (!map.IsEditorReadyForRequest) { yield(); }

	auto preferDir = g_travelDir;
	auto backDir   = IntToDir((DirToInt(preferDir) + 2) % 4);

	// First pass: prefer direction matching current travel direction.
	for (uint r = 0; r < map.ConnectResults.Length; r++) {
		auto res = map.ConnectResults[r];
		if (res is null || !res.CanPlace) continue;
		auto dir = ConvertDir(res.Dir);
		if (dir != preferDir) continue;
		if (CanPlaceBlock(map, blockName, dir, res.Coord)) {
			uint preLen = GetApp().RootMap.Blocks.Length;
			if (PlaceBlock(map, blockName, dir, res.Coord)) {
				g_travelDir = dir;
				return FindNewlyPlacedBlock(blockName, preLen, res.Coord);
			}
		}
	}

	// Second pass: any valid result except directly backward.
	for (uint r = 0; r < map.ConnectResults.Length; r++) {
		auto res = map.ConnectResults[r];
		if (res is null || !res.CanPlace) continue;
		auto coord = res.Coord;
		auto dir   = ConvertDir(res.Dir);
		if (dir == backDir) continue;
		if (CanPlaceBlock(map, blockName, dir, coord)) {
			uint preLen = GetApp().RootMap.Blocks.Length;
			if (PlaceBlock(map, blockName, dir, coord)) {
				g_travelDir = dir;
				return FindNewlyPlacedBlock(blockName, preLen, coord);
			}
		}
	}
	// Third pass: try backDir results — some blocks (e.g. tilt transitions) report
	// backDir as their exit but physically go straight. Only reached if all other
	// candidates failed, so the risk of backward placement is minimal.
	// Log everything so we can diagnose why passes 1 and 2 failed.
	{
		string prevName = (prevBlock !is null) ? prevBlock.BlockModel.IdName : "?";
		LogConnectResults(map, prevPos, blockName, prevName);
	}
	for (uint r = 0; r < map.ConnectResults.Length; r++) {
		auto res = map.ConnectResults[r];
		if (res is null || !res.CanPlace) continue;
		auto coord = res.Coord;
		auto dir   = ConvertDir(res.Dir);
		if (dir != backDir) continue;
		if (CanPlaceBlock(map, blockName, dir, coord)) {
			uint preLen = GetApp().RootMap.Blocks.Length;
			if (PlaceBlock(map, blockName, dir, coord)) {
				// Don't update g_travelDir to backDir — the block physically goes straight.
				TGprint("    PlaceConnected pass3 (backDir): placed " + blockName + " @ " + tostring(coord) + "  dir=" + DirStr(dir) + "  g_travelDir unchanged=" + DirStr(g_travelDir));
				return FindNewlyPlacedBlock(blockName, preLen, coord);
			}
		}
	}
	return int3(-1, -1, -1);
}

// Place blockName using the backward connect result from GetConnectResults.
// The engine calculates the correct anchor coord — same approach as PlaceConnected
// but specifically taking the backDir result instead of filtering it out.
// g_travelDir is updated to reverseDir on success.
int3 PlaceReversedConnected(CGameEditorPluginMap@ map, int3 prevPos, const string &in blockName)
{
	auto prevBlock = GetBlockAt(map, prevPos);
	if (prevBlock is null) {
		TGprint("  PlaceReversedConnected: no block at " + tostring(prevPos));
		return int3(-1, -1, -1);
	}
	auto info = map.GetBlockModelFromName(blockName);
	if (info is null) {
		TGprint("  PlaceReversedConnected: block model not found: " + blockName);
		return int3(-1, -1, -1);
	}

	auto reverseDir = IntToDir((DirToInt(g_travelDir) + 2) % 4);
	TGprint("  PlaceReversedConnected: " + blockName + "  prevPos=" + tostring(prevPos) + "  travelDir=" + DirStr(g_travelDir) + "  reverseDir=" + DirStr(reverseDir));

	while (!map.IsEditorReadyForRequest) { yield(); }
	map.GetConnectResults(prevBlock, info);
	while (!map.IsEditorReadyForRequest) { yield(); }

	// Dump ALL results so we can see what the game returned (not just the reverseDir one).
	{
		string prevName = prevBlock.BlockModel.IdName;
		TGprint("    [ConnectResults] " + blockName + " from " + prevName + " @ " + tostring(prevPos)
			+ "  want=" + DirStr(reverseDir) + "  total=" + tostring(map.ConnectResults.Length));
		for (uint r = 0; r < map.ConnectResults.Length; r++) {
			auto res = map.ConnectResults[r];
			if (res is null) { TGprint("      [" + tostring(r) + "] null"); continue; }
			auto dir = ConvertDir(res.Dir);
			string canConn  = res.CanPlace ? "canConn" : "noConn";
			string canPlace = res.CanPlace ? (CanPlaceBlock(map, blockName, dir, res.Coord) ? "canPlace" : "BLOCKED") : "—";
			string tag = (dir == reverseDir) ? " <want" : "";
			TGprint("      [" + tostring(r) + "] dir=" + DirStr(dir) + "  coord=" + tostring(res.Coord)
				+ "  " + canConn + "  " + canPlace + tag);
		}
	}

	for (uint r = 0; r < map.ConnectResults.Length; r++) {
		auto res = map.ConnectResults[r];
		if (res is null || !res.CanPlace) continue;
		auto dir = ConvertDir(res.Dir);
		if (dir != reverseDir) continue;
		TGprint("    backDir result: coord=" + tostring(res.Coord) + "  dir=" + DirStr(dir));
		if (CanPlaceBlock(map, blockName, dir, res.Coord)) {
			uint preLen = GetApp().RootMap.Blocks.Length;
			if (PlaceBlock(map, blockName, dir, res.Coord)) {
				// Do NOT update g_travelDir here. The slope does not physically
				// reverse the car's direction. Flipping g_travelDir to reverseDir
				// would cause every subsequent block and curve to use the wrong
				// direction, cascading a full East/West flip across the entire track.
				return FindNewlyPlacedBlock(blockName, preLen, res.Coord);
			}
		} else {
			TGprint("    backDir result blocked at " + tostring(res.Coord));
		}
	}
	TGprint("  PlaceReversedConnected: no usable backDir result for " + blockName);
	return int3(-1, -1, -1);
}

// Place blockName with the direction OPPOSITE to travelDir at prevPos (y-1 or y=0).
// Used for SlopeDown entry (SLOPE_END reversed) and exit (SLOPE_START reversed).
// Updates g_travelDir to the reverse direction on success — slope body blocks then
// connect correctly in the new physical travel direction.
int3 PlaceReversed(CGameEditorPluginMap@ map, int3 prevPos, const string &in blockName)
{
	auto reverseDir = IntToDir((DirToInt(g_travelDir) + 2) % 4);
	TGprint("  PlaceReversed: " + blockName + "  prevPos=" + tostring(prevPos) + "  travelDir=" + DirStr(g_travelDir) + "  reverseDir=" + DirStr(reverseDir));
	// Only vary Y: try y-1 (slope anchor sits one below flat level), then y=0.
	// No horizontal offset — the block must connect directly to prevPos.
	for (int yOff = -1; yOff <= 0; yOff++) {
		int3 tryCoord = int3(prevPos.x, prevPos.y + yOff, prevPos.z);
		while (!map.IsEditorReadyForRequest) { yield(); }
		bool canPlace = CanPlaceBlock(map, blockName, reverseDir, tryCoord);
		TGprint("    yOff=" + tostring(yOff) + "  tryCoord=" + tostring(tryCoord) + "  canPlace=" + (canPlace ? "YES" : "NO"));
		if (canPlace) {
			while (!map.IsEditorReadyForRequest) { yield(); }
			uint preLen = GetApp().RootMap.Blocks.Length;
			bool placed = PlaceBlock(map, blockName, reverseDir, tryCoord);
			TGprint("    PlaceBlock result=" + (placed ? "OK" : "FAILED"));
			if (placed) {
				g_travelDir = reverseDir;  // physical travel direction is now reversed
				return FindNewlyPlacedBlock(blockName, preLen, tryCoord);
			}
		}
	}
	TGprint("  PlaceReversed: all attempts failed for " + blockName);
	return int3(-1, -1, -1);
}

// Like PlaceReversed but does NOT update g_travelDir.
// Used for tilt blocks: we only need the block physically rotated 180° to find
// a snapping end — the road still continues in the same travel direction.
int3 PlaceFlipped(CGameEditorPluginMap@ map, int3 prevPos, const string &in blockName)
{
	auto flipDir = IntToDir((DirToInt(g_travelDir) + 2) % 4);
	TGprint("  PlaceFlipped: " + blockName + "  prevPos=" + tostring(prevPos) + "  travelDir=" + DirStr(g_travelDir) + "  flipDir=" + DirStr(flipDir));
	for (int yOff = -1; yOff <= 0; yOff++) {
		int3 tryCoord = int3(prevPos.x, prevPos.y + yOff, prevPos.z);
		while (!map.IsEditorReadyForRequest) { yield(); }
		bool canPlace = CanPlaceBlock(map, blockName, flipDir, tryCoord);
		TGprint("    yOff=" + tostring(yOff) + "  tryCoord=" + tostring(tryCoord) + "  canPlace=" + (canPlace ? "YES" : "NO"));
		if (canPlace) {
			while (!map.IsEditorReadyForRequest) { yield(); }
			uint preLen = GetApp().RootMap.Blocks.Length;
			bool placed = PlaceBlock(map, blockName, flipDir, tryCoord);
			TGprint("    PlaceBlock result=" + (placed ? "OK" : "FAILED"));
			if (placed) {
				// g_travelDir is NOT updated here — caller decides whether to update it.
				return FindNewlyPlacedBlock(blockName, preLen, tryCoord);
			}
		}
	}
	TGprint("  PlaceFlipped: all attempts failed for " + blockName);
	return int3(-1, -1, -1);
}
// ── Transition helpers ────────────────────────────────────────────────────────────────────
// All helpers read/write g_travelDir so direction is tracked through transitions.

// Ascending entry: SLOPE_START (flat→slope going up).
// Descending entry: SLOPE_END reversed 180° (flat→slope going down). Falls back to ascending.
int3 EnterSlope(CGameEditorPluginMap@ map, int3 prevPos, SlopeDir &out dir)
{
	if (MathRand(0, 1) == 0) {
		int3 newPos = PlaceReversedConnected(map, prevPos, SLOPE_END);
		if (newPos.x >= 0) {
			dir = SlopeDir::SlopeDown;
			TGprint("V4 trans: Flat→Slope/Down  " + SLOPE_END + " @ " + tostring(newPos) + "  dir=" + DirStr(g_travelDir));
			return newPos;
		}
		TGprint("  → EnterSlope: " + SLOPE_END + " (reversed) failed from " + tostring(prevPos) + "  travelDir=" + DirStr(g_travelDir) + ", trying SlopeUp");
	}
	dir = SlopeDir::SlopeUp;
	int3 newPos = PlaceConnected(map, prevPos, SLOPE_START);
	if (newPos.x < 0) {
		TGprint("  → EnterSlope: " + SLOPE_START + " failed from " + tostring(prevPos) + "  travelDir=" + DirStr(g_travelDir));
		return int3(-1, -1, -1);
	}
	TGprint("V4 trans: Flat→Slope/Up  " + SLOPE_START + " @ " + tostring(newPos) + "  dir=" + DirStr(g_travelDir));
	return newPos;
}

// Exit slope → flat.
// SlopeDown: slope body forward socket connects to SLOPE_START (exits at lower flat).
// SlopeUp:   slope body forward socket connects to SLOPE_END (exits at upper flat).
int3 ExitSlope(CGameEditorPluginMap@ map, int3 prevPos, SlopeDir dir)
{
	if (dir == SlopeDir::SlopeDown) {
		int3 newPos = PlaceConnected(map, prevPos, SLOPE_START);
		if (newPos.x >= 0) { TGprint("V4 trans: Slope/Down→Flat  " + SLOPE_START + " @ " + tostring(newPos) + "  dir=" + DirStr(g_travelDir)); return newPos; }
		TGprint("  → ExitSlope: " + SLOPE_START + " failed from " + tostring(prevPos) + "  travelDir=" + DirStr(g_travelDir));
		LogPlacementDiag(map, prevPos, SLOPE_START);
		return int3(-1, -1, -1);
	}
	// SlopeUp
	int3 newPos = PlaceConnected(map, prevPos, SLOPE_END);
	if (newPos.x < 0) {
		TGprint("  → ExitSlope: " + SLOPE_END + " failed from " + tostring(prevPos) + "  travelDir=" + DirStr(g_travelDir));
		LogPlacementDiag(map, prevPos, SLOPE_END);
		return int3(-1, -1, -1);
	}
	TGprint("V4 trans: Slope/Up→Flat  " + SLOPE_END + " @ " + tostring(newPos) + "  dir=" + DirStr(g_travelDir));
	return newPos;
}

int3 ExitTilt(CGameEditorPluginMap@ map, int3 prevPos, TiltSide side)
{
	string block1 = (side == TiltSide::TiltRight) ? TILT_DOWN_RIGHT : TILT_DOWN_LEFT;
	string block2 = (side == TiltSide::TiltRight) ? TILT_DOWN_LEFT  : TILT_DOWN_RIGHT;
	int3 newPos = PlaceConnected(map, prevPos, block1);
	if (newPos.x >= 0) { TGprint("V4 trans: Tilt→Flat  " + block1 + " @ " + tostring(newPos) + "  dir=" + DirStr(g_travelDir)); return newPos; }
	TGprint("  → ExitTilt: " + block1 + " failed from " + tostring(prevPos) + "  travelDir=" + DirStr(g_travelDir) + ", trying " + block2);
	newPos = PlaceConnected(map, prevPos, block2);
	if (newPos.x >= 0) { TGprint("V4 trans: Tilt→Flat  " + block2 + " @ " + tostring(newPos) + "  dir=" + DirStr(g_travelDir)); return newPos; }
	TGprint("  → ExitTilt: " + block2 + " also failed from " + tostring(prevPos) + "  travelDir=" + DirStr(g_travelDir));
	return int3(-1, -1, -1);
}

int3 EnterTilt(CGameEditorPluginMap@ map, int3 prevPos, TiltSide &out side)
{
	// Try both sides; for each side try normal (PlaceConnected) then reversed
	// (PlaceReversed). Tilt transition blocks have one flat face and one tilted
	// face — which orientation the engine accepts depends on the approach geometry.
	TiltSide firstSide = (MathRand(0, 1) == 0) ? TiltSide::TiltLeft : TiltSide::TiltRight;
	for (int attempt = 0; attempt < 2; attempt++) {
		side = (attempt == 0) ? firstSide
		                      : (firstSide == TiltSide::TiltLeft ? TiltSide::TiltRight : TiltSide::TiltLeft);
		string block = (side == TiltSide::TiltRight) ? TILT_UP_RIGHT : TILT_UP_LEFT;

		// Normal placement via connect results.
		int3 newPos = PlaceConnected(map, prevPos, block);
		if (newPos.x >= 0) {
			TGprint("V4 trans: Flat→Tilt  " + block + " (normal) @ " + tostring(newPos) + "  dir=" + DirStr(g_travelDir));
			return newPos;
		}
		TGprint("  → EnterTilt: " + block + " (normal) failed from " + tostring(prevPos) + "  travelDir=" + DirStr(g_travelDir));
		LogPlacementDiag(map, prevPos, block);

		// Flipped placement — rotates block 180°, g_travelDir unchanged.
		// Tilt transitions go straight; flipping is purely to find a snapping face.
		newPos = PlaceFlipped(map, prevPos, block);
		if (newPos.x >= 0) {
			TGprint("V4 trans: Flat→Tilt  " + block + " (flipped) @ " + tostring(newPos) + "  dir=" + DirStr(g_travelDir));
			return newPos;
		}
		TGprint("  → EnterTilt: " + block + " (flipped) failed from " + tostring(prevPos) + "  travelDir=" + DirStr(g_travelDir));
	}
	return int3(-1, -1, -1);
}
// ── Diagnostic helper ─────────────────────────────────────────────────────────
// Called after a placement failure. Logs what connect results existed and
// whether CanPlaceBlock succeeded for each candidate position.
void LogPlacementDiag(CGameEditorPluginMap@ map, int3 prevPos, const string &in blockName)
{
	auto prevBlock = GetBlockAt(map, prevPos);
	if (prevBlock is null) {
		TGprint("  → diag: no block found at prevPos=" + tostring(prevPos));
		return;
	}
	auto info = map.GetBlockModelFromName(blockName);
	if (info is null) {
		TGprint("  → diag: block model '" + blockName + "' not found in game");
		return;
	}
	while (!map.IsEditorReadyForRequest) { yield(); }
	map.GetConnectResults(prevBlock, info);
	while (!map.IsEditorReadyForRequest) { yield(); }

	int total    = int(map.ConnectResults.Length);
	int nCanConn = 0;
	int nBlocked = 0;
	string details = "";
	for (uint r = 0; r < map.ConnectResults.Length; r++) {
		auto res = map.ConnectResults[r];
		if (res is null || !res.CanPlace) continue;
		nCanConn++;
		auto dir = ConvertDir(res.Dir);
		if (CanPlaceBlock(map, blockName, dir, res.Coord))
			details += " " + DirStr(dir) + "@" + tostring(res.Coord) + "=open";
		else {
			nBlocked++;
			details += " " + DirStr(dir) + "@" + tostring(res.Coord) + "=blocked";
		}
	}
	TGprint("  → from " + prevBlock.BlockModel.IdName + " @ " + tostring(prevPos)
		+ "  travelDir=" + DirStr(g_travelDir)
		+ "  connectResults=" + tostring(total)
		+ "  canConnect=" + tostring(nCanConn)
		+ "  blocked=" + tostring(nBlocked)
		+ (details.Length > 0 ? "  [" + details + " ]" : "  [no candidates]"));
}

// ── Clear helper ──────────────────────────────────────────────────────────────

void ClearPlaced(CGameEditorPluginMap@ map, array<int3> &in coords)
{
	for (uint i = 0; i < coords.Length; i++) {
		while (!map.IsEditorReadyForRequest) { yield(); }
		auto b = map.GetBlock(coords[i]);
		if (b !is null) {
			string foundName = b.BlockModel.IdName;
			int3 foundCoord = int3(b.CoordX, b.CoordY, b.CoordZ);
			map.RemoveBlock(foundCoord);
			// Verify removal succeeded.
			while (!map.IsEditorReadyForRequest) { yield(); }
			auto bCheck = map.GetBlock(coords[i]);
			if (bCheck !is null)
				TGprint("V4 clear [" + tostring(i) + "]: REMOVAL FAILED for '" + foundName + "' at " + tostring(foundCoord) + " — block still present");
			continue;
		}
		// GetBlock returned null — probe nearby cells in a full 2D grid.
		// Large blocks (curves, chicanes) may only be queryable at a diagonal
		// offset from their logged anchor — separate X/Z linear scans miss those.
		bool removed = false;
		for (int xOff = -6; xOff <= 6 && !removed; xOff++) {
			for (int zOff = -6; zOff <= 6 && !removed; zOff++) {
				if (xOff == 0 && zOff == 0) continue;
				for (int yOff = -1; yOff <= 1 && !removed; yOff++) {
					int3 scanCoord = int3(coords[i].x + xOff, coords[i].y + yOff, coords[i].z + zOff);
					while (!map.IsEditorReadyForRequest) { yield(); }
					auto b2 = map.GetBlock(scanCoord);
					if (b2 !is null) {
						TGprint("V4 clear [" + tostring(i) + "]: found '" + b2.BlockModel.IdName + "' at offset <" + tostring(xOff) + "," + tostring(yOff) + "," + tostring(zOff) + ">  anchor=<" + tostring(b2.CoordX) + "," + tostring(b2.CoordY) + "," + tostring(b2.CoordZ) + ">  logged=" + tostring(coords[i]));
						// Use the scan coord (where GetBlock found it) for RemoveBlock —
						// calling RemoveBlock at the anchor can silently fail if GetBlock
						// at that exact anchor coord also returns null.
						map.RemoveBlock(scanCoord);
						while (!map.IsEditorReadyForRequest) { yield(); }
						auto bVerify = map.GetBlock(scanCoord);
						if (bVerify !is null)
							TGprint("V4 clear [" + tostring(i) + "]: REMOVAL FAILED at scanCoord=" + tostring(scanCoord) + " — retrying at anchor");
						else
							removed = true;
						if (!removed) {
							// Retry at anchor in case engine needs canonical coord.
							int3 anchor = int3(b2.CoordX, b2.CoordY, b2.CoordZ);
							map.RemoveBlock(anchor);
							while (!map.IsEditorReadyForRequest) { yield(); }
							removed = true;
						}
					}
				}
			}
		}
		if (!removed) {
			TGprint("V4 clear [" + tostring(i) + "]: MISSED — nothing found at " + tostring(coords[i]) + " or within 2D ±6 grid — trying direct remove");
			map.RemoveBlock(coords[i]);
		}
	}
}

// ── Main ──────────────────────────────────────────────────────────────────────

void Run()
{
	uint64 before = Time::get_Now();

	auto app = cast<CTrackMania>(GetApp());
	if (app is null) return;

	auto editor = cast<CGameCtnEditorFree>(app.Editor);
	if (editor is null) { UI::ShowNotification("Editor not open!"); return; }

	auto map = cast<CGameEditorPluginMap>(editor.PluginMapType);
	if (map is null) return;

	LoadMapSize();
	LoadPools();

	if (flatPool.Length == 0) {
		TGprint("\\$f00V4: flat pool is empty, cannot generate.");
		UI::ShowNotification("V4: flat pool empty. Check roadtech_v4_blocks.txt.");
		return;
	}

	int3 startPos;
	CGameCtnBlock@ startBlock = FindStartBlock(map, startPos);
	if (startBlock is null) {
		TGprint("\\$f00V4: No Start block found. Place RoadTechStart first.");
		UI::ShowNotification("V4: Place a RoadTechStart block first!");
		return;
	}
	TGprint("V4 start: " + tostring(startBlock.BlockModel.IdName) + " at " + tostring(startPos));

	double baseSeed = ConvertSeed(seedText);

	for (int attempt = 0; attempt < MAX_ATTEMPTS; attempt++)
	{
		if (attempt > 0)
			TGprint("\\$f0fV4: retrying with new seed (attempt " + tostring(attempt + 1) + ")...");

		seedDouble = baseSeed + attempt * 1337.0;

		array<int3> placedCoords;
		array<CGameEditorPluginMap::ECardinalDirections> placedDirs;
		int3 prevPos       = startPos;
		SurfaceState state = SurfaceState::Flat;
		TiltSide tiltSide  = TiltSide::TiltNone;
		SlopeDir slopeDir  = SlopeDir::SlopeUp;
		int stateRun       = 0;
		int flatRun        = 0;
		int placed         = 0;
		bool needsRedo     = false;
		g_travelDir = GetBlockDirection(startBlock);
		auto initDir = g_travelDir;  // saved for direction restore after full backtrack

		TGprint("\\$0f0\\$sGenerating track (V4 RoadTech surface-state)!");

		for (int i = 0; placed < st_maxBlocks && i < st_maxBlocks * 30; i++)
		{
			// ── Pick target ───────────────────────────────────────────────

			int wFlat  = 60;
			int wSlope = (st_v4Slope && slopePool.Length > 0) ? 20 : 0;
			int wTilt  = (st_v4Tilt  && tiltPool.Length  > 0) ? 20 : 0;
			int total  = wFlat + wSlope + wTilt;
			int roll   = MathRand(0, total - 1);

			SurfaceState targetState;
			string targetBlock;

			if (roll < wFlat) {
				targetState = SurfaceState::Flat;
				targetBlock = flatPool[MathRand(0, int(flatPool.Length) - 1)];
			} else if (roll < wFlat + wSlope) {
				targetState = SurfaceState::Slope;
				// Use directional pool when already in slope, full pool otherwise
				// (direction gets set by EnterSlope for new slope sections).
				array<string>@ sp = slopePool;
				if (state == SurfaceState::Slope) {
					sp = (slopeDir == SlopeDir::SlopeUp) ? slopeUpPool : slopeDownPool;
				}
				targetBlock = sp[MathRand(0, int(sp.Length) - 1)];
			} else {
				targetState = SurfaceState::Tilt;
				// When already in tilt, use the side-specific pool to avoid
				// mixing Left/Right blocks which causes exit transition failures.
				array<string>@ tp = tiltPool;
				if (state == SurfaceState::Tilt) {
					tp = (tiltSide == TiltSide::TiltLeft) ? tiltLeftPool : tiltRightPool;
				}
				targetBlock = tp[MathRand(0, int(tp.Length) - 1)];
			}

			// ── Enforce run limits ────────────────────────────────────────

			if (state == SurfaceState::Flat && flatRun < MIN_FLAT_RUN && targetState != SurfaceState::Flat) {
				targetState = SurfaceState::Flat;
				targetBlock = flatPool[MathRand(0, int(flatPool.Length) - 1)];
			}
			if (state == SurfaceState::Slope && stateRun < MIN_SLOPE_RUN && targetState != SurfaceState::Slope) {
				targetState = SurfaceState::Slope;
				array<string>@ minPool = (slopeDir == SlopeDir::SlopeUp) ? slopeUpPool : slopeDownPool;
				targetBlock = minPool[MathRand(0, int(minPool.Length) - 1)];
			}
			if (state == SurfaceState::Tilt && stateRun < MIN_TILT_RUN && targetState != SurfaceState::Tilt) {
				targetState = SurfaceState::Tilt;
				targetBlock = tiltPool[MathRand(0, int(tiltPool.Length) - 1)];
			}
			if (state == SurfaceState::Slope && stateRun >= MAX_SLOPE_RUN && targetState != SurfaceState::Flat) {
				targetState = SurfaceState::Flat;
				targetBlock = flatPool[MathRand(0, int(flatPool.Length) - 1)];
			}
			if (state == SurfaceState::Tilt && stateRun >= MAX_TILT_RUN && targetState != SurfaceState::Flat) {
				targetState = SurfaceState::Flat;
				targetBlock = flatPool[MathRand(0, int(flatPool.Length) - 1)];
			}

			// ── Transition ────────────────────────────────────────────────

			bool transOk = true;

			if (state == targetState) {
				// No transition needed
			}
			else if (state == SurfaceState::Flat && targetState == SurfaceState::Slope) {
				int3 p = EnterSlope(map, prevPos, slopeDir);
				if (p.x < 0) { transOk = false; }
				else {
					prevPos = p; placed++; placedCoords.InsertLast(p); placedDirs.InsertLast(g_travelDir); state = SurfaceState::Slope; stateRun = 0; flatRun = 0;
					// Re-pick target from the now-known directional pool.
					array<string>@ sp = (slopeDir == SlopeDir::SlopeUp) ? slopeUpPool : slopeDownPool;
					if (sp.Length > 0) targetBlock = sp[MathRand(0, int(sp.Length) - 1)];
				}
			}
			else if (state == SurfaceState::Flat && targetState == SurfaceState::Tilt) {
				int3 p = EnterTilt(map, prevPos, tiltSide);
				if (p.x < 0) { transOk = false; }
				else {
					prevPos = p; placed++; placedCoords.InsertLast(p); placedDirs.InsertLast(g_travelDir); state = SurfaceState::Tilt; stateRun = 0; flatRun = 0;
					// Re-pick target from the now-known side pool so the first
					// tilt body block is also side-consistent.
					array<string>@ sp = (tiltSide == TiltSide::TiltLeft) ? tiltLeftPool : tiltRightPool;
					if (sp.Length > 0) targetBlock = sp[MathRand(0, int(sp.Length) - 1)];
				}
			}
			else if (state == SurfaceState::Slope && targetState == SurfaceState::Flat) {
				int3 p = ExitSlope(map, prevPos, slopeDir);
				if (p.x < 0) { transOk = false; }
				else { prevPos = p; placed++; placedCoords.InsertLast(p); placedDirs.InsertLast(g_travelDir); state = SurfaceState::Flat; stateRun = 0; flatRun = 0; }
			}
			else if (state == SurfaceState::Slope && targetState == SurfaceState::Tilt) {
				int3 p = ExitSlope(map, prevPos, slopeDir);
				if (p.x < 0) { transOk = false; }
				else {
					prevPos = p; placed++; placedCoords.InsertLast(p); placedDirs.InsertLast(g_travelDir); state = SurfaceState::Flat;
					int3 p2 = EnterTilt(map, prevPos, tiltSide);
					if (p2.x < 0) { transOk = false; }
					else { prevPos = p2; placed++; placedCoords.InsertLast(p2); placedDirs.InsertLast(g_travelDir); state = SurfaceState::Tilt; stateRun = 0; flatRun = 0; }
				}
			}
			else if (state == SurfaceState::Tilt && targetState == SurfaceState::Flat) {
				int3 p = ExitTilt(map, prevPos, tiltSide);
				if (p.x < 0) { transOk = false; }
				else { prevPos = p; placed++; placedCoords.InsertLast(p); placedDirs.InsertLast(g_travelDir); state = SurfaceState::Flat; stateRun = 0; flatRun = 0; tiltSide = TiltSide::TiltNone; }
			}
			else if (state == SurfaceState::Tilt && targetState == SurfaceState::Slope) {
				int3 p = ExitTilt(map, prevPos, tiltSide);
				if (p.x < 0) { transOk = false; }
				else {
					prevPos = p; placed++; placedCoords.InsertLast(p); placedDirs.InsertLast(g_travelDir); state = SurfaceState::Flat; tiltSide = TiltSide::TiltNone;
					int3 p2 = EnterSlope(map, prevPos, slopeDir);
					if (p2.x < 0) { transOk = false; }
					else {
						prevPos = p2; placed++; placedCoords.InsertLast(p2); placedDirs.InsertLast(g_travelDir); state = SurfaceState::Slope; stateRun = 0; flatRun = 0;
						array<string>@ sp = (slopeDir == SlopeDir::SlopeUp) ? slopeUpPool : slopeDownPool;
						if (sp.Length > 0) targetBlock = sp[MathRand(0, int(sp.Length) - 1)];
					}
				}
			}

			if (!transOk) {
				string stStr = (state       == SurfaceState::Flat ? "Flat" : state       == SurfaceState::Slope ? "Slope" : "Tilt");
				string tsStr = (targetState == SurfaceState::Flat ? "Flat" : targetState == SurfaceState::Slope ? "Slope" : "Tilt");
				TGprint("\\$f00V4: transition failed (block [" + tostring(placed + 1) + "])  " + stStr + "→" + tsStr + " from " + tostring(prevPos) + ", retrying flat");
				state = SurfaceState::Flat;
				tiltSide = TiltSide::TiltNone;
				stateRun = 0;
				int3 p = PlaceConnected(map, prevPos, flatPool[MathRand(0, int(flatPool.Length) - 1)]);
				if (p.x >= 0) { prevPos = p; placed++; placedCoords.InsertLast(p); placedDirs.InsertLast(g_travelDir); flatRun++; }
				continue;
			}

			// ── Place target block ────────────────────────────────────────

			int3 newPos = PlaceConnected(map, prevPos, targetBlock);
			if (newPos.x < 0) {
				TGprint("\\$f00V4: could not place " + targetBlock + " (block [" + tostring(placed + 1) + "]), trying fallbacks");
				LogPlacementDiag(map, prevPos, targetBlock);

				// Fallback 0: if we just placed a transition block (state changed, stateRun==0),
				// undo it and reset to Flat, then try a flat block from the pre-transition position.
				if (state != SurfaceState::Flat && stateRun == 0 && placedCoords.Length > 0) {
					int3 transCoord = placedCoords[placedCoords.Length - 1];
					while (!map.IsEditorReadyForRequest) { yield(); }
					auto ub = map.GetBlock(transCoord);
					if (ub !is null) map.RemoveBlock(int3(ub.CoordX, ub.CoordY, ub.CoordZ));
					else map.RemoveBlock(transCoord);
					placed--; placedCoords.RemoveLast(); placedDirs.RemoveLast();
					prevPos     = (placedCoords.Length > 0) ? placedCoords[placedCoords.Length - 1] : startPos;
					g_travelDir = (placedDirs.Length   > 0) ? placedDirs[placedDirs.Length - 1]     : initDir;
					state = SurfaceState::Flat; tiltSide = TiltSide::TiltNone; stateRun = 0; flatRun = 0;
					TGprint("V4: undid failed transition, placed [" + tostring(placed) + "]");
					int3 fp = PlaceConnected(map, prevPos, flatPool[MathRand(0, int(flatPool.Length) - 1)]);
					if (fp.x >= 0) {
						placed++; placedCoords.InsertLast(fp); placedDirs.InsertLast(g_travelDir); prevPos = fp; flatRun = 1;
						continue;
					}
				}

				// Fallback 1: try a straight block first, then a random flat block.
				{
					string anyFlat = "RoadTechStraight";
					TGprint("V4: flat-fallback trying " + anyFlat + " from " + tostring(prevPos) + "  travelDir=" + DirStr(g_travelDir));
					int3 flatPos = PlaceConnected(map, prevPos, anyFlat);
					if (flatPos.x >= 0) {
						placed++; placedCoords.InsertLast(flatPos); placedDirs.InsertLast(g_travelDir);
						prevPos = flatPos; state = SurfaceState::Flat; stateRun = 0; flatRun = 1;
						TGprint("V4: flat-fallback succeeded, placed [" + tostring(placed) + "]");
						continue;
					}
					TGprint("V4: flat-fallback failed -- trying slope-escape");
				}

				// Fallback 2+3: slope-down escape — pop 1 then 2 blocks one at a time.
				// After each pop try: SlopeEnd(reversed) -> SlopeStart(reversed) -> flat block.
				// Changes elevation to break out of crowded flat areas.
				{
					bool slopeEscaped = false;
					for (int popK = 1; popK <= 2 && !slopeEscaped && placedCoords.Length > 0; popK++) {
						int3 popCoord = placedCoords[placedCoords.Length - 1];
						string popName = "?";
						auto pbInfo = GetBlockAt(map, popCoord);
						if (pbInfo !is null) popName = pbInfo.BlockModel.IdName;
						TGprint("V4: slope-escape pop: removed block [" + tostring(placed) + "] " + popName + " @ " + tostring(popCoord));
						while (!map.IsEditorReadyForRequest) { yield(); }
						auto pb = map.GetBlock(popCoord);
						if (pb !is null) map.RemoveBlock(int3(pb.CoordX, pb.CoordY, pb.CoordZ));
						else map.RemoveBlock(popCoord);
						placed--;
						placedCoords.RemoveLast(); placedDirs.RemoveLast();
						prevPos     = (placedCoords.Length > 0) ? placedCoords[placedCoords.Length - 1] : startPos;
						g_travelDir = (placedDirs.Length   > 0) ? placedDirs[placedDirs.Length - 1]     : initDir;
						state = SurfaceState::Flat; tiltSide = TiltSide::TiltNone; stateRun = 0; flatRun = 0;
						TGprint("  after pop: prevPos=" + tostring(prevPos) + "  g_travelDir=" + DirStr(g_travelDir));

					// If popping landed on a transition block, also pop it to avoid
					// placing a second SlopeEnd/TiltTransition on top of it.
					if (placedCoords.Length > 0) {
						auto prevB = GetBlockAt(map, prevPos);
						if (prevB !is null) {
							string pn = prevB.BlockModel.IdName;
							if (pn == SLOPE_END || pn == SLOPE_START ||
							    pn == TILT_UP_LEFT || pn == TILT_UP_RIGHT ||
							    pn == TILT_DOWN_LEFT || pn == TILT_DOWN_RIGHT) {
								TGprint("V4: slope-escape also pops transition block [" + tostring(placed) + "] " + pn + " @ " + tostring(prevPos));
								while (!map.IsEditorReadyForRequest) { yield(); }
								auto tb = map.GetBlock(prevPos);
								if (tb !is null) map.RemoveBlock(int3(tb.CoordX, tb.CoordY, tb.CoordZ));
								else map.RemoveBlock(prevPos);
								placed--;
								placedCoords.RemoveLast(); placedDirs.RemoveLast();
								prevPos     = (placedCoords.Length > 0) ? placedCoords[placedCoords.Length - 1] : startPos;
								g_travelDir = (placedDirs.Length   > 0) ? placedDirs[placedDirs.Length - 1]     : initDir;
							}
						}
					}

						TGprint("  slope-escape: trying SLOPE_END from " + tostring(prevPos) + "  reverseDir=" + DirStr(IntToDir((DirToInt(g_travelDir)+2)%4)));
						int3 p1 = PlaceReversedConnected(map, prevPos, SLOPE_END);
						if (p1.x < 0) { TGprint("  slope-escape: SLOPE_END failed"); continue; }
						TGprint("V4 [" + tostring(placed+1) + "] " + SLOPE_END + " (escape-entry) @ " + tostring(p1) + "  dir=" + DirStr(g_travelDir));
						// Save the physical travel direction set by SLOPE_END.
						// PlaceReversed(SLOPE_START) will double-flip it back to original,
						// but the road physically continues in afterSlopeEndDir.
						auto afterSlopeEndDir = g_travelDir;

						// SLOPE_START connects to the slope face (forward exit) of SLOPE_END,
						// so use PlaceConnected (forward result) not PlaceReversedConnected
						// (which finds the flat-face/wrong-end backDir result).
						TGprint("  slope-escape: trying SLOPE_START from " + tostring(p1) + "  travelDir=" + DirStr(g_travelDir));
						int3 p2 = PlaceConnected(map, p1, SLOPE_START);
						if (p2.x < 0) {
							TGprint("  slope-escape: SLOPE_START failed, removing SLOPE_END @ " + tostring(p1));
							while (!map.IsEditorReadyForRequest) { yield(); }
							auto rb1 = map.GetBlock(p1);
							if (rb1 !is null) map.RemoveBlock(int3(rb1.CoordX, rb1.CoordY, rb1.CoordZ));
							else map.RemoveBlock(p1);
							continue;
						}
						TGprint("V4 [" + tostring(placed+2) + "] " + SLOPE_START + " (escape-exit) @ " + tostring(p2) + "  dir=" + DirStr(g_travelDir));
						// PlaceConnected updated g_travelDir to SLOPE_START's exit direction.
						// Restore to afterSlopeEndDir — the actual physical direction the road travels.
						g_travelDir = afterSlopeEndDir;
						TGprint("  slope-escape: restored g_travelDir=" + DirStr(g_travelDir) + " (actual physical direction)");

						string escFlat = flatPool[MathRand(0, int(flatPool.Length) - 1)];
						TGprint("  slope-escape: trying flat " + escFlat + " from " + tostring(p2));
						int3 p3 = PlaceConnected(map, p2, escFlat);
						if (p3.x < 0) {
							TGprint("  slope-escape: flat failed, removing SLOPE_START @ " + tostring(p2) + " and SLOPE_END @ " + tostring(p1));
							while (!map.IsEditorReadyForRequest) { yield(); }
							auto rb2 = map.GetBlock(p2);
							if (rb2 !is null) map.RemoveBlock(int3(rb2.CoordX, rb2.CoordY, rb2.CoordZ));
							else map.RemoveBlock(p2);
							while (!map.IsEditorReadyForRequest) { yield(); }
							auto rb1 = map.GetBlock(p1);
							if (rb1 !is null) map.RemoveBlock(int3(rb1.CoordX, rb1.CoordY, rb1.CoordZ));
							else map.RemoveBlock(p1);
							continue;
						}
						TGprint("V4 [" + tostring(placed+3) + "] " + escFlat + " (escape-flat) @ " + tostring(p3) + "  dir=" + DirStr(g_travelDir));

						placed++; placedCoords.InsertLast(p1); placedDirs.InsertLast(g_travelDir);
						placed++; placedCoords.InsertLast(p2); placedDirs.InsertLast(g_travelDir);
						placed++; placedCoords.InsertLast(p3); placedDirs.InsertLast(g_travelDir);
						prevPos = p3; state = SurfaceState::Flat; stateRun = 0; flatRun = 1;
						TGprint("V4: slope-escape succeeded, placed [" + tostring(placed) + "]");
						slopeEscaped = true;
					}
					if (slopeEscaped) continue;
				}

				// Fallback 4: all options exhausted — stop here, keep what was placed.
				TGprint("\\$f00V4: all fallbacks failed — stopping at [" + tostring(placed) + "] blocks");
				break;
			}

			prevPos = newPos;
			state   = targetState;
			placed++;
			placedCoords.InsertLast(newPos); placedDirs.InsertLast(g_travelDir);
			stateRun++;
			if (state == SurfaceState::Flat) { flatRun++; stateRun = 0; }
			else flatRun = 0;

			TGprint("V4 [" + tostring(placed) + "] " + targetBlock + " @ " + tostring(newPos)
				+ "  dir=" + DirStr(g_travelDir)
				+ "  state=" + (state == SurfaceState::Flat ? "Flat"
					: state == SurfaceState::Slope ? ("Slope/" + (slopeDir == SlopeDir::SlopeUp ? "Up" : "Down"))
					: ("Tilt/" + (tiltSide == TiltSide::TiltLeft ? "L" : "R"))));
		}

		if (needsRedo) {
			TGprint("\\$f0fV4: clearing " + tostring(placedCoords.Length) + " placed blocks...");
			ClearPlaced(map, placedCoords);
			// MAX_ATTEMPTS=1 so no retry — fall through to failure message.
			break;
		}

		// ── Exit any active non-flat state before placing Finish ──────────

		if (state == SurfaceState::Slope) {
			int3 p = ExitSlope(map, prevPos, slopeDir);
			if (p.x >= 0) { prevPos = p; placed++; placedCoords.InsertLast(p); placedDirs.InsertLast(g_travelDir); state = SurfaceState::Flat; }
		}
		if (state == SurfaceState::Tilt) {
			int3 p = ExitTilt(map, prevPos, tiltSide);
			if (p.x >= 0) { prevPos = p; placed++; placedCoords.InsertLast(p); placedDirs.InsertLast(g_travelDir); state = SurfaceState::Flat; tiltSide = TiltSide::TiltNone; }
		}

		// ── Place Finish ──────────────────────────────────────────────────

		string finishName = "RoadTechFinish";
		auto prevBlock = GetBlockAt(map, prevPos);
		if (prevBlock !is null) {
			auto finishInfo = map.GetBlockModelFromName(finishName);
			if (finishInfo is null) {
				TGprint("\\$f00V4: GetBlockModelFromName failed for '" + finishName + "'");
			} else {
				while (!map.IsEditorReadyForRequest) { yield(); }
				map.GetConnectResults(prevBlock, finishInfo);
				while (!map.IsEditorReadyForRequest) { yield(); }
				for (uint r = 0; r < map.ConnectResults.Length; r++) {
					auto res = map.ConnectResults[r];
					if (res is null || !res.CanPlace) continue;
					auto coord = res.Coord;
					auto dir   = ConvertDir(res.Dir);
					if (CanPlaceBlock(map, finishName, dir, coord)) {
						PlaceBlock(map, finishName, dir, coord);
						placedCoords.InsertLast(coord); placedDirs.InsertLast(g_travelDir);
						TGprint("V4 Finish placed at " + tostring(coord));
					}
					break;
				}
			}
		}

		uint64 elapsed = Time::get_Now() - before;
		TGprint("\\$0f0\\$sV4 done: " + tostring(placed) + " blocks in " + tostring(elapsed) + " ms");
		UI::ShowNotification("V4 Track: " + tostring(placed) + " blocks");
		lastRunCoords = placedCoords;
		return;
	}

	// Generation failed — blocks already cleared above.
	TGprint("\\$f00V4: could not generate track. Check logs above for placement details.");
	UI::ShowNotification("V4: Could not generate track.");
}

void ClearLastRun()
{
	auto app = cast<CTrackMania>(GetApp());
	if (app is null) return;
	auto editor = cast<CGameCtnEditorFree>(app.Editor);
	if (editor is null) { UI::ShowNotification("Editor not open!"); return; }
	auto map = cast<CGameEditorPluginMap>(editor.PluginMapType);
	if (map is null) return;

	if (lastRunCoords.Length == 0) {
		UI::ShowNotification("V4: nothing to clear.");
		return;
	}
	ClearPlaced(map, lastRunCoords);
	TGprint("V4: cleared " + tostring(lastRunCoords.Length) + " blocks from last run.");
	UI::ShowNotification("V4: track cleared.");
	lastRunCoords.Resize(0);
}

// Probe the last manually placed block: log its name, coord, stored direction,
// and what GetConnectResults returns for each tilt transition block.
void ProbeLastBlock()
{
	auto app = cast<CTrackMania>(GetApp());
	if (app is null) return;
	auto editor = cast<CGameCtnEditorFree>(app.Editor);
	if (editor is null) { UI::ShowNotification("Editor not open!"); return; }
	auto map = cast<CGameEditorPluginMap>(editor.PluginMapType);
	if (map is null) return;

	auto allB = GetApp().RootMap.Blocks;
	if (allB.Length == 0) { TGprint("V4 probe: no blocks on map."); return; }

	// Take the last block in the array.
	auto b = allB[allB.Length - 1];
	int3 bCoord = int3(b.CoordX, b.CoordY, b.CoordZ);
	string bName = b.BlockModel.IdName;

	// Read stored direction via the block's Dir field.
	string bDir = "?";
	// CGameCtnBlock stores direction as an int (0=N,1=E,2=S,3=W in TM convention).
	// Use DirStr on the converted value if available, otherwise log raw int.
	TGprint("V4 probe: last block = '" + bName + "'  coord=" + tostring(bCoord));

	// Call GetConnectResults for each tilt transition and log every result.
	array<string> tiltBlocks = { TILT_UP_LEFT, TILT_UP_RIGHT, TILT_DOWN_LEFT, TILT_DOWN_RIGHT };
	for (uint t = 0; t < tiltBlocks.Length; t++) {
		string nextName = tiltBlocks[t];
		auto info = map.GetBlockModelFromName(nextName);
		if (info is null) { TGprint("  [" + nextName + "]: model not found"); continue; }

		while (!map.IsEditorReadyForRequest) { yield(); }
		map.GetConnectResults(b, info);
		while (!map.IsEditorReadyForRequest) { yield(); }

		int total = int(map.ConnectResults.Length);
		TGprint("  [" + nextName + "]  connectResults=" + tostring(total));
		for (uint r = 0; r < map.ConnectResults.Length; r++) {
			auto res = map.ConnectResults[r];
			if (res is null) { TGprint("    [" + tostring(r) + "] null"); continue; }
			auto dir = ConvertDir(res.Dir);
			bool canPlace = res.CanPlace ? CanPlaceBlock(map, nextName, dir, res.Coord) : false;
			TGprint("    [" + tostring(r) + "] coord=" + tostring(res.Coord)
				+ "  dir=" + DirStr(dir)
				+ "  CanPlace=" + (res.CanPlace ? "YES" : "NO")
				+ "  canPlaceBlock=" + (canPlace ? "YES" : "NO"));
		}
	}
}

// Check the last block on the map: log its name, coord, and all connection points
// (direction + whether a straight block can connect there).
void CheckDirectionForBlocks()
{
	auto app = cast<CTrackMania>(GetApp());
	if (app is null) return;
	auto editor = cast<CGameCtnEditorFree>(app.Editor);
	if (editor is null) { UI::ShowNotification("Editor not open!"); return; }
	auto map = cast<CGameEditorPluginMap>(editor.PluginMapType);
	if (map is null) return;

	auto allB = GetApp().RootMap.Blocks;
	if (allB.Length == 0) { TGprint("CheckDir: no blocks on map."); return; }

	auto b = allB[allB.Length - 1];
	int3 bCoord = int3(b.CoordX, b.CoordY, b.CoordZ);
	string bName = b.BlockModel.IdName;
	TGprint("CheckDir: last block = '" + bName + "'  anchor=" + tostring(bCoord));

	// Use RoadTechStraight as probe — its connections are simple (one entry, one exit).
	string probeName = "RoadTechStraight";
	auto probeInfo = map.GetBlockModelFromName(probeName);
	if (probeInfo is null) { TGprint("CheckDir: probe model '" + probeName + "' not found"); return; }

	while (!map.IsEditorReadyForRequest) { yield(); }
	map.GetConnectResults(b, probeInfo);
	while (!map.IsEditorReadyForRequest) { yield(); }

	int total = int(map.ConnectResults.Length);
	TGprint("CheckDir: " + tostring(total) + " connection point(s) found for '" + bName + "':");
	for (uint r = 0; r < map.ConnectResults.Length; r++) {
		auto res = map.ConnectResults[r];
		if (res is null) { TGprint("  [" + tostring(r) + "] null"); continue; }
		auto dir = ConvertDir(res.Dir);
		bool canPlace = res.CanPlace ? CanPlaceBlock(map, probeName, dir, res.Coord) : false;
		TGprint("  [" + tostring(r) + "] dir=" + DirStr(dir)
			+ "  coord=" + tostring(res.Coord)
			+ "  CanPlace=" + (res.CanPlace ? "YES" : "NO")
			+ "  canPlaceBlock=" + (canPlace ? "YES" : "NO"));
	}
	if (total == 0) {
		TGprint("  (no connection points — block may not support connections, or map has no valid snap)");
	}
}

} // namespace v4
