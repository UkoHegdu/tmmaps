// Track Generator V4: RoadTech-only, surface state machine.
// Surface states: Flat, Slope, Tilt.
// Block pool loaded from block_data/roadtech_v4_blocks.txt.
// Transition blocks (SlopeStart/End, TiltTransition) are inserted automatically.
// Place a RoadTechStart block first, then generate.

namespace v4 {

enum SurfaceState { Flat, Slope, Tilt }
enum TiltSide { TiltNone, TiltLeft, TiltRight }
enum SlopeDir { SlopeUp, SlopeDown }
// Road surfaces (0-3) and Platform surfaces (4-7).
// Road surfaces transition through SurfaceTech; Platform surfaces are standalone (no Road↔Platform transitions).
// SURFACE_COUNT is a sentinel — always keep it last.
enum Surface { SurfaceTech = 0, SurfaceDirt = 1, SurfaceBump = 2, SurfaceIce = 3,
               SurfacePlatformTech = 4, SurfacePlatformDirt = 5, SurfacePlatformIce = 6, SurfacePlatformGrass = 7,
               SurfacePlatformPlastic = 8,
               SURFACE_COUNT = 9 }

// True for the 4 road surfaces (0-3); false for platform surfaces (4+).
bool IsRoadSurface(Surface s) { return int(s) < 4; }

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
// Minimum run lengths for Flat/Slope/Tilt are user-configurable via the
// "Minimum state length" setting (st_minStateLen, declared in settings.as).
const int MAX_ATTEMPTS  = 1;  // single attempt — clear and fail on hard failure
const int SURF_SWITCH_CHANCE = 20; // percent chance per flat block to try a surface switch

const string RAMP_ESCAPE = "RoadTechRampLow";

// Stadium mode wall boundaries (block coords) and avoidance thresholds.
// Safe playable range: X in [2..45], Z in [2..45].
const int STADIUM_WALL_MIN  = 2;
const int STADIUM_WALL_MAX  = 45;
// Ground terrain sits at Y=9; placing on/below it desyncs against the floor (scanned=Grass).
// Keep block anchors at or above this so descending slopes (which reach one cell below their
// anchor) stay clear of the ground. Bump to 11 if a descent still grazes the floor.
const int STADIUM_FLOOR_MIN = 10;
// Effective ceiling for anchors: the stadium roof is ~Y=39; a climbing slope rises a
// couple of cells above its anchor and the engine refuses a block that would pierce the
// roof (OutOfStadiumBounds has no ceiling term). Keep anchors below this and exit early.
const int STADIUM_CEIL_MAX  = 38;
const int STADIUM_EXIT_DIST = 10;  // exit slope/tilt when fewer than this blocks ahead
const int STADIUM_TURN_DIST = 5;   // force a turn when fewer than this blocks ahead (flat)
const int STADIUM_CEIL_DIST = 4;   // exit a slope-up to flat when within this many Y of the ceiling

// ── Per-surface data tables (indexed by Surface enum value) ──────────────────
// Add a new surface: extend each table, add a pool file, add settings + UI.

// Block name prefix — used by BlockSurface() to identify a block's surface.
const array<string> SURF_PREFIX = {
    "RoadTech",      // SurfaceTech
    "RoadDirt",      // SurfaceDirt
    "RoadBump",      // SurfaceBump
    "RoadIce",       // SurfaceIce
    "PlatformTech",  // SurfacePlatformTech
    "PlatformDirt",  // SurfacePlatformDirt
    "PlatformIce",   // SurfacePlatformIce
    "PlatformGrass",   // SurfacePlatformGrass
    "PlatformPlastic", // SurfacePlatformPlastic
};

// Canonical straight block per surface — used as the flat fallback.
const array<string> SURF_STRAIGHT = {
    "RoadTechStraight",   // SurfaceTech
    "RoadDirtStraight",   // SurfaceDirt
    "RoadBumpStraight",   // SurfaceBump
    "RoadIceStraight",    // SurfaceIce
    "PlatformTechBase",   // SurfacePlatformTech
    "PlatformDirtBase",   // SurfacePlatformDirt
    "PlatformIceBase",    // SurfacePlatformIce
    "PlatformGrassBase",   // SurfacePlatformGrass
    "PlatformPlasticBase", // SurfacePlatformPlastic
};

// Slope entry/exit transition blocks per surface.
const array<string> SURF_SLOPE_START = {
    "RoadTechSlopeStart2x1",    // SurfaceTech
    "RoadDirtSlopeStart2x1",    // SurfaceDirt
    "RoadBumpSlopeStart2x1",    // SurfaceBump
    "RoadIceSlopeStart2x1",     // SurfaceIce
    "PlatformTechSlope2Start",  // SurfacePlatformTech
    "PlatformDirtSlope2Start",  // SurfacePlatformDirt
    "PlatformIceSlope2Start",   // SurfacePlatformIce
    "PlatformGrassSlope2Start",   // SurfacePlatformGrass
    "PlatformPlasticSlope2Start", // SurfacePlatformPlastic
};
const array<string> SURF_SLOPE_END = {
    "RoadTechSlopeEnd2x1",    // SurfaceTech
    "RoadDirtSlopeEnd2x1",    // SurfaceDirt
    "RoadBumpSlopeEnd2x1",    // SurfaceBump
    "RoadIceSlopeEnd2x1",     // SurfaceIce
    "PlatformTechSlope2End",  // SurfacePlatformTech
    "PlatformDirtSlope2End",  // SurfacePlatformDirt
    "PlatformIceSlope2End",   // SurfacePlatformIce
    "PlatformGrassSlope2End",   // SurfacePlatformGrass
    "PlatformPlasticSlope2End", // SurfacePlatformPlastic
};

// Alternate (smaller) slope-start block per surface.
// Non-empty only for Platform surfaces. Used 50/50 with SURF_SLOPE_START on normal entry;
// used exclusively (instead of SURF_SLOPE_START) during slope-escape fallback.
const array<string> SURF_SLOPE_START2 = {
    "",  // SurfaceTech
    "",  // SurfaceDirt
    "",  // SurfaceBump
    "",  // SurfaceIce
    "PlatformTechSlope2Start2",  // SurfacePlatformTech
    "PlatformDirtSlope2Start2",  // SurfacePlatformDirt
    "PlatformIceSlope2Start2",   // SurfacePlatformIce
    "PlatformGrassSlope2Start2",   // SurfacePlatformGrass
    "PlatformPlasticSlope2Start2", // SurfacePlatformPlastic
};

// Tilt entry/exit transition blocks per surface (empty = surface has no tilt).
// Platform surfaces reuse their slope-start/end blocks as tilt transitions.
const array<string> SURF_TILT_UP_LEFT = {
    "RoadTechTiltTransition1UpLeft",        // SurfaceTech
    "RoadDirtTiltTransition1UpLeft",        // SurfaceDirt
    "RoadBumpTiltTransition1UpLeft",        // SurfaceBump
    "",                                     // SurfaceIce — no tilt
    "PlatformTechTiltTransition1UpLeft",    // SurfacePlatformTech
    "PlatformDirtTiltTransition1UpLeft",    // SurfacePlatformDirt
    "PlatformIceTiltTransition1UpLeft",     // SurfacePlatformIce
    "PlatformGrassTiltTransition1UpLeft",    // SurfacePlatformGrass
    "PlatformPlasticTiltTransition1UpLeft",  // SurfacePlatformPlastic
};
const array<string> SURF_TILT_UP_RIGHT = {
    "RoadTechTiltTransition1UpRight",       // SurfaceTech
    "RoadDirtTiltTransition1UpRight",       // SurfaceDirt
    "RoadBumpTiltTransition1UpRight",       // SurfaceBump
    "",                                     // SurfaceIce — no tilt
    "PlatformTechTiltTransition1UpRight",   // SurfacePlatformTech
    "PlatformDirtTiltTransition1UpRight",   // SurfacePlatformDirt
    "PlatformIceTiltTransition1UpRight",    // SurfacePlatformIce
    "PlatformGrassTiltTransition1UpRight",   // SurfacePlatformGrass
    "PlatformPlasticTiltTransition1UpRight", // SurfacePlatformPlastic
};
const array<string> SURF_TILT_DOWN_LEFT = {
    "RoadTechTiltTransition1DownLeft",      // SurfaceTech
    "RoadDirtTiltTransition1DownLeft",      // SurfaceDirt
    "RoadBumpTiltTransition1DownLeft",      // SurfaceBump
    "",                                     // SurfaceIce — no tilt
    "PlatformTechTiltTransition1DownLeft",  // SurfacePlatformTech
    "PlatformDirtTiltTransition1DownLeft",  // SurfacePlatformDirt
    "PlatformIceTiltTransition1DownLeft",   // SurfacePlatformIce
    "PlatformGrassTiltTransition1DownLeft",  // SurfacePlatformGrass
    "PlatformPlasticTiltTransition1DownLeft",// SurfacePlatformPlastic
};
const array<string> SURF_TILT_DOWN_RIGHT = {
    "RoadTechTiltTransition1DownRight",      // SurfaceTech
    "RoadDirtTiltTransition1DownRight",      // SurfaceDirt
    "RoadBumpTiltTransition1DownRight",      // SurfaceBump
    "",                                      // SurfaceIce — no tilt
    "PlatformTechTiltTransition1DownRight",  // SurfacePlatformTech
    "PlatformDirtTiltTransition1DownRight",  // SurfacePlatformDirt
    "PlatformIceTiltTransition1DownRight",   // SurfacePlatformIce
    "PlatformGrassTiltTransition1DownRight",  // SurfacePlatformGrass
    "PlatformPlasticTiltTransition1DownRight",// SurfacePlatformPlastic
};

// Capability flags per surface.
const array<bool> SURF_HAS_SLOPE = { true, true, true, true, true, true, true, true, true };
const array<bool> SURF_HAS_TILT  = { true, true, true, false, true, true, true, true, true }; // Ice has no tilt; all Platform surfaces support tilt

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
    // Platform surfaces (4-7): standalone — no Road↔Platform transitions
    "", "", "", "", "",  // SurfacePlatformTech
    "", "", "", "", "",  // SurfacePlatformDirt
    "", "", "", "", "",  // SurfacePlatformIce
    "", "", "", "", "",  // SurfacePlatformGrass
    "", "", "", "", "",  // SurfacePlatformPlastic
};

// Current surface — updated whenever a surface transition block is placed.
// Governs which slope/tilt transition block constants are used.
Surface g_surface = Surface::SurfaceTech;

// Coords of the last successful V4 generation (used by ClearLastRun).
array<int3> lastRunCoords;

// Coord of the auto-placed start block (int3(-1,-1,-1) if user placed it manually).
int3 g_placedStartCoord = int3(-1, -1, -1);
int3 g_startPos         = int3(-1, -1, -1); // set at generation start; candidates landing here are skipped

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
// Base pools — Ramp and Special blocks excluded.
// Used by PickFiltered to apply the ramp/special frequency reduction.
array<string> flatBasePool;
array<string> slopeUpBasePool;
array<string> slopeDownBasePool;
array<string> tiltLeftBasePool;
array<string> tiltRightBasePool;

// Probability (0-99) that a Ramp or Special block pick is kept.
// 20 = 80% reduction (only 1 in 5 picks that land on Ramp/Special are accepted).
const int RAMP_SPECIAL_KEEP_CHANCE = 20;
// Stadium mode: curves dead-end far more often than straights in the tight arena and
// make turns feel cramped. When a curve is randomly rolled for a flat section, keep it
// only this % of the time; otherwise re-roll toward a non-curve block. Does NOT affect
// forced wall-avoidance turns — those still place curves on purpose.
const int STADIUM_CURVE_KEEP_CHANCE = 25;
// Mid-slope curve down-weighting (platform). Same idea as STADIUM_CURVE_KEEP_CHANCE but for
// slope bodies: when a Slope2Curve is rolled, keep it only this % of the time, else re-roll
// toward a straight — so slopes aren't curve-spammed once curves are enabled.
const int SLOPE_CURVE_KEEP_CHANCE = 25;
// Mid-slope hole-block down-weighting (platform). Slope2StraightWithHole24m is a valid slope
// body but has a gap in the middle, so keep it only this % of the time — a rare hazard.
const int SLOPE_HOLE_KEEP_CHANCE = 5;
// Flat base-ramp down-weighting. SlopeBase/Slope2Base ascend (or descend, when reversed) every
// time, so a flat pool full of them makes the track yo-yo. Keep a rolled ramp only this % of the
// time (~1/3) so flat sections are mostly level. Applies in all modes.
const int FLAT_RAMP_KEEP_CHANCE = 33;

// Current forward travel direction — set at generation start, updated by PlaceConnected.
CGameEditorPluginMap::ECardinalDirections g_travelDir;

// Forced exit direction for the next PlaceConnected call — used to steer curves left or right.
// -1 = no preference (normal behaviour). Consumed and reset inside PlaceConnected.
int g_forceTurnDirIdx = -1;

// Exit-state hint for DetectHeading on the next placement. Transition blocks don't reveal their
// exit state by name (SlopeStart is exit=Slope when entering a slope, but exit=Flat when reused
// reversed to leave a down-slope), so the transition helpers set this to the state the block
// transitions INTO and DetectHeading probes that straight first. -1 = infer from block name
// (the correct behaviour for body blocks). Holds a SurfaceState value (Flat/Slope/Tilt) otherwise.
int g_probeExitState = -1;

// S2S slope↔tilt switch: when set, the next body block is placed SIDE-attached (a ~90° pivot
// on the dual Slope2Straight) instead of straight ahead — the slope and tilt roles are
// perpendicular, so continuing straight inverts the slope and produces a \/ kink. Consumed at
// the placement site. g_s2sSidePref biases which side to pivot toward (TiltNone = either).
bool g_s2sSideAttach = false;
TiltSide g_s2sSidePref = TiltSide::TiltNone;

// Slope2Straight forced-transition state lives as loop-local variables inside Run()
// (s2sForcedTiltSide / s2sHasForcedSlope / s2sForcedSlopeDir) — it is set by the S2S
// decision block and consumed by the matching Slope↔Tilt shortcut within the same
// iteration, so it does not need to be (and no longer is) global.

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

// Hard stadium boundary: in stadium mode, no block may be placed outside the safe
// X/Z margins [STADIUM_WALL_MIN..STADIUM_WALL_MAX], nor on/below the ground floor
// (Y < STADIUM_FLOOR_MIN). There is no ceiling limit yet — escapes only descend, so
// the track never climbs into one (revisit when escape becomes bidirectional).
// Returns false when stadium mode is off, so callers can guard every placement
// unconditionally.
bool OutOfStadiumBounds(int3 coord)
{
	if (!st_stadiumMode) return false;
	return coord.x < STADIUM_WALL_MIN || coord.x > STADIUM_WALL_MAX
		|| coord.z < STADIUM_WALL_MIN || coord.z > STADIUM_WALL_MAX
		|| coord.y < STADIUM_FLOOR_MIN;
}

// Distance from pos to the wall ahead in dir, using the stadium safe margins.
int StadiumDistAhead(int3 pos, CGameEditorPluginMap::ECardinalDirections dir)
{
	switch(dir) {
		case CGameEditorPluginMap::ECardinalDirections::North: return STADIUM_WALL_MAX - pos.z;
		case CGameEditorPluginMap::ECardinalDirections::South: return pos.z - STADIUM_WALL_MIN;
		case CGameEditorPluginMap::ECardinalDirections::East:  return pos.x - STADIUM_WALL_MIN;
		case CGameEditorPluginMap::ECardinalDirections::West:  return STADIUM_WALL_MAX - pos.x;
	}
	return 999;
}

bool IsTiltDirectedCurve(const string &in blockName)
{
	if (blockName.IndexOf("TiltCurve") < 0) return false;
	string lower = blockName.ToLower();
	return lower.IndexOf("downleft")  >= 0 || lower.IndexOf("upleft")  >= 0 ||
	       lower.IndexOf("downright") >= 0 || lower.IndexOf("upright") >= 0;
}

