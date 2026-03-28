// Track Generator V4: RoadTech-only, surface state machine.
// Surface states: Flat, Slope, Tilt.
// Block pool loaded from block_data/roadtech_v4_blocks.txt.
// Transition blocks (SlopeStart/End, TiltTransition) are inserted automatically.
// Place a RoadTechStart block first, then generate.

namespace v4 {

enum SurfaceState { Flat, Slope, Tilt }
enum TiltSide { TiltNone, TiltLeft, TiltRight }
enum SlopeDir { SlopeUp, SlopeDown }
// Road surfaces supported by the generator.
// SurfaceTech is the base; all others transition through Tech.
// SURFACE_COUNT is a sentinel — always keep it last.
enum Surface { SurfaceTech = 0, SurfaceDirt = 1, SurfaceBump = 2, SurfaceIce = 3, SURFACE_COUNT = 4 }

// Combined phase — single value encoding current surface state + direction/side.
// Use this for fallback decisions instead of checking state+slopeDir+tiltSide separately.
enum TrackPhase { PhaseFlat = 0, PhaseSlopeUp = 1, PhaseSlopeDown = 2, PhaseTiltLeft = 3, PhaseTiltRight = 4 }

TrackPhase ComputePhase(SurfaceState s, SlopeDir sd, TiltSide ts)
{
	if (s == SurfaceState::Slope) return sd == SlopeDir::SlopeUp ? TrackPhase::PhaseSlopeUp : TrackPhase::PhaseSlopeDown;
	if (s == SurfaceState::Tilt)  return ts == TiltSide::TiltLeft ? TrackPhase::PhaseTiltLeft : TrackPhase::PhaseTiltRight;
	return TrackPhase::PhaseFlat;
}

const int MAX_SLOPE_RUN = 8;
const int MAX_TILT_RUN  = 12;
const int MIN_FLAT_RUN  = 3;
const int MIN_SLOPE_RUN = 3;
const int MIN_TILT_RUN  = 3;
const int MAX_ATTEMPTS  = 1;  // single attempt — clear and fail on hard failure

const string RAMP_ESCAPE = "RoadTechRampLow";

// ── Per-surface data tables (indexed by Surface enum value) ──────────────────
// Add a new surface: extend each table, add a pool file, add settings + UI.

// Block name prefix — used by BlockSurface() to identify a block's surface.
const array<string> SURF_PREFIX = {
    "RoadTech",  // SurfaceTech
    "RoadDirt",  // SurfaceDirt
    "RoadBump",  // SurfaceBump
    "RoadIce",   // SurfaceIce
};

// Canonical straight block per surface — used as the flat fallback.
const array<string> SURF_STRAIGHT = {
    "RoadTechStraight",  // SurfaceTech
    "RoadDirtStraight",  // SurfaceDirt
    "RoadBumpStraight",  // SurfaceBump
    "RoadIceStraight",   // SurfaceIce
};

// Slope entry/exit transition blocks per surface.
const array<string> SURF_SLOPE_START = {
    "RoadTechSlopeStart2x1",  // SurfaceTech
    "RoadDirtSlopeStart2x1",  // SurfaceDirt
    "RoadBumpSlopeStart2x1",  // SurfaceBump
    "RoadIceSlopeStart2x1",   // SurfaceIce
};
const array<string> SURF_SLOPE_END = {
    "RoadTechSlopeEnd2x1",    // SurfaceTech
    "RoadDirtSlopeEnd2x1",    // SurfaceDirt
    "RoadBumpSlopeEnd2x1",    // SurfaceBump
    "RoadIceSlopeEnd2x1",     // SurfaceIce
};

// Tilt entry/exit transition blocks per surface (empty = surface has no tilt).
const array<string> SURF_TILT_UP_LEFT = {
    "RoadTechTiltTransition1UpLeft",   // SurfaceTech
    "RoadDirtTiltTransition1UpLeft",   // SurfaceDirt
    "RoadBumpTiltTransition1UpLeft",   // SurfaceBump
    "",                                // SurfaceIce — no tilt
};
const array<string> SURF_TILT_UP_RIGHT = {
    "RoadTechTiltTransition1UpRight",  // SurfaceTech
    "RoadDirtTiltTransition1UpRight",  // SurfaceDirt
    "RoadBumpTiltTransition1UpRight",  // SurfaceBump
    "",                                // SurfaceIce — no tilt
};
const array<string> SURF_TILT_DOWN_LEFT = {
    "RoadTechTiltTransition1DownLeft", // SurfaceTech
    "RoadDirtTiltTransition1DownLeft", // SurfaceDirt
    "RoadBumpTiltTransition1DownLeft", // SurfaceBump
    "",                                // SurfaceIce — no tilt
};
const array<string> SURF_TILT_DOWN_RIGHT = {
    "RoadTechTiltTransition1DownRight",// SurfaceTech
    "RoadDirtTiltTransition1DownRight",// SurfaceDirt
    "RoadBumpTiltTransition1DownRight",// SurfaceBump
    "",                                // SurfaceIce — no tilt
};

// Capability flags per surface.
const array<bool> SURF_HAS_SLOPE = { true, true, true, true  };
const array<bool> SURF_HAS_TILT  = { true, true, true, false }; // Ice has no tilt

// Surface ↔ Tech transition blocks, flat array indexed [surf * 5 + phase].
// Phase order matches TrackPhase enum: 0=Flat, 1=SlopeUp, 2=SlopeDown, 3=TiltLeft, 4=TiltRight.
// Empty string = transition not available (incompatible phase for this surface).
// These blocks are bidirectional by rotation — same block for Tech→X and X→Tech.
const array<string> SURF_TRANS_TABLE = {
    // SurfaceTech (0): no transition needed
    "", "", "", "", "",
    // SurfaceDirt (1)
    "RoadTechToRoadDirt", "RoadTechToRoadDirtSlopeUp", "RoadTechToRoadDirtSlopeDown", "RoadTechToRoadDirtTiltLeft", "RoadTechToRoadDirtTiltRight",
    // SurfaceBump (2)
    "RoadTechToRoadBump", "RoadTechToRoadBumpSlopeUp", "RoadTechToRoadBumpSlopeDown", "RoadTechToRoadBumpTiltLeft", "RoadTechToRoadBumpTiltRight",
    // SurfaceIce (3) — no tilt transitions
    "RoadTechToRoadIce", "RoadTechToRoadIceSlopeUp", "RoadTechToRoadIceSlopeDown", "", "",
};

// Current surface — updated whenever a surface transition block is placed.
// Governs which slope/tilt transition block constants are used.
Surface g_surface = Surface::SurfaceTech;

// Coords of the last successful V4 generation (used by ClearLastRun).
array<int3> lastRunCoords;

// Probe block used by CheckDirectionForBlocks — set from the UI dropdown before calling.
string g_checkDirProbeName = "RoadTechStraight";

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

