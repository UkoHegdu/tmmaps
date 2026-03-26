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

// Snapshot all coords currently occupied by blockName (used to find the newly-placed block).
array<int3> SnapshotBlockCoords(const string &in blockName)
{
	array<int3> coords;
	auto allB = GetApp().RootMap.Blocks;
	for (uint ak = 0; ak < allB.Length; ak++) {
		if (allB[ak].BlockModel.IdName == blockName)
			coords.InsertLast(int3(allB[ak].CoordX, allB[ak].CoordY, allB[ak].CoordZ));
	}
	return coords;
}

// After placing blockName, find the coord that was NOT in preCoords (the newly placed block).
int3 FindNewlyPlacedBlock(const string &in blockName, array<int3> &in preCoords, int3 fallback)
{
	auto allB = GetApp().RootMap.Blocks;
	for (uint ak = 0; ak < allB.Length; ak++) {
		if (allB[ak].BlockModel.IdName == blockName) {
			int3 c = int3(allB[ak].CoordX, allB[ak].CoordY, allB[ak].CoordZ);
			bool wasExisting = false;
			for (uint pi = 0; pi < preCoords.Length; pi++) {
				if (preCoords[pi].x == c.x && preCoords[pi].y == c.y && preCoords[pi].z == c.z) {
					wasExisting = true; break;
				}
			}
			if (!wasExisting) return c;
		}
	}
	return fallback;
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
			array<int3> preCoords = SnapshotBlockCoords(blockName);
			if (PlaceBlock(map, blockName, dir, res.Coord)) {
				g_travelDir = dir;
				return FindNewlyPlacedBlock(blockName, preCoords, res.Coord);
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
			array<int3> preCoords = SnapshotBlockCoords(blockName);
			if (PlaceBlock(map, blockName, dir, coord)) {
				g_travelDir = dir;
				return FindNewlyPlacedBlock(blockName, preCoords, coord);
			}
		}
	}
	return int3(-1, -1, -1);
}

// Place blockName with the direction OPPOSITE to travelDir, probing 1-4 cells forward.
// Used for SlopeDown entry (SLOPE_END reversed) and exit (SLOPE_START reversed).
// travelDir is NOT modified — the track continues in the same forward direction.
int3 PlaceReversed(CGameEditorPluginMap@ map, int3 prevPos, const string &in blockName)
{
	auto reverseDir = IntToDir((DirToInt(g_travelDir) + 2) % 4);
	int3 fwd        = MoveDir(g_travelDir);
	for (int offset = 1; offset <= 4; offset++) {
		int3 baseCoord = prevPos;
		for (int k = 0; k < offset; k++) baseCoord = baseCoord.opAdd(fwd);
		// Try y-1 first (reversed slope block's anchor sits one below flat level),
		// then y as fallback.
		for (int yOff = -1; yOff <= 0; yOff++) {
			int3 tryCoord = int3(baseCoord.x, baseCoord.y + yOff, baseCoord.z);
			while (!map.IsEditorReadyForRequest) { yield(); }
			if (CanPlaceBlock(map, blockName, reverseDir, tryCoord)) {
				while (!map.IsEditorReadyForRequest) { yield(); }
				array<int3> preCoords = SnapshotBlockCoords(blockName);
				if (PlaceBlock(map, blockName, reverseDir, tryCoord)) {
					return FindNewlyPlacedBlock(blockName, preCoords, tryCoord);
				}
			}
		}
	}
	return int3(-1, -1, -1);
}
// ── Transition helpers ────────────────────────────────────────────────────────────────────
// All helpers read/write g_travelDir so direction is tracked through transitions.

