// Transition rule engine: filters flat blocks by keywords when transitioning between categories.
// Rules aligned with block_data/transitions_reference.txt
// Within subcategory: NonFlat A -> Flat -> NonFlat B. If no rule exists, pick another block (fallback).
// Cross-subcategory: use Road Tech as hub. All transition blocks have "RoadTechTo" in the name.
// Example: Dirt -> Bump = Dirt -> Tech (RoadTechToRoadDirt) -> Bump (RoadTechToRoadBump)

namespace transitions
{
// Path to block_data for reads. Tries Storage first (deployed), then dev path.
string GetBlockDataPath()
{
	string storage = IO::FromStorageFolder("block_data/");
	// Storage folder may not exist; try reading a known file to validate
	try {
		IO::File f(storage + "flat_blocks_roadtech.txt", IO::FileMode::Read);
		f.Close();
		return storage;
	} catch {}
	return "d:\\REPO\\tmmaps\\block_data\\"; // dev fallback
}

// Subcategory name from block IdName (e.g. RoadTechSlopeBase -> RoadTech)
string GetSubcategoryFromBlockName(const string &in blockName)
{
	// RallyCastleRoad before RoadTech so RallyCastleRoadToRoadTech returns RallyCastleRoad
	if (blockName.IndexOf("RallyCastleRoad") >= 0) return "RallyCastleRoad";
	if (blockName.IndexOf("RoadTech") >= 0) return "RoadTech";
	if (blockName.IndexOf("RoadDirt") >= 0) return "RoadDirt";
	if (blockName.IndexOf("RoadBump") >= 0) return "RoadBump";
	if (blockName.IndexOf("RoadIce") >= 0) return "RoadIce";
	if (blockName.IndexOf("RoadWater") >= 0) return "RoadWater";
	if (blockName.IndexOf("SnowRoad") >= 0) return "SnowRoad";
	return "";
}

// Category: Flat, Slope, Tilt, Diag, RoadIceWithWall
// Transition blocks (SlopeBase, SlopeEnd, TiltTransition, DiagStart, BranchToDiag) are Flat.
string GetCategoryFromBlockName(const string &in blockName)
{
	string lower = blockName.ToLower();
	if (lower.IndexOf("roadicewithwall") >= 0 && lower.IndexOf("roadiceto") < 0) return "RoadIceWithWall";
	if (lower.IndexOf("slope") >= 0 && lower.IndexOf("slopebase") < 0 && lower.IndexOf("slope2base") < 0 && lower.IndexOf("slopestart") < 0 && lower.IndexOf("slopeend") < 0) return "Slope";
	if (lower.IndexOf("tilt") >= 0 && lower.IndexOf("transition") < 0) return "Tilt";
	if (lower.IndexOf("diag") >= 0)
	{
		if (lower.IndexOf("diagleftstart") >= 0 || lower.IndexOf("diagrightstart") >= 0 || lower.IndexOf("branchtodiag") >= 0) return "Flat";
		return "Diag";
	}
	return "Flat";
}

// True if block is flat (or flat transition block). Excludes actual Slope/Tilt/Diag blocks.
bool IsFlatBlock(const string &in blockName)
{
	return GetCategoryFromBlockName(blockName) == "Flat";
}

// Returns keywords for transition. Empty array = no rule (fallback: pick another block).
// fromCategory, toCategory: "Flat", "Slope", "Tilt", "Diag", "RoadIceWithWall"
array<string>@ GetTransitionKeywords(const string &in subcategory, const string &in fromCategory, const string &in toCategory)
{
	// Road Water: no non-flat blocks. Snow Road, Rally Castle Road: disabled (no flat_blocks files)
	if (subcategory == "RoadWater" || subcategory == "SnowRoad" || subcategory == "RallyCastleRoad") return array<string>();

	// Same category: no transition needed
	if (fromCategory == toCategory) return array<string>();

	// Road Tech, Dirt, Bump: same rules
	if (subcategory == "RoadTech" || subcategory == "RoadDirt" || subcategory == "RoadBump")
	{
		if (fromCategory == "Flat" && toCategory == "Slope") return _kw("Base", "End", "Start");
		if (fromCategory == "Slope" && toCategory == "Flat") return _kw("Base", "End", "Start");
		if (fromCategory == "Flat" && toCategory == "Tilt") return _kw("Transition");
		if (fromCategory == "Tilt" && toCategory == "Flat") return _kw("Transition");
		if (fromCategory == "Flat" && toCategory == "Diag") return _kw("Start", "Branch");
		if (fromCategory == "Diag" && toCategory == "Flat") return _kw("Start", "Branch");
	}

	// Road Ice: Slope + RoadIceWithWall
	if (subcategory == "RoadIce")
	{
		if (fromCategory == "Flat" && toCategory == "Slope") return _kw("Base", "End", "Start");
		if (fromCategory == "Slope" && toCategory == "Flat") return _kw("Base", "End", "Start");
		if (fromCategory == "Flat" && toCategory == "RoadIceWithWall") return _kw("RoadIceToRoadIceWithWall");
		if (fromCategory == "RoadIceWithWall" && toCategory == "Flat") return _kw("RoadIceToRoadIceWithWall");
	}

	// Snow Road: Slope + Tilt. Tilt: use Transition; if that doesn't work, try Base, Start, End
	if (subcategory == "SnowRoad")
	{
		if (fromCategory == "Flat" && toCategory == "Slope") return _kw("Base", "End", "Start");
		if (fromCategory == "Slope" && toCategory == "Flat") return _kw("Base", "End", "Start");
		if (fromCategory == "Flat" && toCategory == "Tilt") return _kw("Transition", "Base", "Start", "End");
		if (fromCategory == "Tilt" && toCategory == "Flat") return _kw("Transition", "Base", "Start", "End");
	}

	// Rally Castle Road: Slope (Base, Start), Diag (Start only). Transition to Tech: RallyCastleRoadToRoadTech
	if (subcategory == "RallyCastleRoad")
	{
		if (fromCategory == "Flat" && toCategory == "Slope") return _kw("Base", "Start");
		if (fromCategory == "Slope" && toCategory == "Flat") return _kw("Base", "Start");
		if (fromCategory == "Flat" && toCategory == "Diag") return _kw("Start");
		if (fromCategory == "Diag" && toCategory == "Flat") return _kw("Start");
	}

	return array<string>(); // no rule
}

// Cross-subcategory: fromSub/toSub are RoadTech, RoadDirt, RoadBump, RoadIce.
// Always use Road Tech as hub. Blocks have "RoadTechTo" + other subcategory. Pool = RoadTech flat blocks.
// Road Water and Rally Castle Road excluded (no cross-transition support).
array<string>@ GetCrossSubcategoryKeywords(const string &in fromSub, const string &in toSub)
{
	if (fromSub == toSub) return array<string>();
	if (fromSub.Length == 0 || toSub.Length == 0) return array<string>();

	string otherSub = (fromSub == "RoadTech") ? toSub : fromSub;
	if (otherSub == "RoadTech") return array<string>();

	if (otherSub == "RoadDirt") return _kw("RoadTechToRoadDirt");
	if (otherSub == "RoadBump") return _kw("RoadTechToRoadBump");
	if (otherSub == "RoadIce") return _kw("RoadTechToRoadIce");
	return array<string>();
}

array<string>@ _kw(const string &in a, const string &in b = "", const string &in c = "", const string &in d = "")
{
	array<string>@ arr = array<string>();
	arr.InsertLast(a);
	if (b.Length > 0) arr.InsertLast(b);
	if (c.Length > 0) arr.InsertLast(c);
	if (d.Length > 0) arr.InsertLast(d);
	return arr;
}

// Filter blocks: keep only those whose name contains ANY of the keywords.
array<string>@ FilterBlocksByKeywords(array<string>@ blocks, array<string>@ keywords)
{
	array<string>@ result = array<string>();
	if (keywords.Length == 0) return result;
	for (uint i = 0; i < blocks.Length; i++)
	{
		for (uint k = 0; k < keywords.Length; k++)
		{
			if (blocks[i].IndexOf(keywords[k]) >= 0)
			{
				result.InsertLast(blocks[i]);
				break;
			}
		}
	}
	return result;
}

// Keep only flat blocks. Use for transition candidates - transitions between subcategories must be flat.
array<string>@ FilterToFlatBlocksOnly(array<string>@ blocks)
{
	array<string>@ result = array<string>();
	for (uint i = 0; i < blocks.Length; i++)
	{
		if (IsFlatBlock(blocks[i])) result.InsertLast(blocks[i]);
	}
	return result;
}

// Load flat blocks for subcategory from block_data/flat_blocks_<subcategory>.txt
array<string>@ LoadFlatBlocks(const string &in subcategory)
{
	array<string>@ result = array<string>();
	string path = GetBlockDataPath() + "flat_blocks_" + subcategory.ToLower() + ".txt";
	try
	{
		IO::File f(path, IO::FileMode::Read);
		string line;
		while (!f.EOF())
		{
			line = f.ReadLine().Trim();
			if (line.Length > 0) result.InsertLast(line);
		}
		f.Close();
	}
	catch { /* file not found or error */ }
	return result;
}

// Get transition block candidates for placing between fromBlock and targetBlock.
// Handles both within-subcategory (Flat<->Slope etc.) and cross-subcategory (Dirt<->Tech etc.).
// Returns filtered flat blocks; if empty, no rule or no matching blocks (caller should pick another block).
array<string>@ GetTransitionBlockCandidates(const string &in fromBlockName, const string &in targetBlockName)
{
	string fromSub = GetSubcategoryFromBlockName(fromBlockName);
	string toSub = GetSubcategoryFromBlockName(targetBlockName);
	if (fromSub.Length == 0 && toSub.Length == 0) return array<string>();
	if (fromSub.Length == 0) fromSub = toSub;
	if (toSub.Length == 0) toSub = fromSub;

	// Cross-subcategory: use Road Tech as hub, load from RoadTech flat blocks
	if (fromSub != toSub)
	{
		array<string>@ keywords = GetCrossSubcategoryKeywords(fromSub, toSub);
		if (keywords.Length == 0) return array<string>();
		array<string>@ flatBlocks = LoadFlatBlocks("RoadTech");
		array<string>@ filtered = FilterBlocksByKeywords(flatBlocks, keywords);
		return FilterToFlatBlocksOnly(filtered); // exclude non-flat (e.g. RoadTechToRoadDirtSlope*)
	}

	// Within subcategory: use category-based rules
	string fromCat = GetCategoryFromBlockName(fromBlockName);
	string toCat = GetCategoryFromBlockName(targetBlockName);

	array<string>@ keywords = GetTransitionKeywords(fromSub, fromCat, toCat);
	if (keywords.Length == 0) return array<string>();

	array<string>@ flatBlocks = LoadFlatBlocks(fromSub);
	array<string>@ filtered = FilterBlocksByKeywords(flatBlocks, keywords);
	return FilterToFlatBlocksOnly(filtered); // exclude non-flat
}

// Check if cross-subcategory transition is needed (different road types).
bool NeedsCrossSubcategoryTransition(const string &in fromSub, const string &in toSub)
{
	if (fromSub.Length == 0 || toSub.Length == 0) return false;
	return fromSub != toSub;
}

// Check if a transition is needed: from non-flat to different non-flat (must go via flat).
bool NeedsTransitionViaFlat(const string &in fromCategory, const string &in toCategory)
{
	if (fromCategory == "Flat" || toCategory == "Flat") return false;
	return fromCategory != toCategory;
}

} // namespace transitions
