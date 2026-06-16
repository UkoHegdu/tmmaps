//block blanks
namespace blocks
{
// Legacy style/vista state. The v4 generator does NOT use any of this — it has its own
// per-surface tables. The remaining consumers are:
//   GetBlockFromPoolImpl (blocks_generated.as) — reads CURR_VISTA / CURR_BLOCKS to pick a pool,
//       and uses each RD_* below as the per-role fallback when a pool is empty.
//   Dev-tab block-analysis tools (main.as)      — read RD_STRAIGHT and RD_START.
//   PlaceBlock/CanPlaceBlock wall-clearing guard — read RD_TURN2, RD_UP2, WALL_*.
// The runtime style picker was removed, so CURR_BLOCKS is never reassigned; it stays "TechBlocks"
// and every RD_* keeps its Road Tech default value below.
string CURR_BLOCKS = "TechBlocks";
string CURR_VISTA = "Stadium";  // Stadium | BlueBay | GreenCoast | RedIsland | WhiteShore

string RD_STRAIGHT = "RoadTechStraight";
string RD_START = "RoadTechStart";
string RD_TURN1 = "RoadTechCurve1";
string RD_TURN2 = "RoadTechCurve2";
string RD_UP1 = "RoadTechSlopeBase";
string RD_UP2 = "RoadTechSlopeBase2";
string RD_TURBO1 = "RoadTechSpecialTurbo";
string RD_TURBO2 = "RoadTechSpecialTurbo2";
string RD_TURBOR = "RoadTechSpecialTurboRoulette";
string RD_CP = "RoadTechCheckpoint";
string RD_BOOSTER1 = "RoadTechSpecialBoost";
string RD_BOOSTER2 = "RoadTechSpecialBoost2";
string RD_NOENGINE = "RoadTechSpecialNoEngine";
string RD_SLOWMOTION = "RoadTechSpecialSlowMotion";
string RD_FRAGILE = "RoadTechSpecialFragile";
string RD_NOSTEER = "RoadTechSpecialNoSteering";
string RD_RESET = "RoadTechSpecialReset";
string RD_CRUISE = "RoadTechSpecialCruise";
string RD_NOBRAKE = "RoadTechSpecialNoBrake";
string RD_COOL1 = "RoadTechRampLow";
string RD_COOL2 = "RoadTechRampMed";

//walls (referenced by the PlaceBlock/CanPlaceBlock wall-clearing guard)
string WALL_STRAIGHT = "TrackWallStraightPillar";
string WALL_FULL = "DecoWallBasePillar";

// SCENERY_<Vista>, BLOCKS_<...> arrays and GetBlockFromPoolImpl live in blocks_generated.as
// (run generate_blocks_as.py to regenerate).

string PickFromPool(array<string>@ arr, const string &in fallback)
{
	if (arr.Length > 0)
		return arr[Math::Rand(0, int(arr.Length) - 1)];
	return fallback;
}

// Returns a random block from the generated pool for the current Vista/style/role.
string GetBlockFromPool(const string &in role)
{
	return GetBlockFromPoolImpl(role);
}

} // namespace blocks