// Classify a "## ..." block-data section header. Matches the section keyword on the header
// NAME only (the text before the first " - "), so descriptive text in the parenthetical —
// e.g. a TILT header that mentions "Slope2Straight" / "Slope2Left" — is not misread as
// SLOPE (which the old whole-line ToUpper().IndexOf("SLOPE") check did, dumping banked tilt
// curves into the slope pool). Returns "" for an unrecognised header so the caller keeps
// the current section.
string SectionFromHeader(const string &in headerLine)
{
	string name = headerLine;
	int dash = name.IndexOf(" - ");
	if (dash >= 0) name = name.SubStr(0, dash);
	string h = name.ToUpper();
	if      (h.IndexOf("EXCLUDED")         >= 0) return "EXCLUDED";
	else if (h.IndexOf("SLOPE TRANSITION") >= 0) return "SLOPE_TRANS";
	else if (h.IndexOf("TILT TRANSITION")  >= 0) return "TILT_TRANS";
	else if (h.IndexOf("SLOPE")            >= 0) return "SLOPE";
	else if (h.IndexOf("TILT")             >= 0) return "TILT";
	else if (h.IndexOf("FLAT")             >= 0) return "FLAT";
	return "";
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
				string sec = SectionFromHeader(line);
				if (sec.Length > 0) section = sec;
				continue;
			}

			if (line.Length == 0 || line.SubStr(0, 1) == "#") continue;
			if (section == "EXCLUDED" || section == "SLOPE_TRANS" || section == "TILT_TRANS") continue;

			// Respect the special blocks toggle
			if (!st_v4Special && line.IndexOf("Special") >= 0) continue;

			// Respect the ramp blocks toggle
			if (!st_v4Ramps && line.IndexOf("Ramp") >= 0) continue;

			// Stadium mode: exclude Curve5 (too large for the arena)
			if (st_stadiumMode && line.IndexOf("Curve5") >= 0) continue;

			if (section == "FLAT") {
				flatPool.InsertLast(line);
			} else if (section == "SLOPE" && line.IndexOf("Special") < 0) {
				// Special blocks (turbo, no-engine, …) are flat-only — the slope/tilt
				// variants are buggy, so they never enter the slope/tilt pools.
				slopePool.InsertLast(line);
				bool isDown = line.IndexOf("SlopeDown") >= 0;
				bool isUp   = line.IndexOf("SlopeUp")   >= 0;
				// Neutral blocks (no SlopeDown/SlopeUp suffix) go into both pools.
				if (!isDown) slopeUpPool.InsertLast(line);
				if (!isUp)   slopeDownPool.InsertLast(line);
			} else if (section == "TILT" && !IsTiltDirectedCurve(line) && line.IndexOf("Special") < 0) {
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
	// Platform tilt is always false — not added yet.
	array<string> xFiles   = { "roaddirt_v4_blocks.txt", "roadbump_v4_blocks.txt", "roadice_v4_blocks.txt",
	                            "platformtech_v4_blocks.txt", "platformdirt_v4_blocks.txt", "platformice_v4_blocks.txt",
	                            "platformgrass_v4_blocks.txt", "platformplastic_v4_blocks.txt" };
	array<bool>   xEnabled = { st_v4Dirt,      st_v4Bump,      st_v4Ice,
	                            st_v4PlatformTech, st_v4PlatformDirt, st_v4PlatformIce, st_v4PlatformGrass, st_v4PlatformPlastic };
	array<bool>   xSlope   = { st_v4DirtSlope, st_v4BumpSlope, st_v4IceSlope,
	                            st_v4PlatformTechSlope, st_v4PlatformDirtSlope, st_v4PlatformIceSlope, st_v4PlatformGrassSlope, st_v4PlatformPlasticSlope };
	array<bool>   xTilt    = { st_v4DirtTilt,  st_v4BumpTilt,  false,
	                            st_v4PlatformTechTilt, st_v4PlatformDirtTilt, st_v4PlatformIceTilt, st_v4PlatformGrassTilt, st_v4PlatformPlasticTilt };
	for (uint xi = 0; xi < xFiles.Length; xi++) {
		if (!xEnabled[xi]) continue;
		string xPath = GetBlockDataPath() + xFiles[xi];
		try {
			IO::File xf(xPath, IO::FileMode::Read);
			string xsec = "";
			while (!xf.EOF()) {
				string line = xf.ReadLine().Trim();
				if (line.StartsWith("## ")) {
					string sec = SectionFromHeader(line);
					if (sec.Length > 0) xsec = sec;
					continue;
				}
				if (line.Length == 0 || line.SubStr(0, 1) == "#") continue;
				if (xsec == "EXCLUDED" || xsec == "SLOPE_TRANS" || xsec == "TILT_TRANS") continue;
				if (!st_v4Special && line.IndexOf("Special") >= 0) continue;
				if (!st_v4Ramps   && line.IndexOf("Ramp")    >= 0) continue;
				if (st_stadiumMode && line.IndexOf("Curve5")  >= 0) continue;
				// Platform blocks: only Curve1 and Curve2 — larger curves make turns too tight
				bool isPlatform = xi >= 3;
				if (isPlatform && xsec == "FLAT" &&
				    (line.IndexOf("Curve3") >= 0 || line.IndexOf("Curve4") >= 0 || line.IndexOf("Curve5") >= 0)) continue;
				if (xsec == "FLAT") {
					flatPool.InsertLast(line);
				} else if (xsec == "SLOPE" && xSlope[xi] && line.IndexOf("Special") < 0) {
					// Special slope/tilt variants are buggy — flat-only (see roadtech loop).
					slopePool.InsertLast(line);
					bool isDown = line.IndexOf("SlopeDown") >= 0;
					bool isUp   = line.IndexOf("SlopeUp")   >= 0;
					if (!isDown) slopeUpPool.InsertLast(line);
					if (!isUp)   slopeDownPool.InsertLast(line);
				} else if (xsec == "TILT" && xTilt[xi] && !IsTiltDirectedCurve(line) && line.IndexOf("Special") < 0) {
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
		// Road blocks use "TiltLeft"/"TiltRight" suffixes.
		// Platform blocks use "Tilt2Left"/"Tilt2Right" (specials) or "Slope2Left"/"Slope2Right" (checkpoints).
		bool hasLeft  = name.IndexOf("TiltLeft")  >= 0 || name.IndexOf("Tilt2Left")  >= 0 || name.IndexOf("Slope2Left")  >= 0;
		bool hasRight = name.IndexOf("TiltRight") >= 0 || name.IndexOf("Tilt2Right") >= 0 || name.IndexOf("Slope2Right") >= 0;
		if (!hasLeft && !hasRight) {
			tiltLeftPool.InsertLast(name);
			tiltRightPool.InsertLast(name);
		} else if (hasLeft) {
			tiltLeftPool.InsertLast(name);
		} else {
			tiltRightPool.InsertLast(name);
		}
	}

	// Build base pools — exclude Ramp and Special blocks for frequency reduction.
	flatBasePool.Resize(0);
	slopeUpBasePool.Resize(0);
	slopeDownBasePool.Resize(0);
	tiltLeftBasePool.Resize(0);
	tiltRightBasePool.Resize(0);
	for (uint i = 0; i < flatPool.Length; i++) {
		string n = flatPool[i];
		if (n.IndexOf("Ramp") < 0 && n.IndexOf("Special") < 0) flatBasePool.InsertLast(n);
	}
	for (uint i = 0; i < slopeUpPool.Length; i++) {
		if (slopeUpPool[i].IndexOf("Special") < 0) slopeUpBasePool.InsertLast(slopeUpPool[i]);
	}
	for (uint i = 0; i < slopeDownPool.Length; i++) {
		if (slopeDownPool[i].IndexOf("Special") < 0) slopeDownBasePool.InsertLast(slopeDownPool[i]);
	}
	for (uint i = 0; i < tiltLeftPool.Length; i++) {
		if (tiltLeftPool[i].IndexOf("Special") < 0) tiltLeftBasePool.InsertLast(tiltLeftPool[i]);
	}
	for (uint i = 0; i < tiltRightPool.Length; i++) {
		if (tiltRightPool[i].IndexOf("Special") < 0) tiltRightBasePool.InsertLast(tiltRightPool[i]);
	}

	TGprint("V4 pools loaded — flat: " + tostring(flatPool.Length)
		+ "  slopeUp: " + tostring(slopeUpPool.Length)
		+ "  slopeDown: " + tostring(slopeDownPool.Length)
		+ "  tiltL: " + tostring(tiltLeftPool.Length)
		+ "  tiltR: " + tostring(tiltRightPool.Length));

	// Diagnostic: how many FLAT blocks each surface contributed. A surface that was
	// toggled on but shows 0 here means its block file didn't load (missing/empty/path).
	TGprint("V4 block data path: " + GetBlockDataPath());
	string surfCounts = "";
	for (int s = 0; s < int(Surface::SURFACE_COUNT); s++) {
		string pfx = SURF_PREFIX[s];
		int cnt = 0;
		for (uint i = 0; i < flatPool.Length; i++)
			if (int(flatPool[i].Length) >= int(pfx.Length) && flatPool[i].SubStr(0, pfx.Length) == pfx) cnt++;
		if (cnt > 0) surfCounts += "  " + pfx + "=" + tostring(cnt);
	}
	TGprint("V4 flat pool by surface:" + surfCounts);
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
string GetSlopeStart2()    { return SURF_SLOPE_START2[int(g_surface)]; }
string GetSlopeEnd()       { return SURF_SLOPE_END[int(g_surface)]; }
// Returns "Platform*Slope2Straight" for platform surfaces, "" for road surfaces.
// Used to detect when a direct Slope↔Tilt transition is possible (no transition block needed).
string GetSlope2Straight() {
    int s = int(g_surface);
    if (s < int(Surface::SurfacePlatformTech)) return "";
    return SURF_PREFIX[s] + "Slope2Straight";
}
string GetTiltUpLeft()     { return SURF_TILT_UP_LEFT[int(g_surface)]; }
string GetTiltUpRight()    { return SURF_TILT_UP_RIGHT[int(g_surface)]; }
string GetTiltDownLeft()   { return SURF_TILT_DOWN_LEFT[int(g_surface)]; }
string GetTiltDownRight()  { return SURF_TILT_DOWN_RIGHT[int(g_surface)]; }

// Returns true if pool contains at least one block for the given surface.
// Used to gate slope/tilt weights so we don't roll into a state the current surface can't fill.
bool PoolHasSurface(const array<string>@ pool, Surface surf)
{
	string pfx = SURF_PREFIX[int(surf)];
	for (uint i = 0; i < pool.Length; i++)
		if (pool[i].SubStr(0, pfx.Length) == pfx) return true;
	return false;
}

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

// Like PickFromPool but filters for an explicit surface instead of g_surface.
// Returns "" if no matching blocks are found — caller should fall back to PickFromPool.
string PickFromPoolFor(const array<string>@ pool, Surface surf)
{
	string pfx = SURF_PREFIX[int(surf)];
	array<string> filtered;
	for (uint i = 0; i < pool.Length; i++)
		if (pool[i].SubStr(0, pfx.Length) == pfx)
			filtered.InsertLast(pool[i]);
	if (filtered.Length == 0) return "";
	return filtered[MathRand(0, int(filtered.Length) - 1)];
}

// Pick from pool with Ramp/Special frequency reduction.
// If the picked block is a Ramp or Special, re-roll from basePool with probability
// (100 - RAMP_SPECIAL_KEEP_CHANCE)%. basePool must exclude Ramp/Special blocks.
string PickFiltered(const array<string>@ pool, const array<string>@ basePool)
{
	string pick = PickFromPool(pool);
	if (basePool.Length == 0) return pick;
	if (pick.IndexOf("Ramp") < 0 && pick.IndexOf("Special") < 0) return pick;
	if (MathRand(0, 99) < RAMP_SPECIAL_KEEP_CHANCE) return pick;
	return PickFromPool(basePool);
}

// True for the ascending/descending flat base ramps (SlopeBase, Slope2Base). Distinct names —
// "Slope2Base" does not contain "SlopeBase" — so both are checked explicitly.
bool IsFlatRamp(const string &in name)
{
	return name.IndexOf("SlopeBase") >= 0 || name.IndexOf("Slope2Base") >= 0;
}

// Flat-section pick with down-weighting. Base ramps (SlopeBase/Slope2Base) are down-weighted to
// ~FLAT_RAMP_KEEP_CHANCE% in all modes so the track isn't a constant yo-yo. In stadium mode,
// curves are additionally down-weighted toward straights. Forced wall-avoidance turns bypass
// this (they set targetBlock directly).
string PickFlat()
{
	string pick = PickFiltered(flatPool, flatBasePool);

	// Down-weight base ramps toward non-ramp flat blocks (~1/3 kept).
	if (IsFlatRamp(pick) && MathRand(0, 99) >= FLAT_RAMP_KEEP_CHANCE) {
		for (int attempt = 0; attempt < 5; attempt++) {
			string p2 = PickFiltered(flatPool, flatBasePool);
			if (!IsFlatRamp(p2)) { pick = p2; break; }
		}
	}

	// Stadium: down-weight curves toward straights.
	if (st_stadiumMode && pick.IndexOf("Curve") >= 0 && MathRand(0, 99) >= STADIUM_CURVE_KEEP_CHANCE) {
		for (int attempt = 0; attempt < 5; attempt++) {
			string p2 = PickFiltered(flatPool, flatBasePool);
			if (p2.IndexOf("Curve") < 0) { pick = p2; break; }
		}
	}

	return pick;
}

// Like PickFiltered but additionally down-weights Curve blocks: keep a rolled curve only
// SLOPE_CURVE_KEEP_CHANCE% of the time, else re-roll toward a non-curve (straight) body.
string PickSlopeWeighted(const array<string>@ pool, const array<string>@ basePool)
{
	string pick = PickFiltered(pool, basePool);
	bool isCurve = pick.IndexOf("Curve") >= 0;
	bool isHole  = pick.IndexOf("WithHole") >= 0;
	if (!isCurve && !isHole) return pick;
	int keep = isHole ? SLOPE_HOLE_KEEP_CHANCE : SLOPE_CURVE_KEEP_CHANCE;
	if (MathRand(0, 99) < keep) return pick;
	for (int attempt = 0; attempt < 5; attempt++) {
		string p2 = PickFiltered(pool, basePool);
		if (p2.IndexOf("Curve") < 0 && p2.IndexOf("WithHole") < 0) return p2;
	}
	return pick;  // pool offers nothing plainer — accept what we rolled
}

// Pick a slope-body block. The first body after the entry transition (stateRun == 0) must be
// a straight: platform Slope2Curve blocks dock to the SIDE of a Slope2Straight, not to the
// entry transition block. From the second body on, curves are allowed but down-weighted.
// Gate is platform-only — GetSlope2Straight() is "" on road, so road keeps prior behaviour.
string PickSlopeBody(SlopeDir dir, int stateRun)
{
	bool up = (dir == SlopeDir::SlopeUp);
	array<string>@ pool     = up ? slopeUpPool     : slopeDownPool;
	array<string>@ basePool = up ? slopeUpBasePool : slopeDownBasePool;
	string s2s = GetSlope2Straight();
	if (s2s.Length == 0) return PickFiltered(pool, basePool);  // road: unchanged
	if (stateRun == 0)   return s2s;                           // platform: straight first
	return PickSlopeWeighted(pool, basePool);                  // platform: down-weighted curves
}

// ── Placement helpers ────────────────────────────────────────────────────────────────────────────

// Handle stability test — stores the last placed block's handle and coord.
// PlaceConnected compares this against a fresh GetBlockAt scan to detect stale handles.
CGameCtnBlock@ g_dbgLastHandle = null;
int3           g_dbgLastCoord  = int3(-1, -1, -1);

// ── GetConnectResults cache ───────────────────────────────────────────────────
// Keyed by "prevBlockName|prevBlockDir|targetBlockName".
// Stores candidate (direction, relative-offset-from-prevPos) pairs.
// CanPlace is NOT cached — it reflects map state. We just try PlaceBlock directly.
class ConnectCacheEntry {
    array<CGameEditorPluginMap::ECardinalDirections> dirs;
    array<int3> offsets;
}
dictionary g_connectCache;
int g_cacheHits   = 0;
int g_cacheMisses = 0;

// ── Timing diagnostics ──────────────────────────────────────────────────────────
// Accumulated per Run() (reset alongside the cache counters) and printed in the
// "V4 timing" breakdown. Times are ms (Time::get_Now resolution), so the call
// COUNT matters as much as the total for sub-ms ops. Categories:
//   connect = GetConnectResults + its editor-ready spin (engine round-trips)
//   place   = PlaceBlock (incl. editor-ready spin)
//   scan    = GetBlockAt + FindNewlyPlacedBlock (linear RootMap.Blocks scans — O(n²) overall)
//   remove  = RemoveBlockRobust (incl. its ±6 neighbour scan)
uint64 g_tConnect = 0; int g_nConnect = 0;
uint64 g_tRemove  = 0; int g_nRemove  = 0;
// g_tPlace/g_nPlace live in block_placement.as and g_tScan/g_nScan in main.as — next to the
// functions that write them. Openplanet does not expose globals declared in this v4/ subfolder
// file to the root files, but root-declared globals ARE visible here, so they're read/reset below.
// Fallback firing counts — how often the placement ladder had to recover (wasted work).
int g_nUndoTrans  = 0;  // undid a failed slope/tilt transition block
int g_nFlatFb     = 0;  // flat-fallback (straight/flat block after a failed pick)
int g_nBorderless = 0;  // borderless-adjacent escape (platform one-cell nudge)
int g_nSlopeEsc   = 0;  // slope-escape attempts (pop + reversed slope dive)

// Find the newly placed block by scanning only entries appended after preLen.
// Also captures the handle into g_dbgLastHandle for the stability test.
// Relies on TM appending new blocks to the end of the Blocks array.
int3 FindNewlyPlacedBlock(const string &in blockName, uint preLen, int3 fallback)
{
	uint64 _t = Time::get_Now();
	int3 _r = FindNewlyPlacedBlockImpl(blockName, preLen, fallback);
	g_tScan += Time::get_Now() - _t; g_nScan++;
	return _r;
}
int3 FindNewlyPlacedBlockImpl(const string &in blockName, uint preLen, int3 fallback)
{
	auto allB = GetApp().RootMap.Blocks;
	// Primary: an exact name + requested-coord match anywhere in the array. This is robust to
	// array mutation — a mid-placement wall removal shifts indices, breaking the append-order
	// (preLen) assumption and causing us to latch onto the wrong block (or, when the game only
	// auto-spawned scenery, return a phantom coord that resolves to a DecoWallBasePillar).
	for (uint i = 0; i < allB.Length; i++) {
		if (allB[i].BlockModel.IdName == blockName
		    && int(allB[i].CoordX) == fallback.x
		    && int(allB[i].CoordY) == fallback.y
		    && int(allB[i].CoordZ) == fallback.z) {
			@g_dbgLastHandle = allB[i];
			g_dbgLastCoord   = fallback;
			return fallback;
		}
	}
	// Secondary: append-order scan for blocks whose stored anchor differs from the requested
	// cell (large multi-cell blocks). Skip auto-spawned scenery so it is never mistaken for track.
	for (uint ak = preLen; ak < allB.Length; ak++) {
		string n = allB[ak].BlockModel.IdName;
		if (n == "DecoWallBasePillar" || n == "TrackWallStraightPillar") continue;
		if (n == blockName) {
			@g_dbgLastHandle = allB[ak];
			g_dbgLastCoord   = int3(allB[ak].CoordX, allB[ak].CoordY, allB[ak].CoordZ);
			return g_dbgLastCoord;
		}
	}
	// Not found — the named track block did not actually register (e.g. only auto-deco resolved
	// in the cell). Signal failure rather than returning the phantom requested coord, so the
	// caller falls back instead of building on scenery.
	@g_dbgLastHandle = null;
	return int3(-1, -1, -1);
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

// Returns cached connect results for (prevBlock, targetBlock), calling GetConnectResults
// and populating the cache on the first encounter. Offsets are relative to prevPos.
ConnectCacheEntry@ GetConnectCache(CGameEditorPluginMap@ map, CGameCtnBlock@ prevBlock,
                                   int3 prevPos, const string &in blockName,
                                   CGameCtnBlockInfo@ info)
{
    string key = prevBlock.BlockModel.IdName + "|" + DirStr(GetBlockDirection(prevBlock)) + "|" + blockName;
    ConnectCacheEntry@ entry;
    if (g_connectCache.Get(key, @entry)) {
        g_cacheHits++;
        return entry;
    }

    // Cache miss — call the engine.
    g_cacheMisses++;
    uint64 _t = Time::get_Now();
    while (!map.IsEditorReadyForRequest) { yield(); }
    map.GetConnectResults(prevBlock, info);
    while (!map.IsEditorReadyForRequest) { yield(); }
    g_tConnect += Time::get_Now() - _t; g_nConnect++;

    @entry = ConnectCacheEntry();
    for (uint r = 0; r < map.ConnectResults.Length; r++) {
        auto res = map.ConnectResults[r];
        if (res is null || !res.CanPlace) continue;
        entry.dirs.InsertLast(ConvertDir(res.Dir));
        entry.offsets.InsertLast(int3(res.Coord.x - prevPos.x,
                                      res.Coord.y - prevPos.y,
                                      res.Coord.z - prevPos.z));
    }
    g_connectCache.Set(key, @entry);
    return entry;
}

// Detect the real travel heading out of a just-placed block by probing its open
// exit socket — instead of trusting the placement's orientation stamp (`dir`),
// which is the block's ROTATION, not its travel direction. They coincide for
// straights but differ for curves/tilt-curves, which is what desynced g_travelDir.
//
// Probes the current surface's straight variants (flat, tilt, slope). Only the
// probe matching the exit's surface mates; the others return nothing and are
// skipped, so we don't need to know the section state at the call site.
//
// Heading rule: a result's `dir` is the heading if stepping one cell in `dir`
// (MoveDir) moves AWAY from prevPos (the entry side). The first qualifying result
// wins — blocks with one entry and two forward exits just take the first.
//
// Returns `fallback` if no usable exit is found (e.g. a true straight-through
// transition block, or an unmappable shape) so behaviour never gets worse.
CGameEditorPluginMap::ECardinalDirections DetectHeading(
	CGameEditorPluginMap@ map, int3 placedPos, int3 prevPos,
	const string &in blockName, CGameEditorPluginMap::ECardinalDirections fallback)
{
	auto placedBlock = GetBlockAt(map, placedPos);
	if (placedBlock is null) return fallback;

	// Order probes so the first GetConnectResults call usually mates the exit (one call,
	// fast). Three sources for the ordering, in priority:
	//   1. g_probeExitState — an explicit exit-state hint set by a transition helper. A
	//      transition block does NOT reveal its exit state by name (SlopeStart is exit=Slope
	//      when entering a slope, but exit=Flat when reused reversed to leave a down-slope),
	//      so the helper that placed it tells us the state it transitions INTO.
	//   2. The placed block's own type, for body blocks (TiltStraight, SlopeStraight, …).
	//   3. Flat-first fallback for anything else.
	// Whatever leads, the other two straights stay as fallbacks so a miss still resolves.
	// Road surfaces have dedicated Road*SlopeStraight / Road*TiltStraight blocks. Platform
	// surfaces do NOT — their single dual straight, Slope2Straight, is both the slope and the
	// tilt straight (slopes N↔S, banks E↔W). Probing a non-existent Platform*TiltStraight would
	// resolve to null, be skipped, and silently fall back to the flat probe — which is exactly
	// the heading-misdetection this hint is meant to fix. So on platform use Slope2Straight.
	string flatStr  = GetStraight();
	string s2s      = GetSlope2Straight();  // "" on road, Platform*Slope2Straight on platform
	string tiltStr  = (s2s.Length > 0) ? s2s : SURF_PREFIX[int(g_surface)] + "TiltStraight";
	string slopeStr = (s2s.Length > 0) ? s2s : SURF_PREFIX[int(g_surface)] + "SlopeStraight";
	bool isTrans = blockName.IndexOf("Transition") >= 0
	            || blockName.IndexOf("SlopeStart")  >= 0
	            || blockName.IndexOf("SlopeEnd")    >= 0;
	array<string> probes;
	if (g_probeExitState == int(SurfaceState::Tilt)) {
		probes.InsertLast(tiltStr); probes.InsertLast(flatStr); probes.InsertLast(slopeStr);
	} else if (g_probeExitState == int(SurfaceState::Slope)) {
		probes.InsertLast(slopeStr); probes.InsertLast(flatStr); probes.InsertLast(tiltStr);
	} else if (g_probeExitState == int(SurfaceState::Flat)) {
		probes.InsertLast(flatStr); probes.InsertLast(tiltStr); probes.InsertLast(slopeStr);
	} else if (!isTrans && blockName.IndexOf("Tilt") >= 0) {
		probes.InsertLast(tiltStr); probes.InsertLast(flatStr); probes.InsertLast(slopeStr);
	} else if (!isTrans && blockName.IndexOf("Slope") >= 0) {
		probes.InsertLast(slopeStr); probes.InsertLast(flatStr); probes.InsertLast(tiltStr);
	} else {
		probes.InsertLast(flatStr); probes.InsertLast(tiltStr); probes.InsertLast(slopeStr);
	}
	string rotStr = DirStr(GetBlockDirection(placedBlock));
	for (uint p = 0; p < probes.Length; p++) {
		auto probeInfo = map.GetBlockModelFromName(probes[p]);
		if (probeInfo is null) continue;
		uint64 _t = Time::get_Now();
		while (!map.IsEditorReadyForRequest) { yield(); }
		map.GetConnectResults(placedBlock, probeInfo);
		while (!map.IsEditorReadyForRequest) { yield(); }
		g_tConnect += Time::get_Now() - _t; g_nConnect++;
		// Build a candidate list (for diagnostics) while picking the first decisive socket.
		string cand = "";
		bool decided = false;
		CGameEditorPluginMap::ECardinalDirections head = fallback;
		auto chosenDir = fallback; int3 chosenCoord = int3(0, 0, 0);
		for (uint r = 0; r < map.ConnectResults.Length; r++) {
			auto res = map.ConnectResults[r];
			if (res is null || !res.CanPlace) continue;
			auto dir = ConvertDir(res.Dir);
			int3 c   = res.Coord;
			cand += " [" + DirStr(dir) + "@" + tostring(c) + "]";
			if (decided) continue;
			// The probe is a STRAIGHT, so its orientation reliably gives the travel AXIS
			// (N/S → Z, E/W → X) — but NOT the sign (a straight reports both rotations,
			// and `dir` is orientation, not heading). Take the sign from the exit coord
			// relative to prevPos: heading points from the entry (near prevPos) outward.
			bool zAxis = (dir == CGameEditorPluginMap::ECardinalDirections::North
			           || dir == CGameEditorPluginMap::ECardinalDirections::South);
			if (zAxis) {
				if      (c.z > prevPos.z) { head = CGameEditorPluginMap::ECardinalDirections::North; decided = true; }
				else if (c.z < prevPos.z) { head = CGameEditorPluginMap::ECardinalDirections::South; decided = true; }
			} else {
				if      (c.x > prevPos.x) { head = CGameEditorPluginMap::ECardinalDirections::West;  decided = true; }
				else if (c.x < prevPos.x) { head = CGameEditorPluginMap::ECardinalDirections::East;  decided = true; }
			}
			// Axis difference is zero (ambiguous) — try the next result / probe.
			if (decided) { chosenDir = dir; chosenCoord = c; }
		}
		if (decided) {
			TGprint("    DetectHeading: " + blockName + " rot=" + rotStr
				+ " placed=" + tostring(placedPos) + " prev=" + tostring(prevPos)
				+ " probe=" + probes[p] + " sockets:" + cand
				+ " → chose " + DirStr(chosenDir) + "@" + tostring(chosenCoord)
				+ " heading=" + DirStr(head));
			return head;
		}
	}
	TGprint("    DetectHeading: " + blockName + " rot=" + rotStr
		+ " placed=" + tostring(placedPos) + " prev=" + tostring(prevPos)
		+ " — no decisive exit socket, fallback=" + DirStr(fallback));
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

	// Handle stability test: if the last placed block was at prevPos, compare
	// the stored handle against the fresh GetBlockAt result.
	if (g_dbgLastHandle !is null && g_dbgLastCoord == prevPos) {
		string stored  = g_dbgLastHandle.BlockModel.IdName;
		string scanned = prevBlock.BlockModel.IdName;
		if (stored != scanned)
			TGprint("\\$f00HANDLE STALE @ " + tostring(prevPos) + ": stored=" + stored + "  scanned=" + scanned);
	}

	auto info = map.GetBlockModelFromName(blockName);
	if (info is null) {
		TGprint("\\$f00V4: block model not found: " + blockName);
		return int3(-1, -1, -1);
	}

	auto preferDir = g_travelDir;
	auto backDir   = IntToDir((DirToInt(preferDir) + 2) % 4);
	ConnectCacheEntry@ c = GetConnectCache(map, prevBlock, prevPos, blockName, info);

	// Diagnostic: dump exactly what the placement passes will iterate — the cached
	// CanPlace sockets (engine geometry) plus this position's occupancy/bounds, which
	// the cache does NOT capture. Shows whether the forward (preferDir) socket is
	// genuinely missing vs. present-but-blocked.
	if (st_debug) {
		string cl = "";
		bool sawPrefer = false;
		for (uint r = 0; r < c.dirs.Length; r++) {
			int3 cc = int3(prevPos.x + c.offsets[r].x, prevPos.y + c.offsets[r].y, prevPos.z + c.offsets[r].z);
			if (c.dirs[r] == preferDir) sawPrefer = true;
			string flags = "";
			if (cc == g_startPos)        flags += " START";
			if (OutOfStadiumBounds(cc))  flags += " OOB";
			if (!(GetBlockAt(map, cc) is null)) flags += " OCC";
			cl += " [" + DirStr(c.dirs[r]) + "→" + tostring(cc) + (flags.Length > 0 ? flags : " free") + "]";
		}
		TGprint("    PlaceConnected candidates for " + blockName + " from "
			+ prevBlock.BlockModel.IdName + " @ " + tostring(prevPos)
			+ "  prefer=" + DirStr(preferDir) + (sawPrefer ? "" : " (NOT in candidates!)")
			+ "  back=" + DirStr(backDir) + ":" + (c.dirs.Length > 0 ? cl : " <none>"));
	}

	// Consume forced turn direction (set by caller for curve blocks).
	int forceDirIdx = g_forceTurnDirIdx;
	g_forceTurnDirIdx = -1;

	// First pass: prefer direction matching current travel direction.
	for (uint r = 0; r < c.dirs.Length; r++) {
		auto dir   = c.dirs[r];
		auto coord = int3(prevPos.x + c.offsets[r].x, prevPos.y + c.offsets[r].y, prevPos.z + c.offsets[r].z);
		if (dir != preferDir) continue;
		if (coord == g_startPos) continue;
		if (OutOfStadiumBounds(coord)) continue;
		uint preLen = GetApp().RootMap.Blocks.Length;
		if (PlaceBlock(map, blockName, dir, coord)) {
			int3 placed = FindNewlyPlacedBlock(blockName, preLen, coord);
			// Heading from the block's actual exit geometry, not the orientation stamp `dir`.
			// Falls back to `dir` if no usable exit is found.
			g_travelDir = DetectHeading(map, placed, prevPos, blockName, dir);
			TGprint("    PlaceConnected pass1 (prefer " + DirStr(preferDir) + "): placed " + blockName
				+ " stampDir=" + DirStr(dir) + " @ " + tostring(placed) + " → heading=" + DirStr(g_travelDir));
			return placed;
		}
		TGprint("    PlaceConnected pass1: preferDir " + DirStr(preferDir) + " socket @ "
			+ tostring(coord) + " present but PlaceBlock FAILED (falling through to side/back passes)");
	}

	// Pass 1.5: if a forced exit direction is set (e.g. curve left/right), try it before
	// the general pass 2 so the turn direction is respected rather than left to iteration order.
	if (forceDirIdx >= 0) {
		auto forceDir = IntToDir(forceDirIdx);
		for (uint r = 0; r < c.dirs.Length; r++) {
			auto dir   = c.dirs[r];
			auto coord = int3(prevPos.x + c.offsets[r].x, prevPos.y + c.offsets[r].y, prevPos.z + c.offsets[r].z);
			if (dir != forceDir) continue;
			if (coord == g_startPos) continue;
			if (OutOfStadiumBounds(coord)) continue;
			uint preLen = GetApp().RootMap.Blocks.Length;
			if (PlaceBlock(map, blockName, dir, coord)) {
				g_travelDir = dir;
				return FindNewlyPlacedBlock(blockName, preLen, coord);
			}
		}
		// Forced direction not available — fall through to pass 2 (any non-back dir).
	}

	// Second pass: any valid result except directly backward.
	for (uint r = 0; r < c.dirs.Length; r++) {
		auto dir   = c.dirs[r];
		auto coord = int3(prevPos.x + c.offsets[r].x, prevPos.y + c.offsets[r].y, prevPos.z + c.offsets[r].z);
		if (dir == backDir) continue;
		if (coord == g_startPos) continue;
		if (OutOfStadiumBounds(coord)) continue;
		uint preLen = GetApp().RootMap.Blocks.Length;
		if (PlaceBlock(map, blockName, dir, coord)) {
			int3 placed = FindNewlyPlacedBlock(blockName, preLen, coord);
			// Heading from the block's actual exit geometry, not the orientation stamp `dir`.
			// Falls back to `dir` if no usable exit is found.
			g_travelDir = DetectHeading(map, placed, prevPos, blockName, dir);
			TGprint("    PlaceConnected pass2 (prefer " + DirStr(preferDir) + " unavailable; took non-back): placed "
				+ blockName + " stampDir=" + DirStr(dir) + " @ " + tostring(placed) + " → heading=" + DirStr(g_travelDir));
			return placed;
		}
	}

	// Third pass: try backDir results — some blocks (e.g. tilt transitions) report
	// backDir as their exit but physically go straight. Only reached if all other
	// candidates failed, so the risk of backward placement is minimal.
	for (uint r = 0; r < c.dirs.Length; r++) {
		auto dir   = c.dirs[r];
		auto coord = int3(prevPos.x + c.offsets[r].x, prevPos.y + c.offsets[r].y, prevPos.z + c.offsets[r].z);
		if (dir != backDir) continue;
		if (coord == g_startPos) continue;
		if (OutOfStadiumBounds(coord)) continue;
		uint preLen = GetApp().RootMap.Blocks.Length;
		if (PlaceBlock(map, blockName, dir, coord)) {
			int3 placed = FindNewlyPlacedBlock(blockName, preLen, coord);
			// dir == backDir here, so it's never a valid heading. Detect the real heading
			// from the block's exit; fall back to the current g_travelDir (the old freeze
			// behavior) if no usable exit is found — true straight-through transition blocks.
			auto detected = DetectHeading(map, placed, prevPos, blockName, g_travelDir);
			g_travelDir = detected;
			TGprint("    PlaceConnected pass3 (backDir): placed " + blockName + " @ " + tostring(placed) + "  dir=" + DirStr(dir) + "  detectedHeading=" + DirStr(detected));
			return placed;
		}
	}
	return int3(-1, -1, -1);
}

// Try to place a Finish connected to prevPos. Platform blocks transition freely,
// so this is forgiving: first the natural connect (any non-backward direction/state
// via PlaceConnected), then the same candidates one level below (Y-1). Returns the
// placed coord, or (-1,-1,-1) if nothing fit.
int3 PlaceFinish(CGameEditorPluginMap@ map, int3 prevPos, const string &in finishName)
{
	// 1) Natural connect — full 4-pass placement in any non-backward direction.
	int3 fpos = PlaceConnected(map, prevPos, finishName);
	if (fpos.x >= 0) return fpos;

	// 2) One level below: retry every forward candidate at Y-1.
	auto prevBlock = GetBlockAt(map, prevPos);
	if (prevBlock is null) return int3(-1, -1, -1);
	auto info = map.GetBlockModelFromName(finishName);
	if (info is null) return int3(-1, -1, -1);

	auto backDir = IntToDir((DirToInt(g_travelDir) + 2) % 4);
	ConnectCacheEntry@ c = GetConnectCache(map, prevBlock, prevPos, finishName, info);
	for (uint r = 0; r < c.dirs.Length; r++) {
		auto dir = c.dirs[r];
		if (dir == backDir) continue;
		int3 coord = int3(prevPos.x + c.offsets[r].x, prevPos.y + c.offsets[r].y - 1, prevPos.z + c.offsets[r].z);
		if (coord == g_startPos) continue;
		if (OutOfStadiumBounds(coord)) continue;
		uint preLen = GetApp().RootMap.Blocks.Length;
		if (PlaceBlock(map, finishName, dir, coord)) {
			int3 placedF = FindNewlyPlacedBlock(finishName, preLen, coord);
			TGprint("    finish placed one level below at " + tostring(placedF));
			return placedF;
		}
	}

	// 3) Platform borderless: drop the finish into any free neighbour cell, ignoring
	//    connection geometry — same trick as the flat-adjacent escape. No-op on road.
	int3 adj = PlaceBorderlessAdjacent(map, prevPos, finishName);
	if (adj.x >= 0) return adj;

	return int3(-1, -1, -1);
}

// Platform-only: drop blockName into any free, in-bounds neighbour cell at the same
// height, ignoring connection geometry. Platform blocks have no side borders, so the
// car can roll between any two edge-adjacent platform blocks even when the editor reports
// no connection (it may look awkward, but it's drivable). Tries forward, the two sides,
// then backward; sets g_travelDir toward the chosen cell. Returns placed coord or (-1,-1,-1).
int3 PlaceBorderlessAdjacent(CGameEditorPluginMap@ map, int3 prevPos, const string &in blockName)
{
	// Borderless behaviour only applies to platform surfaces; road blocks need real connections.
	if (int(g_surface) < int(Surface::SurfacePlatformTech)) return int3(-1, -1, -1);

	auto backDir = IntToDir((DirToInt(g_travelDir) + 2) % 4);
	array<CGameEditorPluginMap::ECardinalDirections> order =
		{ g_travelDir, TurnDirLeft(g_travelDir), TurnDirRight(g_travelDir), backDir };

	for (uint i = 0; i < order.Length; i++) {
		auto d = order[i];
		int3 off = MoveDir(d);
		int3 coord = int3(prevPos.x + off.x, prevPos.y + off.y, prevPos.z + off.z);
		if (coord == g_startPos) continue;
		if (OutOfStadiumBounds(coord)) continue;
		if (!(GetBlockAt(map, coord) is null)) continue;  // cell already occupied
		uint preLen = GetApp().RootMap.Blocks.Length;
		if (PlaceBlock(map, blockName, d, coord)) {
			g_travelDir = d;
			g_nBorderless++;
			TGprint("    borderless-adjacent: placed " + blockName + " @ " + tostring(coord) + "  dir=" + DirStr(d));
			return FindNewlyPlacedBlock(blockName, preLen, coord);
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
	if (g_dbgLastHandle !is null && g_dbgLastCoord == prevPos) {
		string stored  = g_dbgLastHandle.BlockModel.IdName;
		string scanned = prevBlock.BlockModel.IdName;
		if (stored != scanned)
			TGprint("\\$f00HANDLE STALE @ " + tostring(prevPos) + ": stored=" + stored + "  scanned=" + scanned);
	}
	auto info = map.GetBlockModelFromName(blockName);
	if (info is null) {
		TGprint("  PlaceReversedConnected: block model not found: " + blockName);
		return int3(-1, -1, -1);
	}

	auto reverseDir = IntToDir((DirToInt(g_travelDir) + 2) % 4);
	TGprint("  PlaceReversedConnected: " + blockName + "  prevPos=" + tostring(prevPos) + "  travelDir=" + DirStr(g_travelDir) + "  reverseDir=" + DirStr(reverseDir));

	ConnectCacheEntry@ c = GetConnectCache(map, prevBlock, prevPos, blockName, info);

	for (uint r = 0; r < c.dirs.Length; r++) {
		auto dir   = c.dirs[r];
		auto coord = int3(prevPos.x + c.offsets[r].x, prevPos.y + c.offsets[r].y, prevPos.z + c.offsets[r].z);
		if (dir != reverseDir) continue;
		if (coord == g_startPos) continue;
		if (OutOfStadiumBounds(coord)) continue;
		TGprint("    backDir result: coord=" + tostring(coord) + "  dir=" + DirStr(dir));
		uint preLen = GetApp().RootMap.Blocks.Length;
		if (PlaceBlock(map, blockName, dir, coord)) {
			// Do NOT update g_travelDir here. The slope does not physically
			// reverse the car's direction. Flipping g_travelDir to reverseDir
			// would cause every subsequent block and curve to use the wrong
			// direction, cascading a full East/West flip across the entire track.
			return FindNewlyPlacedBlock(blockName, preLen, coord);
		}
		TGprint("    backDir result blocked at " + tostring(coord));
	}
	TGprint("  PlaceReversedConnected: no usable backDir result for " + blockName);
	return int3(-1, -1, -1);
}

// Turn-aware reversed placement for down-slope CURVE bodies. PlaceReversedConnected only
// accepts the straight-back result (dir == reverseDir), which works for a Slope2Straight but
// rejects a sloped curve — the curve exits 90° to the side, so none of its results carry the
// straight-back dir. Here the result's `dir` is still used as the block ROTATION (so it keeps
// descending), but selection is by exit OFFSET: take any result that isn't travelling backward
// toward the entry. The real heading is then derived from the placed block's geometry by
// DetectHeading — we do NOT assume the new heading equals reverseDir.
int3 PlaceReversedTurn(CGameEditorPluginMap@ map, int3 prevPos, const string &in blockName)
{
	auto prevBlock = GetBlockAt(map, prevPos);
	if (prevBlock is null) return int3(-1, -1, -1);
	auto info = map.GetBlockModelFromName(blockName);
	if (info is null) return int3(-1, -1, -1);

	auto travelDir = g_travelDir;
	int3 fwd = MoveDir(travelDir);
	g_forceTurnDirIdx = -1;  // the flat-curve forced turn doesn't apply to slope bodies

	ConnectCacheEntry@ c = GetConnectCache(map, prevBlock, prevPos, blockName, info);
	for (uint r = 0; r < c.dirs.Length; r++) {
		auto dir   = c.dirs[r];
		int3 off   = c.offsets[r];
		int3 coord = int3(prevPos.x + off.x, prevPos.y + off.y, prevPos.z + off.z);
		// Reject results that travel backward toward the entry (would climb back up the slope).
		if (off.x * fwd.x + off.z * fwd.z < 0) continue;
		if (coord == g_startPos) continue;
		if (OutOfStadiumBounds(coord)) continue;
		uint preLen = GetApp().RootMap.Blocks.Length;
		if (PlaceBlock(map, blockName, dir, coord)) {
			int3 placed = FindNewlyPlacedBlock(blockName, preLen, coord);
			g_travelDir = DetectHeading(map, placed, prevPos, blockName, travelDir);
			TGprint("    PlaceReversedTurn: placed " + blockName + " @ " + tostring(placed)
				+ "  rot=" + DirStr(dir) + "  heading=" + DirStr(g_travelDir));
			return placed;
		}
	}
	TGprint("  PlaceReversedTurn: no usable forward result for " + blockName);
	return int3(-1, -1, -1);
}

// S2S slope↔tilt switch placement. The dual Slope2Straight slopes along one axis and banks
// along the perpendicular, so switching its role is a ~90° pivot: place the next block on a
// SIDE socket (exit offset perpendicular to current travel) rather than straight ahead, which
// is what inverted the slope into a \/ kink. Uses the engine's reported rotation for that
// socket; DetectHeading sets the real new heading. preferSide biases which side to try first
// (TiltNone = random). Returns (-1,-1,-1) if no side socket is placeable so the caller can
// fall back to the normal straight-ahead placement.
int3 PlaceSwitchSlopeTilt(CGameEditorPluginMap@ map, int3 prevPos, const string &in blockName, TiltSide preferSide)
{
	auto prevBlock = GetBlockAt(map, prevPos);
	if (prevBlock is null) return int3(-1, -1, -1);
	auto info = map.GetBlockModelFromName(blockName);
	if (info is null) return int3(-1, -1, -1);

	// The dual block keeps the SAME rotation as the block we pivot from — only the attach
	// side (and hence travel heading) changes. So we accept only side sockets whose rotation
	// matches the previous block's.
	auto prevRot = GetBlockDirection(prevBlock);

	int3 leftV  = MoveDir(TurnDirLeft(g_travelDir));
	int3 rightV = MoveDir(TurnDirRight(g_travelDir));

	// Order the two sides by preference.
	array<int3> sideOrder;
	if (preferSide == TiltSide::TiltRight)     { sideOrder.InsertLast(rightV); sideOrder.InsertLast(leftV); }
	else if (preferSide == TiltSide::TiltLeft)  { sideOrder.InsertLast(leftV);  sideOrder.InsertLast(rightV); }
	else if (MathRand(0, 1) == 0)               { sideOrder.InsertLast(leftV);  sideOrder.InsertLast(rightV); }
	else                                        { sideOrder.InsertLast(rightV); sideOrder.InsertLast(leftV); }

	ConnectCacheEntry@ c = GetConnectCache(map, prevBlock, prevPos, blockName, info);
	for (uint s = 0; s < sideOrder.Length; s++) {
		int3 want = sideOrder[s];
		for (uint r = 0; r < c.dirs.Length; r++) {
			if (c.dirs[r] != prevRot) continue;  // keep the previous block's rotation
			int3 off = c.offsets[r];
			// Require a positive component toward this side (a sideways/diagonal exit, not straight ahead/back).
			if (off.x * want.x + off.z * want.z <= 0) continue;
			int3 coord = int3(prevPos.x + off.x, prevPos.y + off.y, prevPos.z + off.z);
			if (coord == g_startPos) continue;
			if (OutOfStadiumBounds(coord)) continue;
			uint preLen = GetApp().RootMap.Blocks.Length;
			if (PlaceBlock(map, blockName, c.dirs[r], coord)) {
				int3 placed = FindNewlyPlacedBlock(blockName, preLen, coord);
				g_travelDir = DetectHeading(map, placed, prevPos, blockName, g_travelDir);
				TGprint("    PlaceSwitchSlopeTilt: " + blockName + " @ " + tostring(placed)
					+ "  side=" + ((want.x == leftV.x && want.z == leftV.z) ? "L" : "R")
					+ "  rot=" + DirStr(c.dirs[r]) + "  heading=" + DirStr(g_travelDir));
				return placed;
			}
		}
	}
	TGprint("  PlaceSwitchSlopeTilt: no side socket placeable for " + blockName);
	return int3(-1, -1, -1);
}

// Place blockName rotated 180° from travelDir at prevPos (y-1 or y=0), WITHOUT
// updating g_travelDir.
// Used for tilt blocks: we only need the block physically rotated 180° to find
// a snapping end — the road still continues in the same travel direction.
int3 PlaceFlipped(CGameEditorPluginMap@ map, int3 prevPos, const string &in blockName)
{
	auto flipDir = IntToDir((DirToInt(g_travelDir) + 2) % 4);
	TGprint("  PlaceFlipped: " + blockName + "  prevPos=" + tostring(prevPos) + "  travelDir=" + DirStr(g_travelDir) + "  flipDir=" + DirStr(flipDir));
	for (int yOff = -1; yOff <= 0; yOff++) {
		int3 tryCoord = int3(prevPos.x, prevPos.y + yOff, prevPos.z);
		while (!map.IsEditorReadyForRequest) { yield(); }
		uint preLen = GetApp().RootMap.Blocks.Length;
		bool placed = PlaceBlock(map, blockName, flipDir, tryCoord);
		TGprint("    yOff=" + tostring(yOff) + "  tryCoord=" + tostring(tryCoord) + "  PlaceBlock=" + (placed ? "OK" : "FAILED"));
		if (placed) {
			// g_travelDir is NOT updated here — caller decides whether to update it.
			return FindNewlyPlacedBlock(blockName, preLen, tryCoord);
		}
	}
	TGprint("  PlaceFlipped: all attempts failed for " + blockName);
	return int3(-1, -1, -1);
}
// Uniform per-block log line. Every placed block — body, transition, surface-change —
// prints "V4 [N] <block> @ <coord>  dir=<d>  (<note>)" at the same indentation so the
// block number is always greppable; the note (transition kind, etc.) is secondary.
void LogPlacedBlock(int blockNum, const string &in block, int3 pos, const string &in note)
{
	TGprint("V4 [" + tostring(blockNum) + "] " + block + " @ " + tostring(pos)
		+ "  dir=" + DirStr(g_travelDir)
		+ (note.Length > 0 ? "  (" + note + ")" : ""));
}

// ── Transition helpers ────────────────────────────────────────────────────────────────────
// All helpers read/write g_travelDir so direction is tracked through transitions.

// Ascending entry: SLOPE_START (flat→slope going up).
// Descending entry: SLOPE_END reversed 180° (flat→slope going down). Falls back to ascending.
int3 EnterSlope(CGameEditorPluginMap@ map, int3 prevPos, int blockNum, SlopeDir &out dir)
{
	string slopeEnd   = GetSlopeEnd();
	// For Platform: 50/50 between Slope2Start and Slope2Start2.
	string slopeStart = GetSlopeStart();
	string s2 = GetSlopeStart2();
	if (s2.Length > 0 && MathRand(0, 1) == 0) slopeStart = s2;
	if (MathRand(0, 1) == 0) {
		g_probeExitState = int(SurfaceState::Slope);
		int3 newPos = PlaceReversedConnected(map, prevPos, slopeEnd);
		g_probeExitState = -1;
		if (newPos.x >= 0) {
			dir = SlopeDir::SlopeDown;
			LogPlacedBlock(blockNum, slopeEnd, newPos, "trans Flat→Slope/Down");
			return newPos;
		}
		TGprint("  → EnterSlope: " + slopeEnd + " (reversed) failed from " + tostring(prevPos) + "  travelDir=" + DirStr(g_travelDir) + ", trying SlopeUp");
	}
	dir = SlopeDir::SlopeUp;
	g_probeExitState = int(SurfaceState::Slope);
	int3 newPos = PlaceConnected(map, prevPos, slopeStart);
	g_probeExitState = -1;
	if (newPos.x < 0) {
		TGprint("  → EnterSlope: " + slopeStart + " failed from " + tostring(prevPos) + "  travelDir=" + DirStr(g_travelDir));
		return int3(-1, -1, -1);
	}
	LogPlacedBlock(blockNum, slopeStart, newPos, "trans Flat→Slope/Up");
	return newPos;
}

// Exit slope → flat.
// SlopeDown: slope body forward socket connects to SLOPE_START (exits at lower flat).
// SlopeUp:   slope body forward socket connects to SLOPE_END (exits at upper flat).
int3 ExitSlope(CGameEditorPluginMap@ map, int3 prevPos, int blockNum, SlopeDir dir)
{
	string slopeStart = GetSlopeStart();
	string slopeEnd   = GetSlopeEnd();
	if (dir == SlopeDir::SlopeDown) {
		g_probeExitState = int(SurfaceState::Flat);
		int3 newPos = PlaceReversedConnected(map, prevPos, slopeStart);
		g_probeExitState = -1;
		if (newPos.x >= 0) { LogPlacedBlock(blockNum, slopeStart, newPos, "trans Slope/Down→Flat"); return newPos; }
		TGprint("  → ExitSlope: " + slopeStart + " failed from " + tostring(prevPos) + "  travelDir=" + DirStr(g_travelDir));
		LogPlacementDiag(map, prevPos, slopeStart);
		return int3(-1, -1, -1);
	}
	// SlopeUp
	g_probeExitState = int(SurfaceState::Flat);
	int3 newPos = PlaceConnected(map, prevPos, slopeEnd);
	g_probeExitState = -1;
	if (newPos.x < 0) {
		TGprint("  → ExitSlope: " + slopeEnd + " failed from " + tostring(prevPos) + "  travelDir=" + DirStr(g_travelDir));
		LogPlacementDiag(map, prevPos, slopeEnd);
		return int3(-1, -1, -1);
	}
	LogPlacedBlock(blockNum, slopeEnd, newPos, "trans Slope/Up→Flat");
	return newPos;
}

int3 ExitTilt(CGameEditorPluginMap@ map, int3 prevPos, int blockNum, TiltSide side)
{
	string block1 = (side == TiltSide::TiltRight) ? GetTiltDownRight() : GetTiltDownLeft();
	string block2 = (side == TiltSide::TiltRight) ? GetTiltDownLeft()  : GetTiltDownRight();
	g_probeExitState = int(SurfaceState::Flat);
	int3 newPos = PlaceConnected(map, prevPos, block1);
	g_probeExitState = -1;
	if (newPos.x >= 0) { LogPlacedBlock(blockNum, block1, newPos, "trans Tilt→Flat"); return newPos; }
	TGprint("  → ExitTilt: " + block1 + " failed from " + tostring(prevPos) + "  travelDir=" + DirStr(g_travelDir) + ", trying " + block2);
	g_probeExitState = int(SurfaceState::Flat);
	newPos = PlaceConnected(map, prevPos, block2);
	g_probeExitState = -1;
	if (newPos.x >= 0) { LogPlacedBlock(blockNum, block2, newPos, "trans Tilt→Flat"); return newPos; }
	TGprint("  → ExitTilt: " + block2 + " also failed from " + tostring(prevPos) + "  travelDir=" + DirStr(g_travelDir));
	return int3(-1, -1, -1);
}

int3 EnterTilt(CGameEditorPluginMap@ map, int3 prevPos, int blockNum, TiltSide &out side)
{
	TiltSide firstSide = (MathRand(0, 1) == 0) ? TiltSide::TiltLeft : TiltSide::TiltRight;
	for (int attempt = 0; attempt < 2; attempt++) {
		side = (attempt == 0) ? firstSide
		                      : (firstSide == TiltSide::TiltLeft ? TiltSide::TiltRight : TiltSide::TiltLeft);
		string block = (side == TiltSide::TiltRight) ? GetTiltUpRight() : GetTiltUpLeft();
		// For Platform: tilt entry reuses slope-start — apply 50/50 between Start and Start2.
		string tiltS2 = GetSlopeStart2();
		if (tiltS2.Length > 0 && block == GetSlopeStart() && MathRand(0, 1) == 0) block = tiltS2;

		// Normal placement via connect results.
		g_probeExitState = int(SurfaceState::Tilt);
		int3 newPos = PlaceConnected(map, prevPos, block);
		g_probeExitState = -1;
		if (newPos.x >= 0) {
			LogPlacedBlock(blockNum, block, newPos, "trans Flat→Tilt");
			return newPos;
		}
		TGprint("  → EnterTilt: " + block + " (normal) failed from " + tostring(prevPos) + "  travelDir=" + DirStr(g_travelDir));
		LogPlacementDiag(map, prevPos, block);

		// Flipped placement — rotates block 180°, g_travelDir unchanged.
		// Tilt transitions go straight; flipping is purely to find a snapping face.
		g_probeExitState = int(SurfaceState::Tilt);
		newPos = PlaceFlipped(map, prevPos, block);
		g_probeExitState = -1;
		if (newPos.x >= 0) {
			LogPlacedBlock(blockNum, block, newPos, "trans Flat→Tilt (flipped)");
			return newPos;
		}
		TGprint("  → EnterTilt: " + block + " (flipped) failed from " + tostring(prevPos) + "  travelDir=" + DirStr(g_travelDir));
	}
	return int3(-1, -1, -1);
}

// Places a straight Slope2Straight BODY block going forward in travelDir. The SOLID Slope2Straight
// won't expose its banked/forward (northern) faces to GetConnectResults, but the geometrically
// identical *Slope2StraightWithHole24m* variant does — so we probe with the hole block to discover
// the forward connection, then place the SOLID block at that coord+dir.
//   yCrit selects the height of the forward cell by current state:
//     0  = level   (tilt body — same Y)
//    >0  = ascends (slope-up body  — higher Y)
//    <0  = descends(slope-down body — lower Y)
// Returns the placed coord, or int3(-1,-1,-1) if no matching forward connection is offered
// (caller falls back to a flat block forward).
int3 PlaceSlope2StraightForwardHole(CGameEditorPluginMap@ map, int3 prevPos,
                                    CGameEditorPluginMap::ECardinalDirections travelDir, int yCrit)
{
	string solid = GetSlope2Straight();           // "PlatformXSlope2Straight" (empty on road)
	if (solid.Length == 0) return int3(-1, -1, -1);
	string hole = solid + "WithHole24m";          // the variant whose hidden faces the engine enumerates
	auto holeInfo  = map.GetBlockModelFromName(hole);
	auto prevBlock = GetBlockAt(map, prevPos);
	if (holeInfo is null || prevBlock is null) return int3(-1, -1, -1);

	int3 step = MoveDir(travelDir);
	int fwdX = prevPos.x + step.x;   // forward cell on the travel axis; Y is chosen by yCrit
	int fwdZ = prevPos.z + step.z;

	while (!map.IsEditorReadyForRequest) { yield(); }
	map.GetConnectResults(prevBlock, holeInfo);
	while (!map.IsEditorReadyForRequest) { yield(); }

	for (uint r = 0; r < map.ConnectResults.Length; r++) {
		auto res = map.ConnectResults[r];
		if (res is null || !res.CanPlace) continue;
		int3 c = res.Coord;
		if (c.x != fwdX || c.z != fwdZ) continue;          // must be the forward (travel-axis) cell
		if (yCrit == 0 && c.y != prevPos.y) continue;      // level
		if (yCrit  > 0 && c.y <= prevPos.y) continue;      // must ascend
		if (yCrit  < 0 && c.y >= prevPos.y) continue;      // must descend
		auto dir = ConvertDir(res.Dir);
		if (PlaceBlock(map, solid, dir, c)) {
			g_travelDir = travelDir;   // went straight forward — heading preserved
			TGprint("V4 S2S-fwd: " + solid + " @ " + tostring(c) + "  dir=" + DirStr(dir)
				+ "  (WithHole probe, " + (yCrit == 0 ? "level" : (yCrit > 0 ? "up" : "down")) + ")");
			return c;
		}
		TGprint("\\$f80V4 S2S-fwd: PlaceBlock failed @ " + tostring(c) + "  dir=" + DirStr(dir));
		return int3(-1, -1, -1);
	}
	TGprint("\\$f80V4 S2S-fwd: no forward WithHole connection (fwd=<" + tostring(fwdX) + ", *, " + tostring(fwdZ)
		+ ">, yCrit=" + tostring(yCrit) + ") — falling back");
	return int3(-1, -1, -1);
}

// Switches tilt side via a TiltSwitch block (Road surfaces only).
// Tries normal placement then flipped. Updates `side` and returns new pos on success,
// or int3(-1,-1,-1) on failure (caller continues with same side).
int3 SwitchTilt(CGameEditorPluginMap@ map, int3 prevPos, int blockNum, TiltSide curSide, TiltSide &out side)
{
	TiltSide newSide = (curSide == TiltSide::TiltLeft) ? TiltSide::TiltRight : TiltSide::TiltLeft;
	string block = SURF_PREFIX[int(g_surface)] + (newSide == TiltSide::TiltRight ? "TiltSwitchRight" : "TiltSwitchLeft");
	g_probeExitState = int(SurfaceState::Tilt);
	int3 newPos = PlaceConnected(map, prevPos, block);
	g_probeExitState = -1;
	if (newPos.x >= 0) {
		LogPlacedBlock(blockNum, block, newPos, "trans TiltSwitch " + (curSide == TiltSide::TiltLeft ? "L→R" : "R→L"));
		side = newSide;
		return newPos;
	}
	g_probeExitState = int(SurfaceState::Tilt);
	newPos = PlaceFlipped(map, prevPos, block);
	g_probeExitState = -1;
	if (newPos.x >= 0) {
		LogPlacedBlock(blockNum, block, newPos, "trans TiltSwitch " + (curSide == TiltSide::TiltLeft ? "L→R" : "R→L") + " (flipped)");
		side = newSide;
		return newPos;
	}
	TGprint("  → SwitchTilt: " + block + " failed from " + tostring(prevPos) + "  travelDir=" + DirStr(g_travelDir));
	side = curSide;
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

// ── Removal helpers ─────────────────────────────────────────────────────────────

// Robustly remove the block anchored at `coord`, returning true only when the block
// is verifiably gone (verified via GetBlockAt, a linear scan over RootMap.Blocks that
// finds blocks by anchor even when the engine's GetBlock spatial lookup returns null).
//
// Strategy mirrors the proven full-clear logic:
//   1. Fast path — engine GetBlock at the exact coord, remove by reported anchor.
//   2. Direct RemoveBlock at coord — succeeds for some large blocks even when
//      GetBlock at the same coord returns null (Curve4, tilt/curve bodies, etc.).
//   3. ±6 cell scan for a queryable neighbour cell of the same block.
//
// `protect` lists anchors of OTHER blocks that must NOT be removed during the scan
// (pass the currently-placed coords). The block whose anchor equals `coord` is always
// eligible regardless of whether it also appears in `protect`.
//
// IMPORTANT: callers that pop a tracked block MUST route through this (not a bare
// map.RemoveBlock), otherwise large/curve/tilt blocks silently survive removal and,
// once dropped from the tracking array, become orphans the final clear never touches.
bool RemoveBlockRobust(CGameEditorPluginMap@ map, int3 coord, const array<int3>@ protect = null)
{
	uint64 _t = Time::get_Now();
	bool _r = RemoveBlockRobustImpl(map, coord, protect);
	g_tRemove += Time::get_Now() - _t; g_nRemove++;
	return _r;
}
bool RemoveBlockRobustImpl(CGameEditorPluginMap@ map, int3 coord, const array<int3>@ protect = null)
{
	while (!map.IsEditorReadyForRequest) { yield(); }

	// Step 1: engine spatial lookup at the exact coord.
	auto b = map.GetBlock(coord);
	if (b !is null) {
		map.RemoveBlock(int3(b.CoordX, b.CoordY, b.CoordZ));
		while (!map.IsEditorReadyForRequest) { yield(); }
		if (GetBlockAt(map, coord) is null) return true;
	} else {
		// Step 2: direct remove at coord (works for some large blocks).
		map.RemoveBlock(coord);
		while (!map.IsEditorReadyForRequest) { yield(); }
		if (GetBlockAt(map, coord) is null) return true;
	}

	// Step 3: ±6 scan for a queryable neighbour cell of the same block.
	for (int xOff = -6; xOff <= 6; xOff++) {
		for (int zOff = -6; zOff <= 6; zOff++) {
			if (xOff == 0 && zOff == 0) continue;
			for (int yOff = -1; yOff <= 1; yOff++) {
				int3 scanCoord = int3(coord.x + xOff, coord.y + yOff, coord.z + zOff);
				while (!map.IsEditorReadyForRequest) { yield(); }
				auto b2 = map.GetBlock(scanCoord);
				if (b2 is null) continue;
				int3 b2Anchor = int3(b2.CoordX, b2.CoordY, b2.CoordZ);
				bool isTarget = (b2Anchor.x == coord.x && b2Anchor.y == coord.y && b2Anchor.z == coord.z);
				// Skip blocks belonging to another tracked slot (unless it's our target).
				if (!isTarget && protect !is null) {
					bool other = false;
					for (uint j = 0; j < protect.Length && !other; j++)
						if (protect[j].x == b2Anchor.x && protect[j].y == b2Anchor.y && protect[j].z == b2Anchor.z)
							other = true;
					if (other) continue;
				}
				// Use the scan coord (where GetBlock found it); retry at anchor if needed.
				map.RemoveBlock(scanCoord);
				while (!map.IsEditorReadyForRequest) { yield(); }
				if (map.GetBlock(scanCoord) !is null) {
					map.RemoveBlock(b2Anchor);
					while (!map.IsEditorReadyForRequest) { yield(); }
				}
				if (GetBlockAt(map, coord) is null) return true;
			}
		}
	}

	return GetBlockAt(map, coord) is null;
}

// ── Clear helper ──────────────────────────────────────────────────────────────

void ClearPlaced(CGameEditorPluginMap@ map, array<int3> &in coords)
{
	for (uint i = 0; i < coords.Length; i++) {
		if (!RemoveBlockRobust(map, coords[i], coords))
			TGprint("V4 clear [" + tostring(i) + "]: MISSED — could not remove block at " + tostring(coords[i]));
	}
}

// ── Debug: manual single-coord removal ───────────────────────────────────────
// Runs the same logic as ClearPlaced for a single coord entered in the Dev UI.

void DebugRemoveAtCoord()
{
	auto app = cast<CTrackMania>(GetApp());
	if (app is null) return;
	auto editor = cast<CGameCtnEditorFree>(app.Editor);
	if (editor is null) { TGprint("DebugRemove: editor not open"); return; }
	auto map = cast<CGameEditorPluginMap>(editor.PluginMapType);
	if (map is null) return;

	int3 coord = int3(g_dbgRemX, g_dbgRemY, g_dbgRemZ);
	TGprint("DebugRemove: attempting removal at " + tostring(coord));

	if (RemoveBlockRobust(map, coord))
		TGprint("DebugRemove: removed (verified)");
	else
		TGprint("DebugRemove: MISSED — nothing found at " + tostring(coord) + " or within ±6 scan");
}

// ── Manual single-block placement (Settings UI) ──────────────────────────────
// Places the current "dest" block (g_checkDirProbeName) at an explicit coord + direction
// entered in the Settings tab. Lets you drop the destination block at each CheckDir
// candidate to inspect by eye how smooth/uneven the connection is.
void PlaceDestAtCoord()
{
	auto app = cast<CTrackMania>(GetApp());
	if (app is null) return;
	auto editor = cast<CGameCtnEditorFree>(app.Editor);
	if (editor is null) { TGprint("PlaceDest: editor not open"); return; }
	auto map = cast<CGameEditorPluginMap>(editor.PluginMapType);
	if (map is null) return;

	string name = g_checkDirProbeName;
	if (name.Length == 0) { TGprint("\\$f00PlaceDest: no destination block set — use 'Load as dest' first"); return; }
	if (map.GetBlockModelFromName(name) is null) { TGprint("\\$f00PlaceDest: block model '" + name + "' not found"); return; }

	int3 coord = int3(g_destX, g_destY, g_destZ);
	auto dir = DirFromStr(g_destDirText);
	TGprint("PlaceDest: placing '" + name + "' at " + tostring(coord) + "  dir=" + DirStr(dir));
	if (PlaceBlock(map, name, dir, coord))
		TGprint("\\$0f0PlaceDest: placed OK");
	else
		TGprint("\\$f00PlaceDest: PlaceBlock FAILED at " + tostring(coord) + "  dir=" + DirStr(dir));
}

// ── Main ──────────────────────────────────────────────────────────────────────

// Returns the start block name to auto-place based on enabled surface settings.
// One surface enabled → that surface's Start block.
// Multiple or none → PlatformTechStart.
string PickStartBlockName()
{
	array<Surface> enabled;
	if (st_v4Tech)          enabled.InsertLast(Surface::SurfaceTech);
	if (st_v4Dirt)          enabled.InsertLast(Surface::SurfaceDirt);
	if (st_v4Bump)          enabled.InsertLast(Surface::SurfaceBump);
	if (st_v4Ice)           enabled.InsertLast(Surface::SurfaceIce);
	if (st_v4PlatformTech)  enabled.InsertLast(Surface::SurfacePlatformTech);
	if (st_v4PlatformDirt)  enabled.InsertLast(Surface::SurfacePlatformDirt);
	if (st_v4PlatformIce)   enabled.InsertLast(Surface::SurfacePlatformIce);
	if (st_v4PlatformGrass)    enabled.InsertLast(Surface::SurfacePlatformGrass);
	if (st_v4PlatformPlastic)  enabled.InsertLast(Surface::SurfacePlatformPlastic);
	if (enabled.Length == 1) return SURF_PREFIX[int(enabled[0])] + "Start";
	return "PlatformTechStart";
}

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
	g_connectCache.DeleteAll();
	g_cacheHits   = 0;
	g_cacheMisses = 0;
	g_tConnect = 0; g_nConnect = 0;
	g_tPlace   = 0; g_nPlace   = 0;
	g_tScan    = 0; g_nScan    = 0;
	g_tRemove  = 0; g_nRemove  = 0;
	g_nUndoTrans = 0; g_nFlatFb = 0; g_nBorderless = 0; g_nSlopeEsc = 0;
	g_s2sSideAttach = false; g_s2sSidePref = TiltSide::TiltNone;

	if (flatPool.Length == 0) {
		TGprint("\\$f00V4: flat pool is empty, cannot generate.");
		UI::ShowNotification("V4: flat pool empty. Check roadtech_v4_blocks.txt.");
		return;
	}

	int3 startPos;
	g_placedStartCoord = int3(-1, -1, -1);
	CGameCtnBlock@ startBlock = FindStartBlock(map, startPos);
	if (startBlock is null) {
		string startName = PickStartBlockName();
		startPos = int3(129, 87, 125);
		TGprint("V4: no Start block found — auto-placing " + startName + " at " + tostring(startPos));
		if (!PlaceBlock(map, startName, DIR_NORTH, startPos)) {
			TGprint("\\$f00V4: failed to place " + startName);
			UI::ShowNotification("V4: Failed to place start block!");
			return;
		}
		while (!map.IsEditorReadyForRequest) { yield(); }
		@startBlock = map.GetBlock(startPos);
		if (startBlock is null) {
			TGprint("\\$f00V4: start block not found after placement at " + tostring(startPos));
			return;
		}
		g_placedStartCoord = startPos;
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
		g_surface   = BlockSurface(startBlock.BlockModel.IdName);
		g_startPos       = startPos;
		auto initDir     = g_travelDir;  // saved for direction restore after full backtrack
		auto initSurface = g_surface;    // saved for surface restore when all blocks are popped

		TGprint("\\$0f0\\$sGenerating track (V4 surface-state, surface=" + SURF_PREFIX[int(g_surface)] + ")!");

		for (int i = 0; placed < st_maxBlocks && i < st_maxBlocks * 30; i++)
		{
			// ── Update phase ─────────────────────────────────────────────
			phase = ComputePhase(state, slopeDir, tiltSide);

			// S2S forced-transition state — local to this iteration, so stale values
			// from a previous loop can never carry over (no globals involved).
			TiltSide s2sForcedTiltSide = TiltSide::TiltNone;
			bool     s2sHasForcedSlope = false;
			SlopeDir s2sForcedSlopeDir = SlopeDir::SlopeUp;

			// ── Road tilt switch ──────────────────────────────────────────
			// Road surfaces occasionally switch tilt side
			// in-place using a TiltSwitch block instead of exit→enter.
			// Platform has no TiltSwitch blocks — exit+enter handles it instead.
			if (state == SurfaceState::Tilt && IsRoadSurface(g_surface) && MathRand(0, 9) == 0) {
				int3 p = SwitchTilt(map, prevPos, placed + 1, tiltSide, tiltSide);
				if (p.x >= 0) {
					prevPos = p; placed++;
					placedCoords.InsertLast(p); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface);
					stateRun++;
					continue;
				}
			}

			// ── Pick target ───────────────────────────────────────────────

			int wFlat  = 60;
			int wSlope = (SURF_HAS_SLOPE[int(g_surface)] && PoolHasSurface(slopePool, g_surface)) ? 20 : 0;
			int wTilt  = (SURF_HAS_TILT[int(g_surface)]  && PoolHasSurface(tiltPool,  g_surface)) ? 20 : 0;
			int total  = wFlat + wSlope + wTilt;
			int roll   = MathRand(0, total - 1);

			SurfaceState targetState;
			string targetBlock;

			if (roll < wFlat) {
				targetState = SurfaceState::Flat;
				// Surface switch: road surfaces switch among road surfaces; platform surfaces
				// switch among platform surfaces (direct connection, no transition block needed).
				Surface pickSurf = g_surface;
				if (state == SurfaceState::Flat && MathRand(0, 99) < SURF_SWITCH_CHANCE) {
					array<Surface> surfs;
					if (IsRoadSurface(g_surface)) {
						if (st_v4Tech) surfs.InsertLast(Surface::SurfaceTech);
						if (st_v4Dirt) surfs.InsertLast(Surface::SurfaceDirt);
						if (st_v4Bump) surfs.InsertLast(Surface::SurfaceBump);
						if (st_v4Ice)  surfs.InsertLast(Surface::SurfaceIce);
					} else {
						if (st_v4PlatformTech) surfs.InsertLast(Surface::SurfacePlatformTech);
						if (st_v4PlatformDirt) surfs.InsertLast(Surface::SurfacePlatformDirt);
						if (st_v4PlatformIce)  surfs.InsertLast(Surface::SurfacePlatformIce);
						if (st_v4PlatformGrass)   surfs.InsertLast(Surface::SurfacePlatformGrass);
						if (st_v4PlatformPlastic) surfs.InsertLast(Surface::SurfacePlatformPlastic);
					}
					if (surfs.Length > 0) pickSurf = surfs[MathRand(0, int(surfs.Length) - 1)];
				}
				string surfCandidate = (pickSurf != g_surface) ? PickFromPoolFor(flatPool, pickSurf) : "";
				targetBlock = (surfCandidate.Length > 0) ? surfCandidate : PickFlat();
			} else if (roll < wFlat + wSlope) {
				targetState = SurfaceState::Slope;
				// Use directional pool when already in slope, full pool otherwise
				// (direction gets set by EnterSlope for new slope sections).
				if (state == SurfaceState::Slope) {
					targetBlock = PickSlopeBody(slopeDir, stateRun);
				} else {
					targetBlock = PickFiltered(slopePool, slopeUpBasePool);
				}
			} else {
				targetState = SurfaceState::Tilt;
				// When already in tilt, use the side-specific pool to avoid
				// mixing Left/Right blocks which causes exit transition failures.
				if (state == SurfaceState::Tilt) {
					bool left = tiltSide == TiltSide::TiltLeft;
					targetBlock = PickFiltered(left ? tiltLeftPool : tiltRightPool, left ? tiltLeftBasePool : tiltRightBasePool);
				} else {
					targetBlock = PickFiltered(tiltPool, tiltLeftBasePool);
				}
			}

			// ── Slope2Straight decision ───────────────────────────────────
			// When the last placed block is a Slope2Straight, override the normal
			// target pick with a weighted menu of continuation options.
			// Weights: 4/7 continue (a), 1/7 chain another S2S (b),
			//          1/7 tilt-right or slope-up (c1/d1), 1/7 tilt-left or slope-down (c2/d2).
			{
				string s2s = GetSlope2Straight();
				if (s2s.Length > 0 && (state == SurfaceState::Slope || state == SurfaceState::Tilt)
					&& placedCoords.Length > 0) {
					auto lastB = GetBlockAt(map, placedCoords[placedCoords.Length - 1]);
					if (lastB !is null && lastB.BlockModel.IdName == s2s) {
						int droll = MathRand(0, 6); // 0–3 = continue, 4 = chain, 5 = right/up, 6 = left/down
						if (droll == 4) {
							// b) Chain another Slope2Straight in the current direction.
							targetBlock = s2s;
							targetState = state;
							TGprint("V4 S2S: option b — chain Slope2Straight");
						} else if (droll == 5) {
							if (state == SurfaceState::Slope) {
								// c1) Slope → TiltRight
								s2sForcedTiltSide = TiltSide::TiltRight;
								targetState = SurfaceState::Tilt;
								targetBlock = tiltRightPool.Length > 0 ? PickFromPool(tiltRightPool) : PickFromPool(tiltPool);
								TGprint("V4 S2S: option c1 — Slope→TiltRight");
							} else {
								// d1) Tilt → SlopeUp
								s2sHasForcedSlope = true;
								s2sForcedSlopeDir = SlopeDir::SlopeUp;
								targetState = SurfaceState::Slope;
								targetBlock = slopeUpPool.Length > 0 ? PickFromPool(slopeUpPool) : PickFromPool(slopePool);
								TGprint("V4 S2S: option d1 — Tilt→SlopeUp");
							}
						} else if (droll == 6) {
							if (state == SurfaceState::Slope) {
								// c2) Slope → TiltLeft
								s2sForcedTiltSide = TiltSide::TiltLeft;
								targetState = SurfaceState::Tilt;
								targetBlock = tiltLeftPool.Length > 0 ? PickFromPool(tiltLeftPool) : PickFromPool(tiltPool);
								TGprint("V4 S2S: option c2 — Slope→TiltLeft");
							} else {
								// d2) Tilt → SlopeDown
								s2sHasForcedSlope = true;
								s2sForcedSlopeDir = SlopeDir::SlopeDown;
								targetState = SurfaceState::Slope;
								targetBlock = slopeDownPool.Length > 0 ? PickFromPool(slopeDownPool) : PickFromPool(slopePool);
								TGprint("V4 S2S: option d2 — Tilt→SlopeDown");
							}
						}
						// droll 0–3: keep existing pick (option a — continue current state)
					}
				}
			}

			// ── Enforce run limits ────────────────────────────────────────

			if (state == SurfaceState::Flat && flatRun < st_minStateLen && targetState != SurfaceState::Flat) {
				TGprint("V4 min-state: Flat run=" + tostring(flatRun) + " < " + tostring(st_minStateLen)
					+ " — overriding target back to Flat (was wanting other state)");
				targetState = SurfaceState::Flat;
				targetBlock = PickFromPool(flatPool);
			}
			if (state == SurfaceState::Slope && stateRun < st_minStateLen && targetState != SurfaceState::Slope) {
				TGprint("V4 min-state: Slope run=" + tostring(stateRun) + " < " + tostring(st_minStateLen)
					+ " — overriding target back to Slope/" + (slopeDir == SlopeDir::SlopeUp ? "Up" : "Down"));
				targetState = SurfaceState::Slope;
				targetBlock = PickSlopeBody(slopeDir, stateRun);
			}
			if (state == SurfaceState::Tilt && stateRun < st_minStateLen && targetState != SurfaceState::Tilt) {
				TGprint("V4 min-state: Tilt run=" + tostring(stateRun) + " < " + tostring(st_minStateLen)
					+ " — overriding target back to Tilt/" + (tiltSide == TiltSide::TiltLeft ? "L" : "R"));
				targetState = SurfaceState::Tilt;
				array<string>@ minPool = (tiltSide == TiltSide::TiltLeft) ? tiltLeftPool : tiltRightPool;
				targetBlock = PickFromPool(minPool);
			}
			if (state == SurfaceState::Slope && stateRun >= MAX_SLOPE_RUN && targetState != SurfaceState::Flat) {
				targetState = SurfaceState::Flat;
				targetBlock = PickFromPool(flatPool);
			}
			if (state == SurfaceState::Tilt && stateRun >= MAX_TILT_RUN && targetState != SurfaceState::Flat) {
				targetState = SurfaceState::Flat;
				targetBlock = PickFromPool(flatPool);
			}


			// ── Stadium wall avoidance ────────────────────

			if (st_stadiumMode) {
				// Ceiling avoidance: a slope-up climbing toward the roof gets refused by the
				// engine at PlaceBlock time (no ceiling term in OutOfStadiumBounds), which
				// silently drops to a side socket and turns the slope into a tilt. Pre-empt it:
				// when a slope-up is within STADIUM_CEIL_DIST of the ceiling, exit to flat.
				if (state == SurfaceState::Slope && slopeDir == SlopeDir::SlopeUp) {
					int roomAbove = STADIUM_CEIL_MAX - prevPos.y;
					if (roomAbove < STADIUM_CEIL_DIST) {
						targetState = SurfaceState::Flat;
						targetBlock = PickFromPool(flatPool);
						TGprint("Stadium: ceiling in " + tostring(roomAbove) + " (Slope/Up) -> forcing Flat exit");
					}
				}

				int distAhead = StadiumDistAhead(prevPos, g_travelDir);
				if (distAhead < STADIUM_EXIT_DIST && state != SurfaceState::Flat) {
					// Approaching wall in a slope/tilt: exit to flat before turning.
					targetState = SurfaceState::Flat;
					targetBlock = PickFromPool(flatPool);
					TGprint("Stadium: wall in " + tostring(distAhead) + " blocks ("
						+ (state == SurfaceState::Slope ? "Slope" : "Tilt") + ") → forcing Flat exit");
				} else if (distAhead < STADIUM_TURN_DIST && state == SurfaceState::Flat) {
					// About to hit a wall: force a Curve2 turn toward the side with more room.
					string curveBlock = (distAhead < 2)
						? SURF_PREFIX[int(g_surface)] + "Curve1"
						: SURF_PREFIX[int(g_surface)] + "Curve2";
					auto leftDir  = TurnDirLeft(g_travelDir);
					auto rightDir = TurnDirRight(g_travelDir);
					int leftDist  = StadiumDistAhead(prevPos, leftDir);
					int rightDist = StadiumDistAhead(prevPos, rightDir);
					if (leftDist > rightDist)
						g_forceTurnDirIdx = DirToInt(leftDir);
					else if (rightDist > leftDist)
						g_forceTurnDirIdx = DirToInt(rightDir);
					else
						g_forceTurnDirIdx = (MathRand(0, 1) == 0) ? DirToInt(leftDir) : DirToInt(rightDir);
					targetState = SurfaceState::Flat;
					targetBlock = curveBlock;
					TGprint("Stadium: wall in " + tostring(distAhead) + " blocks (Flat) → forcing " + curveBlock);
				}
			}

			// ── Transition ────────────────────────────────────────────────

			bool transOk = true;

			if (state == targetState) {
				// No transition needed
			}
			else if (state == SurfaceState::Flat && targetState == SurfaceState::Slope) {
				auto entryDir = g_travelDir;   // heading before the transition; transitions go straight
				int3 p = EnterSlope(map, prevPos, placed + 1, slopeDir);
				if (p.x < 0) { transOk = false; }
				else {
					prevPos = p; placed++;
					g_travelDir = entryDir;   // continue in the initial direction (don't trust the transition's detected heading)
					placedCoords.InsertLast(p); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface); state = SurfaceState::Slope; stateRun = 0; flatRun = 0;
					// Re-pick target from the now-known directional pool. Straight Slope2Straight
					// bodies are placed forward in the place-target section via the WithHole probe.
					array<string>@ sp = (slopeDir == SlopeDir::SlopeUp) ? slopeUpPool : slopeDownPool;
					if (sp.Length > 0) targetBlock = PickSlopeBody(slopeDir, 0);
				}
			}
			else if (state == SurfaceState::Flat && targetState == SurfaceState::Tilt) {
				auto entryDir = g_travelDir;   // heading before the transition; transitions go straight
				int3 p = EnterTilt(map, prevPos, placed + 1, tiltSide);
				if (p.x < 0) { transOk = false; }
				else {
					prevPos = p; placed++;
					g_travelDir = entryDir;   // continue in the initial direction (don't trust the transition's detected heading)
					placedCoords.InsertLast(p); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface); state = SurfaceState::Tilt; stateRun = 0; flatRun = 0;
					// Re-pick target from the now-known side pool. The first tilt body (platform
					// Slope2Straight) is placed forward in the place-target section via the WithHole probe.
					array<string>@ sp = (tiltSide == TiltSide::TiltLeft) ? tiltLeftPool : tiltRightPool;
					if (sp.Length > 0) targetBlock = PickSlopeBody(slopeDir, 0);
				}
			}
			else if (state == SurfaceState::Slope && targetState == SurfaceState::Flat) {
				int3 p = ExitSlope(map, prevPos, placed + 1, slopeDir);
				if (p.x < 0) {
					if (phase == TrackPhase::PhaseSlopeUp) {
						// Transition block unavailable — pop last slope body block and
						// place a flat block directly. Going uphill the car will jump the
						// height difference, so a missing transition is acceptable.
						TGprint("V4: SlopeUp exit failed — jump-landing fallback: popping last slope block");
						int3 popCoord = placedCoords[placedCoords.Length - 1];
						RemoveBlockRobust(map, popCoord, placedCoords);
						placed--; placedCoords.RemoveLast(); placedDirs.RemoveLast(); placedSurfaces.RemoveLast(); g_surface = (placedSurfaces.Length > 0) ? placedSurfaces[placedSurfaces.Length - 1] : initSurface;
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
				// Platform shortcut: Slope2Straight is simultaneously sloped and tilted.
				// If it was the last body block, skip transition blocks -- just flip state.
				string s2s = GetSlope2Straight();
				auto lastB = (placedCoords.Length > 0) ? GetBlockAt(map, placedCoords[placedCoords.Length - 1]) : null;
				string lastBName = (lastB !is null) ? lastB.BlockModel.IdName : "";
				if (s2s.Length > 0 && lastBName == s2s) {
					// Derive tiltSide from slopeDir (SlopeUp→TiltLeft, SlopeDown→TiltRight),
					// unless the S2S decision pre-set a specific side (options c1/c2).
					if (s2sForcedTiltSide != TiltSide::TiltNone) {
						tiltSide = s2sForcedTiltSide;
						s2sForcedTiltSide = TiltSide::TiltNone;
					} else {
						tiltSide = (slopeDir == SlopeDir::SlopeUp) ? TiltSide::TiltLeft : TiltSide::TiltRight;
					}
					TGprint("V4 trans: Slope->Tilt shortcut via Slope2Straight (no transition block)  tiltSide=" + (tiltSide == TiltSide::TiltLeft ? "L" : "R"));
					state = SurfaceState::Tilt; stateRun = 0; flatRun = 0;
					array<string>@ sp = (tiltSide == TiltSide::TiltLeft) ? tiltLeftPool : tiltRightPool;
					if (sp.Length > 0) targetBlock = PickSlopeBody(slopeDir, 0);
					// Switch is a ~90° pivot on the dual block — side-attach it (see PlaceSwitchSlopeTilt).
					g_s2sSideAttach = true; g_s2sSidePref = tiltSide;
				} else {
					int3 p = ExitSlope(map, prevPos, placed + 1, slopeDir);
					if (p.x < 0) { transOk = false; }
					else {
						prevPos = p; placed++; placedCoords.InsertLast(p); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface); state = SurfaceState::Flat;
						int3 p2 = EnterTilt(map, prevPos, placed + 1, tiltSide);
						if (p2.x < 0) { transOk = false; }
						else { prevPos = p2; placed++; placedCoords.InsertLast(p2); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface); state = SurfaceState::Tilt; stateRun = 0; flatRun = 0; }
					}
				}
			}
			else if (state == SurfaceState::Tilt && targetState == SurfaceState::Flat) {
				int3 p = ExitTilt(map, prevPos, placed + 1, tiltSide);
				if (p.x < 0) { transOk = false; }
				else { prevPos = p; placed++; placedCoords.InsertLast(p); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface); state = SurfaceState::Flat; stateRun = 0; flatRun = 0; tiltSide = TiltSide::TiltNone; }
			}
			else if (state == SurfaceState::Tilt && targetState == SurfaceState::Slope) {
				// Platform shortcut: Slope2Straight is simultaneously sloped and tilted.
				// If it was the last body block, skip transition blocks -- just flip state.
				string s2s = GetSlope2Straight();
				auto lastB = (placedCoords.Length > 0) ? GetBlockAt(map, placedCoords[placedCoords.Length - 1]) : null;
				string lastBName = (lastB !is null) ? lastB.BlockModel.IdName : "";
				if (s2s.Length > 0 && lastBName == s2s) {
					// Derive slopeDir from travel direction (N=up, S=down),
					// unless the S2S decision pre-set a specific direction (options d1/d2).
					if (s2sHasForcedSlope) {
						slopeDir = s2sForcedSlopeDir;
						s2sHasForcedSlope = false;
					} else {
						slopeDir = (g_travelDir == CGameEditorPluginMap::ECardinalDirections::North) ? SlopeDir::SlopeUp : SlopeDir::SlopeDown;
					}
					TGprint("V4 trans: Tilt->Slope shortcut via Slope2Straight (no transition block)  slopeDir=" + (slopeDir == SlopeDir::SlopeUp ? "Up" : "Down"));
					state = SurfaceState::Slope; stateRun = 0; flatRun = 0;
					array<string>@ sp = (slopeDir == SlopeDir::SlopeUp) ? slopeUpPool : slopeDownPool;
					if (sp.Length > 0) targetBlock = PickSlopeBody(slopeDir, 0);
					// Switch is a ~90° pivot on the dual block — side-attach it (see PlaceSwitchSlopeTilt).
					g_s2sSideAttach = true; g_s2sSidePref = TiltSide::TiltNone;
				} else {
					int3 p = ExitTilt(map, prevPos, placed + 1, tiltSide);
					if (p.x < 0) { transOk = false; }
					else {
						prevPos = p; placed++; placedCoords.InsertLast(p); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface); state = SurfaceState::Flat; tiltSide = TiltSide::TiltNone;
						int3 p2 = EnterSlope(map, prevPos, placed + 1, slopeDir);
						if (p2.x < 0) { transOk = false; }
						else {
							prevPos = p2; placed++; placedCoords.InsertLast(p2); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface); state = SurfaceState::Slope; stateRun = 0; flatRun = 0;
							array<string>@ sp = (slopeDir == SlopeDir::SlopeUp) ? slopeUpPool : slopeDownPool;
							if (sp.Length > 0) targetBlock = PickSlopeBody(slopeDir, 0);
						}
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
			// Road surfaces transition through RoadTech as hub (Dirt→Tech→Bump).
			// Platform surfaces connect directly — no transition block needed between them.
			// Each road transition block is tried normal first, then flipped 180° (no dir change)
			// because the block is bidirectional — one orientation has the right surface facing
			// the previous block. Same logic as EnterTilt.
			{
				Surface targetSurface = BlockSurface(targetBlock);
				if (targetSurface != g_surface) {
					bool surfTransOk = true;

					// Platform→Platform: direct switch, no transition block required.
					if (!IsRoadSurface(g_surface) && !IsRoadSurface(targetSurface)) {
						TGprint("V4 surf-trans: " + SURF_PREFIX[int(g_surface)] + "→" + SURF_PREFIX[int(targetSurface)] + " (direct, no block)");
						g_surface = targetSurface;
					}
					// Step 1: if current surface is not Tech, exit to Tech first.
					else if (g_surface != Surface::SurfaceTech) {
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
								LogPlacedBlock(placed + 1, exitName, tp, "surf-trans " + SURF_PREFIX[int(g_surface)] + "→Tech");
								g_surface = Surface::SurfaceTech;
								prevPos = tp; placed++; placedCoords.InsertLast(tp); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface);
							}
						}
					}

					// Step 2: if target is a road surface and not Tech, enter from Tech.
					if (surfTransOk && IsRoadSurface(targetSurface) && targetSurface != Surface::SurfaceTech) {
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
								LogPlacedBlock(placed + 1, enterName, tp, "surf-trans Tech→" + SURF_PREFIX[int(targetSurface)]);
								g_surface = targetSurface;
								prevPos = tp; placed++; placedCoords.InsertLast(tp); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface);
							}
						}
					}

					if (!surfTransOk) continue;
				}
			}

			// ── Place target block ────────────────────────────────────────

			// Recompute phase — a mid-iteration transition may have changed state
			// (e.g. Slope/Down→Flat), and we must use the updated phase for placement.
			phase = ComputePhase(state, slopeDir, tiltSide);

			// For curve blocks, pick left or right turn 50/50 by setting the forced exit dir.
			// Tilt curves and other special blocks are excluded — only plain CurveN blocks.
			// Skip if stadium wall avoidance already picked a direction.
			if (state == SurfaceState::Flat
				&& targetBlock.IndexOf("Curve") >= 0
				&& targetBlock.IndexOf("Tilt") < 0
				&& targetBlock.IndexOf("Slope") < 0
				&& g_forceTurnDirIdx < 0) {
				if (MathRand(0, 1) == 0)
					g_forceTurnDirIdx = DirToInt(TurnDirLeft(g_travelDir));
				else
					g_forceTurnDirIdx = DirToInt(TurnDirRight(g_travelDir));
			}

			// Slope-down body blocks are placed with reverseDir sockets facing forward.
			// PlaceConnected would grab their entry-side sockets (preferDir) instead.
			// A down-slope CURVE exits 90° to the side, which PlaceReversedConnected (straight-
			// back only) rejects — those go through the turn-aware reversed placement instead.
			int3 newPos = int3(-1, -1, -1);
			bool placedBySide = false;
				// Flat base ramps ascend by default; reverse ~half the time so they descend instead.
				bool reverseRamp = (state == SurfaceState::Flat) && IsFlatRamp(targetBlock) && MathRand(0, 1) == 0;
			bool placedBySwitch = false;
			if (g_s2sSideAttach) {
				// S2S slope↔tilt switch: pivot the dual block onto a side socket.
				g_s2sSideAttach = false;
				newPos = PlaceSwitchSlopeTilt(map, prevPos, targetBlock, g_s2sSidePref);
				placedBySide = (newPos.x >= 0);
				placedBySwitch = placedBySide;
				if (!placedBySide)
					TGprint("V4: S2S side-attach found no side socket — falling back to straight placement");
			}
			// Straight dual Slope2Straight body: the solid block hides its forward/banked faces from
			// GetConnectResults, so probe with the WithHole variant and place the solid block forward.
			// On failure newPos stays <0 and we drop into the fallback chain (flat forward) below —
			// never the stamp-matching PlaceConnected, which would skew it onto a banked side.
			bool isDualStraight = (GetSlope2Straight().Length > 0 && targetBlock == GetSlope2Straight());
			if (!placedBySide && isDualStraight) {
				int yCrit = (state == SurfaceState::Slope) ? (slopeDir == SlopeDir::SlopeUp ? 1 : -1) : 0;
				newPos = PlaceSlope2StraightForwardHole(map, prevPos, g_travelDir, yCrit);
				placedBySide = (newPos.x >= 0);   // reuse flag to skip the normal placement pass
			}
			if (!placedBySide && !isDualStraight) {
				if (phase == TrackPhase::PhaseSlopeDown) {
					newPos = (targetBlock.IndexOf("Curve") >= 0)
						? PlaceReversedTurn(map, prevPos, targetBlock)
						: PlaceReversedConnected(map, prevPos, targetBlock);
				} else {
					if (reverseRamp) {
						newPos = PlaceReversedConnected(map, prevPos, targetBlock);  // descend the ramp
						if (newPos.x < 0) newPos = PlaceConnected(map, prevPos, targetBlock);  // else climb
					} else {
						newPos = PlaceConnected(map, prevPos, targetBlock);
					}
				}
			}
			// Tilt→Slope S2S switch: up/down isn't known until the dual block is placed — read it
			// from the pivot block's actual Y change (prevPos is still the pre-placement coord).
			// Drives reversed (down) vs forward (up) for the following slope bodies.
			if (placedBySwitch && state == SurfaceState::Slope && newPos.x >= 0) {
				if      (newPos.y > prevPos.y) slopeDir = SlopeDir::SlopeUp;
				else if (newPos.y < prevPos.y) slopeDir = SlopeDir::SlopeDown;
				TGprint("    S2S Tilt→Slope: slopeDir from Y = " + (slopeDir == SlopeDir::SlopeUp ? "Up" : "Down"));
			}
			if (newPos.x < 0) {
				TGprint("\\$f00V4: could not place " + targetBlock + " (block [" + tostring(placed + 1) + "]), trying fallbacks");
				LogPlacementDiag(map, prevPos, targetBlock);

				// Fallback 0: if we just placed a transition block (state changed, stateRun==0),
				// undo it and reset to Flat, then try a flat block from the pre-transition position.
				if (state != SurfaceState::Flat && stateRun == 0 && placedCoords.Length > 0) {
					int3 transCoord = placedCoords[placedCoords.Length - 1];
					RemoveBlockRobust(map, transCoord, placedCoords);
					placed--; placedCoords.RemoveLast(); placedDirs.RemoveLast(); placedSurfaces.RemoveLast(); g_surface = (placedSurfaces.Length > 0) ? placedSurfaces[placedSurfaces.Length - 1] : initSurface;
					prevPos     = (placedCoords.Length > 0) ? placedCoords[placedCoords.Length - 1] : startPos;
					g_travelDir = (placedDirs.Length   > 0) ? placedDirs[placedDirs.Length - 1]     : initDir;
					state = SurfaceState::Flat; tiltSide = TiltSide::TiltNone; stateRun = 0; flatRun = 0;
					g_nUndoTrans++;
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
					g_nFlatFb++;
					TGprint("V4: flat-fallback trying " + anyFlat + " from " + tostring(prevPos) + "  travelDir=" + DirStr(g_travelDir));
					int3 flatPos = PlaceConnected(map, prevPos, anyFlat);
					if (flatPos.x >= 0) {
						placed++; placedCoords.InsertLast(flatPos); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface);
						prevPos = flatPos; state = SurfaceState::Flat; stateRun = 0; flatRun = 1;
						TGprint("V4: flat-fallback succeeded, placed [" + tostring(placed) + "]");
						continue;
					}
					TGprint("V4: flat-fallback failed -- trying flat-adjacent escape");
				}

				// Fallback 2.5 (platform only): drop a flat block into any free neighbour,
				// ignoring connection geometry — platform blocks are borderless. Keeps the
				// track flat/same-level and avoids an unnecessary downward dive.
				{
					int3 adj = PlaceBorderlessAdjacent(map, prevPos, GetStraight());
					if (adj.x >= 0) {
						placed++; placedCoords.InsertLast(adj); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface);
						prevPos = adj; state = SurfaceState::Flat; stateRun = 0; flatRun = 1;
						TGprint("V4: flat-adjacent escape succeeded, placed [" + tostring(placed) + "]");
						continue;
					}
					TGprint("V4: flat-adjacent escape failed -- trying slope-escape");
				}

				// Fallback 3+4: slope-down escape — pop 1 then 2 blocks one at a time.
				// After each pop try: SlopeEnd(reversed) -> SlopeStart(reversed) -> flat block.
				// Changes elevation to break out of crowded flat areas.
				{
					bool slopeEscaped = false;
					g_nSlopeEsc++;
					for (int popK = 1; popK <= 2 && !slopeEscaped && placedCoords.Length > 0; popK++) {
						int3 popCoord = placedCoords[placedCoords.Length - 1];
						string popName = "?";
						auto pbInfo = GetBlockAt(map, popCoord);
						if (pbInfo !is null) popName = pbInfo.BlockModel.IdName;
						bool popOk = RemoveBlockRobust(map, popCoord, placedCoords);
						TGprint("\\$f80V4: slope-escape pop: " + (popOk ? "removed" : "FAILED to remove") + " block [" + tostring(placed) + "] " + popName + " @ " + tostring(popCoord));
						placed--;
						placedCoords.RemoveLast(); placedDirs.RemoveLast(); placedSurfaces.RemoveLast(); g_surface = (placedSurfaces.Length > 0) ? placedSurfaces[placedSurfaces.Length - 1] : initSurface;
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
							string popS2 = GetSlopeStart2();
							if (pn == GetSlopeEnd() || pn == GetSlopeStart() || (popS2.Length > 0 && pn == popS2) ||
							    pn == GetTiltUpLeft() || pn == GetTiltUpRight() ||
							    pn == GetTiltDownLeft() || pn == GetTiltDownRight()) {
								TGprint("\\$f80V4: slope-escape also pops transition block [" + tostring(placed) + "] " + pn + " @ " + tostring(prevPos));
								RemoveBlockRobust(map, prevPos, placedCoords);
								placed--;
								placedCoords.RemoveLast(); placedDirs.RemoveLast(); placedSurfaces.RemoveLast(); g_surface = (placedSurfaces.Length > 0) ? placedSurfaces[placedSurfaces.Length - 1] : initSurface;
								prevPos     = (placedCoords.Length > 0) ? placedCoords[placedCoords.Length - 1] : startPos;
								g_travelDir = (placedDirs.Length   > 0) ? placedDirs[placedDirs.Length - 1]     : initDir;
							}
						}
					}

						string escSlopeEnd   = GetSlopeEnd();
						// SlopeDown exit: reversed SlopeStart — mirrors ExitSlope(SlopeDown).
						string escSlopeStart = GetSlopeStart();
						TGprint("  slope-escape: trying " + escSlopeEnd + " from " + tostring(prevPos) + "  reverseDir=" + DirStr(IntToDir((DirToInt(g_travelDir)+2)%4)));
						int3 p1 = PlaceReversedConnected(map, prevPos, escSlopeEnd);
						if (p1.x < 0) { TGprint("  slope-escape: " + escSlopeEnd + " failed"); continue; }
						TGprint("V4 [" + tostring(placed+1) + "] " + escSlopeEnd + " (escape-entry) @ " + tostring(p1) + "  dir=" + DirStr(g_travelDir));

						TGprint("  slope-escape: trying " + escSlopeStart + " (reversed) from " + tostring(p1) + "  travelDir=" + DirStr(g_travelDir));
						int3 p2 = PlaceReversedConnected(map, p1, escSlopeStart);
						if (p2.x < 0) {
							TGprint("\\$f80  slope-escape: " + escSlopeStart + " failed, removing [" + tostring(placed+1) + "] " + escSlopeEnd + " @ " + tostring(p1));
							RemoveBlockRobust(map, p1, placedCoords);
							continue;
						}
						TGprint("V4 [" + tostring(placed+2) + "] " + escSlopeStart + " (escape-exit) @ " + tostring(p2) + "  dir=" + DirStr(g_travelDir));
						// Both escape blocks descend via PlaceReversedConnected, which leaves g_travelDir
						// untouched (the descent doesn't reverse physical travel), so g_travelDir already
						// holds the correct heading here — no restore needed.

						// Always use the straight — a level-drop escape needs a small block that
						// fits wherever it lands; a random flat pick can roll a large curve that
						// won't connect (the failure that aborted the escape). Fancier selection later.
						string escFlat = GetStraight();
						TGprint("  slope-escape: trying flat " + escFlat + " from " + tostring(p2));
						int3 p3 = PlaceConnected(map, p2, escFlat);
						if (p3.x < 0) {
							TGprint("\\$f80  slope-escape: flat failed, removing [" + tostring(placed+2) + "] " + escSlopeStart + " @ " + tostring(p2) + " and [" + tostring(placed+1) + "] " + escSlopeEnd + " @ " + tostring(p1));
							RemoveBlockRobust(map, p2, placedCoords);
							RemoveBlockRobust(map, p1, placedCoords);
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
			int3 p = ExitSlope(map, prevPos, placed + 1, slopeDir);
			if (p.x >= 0) { prevPos = p; placed++; placedCoords.InsertLast(p); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface); state = SurfaceState::Flat; }
		}
		if (state == SurfaceState::Tilt) {
			int3 p = ExitTilt(map, prevPos, placed + 1, tiltSide);
			if (p.x >= 0) { prevPos = p; placed++; placedCoords.InsertLast(p); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface); state = SurfaceState::Flat; tiltSide = TiltSide::TiltNone; }
		}

		// ── Place Finish (mandatory) ──────────────────────────────────────
		// A track is invalid without a Finish, so this is best-effort-until-success:
		// try to connect a Finish at prevPos; if it won't fit, pop the last block and
		// retry from the previous position. Block count is not important here.

		string finishName = SURF_PREFIX[int(g_surface)] + "Finish";
		if (map.GetBlockModelFromName(finishName) is null && finishName != "RoadTechFinish") {
			TGprint("V4: " + finishName + " not found, falling back to RoadTechFinish");
			finishName = "RoadTechFinish";
		}

		// Try a finish at the end (natural connect, then one level below). If it still
		// won't fit, pop the last block and retry — at most 2 pops.
		bool finishPlaced = false;
		for (int ftry = 0; ftry < 3 && !finishPlaced && placedCoords.Length > 0; ftry++) {
			int3 fpos = PlaceFinish(map, prevPos, finishName);
			if (fpos.x >= 0) {
				placed++;
				placedCoords.InsertLast(fpos); placedDirs.InsertLast(g_travelDir); placedSurfaces.InsertLast(g_surface);
				prevPos = fpos;
				TGprint("\\$0f0V4 Finish placed at " + tostring(fpos));
				finishPlaced = true;
				break;
			}
			if (ftry >= 2) break;  // already retried after 2 pops — give up

			// Finish didn't fit — pop the last placed block and retry one block earlier.
			int3 popCoord = placedCoords[placedCoords.Length - 1];
			string popName = "?";
			auto pbInfo = GetBlockAt(map, popCoord);
			if (pbInfo !is null) popName = pbInfo.BlockModel.IdName;
			RemoveBlockRobust(map, popCoord, placedCoords);
			TGprint("\\$f80V4: finish didn't fit at " + tostring(prevPos) + " — popped [" + tostring(placed) + "] " + popName + " @ " + tostring(popCoord));
			placed--;
			placedCoords.RemoveLast(); placedDirs.RemoveLast(); placedSurfaces.RemoveLast();
			g_surface   = (placedSurfaces.Length > 0) ? placedSurfaces[placedSurfaces.Length - 1] : initSurface;
			prevPos     = (placedCoords.Length > 0) ? placedCoords[placedCoords.Length - 1] : startPos;
			g_travelDir = (placedDirs.Length   > 0) ? placedDirs[placedDirs.Length - 1]     : initDir;
		}

		if (!finishPlaced) {
			TGprint("\\$f00V4: WARNING — could not place a Finish block after backing up; track has NO finish.");
			UI::ShowNotification("V4: WARNING — track has no Finish block!");
		}

		uint64 elapsed = Time::get_Now() - before;
		TGprint("\\$0f0\\$sV4 done: " + tostring(placed) + " blocks in " + tostring(elapsed) + " ms"
			+ "  cache hits=" + tostring(g_cacheHits) + " misses=" + tostring(g_cacheMisses));
		TGprint("\\$0f0\\$sV4 timing: connect " + tostring(g_tConnect) + "ms/" + tostring(g_nConnect) + "x"
			+ "  place " + tostring(g_tPlace) + "ms/" + tostring(g_nPlace) + "x"
			+ "  scan " + tostring(g_tScan) + "ms/" + tostring(g_nScan) + "x"
			+ "  remove " + tostring(g_tRemove) + "ms/" + tostring(g_nRemove) + "x");
		TGprint("\\$0f0\\$sV4 fallbacks: undoTrans=" + tostring(g_nUndoTrans)
			+ "  flatFb=" + tostring(g_nFlatFb) + "  borderless=" + tostring(g_nBorderless)
			+ "  slopeEsc=" + tostring(g_nSlopeEsc));
		UI::ShowNotification("V4 Track: " + tostring(placed) + " blocks");
		lastRunCoords = placedCoords;
		if (g_placedStartCoord.x >= 0) {
			lastRunCoords.InsertLast(g_placedStartCoord);
			g_placedStartCoord = int3(-1, -1, -1);
		}
		return;
	}

	// Generation failed — auto-placed start block also needs removal.
	if (g_placedStartCoord.x >= 0) {
		array<int3> startOnly = { g_placedStartCoord };
		ClearPlaced(map, startOnly);
		g_placedStartCoord = int3(-1, -1, -1);
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

	CGameCtnBlock@ b = null;
	for (int i = int(allB.Length) - 1; i >= 0; i--) {
		if (BlockKindFromIdName(allB[i].BlockModel.IdName) == "Track") {
			@b = allB[i];
			break;
		}
	}
	if (b is null) { TGprint("CheckDir: no track block found on map."); return; }
	int3 bCoord = int3(b.CoordX, b.CoordY, b.CoordZ);
	string bName = b.BlockModel.IdName;
	TGprint("CheckDir: source block = '" + bName + "'  anchor=" + tostring(bCoord) + "  dir=" + DirStr(GetBlockDirection(b)));

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

// Quick variant of CheckDirectionForBlocks: instead of just logging the candidates, actually
// PLACE the dest block at every connection point the game reports as placeable. Lets you see
// all candidate connections at once and eyeball which orientations join smoothly. Candidates
// are snapshotted before any placement, since placing one block can change the source block's
// connect results mid-loop.
void PlaceAllConnections()
{
	auto app = cast<CTrackMania>(GetApp());
	if (app is null) return;
	auto editor = cast<CGameCtnEditorFree>(app.Editor);
	if (editor is null) { UI::ShowNotification("Editor not open!"); return; }
	auto map = cast<CGameEditorPluginMap>(editor.PluginMapType);
	if (map is null) return;

	auto allB = GetApp().RootMap.Blocks;
	if (allB.Length == 0) { TGprint("PlaceConns: no blocks on map."); return; }

	CGameCtnBlock@ b = null;
	for (int i = int(allB.Length) - 1; i >= 0; i--) {
		if (BlockKindFromIdName(allB[i].BlockModel.IdName) == "Track") {
			@b = allB[i];
			break;
		}
	}
	if (b is null) { TGprint("PlaceConns: no track block found on map."); return; }
	int3 bCoord = int3(b.CoordX, b.CoordY, b.CoordZ);
	string bName = b.BlockModel.IdName;

	string probeName = g_checkDirProbeName;
	if (probeName.Length == 0) { TGprint("\\$f00PlaceConns: no destination block set — use 'Load as dest' first"); return; }
	auto probeInfo = map.GetBlockModelFromName(probeName);
	if (probeInfo is null) { TGprint("\\$f00PlaceConns: probe model '" + probeName + "' not found"); return; }

	while (!map.IsEditorReadyForRequest) { yield(); }
	map.GetConnectResults(b, probeInfo);
	while (!map.IsEditorReadyForRequest) { yield(); }

	// Snapshot placeable candidates before placing anything.
	array<CGameEditorPluginMap::ECardinalDirections> dirs;
	array<int3> coords;
	for (uint r = 0; r < map.ConnectResults.Length; r++) {
		auto res = map.ConnectResults[r];
		if (res is null || !res.CanPlace) continue;
		dirs.InsertLast(ConvertDir(res.Dir));
		coords.InsertLast(res.Coord);
	}

	TGprint("PlaceConns: placing '" + probeName + "' at " + tostring(dirs.Length)
		+ " placeable connection(s) from '" + bName + "' @ " + tostring(bCoord) + "  dir=" + DirStr(GetBlockDirection(b)));
	int ok = 0;
	for (uint i = 0; i < dirs.Length; i++) {
		if (PlaceBlock(map, probeName, dirs[i], coords[i])) {
			ok++;
			TGprint("  placed @ " + tostring(coords[i]) + "  dir=" + DirStr(dirs[i]));
		} else {
			TGprint("\\$f80  FAILED @ " + tostring(coords[i]) + "  dir=" + DirStr(dirs[i]));
		}
	}
	TGprint("\\$0f0PlaceConns: placed " + tostring(ok) + "/" + tostring(dirs.Length));
}

} // namespace v4