// Ascending entry: SLOPE_START (flat→slope going up).
// Descending entry: SLOPE_END reversed 180° (flat→slope going down). Falls back to ascending.
int3 EnterSlope(CGameEditorPluginMap@ map, int3 prevPos, SlopeDir &out dir)
{
	if (MathRand(0, 1) == 0) {
		int3 newPos = PlaceReversed(map, prevPos, SLOPE_END);
		if (newPos.x >= 0) {
			dir = SlopeDir::SlopeDown;
			TGprint("V4 trans: Flat→Slope/Down (" + SLOPE_END + " reversed)");
			return newPos;
		}
	}
	dir = SlopeDir::SlopeUp;
	int3 newPos = PlaceConnected(map, prevPos, SLOPE_START);
	if (newPos.x < 0) return int3(-1, -1, -1);
	TGprint("V4 trans: Flat→Slope/Up (" + SLOPE_START + ")");
	return newPos;
}

// Exit descending slope: SLOPE_START reversed (slope→flat at lower level).
// Exit ascending slope: SLOPE_END (slope→flat returning to entry level).
int3 ExitSlope(CGameEditorPluginMap@ map, int3 prevPos, SlopeDir dir)
{
	if (dir == SlopeDir::SlopeDown) {
		int3 newPos = PlaceReversed(map, prevPos, SLOPE_START);
		if (newPos.x >= 0) { TGprint("V4 trans: Slope/Down→Flat (" + SLOPE_START + " reversed)"); return newPos; }
	}
	int3 newPos = PlaceConnected(map, prevPos, SLOPE_END);
	if (newPos.x < 0) return int3(-1, -1, -1);
	TGprint("V4 trans: Slope/Up→Flat (" + SLOPE_END + ")");
	return newPos;
}

int3 ExitTilt(CGameEditorPluginMap@ map, int3 prevPos, TiltSide side)
{
	string block1 = (side == TiltSide::TiltRight) ? TILT_DOWN_RIGHT : TILT_DOWN_LEFT;
	string block2 = (side == TiltSide::TiltRight) ? TILT_DOWN_LEFT  : TILT_DOWN_RIGHT;
	int3 newPos = PlaceConnected(map, prevPos, block1);
	if (newPos.x >= 0) { TGprint("V4 trans: Tilt→Flat (" + block1 + ")"); return newPos; }
	newPos = PlaceConnected(map, prevPos, block2);
	if (newPos.x >= 0) { TGprint("V4 trans: Tilt→Flat (" + block2 + ")"); return newPos; }
	return int3(-1, -1, -1);
}

int3 EnterTilt(CGameEditorPluginMap@ map, int3 prevPos, TiltSide &out side)
{
	side = (MathRand(0, 1) == 0) ? TiltSide::TiltLeft : TiltSide::TiltRight;
	string block = (side == TiltSide::TiltRight) ? TILT_UP_RIGHT : TILT_UP_LEFT;
	int3 newPos = PlaceConnected(map, prevPos, block);
	if (newPos.x < 0) return int3(-1, -1, -1);
	TGprint("V4 trans: Flat→Tilt (" + block + ")");
	return newPos;
}
// ── Redo helper ───────────────────────────────────────────────────────────────