	// Load extra surface pools — each file mirrors roadtech_v4_blocks.txt structure.
	// Parallel arrays: file name, master enable, slope enable, tilt enable.
	// Ice tilt is always false — RoadIce has no tilt transition blocks.
	array<string> xFiles   = { "roaddirt_v4_blocks.txt", "roadbump_v4_blocks.txt", "roadice_v4_blocks.txt" };
	array<bool>   xEnabled = { st_v4Dirt,                st_v4Bump,                st_v4Ice                };
	array<bool>   xSlope   = { st_v4DirtSlope,           st_v4BumpSlope,           st_v4IceSlope           };
	array<bool>   xTilt    = { st_v4DirtTilt,            st_v4BumpTilt,            false                   };
	for (uint xi = 0; xi < xFiles.Length; xi++) {
		if (!xEnabled[xi]) continue;
		string xPath = GetBlockDataPath() + xFiles[xi];
		try {
			IO::File xf(xPath, IO::FileMode::Read);
			string xsec = "";
			while (!xf.EOF()) {
				string line = xf.ReadLine().Trim();
				if (line.StartsWith("## ")) {
					string h = line.ToUpper();
					if      (h.IndexOf("EXCLUDED")        >= 0) xsec = "EXCLUDED";
					else if (h.IndexOf("SLOPE TRANSITION") >= 0) xsec = "SLOPE_TRANS";
					else if (h.IndexOf("TILT TRANSITION")  >= 0) xsec = "TILT_TRANS";
					else if (h.IndexOf("SLOPE")            >= 0) xsec = "SLOPE";
					else if (h.IndexOf("TILT")             >= 0) xsec = "TILT";
					else if (h.IndexOf("FLAT")             >= 0) xsec = "FLAT";
					continue;
				}
				if (line.Length == 0 || line.SubStr(0, 1) == "#") continue;
				if (xsec == "EXCLUDED" || xsec == "SLOPE_TRANS" || xsec == "TILT_TRANS") continue;
				if (!st_v4Special && line.IndexOf("Special") >= 0) continue;
				if (xsec == "FLAT") {
					flatPool.InsertLast(line);
				} else if (xsec == "SLOPE" && xSlope[xi]) {
					slopePool.InsertLast(line);
					bool isDown = line.IndexOf("SlopeDown") >= 0;
					bool isUp   = line.IndexOf("SlopeUp")   >= 0;
					if (!isDown) slopeUpPool.InsertLast(line);
					if (!isUp)   slopeDownPool.InsertLast(line);
				} else if (xsec == "TILT" && xTilt[xi] && !IsTiltDirectedCurve(line)) {
					tiltPool.InsertLast(line);
				}
			}
			xf.Close();
		} catch {
			TGprint("\\$f00V4: failed to load " + xFiles[xi]);
		}
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

// ── Surface helpers ───────────────────────────────────────────────────────────

// Identifies a block's surface by checking its name prefix against SURF_PREFIX.
// Checks non-Tech surfaces first (longer/more specific prefixes win over "RoadTech").
Surface BlockSurface(const string &in name)
{
	for (int s = int(Surface::SURFACE_COUNT) - 1; s >= 1; s--) {
		string pfx = SURF_PREFIX[s];
		if (int(name.Length) >= int(pfx.Length) && name.SubStr(0, pfx.Length) == pfx)
			return Surface(s);
	}
	return Surface::SurfaceTech;
}

// Returns the Tech↔surface transition block name for the given surface and phase.
// Returns "" if no transition exists (e.g. Ice has no tilt transitions).
// The same block is used in both directions — bidirectional by rotation.
string SurfTransBlock(Surface surf, TrackPhase phase)
{
	return SURF_TRANS_TABLE[int(surf) * 5 + int(phase)];
}

// Convenience accessors using g_surface.
string GetStraight()       { return SURF_STRAIGHT[int(g_surface)]; }
string GetSlopeStart()     { return SURF_SLOPE_START[int(g_surface)]; }
string GetSlopeEnd()       { return SURF_SLOPE_END[int(g_surface)]; }
string GetTiltUpLeft()     { return SURF_TILT_UP_LEFT[int(g_surface)]; }
string GetTiltUpRight()    { return SURF_TILT_UP_RIGHT[int(g_surface)]; }
string GetTiltDownLeft()   { return SURF_TILT_DOWN_LEFT[int(g_surface)]; }
string GetTiltDownRight()  { return SURF_TILT_DOWN_RIGHT[int(g_surface)]; }

// Returns a random block from pool that matches the current surface prefix.
// Falls back to the full pool if no surface-matching blocks exist.
string PickFromPool(const array<string>@ pool) {
	string pfx = SURF_PREFIX[int(g_surface)];
	array<string> filtered;
	for (uint i = 0; i < pool.Length; i++)
		if (pool[i].SubStr(0, pfx.Length) == pfx)
			filtered.InsertLast(pool[i]);
	if (filtered.Length == 0) {
		TGprint("\\$f80PickFromPool: no " + pfx + " blocks in pool, using full pool");
		return pool[MathRand(0, int(pool.Length) - 1)];
	}
	return filtered[MathRand(0, int(filtered.Length) - 1)];
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
				int3 placed = FindNewlyPlacedBlock(blockName, preLen, coord);
				TGprint("    PlaceConnected pass3 (backDir): placed " + blockName + " @ " + tostring(placed) + "  dir=" + DirStr(dir) + "  g_travelDir unchanged=" + DirStr(g_travelDir));
				return placed;
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
	string slopeStart = GetSlopeStart();
	string slopeEnd   = GetSlopeEnd();
	if (MathRand(0, 1) == 0) {
		int3 newPos = PlaceReversedConnected(map, prevPos, slopeEnd);
		if (newPos.x >= 0) {
			dir = SlopeDir::SlopeDown;
			TGprint("V4 trans: Flat→Slope/Down  " + slopeEnd + " @ " + tostring(newPos) + "  dir=" + DirStr(g_travelDir));
			return newPos;
		}
		TGprint("  → EnterSlope: " + slopeEnd + " (reversed) failed from " + tostring(prevPos) + "  travelDir=" + DirStr(g_travelDir) + ", trying SlopeUp");
	}
	dir = SlopeDir::SlopeUp;
	int3 newPos = PlaceConnected(map, prevPos, slopeStart);
	if (newPos.x < 0) {
		TGprint("  → EnterSlope: " + slopeStart + " failed from " + tostring(prevPos) + "  travelDir=" + DirStr(g_travelDir));
		return int3(-1, -1, -1);
	}
	TGprint("V4 trans: Flat→Slope/Up  " + slopeStart + " @ " + tostring(newPos) + "  dir=" + DirStr(g_travelDir));
	return newPos;
}

// Exit slope → flat.
// SlopeDown: slope body forward socket connects to SLOPE_START (exits at lower flat).
// SlopeUp:   slope body forward socket connects to SLOPE_END (exits at upper flat).
int3 ExitSlope(CGameEditorPluginMap@ map, int3 prevPos, SlopeDir dir)
{
	string slopeStart = GetSlopeStart();
	string slopeEnd   = GetSlopeEnd();
	if (dir == SlopeDir::SlopeDown) {
		int3 newPos = PlaceReversedConnected(map, prevPos, slopeStart);
		if (newPos.x >= 0) { TGprint("V4 trans: Slope/Down→Flat  " + slopeStart + " @ " + tostring(newPos) + "  dir=" + DirStr(g_travelDir)); return newPos; }
		TGprint("  → ExitSlope: " + slopeStart + " failed from " + tostring(prevPos) + "  travelDir=" + DirStr(g_travelDir));
		LogPlacementDiag(map, prevPos, slopeStart);
		return int3(-1, -1, -1);
	}
	// SlopeUp
	int3 newPos = PlaceConnected(map, prevPos, slopeEnd);
	if (newPos.x < 0) {
		TGprint("  → ExitSlope: " + slopeEnd + " failed from " + tostring(prevPos) + "  travelDir=" + DirStr(g_travelDir));
		LogPlacementDiag(map, prevPos, slopeEnd);
		return int3(-1, -1, -1);
	}
	TGprint("V4 trans: Slope/Up→Flat  " + slopeEnd + " @ " + tostring(newPos) + "  dir=" + DirStr(g_travelDir));
	return newPos;
}

int3 ExitTilt(CGameEditorPluginMap@ map, int3 prevPos, TiltSide side)
{
	string block1 = (side == TiltSide::TiltRight) ? GetTiltDownRight() : GetTiltDownLeft();
	string block2 = (side == TiltSide::TiltRight) ? GetTiltDownLeft()  : GetTiltDownRight();
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
	TiltSide firstSide = (MathRand(0, 1) == 0) ? TiltSide::TiltLeft : TiltSide::TiltRight;
	for (int attempt = 0; attempt < 2; attempt++) {
		side = (attempt == 0) ? firstSide
		                      : (firstSide == TiltSide::TiltLeft ? TiltSide::TiltRight : TiltSide::TiltLeft);
		string block = (side == TiltSide::TiltRight) ? GetTiltUpRight() : GetTiltUpLeft();

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
		array<Surface> placedSurfaces;
		int3 prevPos       = startPos;
		SurfaceState state = SurfaceState::Flat;
		TiltSide tiltSide  = TiltSide::TiltNone;
		SlopeDir slopeDir  = SlopeDir::SlopeUp;
		int stateRun       = 0;
		int flatRun        = 0;
		TrackPhase phase   = TrackPhase::PhaseFlat;
		int placed         = 0;
		bool needsRedo     = false;
		g_travelDir = GetBlockDirection(startBlock);
		g_surface   = Surface::SurfaceTech;
		auto initDir = g_travelDir;  // saved for direction restore after full backtrack

		TGprint("\\$0f0\\$sGenerating track (V4 RoadTech surface-state)!");

		for (int i = 0; placed < st_maxBlocks && i < st_maxBlocks * 30; i++)
		{
			// ── Update phase ─────────────────────────────────────────────
			phase = ComputePhase(state, slopeDir, tiltSide);

			// ── Pick target ───────────────────────────────────────────────

			int wFlat  = 60;
			int wSlope = (st_v4Slope && slopePool.Length > 0 && SURF_HAS_SLOPE[int(g_surface)]) ? 20 : 0;
			int wTilt  = (st_v4Tilt  && tiltPool.Length  > 0 && SURF_HAS_TILT[int(g_surface)])  ? 20 : 0;
			int total  = wFlat + wSlope + wTilt;
			int roll   = MathRand(0, total - 1);

			SurfaceState targetState;
			string targetBlock;

			if (roll < wFlat) {
				targetState = SurfaceState::Flat;
				targetBlock = PickFromPool(flatPool);
			} else if (roll < wFlat + wSlope) {
				targetState = SurfaceState::Slope;
				// Use directional pool when already in slope, full pool otherwise
				// (direction gets set by EnterSlope for new slope sections).
				array<string>@ sp = slopePool;
				if (state == SurfaceState::Slope) {
					sp = (slopeDir == SlopeDir::SlopeUp) ? slopeUpPool : slopeDownPool;
				}
				targetBlock = PickFromPool(sp);
			} else {
				targetState = SurfaceState::Tilt;
				// When already in tilt, use the side-specific pool to avoid
				// mixing Left/Right blocks which causes exit transition failures.
				array<string>@ tp = tiltPool;
				if (state == SurfaceState::Tilt) {
					tp = (tiltSide == TiltSide::TiltLeft) ? tiltLeftPool : tiltRightPool;
				}
				targetBlock = PickFromPool(tp);
			}

			// ── Enforce run limits ────────────────────────────────────────

			if (state == SurfaceState::Flat && flatRun < MIN_FLAT_RUN && targetState != SurfaceState::Flat) {
				targetState = SurfaceState::Flat;
				targetBlock = PickFromPool(flatPool);
			}
			if (state == SurfaceState::Slope && stateRun < MIN_SLOPE_RUN && targetState != SurfaceState::Slope) {
				targetState = SurfaceState::Slope;
				array<string>@ minPool = (slopeDir == SlopeDir::SlopeUp) ? slopeUpPool : slopeDownPool;
				targetBlock = PickFromPool(minPool);
			}
			if (state == SurfaceState::Tilt && stateRun < MIN_TILT_RUN && targetState != SurfaceState::Tilt) {
				targetState = SurfaceState::Tilt;
				targetBlock = PickFromPool(tiltPool);
			}
			if (state == SurfaceState::Slope && stateRun >= MAX_SLOPE_RUN && targetState != SurfaceState::Flat) {
				targetState = SurfaceState::Flat;
				targetBlock = PickFromPool(flatPool);
			}
			if (state == SurfaceState::Tilt && stateRun >= MAX_TILT_RUN && targetState != SurfaceState::Flat) {
				targetState = SurfaceState::Flat;
				targetBlock = PickFromPool(flatPool);
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
					prevPos = p; placed++; placedCoords.InsertLast(p); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface); state = SurfaceState::Slope; stateRun = 0; flatRun = 0;
					// Re-pick target from the now-known directional pool.
					array<string>@ sp = (slopeDir == SlopeDir::SlopeUp) ? slopeUpPool : slopeDownPool;
					if (sp.Length > 0) targetBlock = PickFromPool(sp);
				}
			}
			else if (state == SurfaceState::Flat && targetState == SurfaceState::Tilt) {
				int3 p = EnterTilt(map, prevPos, tiltSide);
				if (p.x < 0) { transOk = false; }
				else {
					prevPos = p; placed++; placedCoords.InsertLast(p); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface); state = SurfaceState::Tilt; stateRun = 0; flatRun = 0;
					// Re-pick target from the now-known side pool so the first
					// tilt body block is also side-consistent.
					array<string>@ sp = (tiltSide == TiltSide::TiltLeft) ? tiltLeftPool : tiltRightPool;
					if (sp.Length > 0) targetBlock = PickFromPool(sp);
				}
			}
			else if (state == SurfaceState::Slope && targetState == SurfaceState::Flat) {
				int3 p = ExitSlope(map, prevPos, slopeDir);
				if (p.x < 0) {
					if (phase == TrackPhase::PhaseSlopeUp) {
						// Transition block unavailable — pop last slope body block and
						// place a flat block directly. Going uphill the car will jump the
						// height difference, so a missing transition is acceptable.
						TGprint("V4: SlopeUp exit failed — jump-landing fallback: popping last slope block");
						int3 popCoord = placedCoords[placedCoords.Length - 1];
						while (!map.IsEditorReadyForRequest) { yield(); }
						auto pb = map.GetBlock(popCoord);
						if (pb !is null) map.RemoveBlock(int3(pb.CoordX, pb.CoordY, pb.CoordZ));
						else map.RemoveBlock(popCoord);
						placed--; placedCoords.RemoveLast(); placedDirs.RemoveLast(); placedSurfaces.RemoveLast(); g_surface = (placedSurfaces.Length > 0) ? placedSurfaces[placedSurfaces.Length - 1] : Surface::SurfaceTech;
						prevPos     = (placedCoords.Length > 0) ? placedCoords[placedCoords.Length - 1] : startPos;
						g_travelDir = (placedDirs.Length   > 0) ? placedDirs[placedDirs.Length - 1]     : initDir;
						state = SurfaceState::Flat; tiltSide = TiltSide::TiltNone; stateRun = 0;
						int3 fp = PlaceConnected(map, prevPos, PickFromPool(flatPool));
						if (fp.x >= 0) {
							TGprint("V4: jump-landing flat placed @ " + tostring(fp));
							prevPos = fp; placed++; placedCoords.InsertLast(fp); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface);
							flatRun = 1; continue;
						}
						TGprint("V4: jump-landing flat also failed — falling through to generic fallback");
						transOk = false;
					} else {
						transOk = false;
					}
				}
				else { prevPos = p; placed++; placedCoords.InsertLast(p); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface); state = SurfaceState::Flat; stateRun = 0; flatRun = 0; }
			}
			else if (state == SurfaceState::Slope && targetState == SurfaceState::Tilt) {
				int3 p = ExitSlope(map, prevPos, slopeDir);
				if (p.x < 0) { transOk = false; }
				else {
					prevPos = p; placed++; placedCoords.InsertLast(p); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface); state = SurfaceState::Flat;
					int3 p2 = EnterTilt(map, prevPos, tiltSide);
					if (p2.x < 0) { transOk = false; }
					else { prevPos = p2; placed++; placedCoords.InsertLast(p2); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface); state = SurfaceState::Tilt; stateRun = 0; flatRun = 0; }
				}
			}
			else if (state == SurfaceState::Tilt && targetState == SurfaceState::Flat) {
				int3 p = ExitTilt(map, prevPos, tiltSide);
				if (p.x < 0) { transOk = false; }
				else { prevPos = p; placed++; placedCoords.InsertLast(p); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface); state = SurfaceState::Flat; stateRun = 0; flatRun = 0; tiltSide = TiltSide::TiltNone; }
			}
			else if (state == SurfaceState::Tilt && targetState == SurfaceState::Slope) {
				int3 p = ExitTilt(map, prevPos, tiltSide);
				if (p.x < 0) { transOk = false; }
				else {
					prevPos = p; placed++; placedCoords.InsertLast(p); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface); state = SurfaceState::Flat; tiltSide = TiltSide::TiltNone;
					int3 p2 = EnterSlope(map, prevPos, slopeDir);
					if (p2.x < 0) { transOk = false; }
					else {
						prevPos = p2; placed++; placedCoords.InsertLast(p2); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface); state = SurfaceState::Slope; stateRun = 0; flatRun = 0;
						array<string>@ sp = (slopeDir == SlopeDir::SlopeUp) ? slopeUpPool : slopeDownPool;
						if (sp.Length > 0) targetBlock = PickFromPool(sp);
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
				int3 p = PlaceConnected(map, prevPos, PickFromPool(flatPool));
				if (p.x >= 0) { prevPos = p; placed++; placedCoords.InsertLast(p); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface); flatRun++; }
				continue;
			}

			// ── Surface transition ────────────────────────────────────────

			// If the target block is on a different surface, insert transition block(s).
			// Non-Tech surfaces can only transition through Tech — so going Dirt→Bump
			// requires two blocks: Dirt→Tech then Tech→Bump.
			// Each transition block is tried normal first, then flipped 180° (no dir change)
			// because the block is bidirectional — one orientation has the right surface facing
			// the previous block. Same logic as EnterTilt.
			{
				Surface targetSurface = BlockSurface(targetBlock);
				if (targetSurface != g_surface) {
					bool surfTransOk = true;

					// Step 1: if current surface is not Tech, exit to Tech first.
					if (g_surface != Surface::SurfaceTech) {
						string exitName = SurfTransBlock(g_surface, phase);
						if (exitName.Length == 0) {
							TGprint("V4: surf-trans exit " + SURF_PREFIX[int(g_surface)] + "→Tech not available for phase " + tostring(int(phase)) + " — skipping target");
							surfTransOk = false;
						} else {
							int3 tp = (phase == TrackPhase::PhaseSlopeDown)
								? PlaceReversedConnected(map, prevPos, exitName)
								: PlaceConnected(map, prevPos, exitName);
							if (tp.x < 0) tp = PlaceFlipped(map, prevPos, exitName);
							if (tp.x < 0) {
								TGprint("V4: surf-trans exit (" + exitName + ") failed — skipping target");
								surfTransOk = false;
							} else {
								TGprint("V4 surf-trans: " + exitName + " @ " + tostring(tp) + "  " + SURF_PREFIX[int(g_surface)] + "→Tech");
								g_surface = Surface::SurfaceTech;
								prevPos = tp; placed++; placedCoords.InsertLast(tp); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface);
							}
						}
					}

					// Step 2: if target is not Tech, enter from Tech.
					if (surfTransOk && targetSurface != Surface::SurfaceTech) {
						string enterName = SurfTransBlock(targetSurface, phase);
						if (enterName.Length == 0) {
							TGprint("V4: surf-trans enter Tech→" + SURF_PREFIX[int(targetSurface)] + " not available for phase " + tostring(int(phase)) + " — skipping target");
							surfTransOk = false;
						} else {
							int3 tp = (phase == TrackPhase::PhaseSlopeDown)
								? PlaceReversedConnected(map, prevPos, enterName)
								: PlaceConnected(map, prevPos, enterName);
							if (tp.x < 0) tp = PlaceFlipped(map, prevPos, enterName);
							if (tp.x < 0) {
								TGprint("V4: surf-trans enter (" + enterName + ") failed — skipping target");
								surfTransOk = false;
							} else {
								TGprint("V4 surf-trans: " + enterName + " @ " + tostring(tp) + "  Tech→" + SURF_PREFIX[int(targetSurface)]);
								g_surface = targetSurface;
								prevPos = tp; placed++; placedCoords.InsertLast(tp); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface);
							}
						}
					}

					if (!surfTransOk) continue;
				}
			}

			// ── Place target block ────────────────────────────────────────

			// Slope-down body blocks are placed with reverseDir sockets facing forward.
			// PlaceConnected would grab their entry-side sockets (preferDir) instead.
			int3 newPos = (phase == TrackPhase::PhaseSlopeDown)
				? PlaceReversedConnected(map, prevPos, targetBlock)
				: PlaceConnected(map, prevPos, targetBlock);
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
					placed--; placedCoords.RemoveLast(); placedDirs.RemoveLast(); placedSurfaces.RemoveLast(); g_surface = (placedSurfaces.Length > 0) ? placedSurfaces[placedSurfaces.Length - 1] : Surface::SurfaceTech;
					prevPos     = (placedCoords.Length > 0) ? placedCoords[placedCoords.Length - 1] : startPos;
					g_travelDir = (placedDirs.Length   > 0) ? placedDirs[placedDirs.Length - 1]     : initDir;
					state = SurfaceState::Flat; tiltSide = TiltSide::TiltNone; stateRun = 0; flatRun = 0;
					TGprint("V4: undid failed transition, placed [" + tostring(placed) + "]");
					int3 fp = PlaceConnected(map, prevPos, PickFromPool(flatPool));
					if (fp.x >= 0) {
						placed++; placedCoords.InsertLast(fp); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface); prevPos = fp; flatRun = 1;
						continue;
					}
				}

				// Fallback 1: if the block name contains Left/Right, try the mirrored variant.
				{
					string mirrorBlock = "";
					if      (targetBlock.IndexOf("Left")  >= 0) mirrorBlock = targetBlock.Replace("Left",  "Right");
					else if (targetBlock.IndexOf("Right") >= 0) mirrorBlock = targetBlock.Replace("Right", "Left");
					if (mirrorBlock != "") {
						TGprint("V4: mirror-fallback trying " + mirrorBlock + " from " + tostring(prevPos) + "  travelDir=" + DirStr(g_travelDir));
						int3 mirrorPos = (phase == TrackPhase::PhaseSlopeDown)
							? PlaceReversedConnected(map, prevPos, mirrorBlock)
							: PlaceConnected(map, prevPos, mirrorBlock);
						if (mirrorPos.x >= 0) {
							placed++; placedCoords.InsertLast(mirrorPos); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface);
							prevPos = mirrorPos; stateRun++; flatRun = (state == SurfaceState::Flat) ? flatRun + 1 : flatRun;
							TGprint("V4: mirror-fallback succeeded, placed [" + tostring(placed) + "]");
							continue;
						}
					}
				}

				// Fallback 2: try a straight block first, then a random flat block.
				{
					string anyFlat = GetStraight();
					TGprint("V4: flat-fallback trying " + anyFlat + " from " + tostring(prevPos) + "  travelDir=" + DirStr(g_travelDir));
					int3 flatPos = PlaceConnected(map, prevPos, anyFlat);
					if (flatPos.x >= 0) {
						placed++; placedCoords.InsertLast(flatPos); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface);
						prevPos = flatPos; state = SurfaceState::Flat; stateRun = 0; flatRun = 1;
						TGprint("V4: flat-fallback succeeded, placed [" + tostring(placed) + "]");
						continue;
					}
					TGprint("V4: flat-fallback failed -- trying slope-escape");
				}

				// Fallback 3+4: slope-down escape — pop 1 then 2 blocks one at a time.
				// After each pop try: SlopeEnd(reversed) -> SlopeStart(reversed) -> flat block.
				// Changes elevation to break out of crowded flat areas.
				{
					bool slopeEscaped = false;
					for (int popK = 1; popK <= 2 && !slopeEscaped && placedCoords.Length > 0; popK++) {
						int3 popCoord = placedCoords[placedCoords.Length - 1];
						string popName = "?";
						auto pbInfo = GetBlockAt(map, popCoord);
						if (pbInfo !is null) popName = pbInfo.BlockModel.IdName;
						TGprint("\\$f80V4: slope-escape pop: removed block [" + tostring(placed) + "] " + popName + " @ " + tostring(popCoord));
						while (!map.IsEditorReadyForRequest) { yield(); }
						auto pb = map.GetBlock(popCoord);
						if (pb !is null) map.RemoveBlock(int3(pb.CoordX, pb.CoordY, pb.CoordZ));
						else map.RemoveBlock(popCoord);
						placed--;
						placedCoords.RemoveLast(); placedDirs.RemoveLast(); placedSurfaces.RemoveLast(); g_surface = (placedSurfaces.Length > 0) ? placedSurfaces[placedSurfaces.Length - 1] : Surface::SurfaceTech;
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
							if (pn == GetSlopeEnd() || pn == GetSlopeStart() ||
							    pn == GetTiltUpLeft() || pn == GetTiltUpRight() ||
							    pn == GetTiltDownLeft() || pn == GetTiltDownRight()) {
								TGprint("\\$f80V4: slope-escape also pops transition block [" + tostring(placed) + "] " + pn + " @ " + tostring(prevPos));
								while (!map.IsEditorReadyForRequest) { yield(); }
								auto tb = map.GetBlock(prevPos);
								if (tb !is null) map.RemoveBlock(int3(tb.CoordX, tb.CoordY, tb.CoordZ));
								else map.RemoveBlock(prevPos);
								placed--;
								placedCoords.RemoveLast(); placedDirs.RemoveLast(); placedSurfaces.RemoveLast(); g_surface = (placedSurfaces.Length > 0) ? placedSurfaces[placedSurfaces.Length - 1] : Surface::SurfaceTech;
								prevPos     = (placedCoords.Length > 0) ? placedCoords[placedCoords.Length - 1] : startPos;
								g_travelDir = (placedDirs.Length   > 0) ? placedDirs[placedDirs.Length - 1]     : initDir;
							}
						}
					}

						string escSlopeEnd   = GetSlopeEnd();
						string escSlopeStart = GetSlopeStart();
						TGprint("  slope-escape: trying " + escSlopeEnd + " from " + tostring(prevPos) + "  reverseDir=" + DirStr(IntToDir((DirToInt(g_travelDir)+2)%4)));
						int3 p1 = PlaceReversedConnected(map, prevPos, escSlopeEnd);
						if (p1.x < 0) { TGprint("  slope-escape: " + escSlopeEnd + " failed"); continue; }
						TGprint("V4 [" + tostring(placed+1) + "] " + escSlopeEnd + " (escape-entry) @ " + tostring(p1) + "  dir=" + DirStr(g_travelDir));
						auto afterSlopeEndDir = g_travelDir;

						TGprint("  slope-escape: trying " + escSlopeStart + " from " + tostring(p1) + "  travelDir=" + DirStr(g_travelDir));
						int3 p2 = PlaceConnected(map, p1, escSlopeStart);
						if (p2.x < 0) {
							TGprint("\\$f80  slope-escape: " + escSlopeStart + " failed, removing [" + tostring(placed+1) + "] " + escSlopeEnd + " @ " + tostring(p1));
							while (!map.IsEditorReadyForRequest) { yield(); }
							auto rb1 = map.GetBlock(p1);
							if (rb1 !is null) map.RemoveBlock(int3(rb1.CoordX, rb1.CoordY, rb1.CoordZ));
							else map.RemoveBlock(p1);
							continue;
						}
						TGprint("V4 [" + tostring(placed+2) + "] " + escSlopeStart + " (escape-exit) @ " + tostring(p2) + "  dir=" + DirStr(g_travelDir));
						// PlaceConnected updated g_travelDir to SLOPE_START's exit direction.
						// Restore to afterSlopeEndDir — the actual physical direction the road travels.
						g_travelDir = afterSlopeEndDir;
						TGprint("  slope-escape: restored g_travelDir=" + DirStr(g_travelDir) + " (actual physical direction)");

						string escFlat = PickFromPool(flatPool);
						TGprint("  slope-escape: trying flat " + escFlat + " from " + tostring(p2));
						int3 p3 = PlaceConnected(map, p2, escFlat);
						if (p3.x < 0) {
							TGprint("\\$f80  slope-escape: flat failed, removing [" + tostring(placed+2) + "] " + escSlopeStart + " @ " + tostring(p2) + " and [" + tostring(placed+1) + "] " + escSlopeEnd + " @ " + tostring(p1));
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

						placed++; placedCoords.InsertLast(p1); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface);
						placed++; placedCoords.InsertLast(p2); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface);
						placed++; placedCoords.InsertLast(p3); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface);
						prevPos = p3; state = SurfaceState::Flat; stateRun = 0; flatRun = 1;
						TGprint("V4: slope-escape succeeded, placed [" + tostring(placed) + "]");
						slopeEscaped = true;
					}
					if (slopeEscaped) continue;
				}

				// Fallback 5: all options exhausted — stop here, keep what was placed.
				TGprint("\\$f00V4: all fallbacks failed — stopping at [" + tostring(placed) + "] blocks");
				break;
			}

			prevPos = newPos;
			state   = targetState;
			placed++;
			placedCoords.InsertLast(newPos); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface);
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
			if (p.x >= 0) { prevPos = p; placed++; placedCoords.InsertLast(p); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface); state = SurfaceState::Flat; }
		}
		if (state == SurfaceState::Tilt) {
			int3 p = ExitTilt(map, prevPos, tiltSide);
			if (p.x >= 0) { prevPos = p; placed++; placedCoords.InsertLast(p); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface); state = SurfaceState::Flat; tiltSide = TiltSide::TiltNone; }
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
						placedCoords.InsertLast(coord); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface);
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
	array<string> tiltBlocks = { GetTiltUpLeft(), GetTiltUpRight(), GetTiltDownLeft(), GetTiltDownRight() };
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

	string probeName = g_checkDirProbeName;
	auto probeInfo = map.GetBlockModelFromName(probeName);
	if (probeInfo is null) { TGprint("CheckDir: probe model '" + probeName + "' not found"); return; }

	while (!map.IsEditorReadyForRequest) { yield(); }
	map.GetConnectResults(b, probeInfo);
	while (!map.IsEditorReadyForRequest) { yield(); }

	int total = int(map.ConnectResults.Length);
	TGprint("CheckDir: " + tostring(total) + " connection point(s) found for '" + probeName + "' from '" + bName + "':");
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