void ClearPlaced(CGameEditorPluginMap@ map, array<int3> &in coords)
{
	for (uint i = 0; i < coords.Length; i++) {
		while (!map.IsEditorReadyForRequest) { yield(); }
		// coords[i] is the block's actual anchor (from PlaceConnected anchor scan).
		auto b = map.GetBlock(coords[i]);
		if (b !is null) {
			map.RemoveBlock(int3(b.CoordX, b.CoordY, b.CoordZ));
		} else {
			// GetBlock returned null for this coord. Log it so we can diagnose,
			// then try direct removal in case the stored anchor works anyway.
			if (st_debug) TGprint("V4 clear: GetBlock null at " + tostring(coords[i]) + " — trying direct remove");
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

		for (int i = 0; placed < st_maxBlocks && i < st_maxBlocks * 20; i++)
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
				TGprint("\\$f00V4: transition failed (block [" + tostring(placed + 1) + "]), retrying flat");
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

				// Fallback 0: if we just placed a transition block (state changed from Flat,
				// stateRun == 0), undo it and reset to Flat before trying ramp/flat fallbacks.
				if (state != SurfaceState::Flat && stateRun == 0 && placedCoords.Length > 0) {
					int3 transCoord = placedCoords[placedCoords.Length - 1];
					while (!map.IsEditorReadyForRequest) { yield(); }
					auto ub = map.GetBlock(transCoord);
					if (ub !is null) map.RemoveBlock(int3(ub.CoordX, ub.CoordY, ub.CoordZ));
					else map.RemoveBlock(transCoord);
					placed--; placedCoords.RemoveLast(); placedDirs.RemoveLast();
					prevPos = (placedCoords.Length > 0) ? placedCoords[placedCoords.Length - 1] : startPos;
					g_travelDir = (placedDirs.Length > 0) ? placedDirs[placedDirs.Length-1] : initDir;
					state = SurfaceState::Flat; tiltSide = TiltSide::TiltNone; stateRun = 0; flatRun = 0;
					TGprint("V4: undid failed transition, placed [" + tostring(placed) + "]");
					int3 fp = PlaceConnected(map, prevPos, flatPool[MathRand(0, int(flatPool.Length) - 1)]);
					if (fp.x >= 0) {
						placed++; placedCoords.InsertLast(fp); placedDirs.InsertLast(g_travelDir); prevPos = fp; flatRun = 1;
						continue;
					}
				}

				// Fallback 1: ramp escape — always tried regardless of pool setting.
				{
					int3 rampPos = PlaceConnected(map, prevPos, RAMP_ESCAPE);
					if (rampPos.x >= 0) {
						placed++; placedCoords.InsertLast(rampPos); placedDirs.InsertLast(g_travelDir);
						string anyFlat = flatPool[MathRand(0, int(flatPool.Length) - 1)];
						int3 flatPos = PlaceConnected(map, rampPos, anyFlat);
						if (flatPos.x >= 0) {
							placed++; placedCoords.InsertLast(flatPos); placedDirs.InsertLast(g_travelDir);
							prevPos  = flatPos;
							state    = SurfaceState::Flat;
							stateRun = 0; flatRun = 1;
							TGprint("V4: ramp escape, placed [" + tostring(placed) + "]");
							continue;
						}
						// Ramp placed but no flat after — undo it and fall through.
						while (!map.IsEditorReadyForRequest) { yield(); }
						auto rb = map.GetBlock(rampPos);
						if (rb !is null) map.RemoveBlock(int3(rb.CoordX, rb.CoordY, rb.CoordZ));
						else map.RemoveBlock(rampPos);
						placed--; placedCoords.RemoveLast(); placedDirs.RemoveLast();
						g_travelDir = (placedDirs.Length > 0) ? placedDirs[placedDirs.Length-1] : initDir;
					}
				}

				// Fallback 2: try a simple flat block connected normally from prevPos.
				{
					string anyFlat = flatPool[MathRand(0, int(flatPool.Length) - 1)];
					int3 flatPos = PlaceConnected(map, prevPos, anyFlat);
					if (flatPos.x >= 0) {
						placed++; placedCoords.InsertLast(flatPos); placedDirs.InsertLast(g_travelDir);
						prevPos  = flatPos;
						state    = SurfaceState::Flat;
						stateRun = 0; flatRun = 1;
						TGprint("V4: flat-fallback, placed [" + tostring(placed) + "]");
						continue;
					}
				}

				// Fallback 3: slope-down escape — pop 1, 2, or 3 blocks one at a time,
			// after each pop try: SlopeEnd(reversed) → SlopeStart(reversed) → flat.
			// This routes through a small dip to break out of collision dead-ends.
			if (state == SurfaceState::Flat && slopeDownPool.Length > 0) {
				bool slopeEscaped = false;
				for (int popK = 1; popK <= 3 && !slopeEscaped && placedCoords.Length > 0; popK++) {
					int3 popCoord = placedCoords[placedCoords.Length - 1];
					TGprint("V4: slope-escape pop [" + tostring(placed) + "]");
					while (!map.IsEditorReadyForRequest) { yield(); }
					auto pb = map.GetBlock(popCoord);
					if (pb !is null) map.RemoveBlock(int3(pb.CoordX, pb.CoordY, pb.CoordZ));
					else map.RemoveBlock(popCoord);
					placed--;
					placedCoords.RemoveLast(); placedDirs.RemoveLast();
					prevPos     = (placedCoords.Length > 0) ? placedCoords[placedCoords.Length - 1] : startPos;
					g_travelDir = (placedDirs.Length   > 0) ? placedDirs[placedDirs.Length - 1]     : initDir;

					// SlopeEnd reversed = enter downhill; SlopeStart reversed = exit back to flat.
					int3 p1 = PlaceReversed(map, prevPos, SLOPE_END);
					if (p1.x < 0) continue;

					int3 p2 = PlaceReversed(map, p1, SLOPE_START);
					if (p2.x < 0) {
						while (!map.IsEditorReadyForRequest) { yield(); }
						auto rb1 = map.GetBlock(p1);
						if (rb1 !is null) map.RemoveBlock(int3(rb1.CoordX, rb1.CoordY, rb1.CoordZ));
						else map.RemoveBlock(p1);
						continue;
					}

					string escFlat = flatPool[MathRand(0, int(flatPool.Length) - 1)];
					int3 p3 = PlaceConnected(map, p2, escFlat);
					if (p3.x < 0) {
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

					placed++; placedCoords.InsertLast(p1); placedDirs.InsertLast(g_travelDir);
					placed++; placedCoords.InsertLast(p2); placedDirs.InsertLast(g_travelDir);
					placed++; placedCoords.InsertLast(p3); placedDirs.InsertLast(g_travelDir);
					prevPos = p3; state = SurfaceState::Flat; stateRun = 0; flatRun = 1;
					TGprint("V4: slope-escape succeeded, placed [" + tostring(placed) + "]");
					slopeEscaped = true;
				}
				if (slopeEscaped) continue;
			}

			// Fallback 4: mini-backtrack — pop last 1-3 blocks, retry flat.
				{
					int popCount = Math::Min(3, int(placedCoords.Length));
					for (int k = 0; k < popCount; k++) {
						int3 popCoord = placedCoords[placedCoords.Length - 1];
						TGprint("V4: removing [" + tostring(placed) + "] for backtrack");
						while (!map.IsEditorReadyForRequest) { yield(); }
						auto pb = map.GetBlock(popCoord);
						if (pb !is null) map.RemoveBlock(int3(pb.CoordX, pb.CoordY, pb.CoordZ));
						else map.RemoveBlock(popCoord);
						placed--;
						placedCoords.RemoveLast(); placedDirs.RemoveLast();
					}
					prevPos = (placedCoords.Length > 0) ? placedCoords[placedCoords.Length - 1] : startPos;
					g_travelDir = (placedDirs.Length > 0) ? placedDirs[placedDirs.Length-1] : initDir;
					state = SurfaceState::Flat; tiltSide = TiltSide::TiltNone; stateRun = 0; flatRun = 0;
					string anyFlat2 = flatPool[MathRand(0, int(flatPool.Length) - 1)];
					int3 btPos = PlaceConnected(map, prevPos, anyFlat2);
					if (btPos.x >= 0) {
						placed++; placedCoords.InsertLast(btPos); placedDirs.InsertLast(g_travelDir); prevPos = btPos; flatRun = 1;
						TGprint("V4: mini-backtrack, placed [" + tostring(placed) + "]");
						continue;
					}
				}

				// Fallback 5: clear everything and redo with a different seed.
				TGprint("\\$f00V4: all fallbacks failed — triggering full redo");
				needsRedo = true;
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
			TGprint("\\$f0fV4: clearing " + tostring(placedCoords.Length) + " blocks for redo...");
			ClearPlaced(map, placedCoords);
			continue;
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

	// All attempts exhausted
	TGprint("\\$f00V4: generation failed after " + tostring(MAX_ATTEMPTS) + " attempts.");
	UI::ShowNotification("V4: Could not generate track after " + tostring(MAX_ATTEMPTS) + " attempts.");
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

} // namespace v4
