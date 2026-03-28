void Begin()
{
	v4::Run();
}

void BeginLegacy()
{
	uint64 before = Time::get_Now();

	//preparing
	auto app = cast<CTrackMania>(GetApp());
	if (app is null) {
		return;
	}
		
	auto editor = cast<CGameCtnEditorFree>(app.Editor);
	if (editor is null) {
		UI::ShowNotification("editor is not opened!");
		warn("editor is not opened!");
		return;
	}
	
	auto map = cast<CGameEditorPluginMap>(editor.PluginMapType);
	if (map is null) {
		return;
	}
	
	map.RemoveAllBlocks();	
	if(blocks::IsMultipleBlockTypesSelected())
	{
		RandomBlocks();
	}
	
	seedDouble = ConvertSeed(seedText);
	//--
	
	TGprint("\\$0f0\\$sGenerating new track!");
	
	//variables
	auto dir = RandomDirection();
	auto point = RandomPoint();
	auto prevDir = dir;
	auto prevPrevDir = dir;
	auto prevPoint = point;
	auto prevPrevPoint = point;
	auto connectPoint = int3(0,0,0);
	string blockType = blocks::CURR_BLOCKS;
	string prevBlockType = blocks::CURR_BLOCKS;
	bool wasBlockTypeSwitched = false;
	int blocksPlacedAfterCP = 0;
	//--
	
	//start block
	PlaceBlock(map, blocks::RD_START, dir, point);
	TGprint("Created START block, at " + tostring(point) + ", pointing " + tostring(dir));
	map.SetBlockSkin(GetBlockAt(map, point), BANNER_LINK);
	point = point.opAdd(MoveDir(dir));
	//--
	
	int blockCantBePlacedCount = 0;
	int effectiveMaxBlocks = blocks::extendedSlopes ? Math::Min(st_maxBlocks, 100) : st_maxBlocks;
	array<int3>@ hist_placed = array<int3>();
	array<int3>@ hist_nextPoint = array<int3>();
	array<int>@ hist_nextDir = array<int>();
	array<string>@ hist_block = array<string>();

	for	(int blockIndex = 1; blockIndex <= effectiveMaxBlocks; blockIndex++)
	{
		if(blockCantBePlacedCount >= 50)
		{
			TGprint("\\$f00cant continue the track atfter " + tostring(blockIndex) + " blocks placed :(");
			break;
		}
		
		if(blocks::randomcolors)
		{
			map.NextMapElemColor = RandomColor();
		}
		
		blockType = blocks::CURR_BLOCKS;
		bool wasBlockTypeSwitchedLocal = false;
	
		string block = RandomBlock();
		auto dirCopy = dir;
		auto pointCopy = point;
		int turn = MathRand(1,3);
		bool blockPlaced = false;
		bool techConnect = false;
		
		if(st_useCpBlocks)
		{
			blocksPlacedAfterCP++;
			if(blocksPlacedAfterCP >= st_cpBlocks)
			{
				block = blocks::RD_CP;
			}
		}
		
		//special block check before
		if((block == blocks::RD_STRAIGHT && point.y == 9 && MathRand(1,8) == 4))
		{
			block = blocks::RD_END;
			dir = TurnDirLeft(dir);
			dir = TurnDirLeft(dir);
		}
		else if(block == blocks::RD_TURN1 || block == blocks::RD_TURN2 || block == blocks::RD_TURN3 || block == blocks::RD_TURN4)
		{
			if(block == blocks::RD_TURN2)
			{
				if (turn == 1)
				{
					TGprint("Turn Right");
					dir = TurnDirRight(dir);
					if(dir == DIR_EAST)
					{
						point = point.opAdd(MoveDir(dir));
					}
					else if(dir == DIR_WEST)
					{
						point = point.opAdd(MoveDir(TurnDirLeft(dir)));
					}
					else if(dir == DIR_SOUTH)
					{
						point = point.opAdd(MoveDir(dir)).opAdd(MoveDir(TurnDirLeft(dir)));
					}
				}
				else
				{
					TGprint("Turn Left");
					dir = TurnDirLeft(dir);
					dir = TurnDirLeft(dir);
					if(dir == DIR_EAST)
					{
						point = point.opAdd(MoveDir(TurnDirRight(dir)));
					}
					else if(dir == DIR_WEST)
					{
						point = point.opAdd(MoveDir(TurnDirRight(TurnDirRight(dir))));
					}
					else if(dir == DIR_NORTH)
					{
						point = point.opAdd(MoveDir(TurnDirRight(dir))).opAdd(MoveDir(TurnDirRight(TurnDirRight(dir))));
					}
				}
			}
			else
			{
				switch(turn)
				{	
					case 1:
						TGprint("Turn Right");
						dir = TurnDirRight(dir);
						break;
					case 2: 
						TGprint("Turn Left");
						dir = TurnDirLeft(dir);
						dir = TurnDirLeft(dir);
				}
			}
		}
		else if(block == blocks::RD_UP1 || block == blocks::RD_UP2)
		{
			if(point.y >= MAX_Y)
			{
				TGprint("WAYTOOHIGH");
				block = blocks::RD_STRAIGHT;
			}
			else if(turn == 2 && point.y >= 12)
			{
				dir = TurnDirLeft(dir);
				dir = TurnDirLeft(dir);
				if(block == blocks::RD_UP1)
				{
					point = point.opAdd(int3(0,-1,0));
				}
				else
				{
					point = point.opAdd(int3(0,-2,0));
				}
			}
		}
		else if(block == blocks::RD_CONNECT)
		{
			if(blocks::CURR_BLOCKS == "TechBlocks" || blocks::CURR_BLOCKS == "WaterBlocks") 
			{
				techConnect = true;
				block = blocks::RD_STRAIGHT;
			}
			if(CanPlaceBlock(map, block, dir, point.opAdd(MoveDir(dir))) && CanPlaceBlock(map, block, dir, point.opAdd(MoveDir(dir)).opAdd(MoveDir(dir))))
			{
				TGprint("Switch Block Type");
				if(blocks::CURR_BLOCKS != "OpenTechRoadBlocks" && blocks::CURR_BLOCKS != "OpenDirtRoadBlocks" && blocks::CURR_BLOCKS != "OpenIceRoadBlocks" && blocks::CURR_BLOCKS != "OpenGrassRoadBlocks" && blocks::CURR_BLOCKS != "PlatformTechBlocks" && blocks::CURR_BLOCKS != "PlatformDirtBlocks" && blocks::CURR_BLOCKS != "PlatformIceBlocks" && blocks::CURR_BLOCKS != "PlatformGrassBlocks" && blocks::CURR_BLOCKS != "PlasticBlocks")
				{
					dir = TurnDirLeft(dir);
					dir = TurnDirLeft(dir);
				}
				wasBlockTypeSwitchedLocal = true;
			}
			else 
			{
				techConnect = false;
				block = blocks::RD_STRAIGHT;
			}
		}
		else if(block == blocks::RD_BOOSTER1 || block == blocks::RD_BOOSTER2)
		{
			if (turn > 1)
			{
				dir = TurnDirLeft(dir);
				dir = TurnDirLeft(dir);
			}
		}
		//--
		
		// Transition logic: if prev block is non-flat and we're placing different category, use transition block
		string prevBlockName = "";
		auto prevBlock = map.GetBlock(prevPoint);
		if (prevBlock !is null) prevBlockName = tostring(prevBlock.BlockModel.IdName);
		if (prevBlockName.Length > 0)
		{
			string fromCat = transitions::GetCategoryFromBlockName(prevBlockName);
			string toCat = transitions::GetCategoryFromBlockName(block);
			if (transitions::NeedsTransitionViaFlat(fromCat, toCat))
			{
				array<string>@ candidates = transitions::GetTransitionBlockCandidates(prevBlockName, block);
				if (candidates.Length > 0)
					block = blocks::PickFromPool(candidates, block);
			}
		}
		
		//placing block
		if(CanPlaceBlock(map, block, dir, point))
		{
			PlaceBlock(map, block, dir, point);
			blockPlaced = true;
		}
		//--	

		if(blockPlaced)
		{
			//special block check after
			if(block == blocks::RD_END)
			{
				dir = dirCopy;
				point = point.opAdd(MoveDir(dir));
				if(MathRand(1,3) == 2)
				{
					if (CanPlaceBlock(map, block, dir, point.opAdd(MoveDir(dir))))
					{
						point = point.opAdd(MoveDir(dir));
					}
				}
				PlaceBlock(map, block, dir, point);
			}
			else if(block == blocks::RD_TURN1)
			{
				if(turn == 2)
				{
					dir = dirCopy;
					dir = TurnDirLeft(dir);
				}
			}
			else if(block == blocks::RD_TURN2)
			{
				if (turn == 1)
				{
					point = pointCopy.opAdd(MoveDir(dirCopy));
					dir = TurnDirRight(dirCopy);
					point = point.opAdd(MoveDir(dir));
				}
				else
				{
					point = pointCopy.opAdd(MoveDir(dirCopy));
					dir = TurnDirLeft(dirCopy);
					point = point.opAdd(MoveDir(dir));
				}
			}
			else if(block == blocks::RD_UP1 || block == blocks::RD_UP2)
			{
				if(turn == 2 && point.y >= 12)
				{
					dir = dirCopy;
				}
				else
				{
					if(block == blocks::RD_UP1)
					{
						point = point.opAdd(int3(0,1,0));
					}
					else
					{
						point = point.opAdd(int3(0,2,0));
					}
				}
			}
			else if(block == blocks::RD_CONNECT || techConnect)
			{
				dir = dirCopy;
				RandomBlocks();				
				
				point = point.opAdd(MoveDir(dir));
				
				if(blocks::CURR_BLOCKS == "OpenTechRoadBlocks" || blocks::CURR_BLOCKS == "OpenDirtRoadBlocks" || blocks::CURR_BLOCKS == "OpenIceRoadBlocks" || blocks::CURR_BLOCKS == "OpenGrassRoadBlocks" || blocks::CURR_BLOCKS == "PlatformTechBlocks" || blocks::CURR_BLOCKS == "PlatformDirtBlocks" || blocks::CURR_BLOCKS == "PlatformIceBlocks" || blocks::CURR_BLOCKS == "PlatformGrassBlocks" || blocks::CURR_BLOCKS == "PlasticBlocks")
				{
					dir = TurnDirLeft(dir);
					dir = TurnDirLeft(dir);					
				}
				
				if (blocks::CURR_BLOCKS != "TechBlocks" && blocks::CURR_BLOCKS != "WaterBlocks")
				{	
					PlaceBlock(map, blocks::RD_CONNECT, dir, point);
				}
				else
				{
					PlaceBlock(map, blocks::RD_STRAIGHT, dir, point);
				}
				connectPoint = point;
				TGprint("placed connect point at " + tostring(connectPoint));
				
				if(blocks::CURR_BLOCKS == "OpenTechRoadBlocks" || blocks::CURR_BLOCKS == "OpenDirtRoadBlocks" || blocks::CURR_BLOCKS == "OpenIceRoadBlocks" || blocks::CURR_BLOCKS == "OpenGrassRoadBlocks" || blocks::CURR_BLOCKS == "PlatformTechBlocks" || blocks::CURR_BLOCKS == "PlatformDirtBlocks" || blocks::CURR_BLOCKS == "PlatformIceBlocks" || blocks::CURR_BLOCKS == "PlatformGrassBlocks" || blocks::CURR_BLOCKS == "PlasticBlocks")
				{
					dir = dirCopy;
				}
			}
			else if(block == blocks::RD_CP)
			{
				auto checkpoint = map.GetBlock(point);
				map.SetBlockSkin(checkpoint, BANNER_LINK);
			}
			else if(block == blocks::RD_BOOSTER1 || block == blocks::RD_BOOSTER2)
			{
				dir = dirCopy;
			}
			//--
			
			//set point to the next block
			point = point.opAdd(MoveDir(dir));
			//--
		}	
		
		//check for the next 2 blocks
		if (!blockPlaced || !CanPlaceBlock(map, blocks::RD_STRAIGHT, dir, point) || !CanPlaceBlock(map, blocks::RD_STRAIGHT, dir, point.opAdd(MoveDir(dir))))
		{
			// Try escape: place platform one level below, left or right (no walls so road can continue below)
			bool escaped = false;
			int3 posBelowLeft = point.opAdd(int3(0, -1, 0)).opAdd(MoveDir(TurnDirLeft(dir)));
			int3 posBelowRight = point.opAdd(int3(0, -1, 0)).opAdd(MoveDir(TurnDirRight(dir)));
			if (CanPlaceBlock(map, blocks::PLATFORM_DROP, dir, posBelowLeft) && CanPlaceBlock(map, blocks::RD_STRAIGHT, dir, posBelowLeft.opAdd(MoveDir(dir))) && CanPlaceBlock(map, blocks::RD_STRAIGHT, dir, posBelowLeft.opAdd(MoveDir(dir)).opAdd(MoveDir(dir))))
			{
				PlaceBlock(map, blocks::PLATFORM_DROP, dir, posBelowLeft);
				point = posBelowLeft.opAdd(MoveDir(dir));
				prevPrevPoint = prevPoint;  // block before the platform
				prevPoint = posBelowLeft;
				escaped = true;
				TGprint("Dead end escape: platform below-left at " + tostring(posBelowLeft));
			}
			else if (CanPlaceBlock(map, blocks::PLATFORM_DROP, dir, posBelowRight) && CanPlaceBlock(map, blocks::RD_STRAIGHT, dir, posBelowRight.opAdd(MoveDir(dir))) && CanPlaceBlock(map, blocks::RD_STRAIGHT, dir, posBelowRight.opAdd(MoveDir(dir)).opAdd(MoveDir(dir))))
			{
				PlaceBlock(map, blocks::PLATFORM_DROP, dir, posBelowRight);
				point = posBelowRight.opAdd(MoveDir(dir));
				prevPrevPoint = prevPoint;  // block before the platform
				prevPoint = posBelowRight;
				escaped = true;
				TGprint("Dead end escape: platform below-right at " + tostring(posBelowRight));
			}
			if (escaped)
			{
				prevDir = dir;
				if (blocks::extendedSlopes) {
					hist_placed.InsertLast(prevPoint);
					hist_nextPoint.InsertLast(point);
					hist_nextDir.InsertLast(DirToInt(dir));
					hist_block.InsertLast(blocks::PLATFORM_DROP);
					if (hist_placed.Length > 20) {
						hist_placed.RemoveAt(0);
						hist_nextPoint.RemoveAt(0);
						hist_nextDir.RemoveAt(0);
						hist_block.RemoveAt(0);
					}
				}
				blockCantBePlacedCount = 0;
				continue;
			}

			TGprint(block + " block cannot be placed at " + tostring(point) +", canceling previous one");
			map.RemoveBlock(prevPoint);

			int rollbackCount = 1;
			if (blocks::extendedSlopes && hist_placed.Length > 0 && IsSlopeBlock(hist_block[hist_placed.Length - 1]))
			{
				// count consecutive slope blocks at end of history (including the one we just removed)
				uint L = 1;
				while (L < hist_placed.Length && IsSlopeBlock(hist_block[hist_placed.Length - 1 - int(L)]))
					L++;
				L = Math::Min(L, blockIndex);
				if (L > 1)
				{
					TGprint("Rolling back slope segment: " + tostring(L) + " blocks");
					uint restoreIdx = hist_placed.Length - L;
					int3 restoreNextPoint = hist_nextPoint[restoreIdx];
					int restoreNextDir = hist_nextDir[restoreIdx];
					int3 restorePrevPoint = hist_placed[restoreIdx];
					// remove L-1 more blocks from map (we already removed the last one at prevPoint)
					for (uint k = 1; k < L; k++)
					{
						int3 removeAt = hist_placed[hist_placed.Length - 1 - int(k)];
						while (!map.IsEditorReadyForRequest) { yield(); }
						map.RemoveBlock(removeAt);
					}
					// check if we rolled back over a connect block
					for (uint k = 0; k < L && k < hist_block.Length; k++)
					{
						if (hist_block[hist_block.Length - 1 - int(k)] == blocks::RD_CONNECT)
						{
							while (!map.IsEditorReadyForRequest) { yield(); }
							map.RemoveBlock(connectPoint);
							wasBlockTypeSwitched = false;
							blocks::SetBlockType(prevBlockType);
							break;
						}
					}
					hist_placed.RemoveRange(restoreIdx, L);
					hist_nextPoint.RemoveRange(restoreIdx, L);
					hist_nextDir.RemoveRange(restoreIdx, L);
					hist_block.RemoveRange(restoreIdx, L);
					point = restoreNextPoint;
					dir = IntToDir(restoreNextDir);
					prevPoint = restorePrevPoint;
					prevDir = dir;
					prevPrevPoint = (restoreIdx > 0) ? hist_placed[restoreIdx - 1] : prevPoint;
					prevPrevDir = (restoreIdx > 0) ? IntToDir(hist_nextDir[restoreIdx - 1]) : prevDir;
					rollbackCount = int(L);
				}
			}

			if (rollbackCount == 1)
			{
				if(st_useCpBlocks && block == blocks::RD_CP)
				{
					blocksPlacedAfterCP = blocksPlacedAfterCP-2;
				}
				if(wasBlockTypeSwitched)
				{
					TGprint("removing connect point from " + tostring(connectPoint));
					map.RemoveBlock(connectPoint);
					prevDir = prevPrevDir;
					prevPoint = prevPrevPoint;
					wasBlockTypeSwitchedLocal = false;
				}
				blocks::SetBlockType(prevBlockType);
				point = prevPoint;
				dir = prevDir;
			}
			
			blockIndex -= rollbackCount;
			blockCantBePlacedCount++;
			continue;
		}
		//--
		
		if(st_useCpBlocks && block == blocks::RD_CP)
		{
			blocksPlacedAfterCP = 0;
		}
		
		wasBlockTypeSwitched = wasBlockTypeSwitchedLocal;
		
		// placement history for extended-slopes multi-block rollback
		if (blocks::extendedSlopes) {
			hist_placed.InsertLast(prevPoint);
			hist_nextPoint.InsertLast(point);
			hist_nextDir.InsertLast(DirToInt(dir));
			hist_block.InsertLast(block);
			if (hist_placed.Length > 20) {
				hist_placed.RemoveAt(0);
				hist_nextPoint.RemoveAt(0);
				hist_nextDir.RemoveAt(0);
				hist_block.RemoveAt(0);
			}
		}
		
		TGprint("Placed " + block + " block, at " + tostring(prevPoint));
		prevDir = dir;
		prevPrevDir = dir;
		prevPrevPoint = prevPoint;
		prevPoint = point;
		prevBlockType = blockType;
		blockCantBePlacedCount = 0;
	}
	
	//finish block
	bool finishPlaced = true;
	if (!PlaceBlock(map, blocks::RD_FINISH, dir, point))
	{	
		finishPlaced = false;
		for(int blockTypeIndex = 1; blockTypeIndex <= 4; blockTypeIndex++)
		{
			blocks::SetBlockType(blockTypeIndex);
			if (PlaceBlock(map, blocks::RD_FINISH, dir, point))
			{
				finishPlaced = true;
				break;
			}
		}
	}	
	if(!finishPlaced) 
	{ 
		warn("cant place finish");
		return; 
	}
	map.SetBlockSkin(GetBlockAt(map, point), BANNER_LINK);
	TGprint("Created FINISH block at " + tostring(point));
	//--
	
	print("\\$0f0\\$sTrack generated in "+ tostring(Time::get_Now() - before) + " milliseconds!");
}

void Preload()
{
	uint64 before = Time::get_Now();
	auto app = cast<CTrackMania>(GetApp());
	if (app is null) {
		return;
	}
		
	auto editor = cast<CGameCtnEditorFree>(app.Editor);
	if (editor is null) {
		UI::ShowNotification("editor is not opened!");
		warn("editor is not opened!");
		return;
	}
	
	auto map = cast<CGameEditorPluginMap>(editor.PluginMapType);
	if (map is null) {
		return;
	}
	
	map.PreloadAllBlocks();
	preloaded = true;
	
	print("\\$080\\$sAll block preloaded in "+ tostring(Time::get_Now() - before) + " milliseconds!");
}

void Undo()
{
	auto app = cast<CTrackMania>(GetApp());
	if (app is null) {
		return;
	}
		
	auto editor = cast<CGameCtnEditorFree>(app.Editor);
	if (editor is null) {
		UI::ShowNotification("editor is not opened!");
		warn("editor is not opened!");
		return;
	}
	
	auto map = cast<CGameEditorPluginMap>(editor.PluginMapType);
	if (map is null) {
		return;
	}
	
	map.RemoveAllBlocks();
}

bool IsSlopeBlock(const string &in blockName)
{
	return (blockName == blocks::RD_UP1 || blockName == blocks::RD_UP2);
}

// Classify block by IdName prefix (Nadeo naming). Returns "Scenery", "Track", or "Other".
string BlockKindFromIdName(const string &in idName)
{
	if (idName.Length < 2) return "Other";
	// Scenery / deco (non-drivable): Deco, Obstacle, Structure, StageTechnics, Flag, Canopy, Stand, WaterWall, GateSpecial, TechnicsScreen
	if (idName.SubStr(0, 4) == "Deco") return "Scenery";
	if (idName.SubStr(0, 8) == "Obstacle") return "Scenery";
	if (idName.SubStr(0, 9) == "Structure") return "Scenery";
	if (idName.SubStr(0, 13) == "StageTechnics") return "Scenery";
	if (idName.SubStr(0, 4) == "Flag") return "Scenery";
	if (idName.SubStr(0, 6) == "Canopy") return "Scenery";
	if (idName.SubStr(0, 5) == "Stand") return "Scenery";
	if (idName.SubStr(0, 9) == "WaterWall") return "Scenery";
	if (idName.SubStr(0, 11) == "GateSpecial") return "Scenery";
	if (idName.SubStr(0, 14) == "TechnicsScreen") return "Scenery";
	// Track / road / platform (drivable or track structure)
	if (idName.SubStr(0, 4) == "Road") return "Track";
	if (idName.SubStr(0, 9) == "TrackWall") return "Track";
	if (idName.SubStr(0, 8) == "Platform") return "Track";
	if (idName.SubStr(0, 4) == "Open") return "Track";
	if (idName.SubStr(0, 5) == "Rally") return "Track";
	if (idName.SubStr(0, 4) == "Snow") return "Track";
	return "Other";
}

void DumpBlockNames()
{
	auto app = cast<CTrackMania>(GetApp());
	if (app is null) {
		return;
	}

	auto editor = cast<CGameCtnEditorFree>(app.Editor);
	if (editor is null) {
		UI::ShowNotification("Editor is not opened!");
		warn("Editor is not opened!");
		return;
	}

	auto map = cast<CGameEditorPluginMap>(editor.PluginMapType);
	if (map is null) {
		return;
	}

	uint count = map.BlockModels.Length;
	print("\\$0f0\\$s--- Block names dump (" + tostring(count) + " block models) ---");
	print("\\$0f0\\$sFormat: IdName | Kind (Scenery / Track / Other). Kind is guessed from name prefix; API does not expose default vs custom.");
	for (uint i = 0; i < count; i++) {
		auto model = map.BlockModels[i];
		if (model !is null) {
			string idName = tostring(model.IdName);
			string kind = BlockKindFromIdName(idName);
			print(idName + " | " + kind);
		}
	}
	print("\\$0f0\\$s--- End block names dump ---");
	UI::ShowNotification("Dumped " + tostring(count) + " block names (with kind) to the OpenPlanet log.");
}

void FindSuitableBlocksForSlope()
{
	auto app = cast<CTrackMania>(GetApp());
	if (app is null) {
		return;
	}

	auto editor = cast<CGameCtnEditorFree>(app.Editor);
	if (editor is null) {
		UI::ShowNotification("Editor is not opened!");
		warn("Editor is not opened!");
		return;
	}

	auto map = cast<CGameEditorPluginMap>(editor.PluginMapType);
	if (map is null) {
		return;
	}

	// Get first slope block from pool
	string testBlock = blocks::GetBlockFromPool("Slope");
	if (testBlock == "" || testBlock == blocks::RD_STRAIGHT) {
		TGprint("\\$f00No slope blocks available in current pool!");
		UI::ShowNotification("No slope blocks available!");
		return;
	}

	TGprint("\\$0f0\\$s=== Finding suitable blocks for: " + testBlock + " ===");
	
	// Place test block at a safe location
	int3 testPoint = int3(MAX_X / 2, 9, MAX_Z / 2);
	auto testDir = DIR_NORTH;
	
	// Clear area first
	while (!map.IsEditorReadyForRequest) { yield(); }
	map.RemoveBlock(testPoint);
	while (!map.IsEditorReadyForRequest) { yield(); }
	map.RemoveBlock(testPoint.opAdd(MoveDir(testDir)));
	while (!map.IsEditorReadyForRequest) { yield(); }
	map.RemoveBlock(testPoint.opAdd(MoveDir(testDir)).opAdd(MoveDir(testDir)));
	
	// Place the test block
	if (!PlaceBlock(map, testBlock, testDir, testPoint)) {
		TGprint("\\$f00Failed to place test block: " + testBlock);
		UI::ShowNotification("Failed to place test block!");
		return;
	}
	
	// Get the placed block to check its exit
	auto placedBlock = map.GetBlock(testPoint);
	if (placedBlock is null) {
		TGprint("\\$f00Failed to get placed block!");
		return;
	}
	
	// Calculate next position (after slope: move forward, and up by 1 for Slope, 2 for Slope2)
	int3 nextPoint = testPoint.opAdd(MoveDir(testDir));
	// Detect slope type from block name: "Slope2" = goes up 2, "Slope" (but not "Slope2") = goes up 1
	// Check Slope2 first since it contains "Slope"
	if (testBlock.IndexOf("Slope2") >= 0) {
		nextPoint = nextPoint.opAdd(int3(0, 2, 0));
	} else if (testBlock.IndexOf("Slope") >= 0 || testBlock.IndexOf("SlopeBase") >= 0) {
		nextPoint = nextPoint.opAdd(int3(0, 1, 0));
	}
	auto nextDir = testDir; // Direction stays same for slopes (unless turn)
	
	TGprint("Test block placed at " + tostring(testPoint) + ", testing connectivity at " + tostring(nextPoint) + " direction " + tostring(nextDir));
	
	// Test all blocks
	array<string> suitableBlocks;
	uint totalTested = 0;
	uint trackBlocks = 0;
	
	for (uint i = 0; i < map.BlockModels.Length; i++) {
		auto model = map.BlockModels[i];
		if (model is null) continue;
		
		string blockName = tostring(model.IdName);
		string kind = BlockKindFromIdName(blockName);
		
		// Only test Track blocks (skip Scenery and Other)
		if (kind != "Track") continue;
		
		trackBlocks++;
		
		// Test if this block can be placed after the test block
		if (CanPlaceBlock(map, blockName, nextDir, nextPoint)) {
			suitableBlocks.InsertLast(blockName);
		}
		
		totalTested++;
		if (totalTested % 100 == 0) {
			TGprint("Tested " + tostring(totalTested) + " blocks...");
		}
	}
	
	// Log results
	TGprint("\\$0f0\\$s=== Results ===");
	TGprint("Test block: " + testBlock);
	TGprint("Total track blocks tested: " + tostring(trackBlocks));
	TGprint("Suitable blocks found: " + tostring(suitableBlocks.Length));
	TGprint("\\$0f0\\$s--- Suitable blocks ---");
	
	for (uint i = 0; i < suitableBlocks.Length; i++) {
		print(suitableBlocks[i]);
	}
	
	TGprint("\\$0f0\\$s=== End results ===");
	
	// Clean up test block
	while (!map.IsEditorReadyForRequest) { yield(); }
	map.RemoveBlock(testPoint);
	
	UI::ShowNotification("Found " + tostring(suitableBlocks.Length) + " suitable blocks (see log)");
}

// Return block handle at position from RootMap.Blocks (avoids map.GetBlock return type issues).
CGameCtnBlock@ GetBlockAt(CGameEditorPluginMap@ map, int3 pos)
{
	auto allBlocks = GetApp().RootMap.Blocks;
	CGameCtnBlock@ fallback = null;
	for (uint i = 0; i < allBlocks.Length; i++) {
		if (int(allBlocks[i].CoordX) == pos.x && int(allBlocks[i].CoordY) == pos.y && int(allBlocks[i].CoordZ) == pos.z) {
			// Skip auto-placed infrastructure blocks (pillars, deco bases) so that
			// the underlying track block is returned instead.
			string n = allBlocks[i].BlockModel.IdName;
			if (n == "TrackWallStraightPillar" || n == "DecoWallBasePillar") {
				if (fallback is null) @fallback = allBlocks[i];
				continue;
			}
			return allBlocks[i];
		}
	}
	return fallback;
}

// Get cardinal direction from a map block (RootMap.Blocks[i]). Tries BlockDir then Dir (0=North,1=East,2=South,3=West).
CGameEditorPluginMap::ECardinalDirections GetBlockDirection(CGameCtnBlock@ block)
{
	if (block is null) return DIR_NORTH;
	// Try common API names for block direction (Nadeo/OpenPlanet)
	try {
		int d = block.BlockDir;
		return IntToDir(d & 3);
	} catch {}
	try {
		int d = block.Dir;
		return IntToDir(d & 3);
	} catch {}
	return DIR_NORTH;
}

// Compute next position after a block (forward + optional slope height). Returns (nextPos, nextDir).
void GetNextPositionAfterBlock(CGameEditorPluginMap@ map, int3 pos, CGameEditorPluginMap::ECardinalDirections dir, const string &in blockName, int3 &out nextPos, CGameEditorPluginMap::ECardinalDirections &out nextDir)
{
	nextPos = pos.opAdd(MoveDir(dir));
	nextDir = dir;
	// Slope: exit is one cell forward and up
	if (blockName.IndexOf("Slope2") >= 0) {
		nextPos = nextPos.opAdd(int3(0, 2, 0));
	} else if (blockName.IndexOf("Slope") >= 0 || blockName.IndexOf("SlopeBase") >= 0) {
		nextPos = nextPos.opAdd(int3(0, 1, 0));
	}
	// Turns would change nextDir; for "straight line" we keep dir. Add turn logic here if needed.
}

// Find Start block on map (first with "Start" in name, excluding Slope2Start/LoopStart). Sets startPos and returns block.
CGameCtnBlock@ FindStartBlock(CGameEditorPluginMap@ map, int3 &out startPos)
{
	auto blocks = GetApp().RootMap.Blocks;
	for (uint i = 0; i < blocks.Length; i++) {
		string name = blocks[i].BlockModel.IdName;
		if (name.IndexOf("Start") >= 0 && name.IndexOf("Slope2Start") < 0 && name.IndexOf("LoopStart") < 0) {
			startPos = int3(blocks[i].CoordX, blocks[i].CoordY, blocks[i].CoordZ);
			return blocks[i];
		}
	}
	return null;
}

// Check if block name contains keywords indicating non-flat geometry
bool HasNonFlatKeywords(const string &in blockName)
{
	string lower = blockName.ToLower();
	return (lower.IndexOf("slope") >= 0 || 
	        lower.IndexOf("tilt") >= 0 || 
	        lower.IndexOf("transition") >= 0 || 
	        lower.IndexOf("up") >= 0 || 
	        lower.IndexOf("down") >= 0 || 
	        lower.IndexOf("ramp") >= 0);
}

// Generate flat blocks for a Road subcategory: find placed Start, test blocks with prefix, write to flat_blocks_<subcategory>.txt
// subcategory: "RoadTech", "RoadDirt", "RoadBump", "RoadIce", "RoadWater"
void GenerateFlatBlocksBySubcategory(const string &in subcategory)
{
	auto app = cast<CTrackMania>(GetApp());
	if (app is null) {
		UI::ShowNotification("App not available!");
		return;
	}
	auto editor = cast<CGameCtnEditorFree>(app.Editor);
	if (editor is null) {
		UI::ShowNotification("Editor is not opened!");
		return;
	}
	auto map = cast<CGameEditorPluginMap>(editor.PluginMapType);
	if (map is null) {
		UI::ShowNotification("Map not available!");
		return;
	}

	int3 startPos;
	CGameCtnBlock@ startBlock = FindStartBlock(map, startPos);
	if (startBlock is null) {
		TGprint("\\$f00No Start block found! Place a Start block (e.g. " + subcategory + "Start) first.");
		UI::ShowNotification("Place a Start block first!");
		return;
	}

	string startBlockName = tostring(startBlock.BlockModel.IdName);
	TGprint("\\$0f0\\$s=== Flat blocks: " + subcategory + " ===");
	TGprint("Using block: " + startBlockName + " at " + tostring(startPos));

	array<string> connectedBlocks;
	uint tested = 0;
	string prefix = subcategory;  // e.g. "RoadTech"
	for (uint i = 0; i < map.BlockModels.Length; i++) {
		auto model = map.BlockModels[i];
		if (model is null) continue;
		string blockName = tostring(model.IdName);
		if (BlockKindFromIdName(blockName) != "Track") continue;
		if (blockName.IndexOf(prefix) < 0) continue;  // only blocks with this prefix

		tested++;
		auto result = ConnectBlocks(map, startPos, blockName);
		if (result !is null) {
			connectedBlocks.InsertLast(blockName);
		}
		if (tested % 50 == 0 && tested > 0) {
			TGprint("Tested " + tostring(tested) + " " + subcategory + " blocks...");
		}
	}

	TGprint(subcategory + " blocks that connect: " + tostring(connectedBlocks.Length));

	string flatFile = "d:\\REPO\\tmmaps\\block_data\\flat_blocks_" + subcategory.ToLower() + ".txt";
	try {
		IO::File file(flatFile, IO::FileMode::Write);
		for (uint i = 0; i < connectedBlocks.Length; i++) {
			file.Write(connectedBlocks[i] + "\n");
		}
		file.Close();
		TGprint("\\$0f0\\$sSaved: " + flatFile);
		UI::ShowNotification("Flat blocks " + subcategory + ": " + tostring(connectedBlocks.Length));
	} catch {
		TGprint("\\$f00Failed to write: " + flatFile);
		UI::ShowNotification("Failed to write flat blocks file!");
	}
}

// Generate flat blocks list: find placed block, test which blocks connect, write to flat_blocks_<vista>.txt
// append: true = append to file, false = overwrite (Create)
void GenerateFlatBlocks(const string &in vistaName, bool append)
{
	auto app = cast<CTrackMania>(GetApp());
	if (app is null) {
		UI::ShowNotification("App not available!");
		return;
	}
	auto editor = cast<CGameCtnEditorFree>(app.Editor);
	if (editor is null) {
		UI::ShowNotification("Editor is not opened!");
		return;
	}
	auto map = cast<CGameEditorPluginMap>(editor.PluginMapType);
	if (map is null) {
		UI::ShowNotification("Map not available!");
		return;
	}

	int3 startPos;
	CGameCtnBlock@ startBlock = FindStartBlock(map, startPos);
	if (startBlock is null) {
		TGprint("\\$f00No Start block found! Place a Start block first.");
		UI::ShowNotification("Place a Start block first!");
		return;
	}

	string startBlockName = tostring(startBlock.BlockModel.IdName);
	TGprint("\\$0f0\\$s=== Flat blocks: " + (append ? "Append" : "Create") + " for " + vistaName + " ===");
	TGprint("Using block: " + startBlockName + " at " + tostring(startPos));

	array<string> connectedBlocks;
	uint tested = 0;
	for (uint i = 0; i < map.BlockModels.Length; i++) {
		auto model = map.BlockModels[i];
		if (model is null) continue;
		string blockName = tostring(model.IdName);
		if (BlockKindFromIdName(blockName) != "Track") continue;

		tested++;
		auto result = ConnectBlocks(map, startPos, blockName);
		if (result !is null) {
			connectedBlocks.InsertLast(blockName);
		}
		if (tested % 200 == 0) {
			TGprint("Tested " + tostring(tested) + " blocks...");
		}
	}

	TGprint("Blocks that connect: " + tostring(connectedBlocks.Length));

	string vistaLower = vistaName.ToLower();
	string flatFile = "d:\\REPO\\tmmaps\\block_data\\flat_blocks_" + vistaLower + ".txt";

	try {
		IO::File file(flatFile, append ? IO::FileMode::Append : IO::FileMode::Write);
		for (uint i = 0; i < connectedBlocks.Length; i++) {
			file.Write(connectedBlocks[i] + "\n");
		}
		file.Close();
		TGprint("\\$0f0\\$sSaved: " + flatFile + (append ? " (appended)" : " (overwrite)"));
		UI::ShowNotification((append ? "Appended" : "Created") + " flat blocks for " + vistaName + ": " + tostring(connectedBlocks.Length));
	} catch {
		TGprint("\\$f00Failed to write: " + flatFile);
		UI::ShowNotification("Failed to write flat blocks file!");
	}
}

// Phase 1: Identify blocks that need connectivity data
// Tests all track blocks against a Start block and categorizes them
// vistaName: "Stadium", "BlueBay", "GreenCoast", "RedIsland", "WhiteShore" - used for filenames and filtering
void GenerateConnectivityPhase1(const string &in vistaName)
{
	auto app = cast<CTrackMania>(GetApp());
	if (app is null) {
		UI::ShowNotification("App not available!");
		return;
	}

	auto editor = cast<CGameCtnEditorFree>(app.Editor);
	if (editor is null) {
		UI::ShowNotification("Editor is not opened!");
		return;
	}

	auto map = cast<CGameEditorPluginMap>(editor.PluginMapType);
	if (map is null) {
		UI::ShowNotification("Map not available!");
		return;
	}

	TGprint("\\$0f0\\$s=== Phase 1: Identifying blocks that need connectivity data ===");

	// Find or place Start block
	int3 startPos;
	CGameCtnBlock@ startBlock = FindStartBlock(map, startPos);
	if (startBlock is null) {
		// Place a Start block if none exists
		TGprint("No Start block found. Placing one...");
		startPos = int3(0, 0, 0);
		if (!PlaceBlock(map, blocks::RD_START, DIR_NORTH, startPos)) {
			UI::ShowNotification("Failed to place Start block!");
			return;
		}
		// Verify block was placed by checking at position (don't reassign startBlock)
		auto placedBlock = map.GetBlock(startPos);
		if (placedBlock is null) {
			UI::ShowNotification("Failed to find Start block after placement!");
			return;
		}
		string startBlockName = tostring(placedBlock.BlockModel.IdName);
		TGprint("Using Start block: " + startBlockName + " at " + tostring(startPos));
	} else {
		string startBlockName = tostring(startBlock.BlockModel.IdName);
		TGprint("Using Start block: " + startBlockName + " at " + tostring(startPos));
	}

	// Arrays to collect results
	array<string> blocksNeedingConnectivity;  // Blocks that need connectivity data
	array<string> blocksConnectingToStart;     // Blocks that can connect to Start (for verification)

	// Optional: Load Stadium's block list to filter out common blocks (only test Vista-specific)
	dictionary blocksInStadium;
	bool filterToVistaSpecific = (vistaName != "Stadium");
	if (filterToVistaSpecific) {
		string stadiumFile = IO::FromUserGameFolder("flat_blocks_stadium.txt");
		try {
			IO::File stadiumFileHandle(stadiumFile, IO::FileMode::Read);
			string line;
			while (!stadiumFileHandle.EOF()) {
				line = stadiumFileHandle.ReadLine();
				line = line.Trim();
				if (line.Length > 0) {
					blocksInStadium[line] = true;
				}
			}
			stadiumFileHandle.Close();
			TGprint("Loaded Stadium block list: " + tostring(blocksInStadium.GetSize()) + " blocks (will skip these)");
		} catch {
			TGprint("\\$ff0Stadium file not found or error reading. Testing all blocks in this Vista. Run Phase 1 for Stadium first to enable filtering.");
			filterToVistaSpecific = false;
		}
	}

	// Test all track blocks
	uint totalTrackBlocks = 0;
	uint tested = 0;
	uint skippedCommon = 0;
	for (uint i = 0; i < map.BlockModels.Length; i++) {
		auto model = map.BlockModels[i];
		if (model is null) continue;
		
		string blockName = tostring(model.IdName);
		if (BlockKindFromIdName(blockName) != "Track") continue;
		
		totalTrackBlocks++;
		
		// Skip if filtering and this block is in Stadium
		if (filterToVistaSpecific && blocksInStadium.Exists(blockName)) {
			skippedCommon++;
			continue;
		}
		
		tested++;
		
		// Test if this block can connect to Start
		auto result = ConnectBlocks(map, startPos, blockName);
		bool canConnect = (result !is null);
		
		if (canConnect) {
			blocksConnectingToStart.InsertLast(blockName);
			
			// Check if it has non-flat keywords
			if (HasNonFlatKeywords(blockName)) {
				blocksNeedingConnectivity.InsertLast(blockName);
			}
		} else {
			// Cannot connect to Start → needs special connection → needs connectivity data
			blocksNeedingConnectivity.InsertLast(blockName);
		}
		
		if (tested % 100 == 0) {
			TGprint("Tested " + tostring(tested) + " track blocks...");
		}
	}

	TGprint("\\$0f0\\$s=== Phase 1 Results ===");
	TGprint("Vista: " + vistaName);
	TGprint("Total track blocks available: " + tostring(totalTrackBlocks));
	if (filterToVistaSpecific && skippedCommon > 0) {
		TGprint("Skipped common blocks (in Stadium): " + tostring(skippedCommon));
	}
	TGprint("Blocks tested: " + tostring(tested));
	TGprint("Blocks that can connect to Start: " + tostring(blocksConnectingToStart.Length));
	TGprint("Blocks needing connectivity data: " + tostring(blocksNeedingConnectivity.Length));

	// Write files to OpenPlanet user folder (Vista-specific filenames)
	string vistaLower = vistaName.ToLower();
	string blocksToTestFile = IO::FromUserGameFolder("blocks_to_test_" + vistaLower + ".txt");
	string blocksConnectingFile = IO::FromUserGameFolder("flat_blocks_" + vistaLower + ".txt");

	// Write blocks_to_test.txt (one block name per line)
	try {
		IO::File file1(blocksToTestFile, IO::FileMode::Write);
		for (uint i = 0; i < blocksNeedingConnectivity.Length; i++) {
			file1.Write(blocksNeedingConnectivity[i] + "\n");
		}
		file1.Close();
		TGprint("\\$0f0\\$sSaved: " + blocksToTestFile);
	} catch {
		TGprint("\\$f00Failed to write: " + blocksToTestFile);
	}

	// Write flat_blocks.txt (one block name per line, blocks that can connect to Start)
	try {
		IO::File file2(blocksConnectingFile, IO::FileMode::Write);
		for (uint i = 0; i < blocksConnectingToStart.Length; i++) {
			file2.Write(blocksConnectingToStart[i] + "\n");
		}
		file2.Close();
		TGprint("\\$0f0\\$sSaved: " + blocksConnectingFile);
	} catch {
		TGprint("\\$f00Failed to write: " + blocksConnectingFile);
	}

	TGprint("\\$0f0\\$s=== Phase 1 Complete ===");
	TGprint("Files saved to OpenPlanet user folder:");
	TGprint("  - blocks_to_test_" + vistaLower + ".txt (" + tostring(blocksNeedingConnectivity.Length) + " blocks)");
	TGprint("  - flat_blocks_" + vistaLower + ".txt (" + tostring(blocksConnectingToStart.Length) + " blocks)");
	TGprint("\\$888Note: Run Phase 1 for each Vista (Stadium, BlueBay, GreenCoast, RedIsland, WhiteShore).");
	TGprint("\\$888For non-Stadium Vistas, you can filter to Vista-specific blocks manually if needed.");
	
	UI::ShowNotification("Phase 1 complete for " + vistaName + "! Check log for file locations.");
}

// Place Transition blocks + overlap blocks (in both connectivity and flat_blocks) for visual inspection
void PlaceTransitionBlocks()
{
	auto app = cast<CTrackMania>(GetApp());
	if (app is null) {
		UI::ShowNotification("App not available!");
		return;
	}
	auto editor = cast<CGameCtnEditorFree>(app.Editor);
	if (editor is null) {
		UI::ShowNotification("Editor is not opened!");
		return;
	}
	auto map = cast<CGameEditorPluginMap>(editor.PluginMapType);
	if (map is null) {
		UI::ShowNotification("Map not available!");
		return;
	}

	LoadMapSize();
	map.RemoveAllBlocks();
	while (!map.IsEditorReadyForRequest) { yield(); }

	// Use FreeBlock mode so blocks can be placed anywhere
	auto prevPlaceMode = map.PlaceMode;
	map.PlaceMode = PLACE_MODE_FREEBLOCK;

	// 1) Transition blocks
	array<string> transitionBlocks;
	for (uint i = 0; i < map.BlockModels.Length; i++) {
		auto model = map.BlockModels[i];
		if (model is null) continue;
		string name = tostring(model.IdName);
		if (name.ToLower().IndexOf("transition") < 0) continue;
		if (BlockKindFromIdName(name) != "Track") continue;
		transitionBlocks.InsertLast(name);
	}

	// 2) Overlap: blocks in BOTH connectivity_stadium AND flat_blocks_stadium
	dictionary flatBlocks;
	string flatFile = transitions::GetBlockDataPath() + "flat_blocks_stadium.txt";
	try {
		IO::File f(flatFile, IO::FileMode::Read);
		string line;
		while (!f.EOF()) {
			line = f.ReadLine().Trim();
			if (line.Length > 0) flatBlocks[line] = true;
		}
		f.Close();
	} catch { TGprint("\\$ff0Could not read flat_blocks_stadium.txt"); }

	array<string> overlapBlocks;
	string connectivityFile = transitions::GetBlockDataPath() + "connectivity_stadium.txt";
	try {
		IO::File f(connectivityFile, IO::FileMode::Read);
		string line;
		while (!f.EOF()) {
			line = f.ReadLine().Trim();
			if (line.Length > 0 && line.IndexOf("|") >= 0) {
				string blockName = line.SubStr(0, line.IndexOf("|"));
				if (flatBlocks.Exists(blockName)) {
					overlapBlocks.InsertLast(blockName);
				}
			}
		}
		f.Close();
	} catch { TGprint("\\$ff0Could not read connectivity_stadium.txt"); }

	// Combine: transition first, then overlap (avoid duplicates)
	dictionary placed;
	array<string> toPlace;
	for (uint i = 0; i < transitionBlocks.Length; i++) {
		if (!placed.Exists(transitionBlocks[i])) {
			toPlace.InsertLast(transitionBlocks[i]);
			placed[transitionBlocks[i]] = true;
		}
	}
	for (uint i = 0; i < overlapBlocks.Length; i++) {
		if (!placed.Exists(overlapBlocks[i])) {
			toPlace.InsertLast(overlapBlocks[i]);
			placed[overlapBlocks[i]] = true;
		}
	}

	TGprint("\\$0f0\\$sPlacing " + tostring(transitionBlocks.Length) + " Transition + " + tostring(overlapBlocks.Length) + " overlap = " + tostring(toPlace.Length) + " blocks (FreeBlock mode)");

	int cols = 12;
	int spacing = 4;
	int baseX = MAX_X / 2 - (cols / 2) * spacing;
	int baseZ = 8;
	int baseY = 5;

	for (uint i = 0; i < toPlace.Length; i++) {
		int row = int(i) / cols;
		int col = int(i) % cols;
		int3 pos = int3(baseX + col * spacing, baseY + row * 3, baseZ + row * spacing);
		if (!PlaceBlock(map, toPlace[i], DIR_NORTH, pos)) {
			TGprint("\\$ff0Skip: " + toPlace[i]);
		}
		while (!map.IsEditorReadyForRequest) { yield(); }
	}

	map.PlaceMode = prevPlaceMode;
	TGprint("\\$0f0\\$sDone. Inspect blocks in editor.");
	UI::ShowNotification("Placed " + tostring(toPlace.Length) + " blocks (Transition + overlap). Inspect visually.");
}

// Phase 2 test: Check first block only (Stadium). Same as Phase 2 Stadium but only the first block in the file.
void GenerateConnectivityPhase2FirstBlock()
{
	GenerateConnectivityPhase2("Stadium", 1);  // limit to 1 block
}

// Phase 2: Generate connectivity data for blocks that need it
// For each block from Phase 1, tests which blocks can connect after it
// vistaName: "Stadium", "BlueBay", etc. - used for filenames
// maxBlocks: 0 = all blocks; >0 = only process first N blocks
void GenerateConnectivityPhase2(const string &in vistaName, uint maxBlocks = 0)
{
	auto app = cast<CTrackMania>(GetApp());
	if (app is null) {
		UI::ShowNotification("App not available!");
		return;
	}

	auto editor = cast<CGameCtnEditorFree>(app.Editor);
	if (editor is null) {
		UI::ShowNotification("Editor is not opened!");
		return;
	}

	auto map = cast<CGameEditorPluginMap>(editor.PluginMapType);
	if (map is null) {
		UI::ShowNotification("Map not available!");
		return;
	}

	TGprint("\\$0f0\\$s=== Phase 2: Generating connectivity data ===");
	TGprint("Vista: " + vistaName);

	// Load Phase 1 results: blocks_to_test_<vista>.txt from block_data folder
	string vistaLower = vistaName.ToLower();
	string blockDataPath = transitions::GetBlockDataPath() + "blocks_to_test_" + vistaLower + ".txt";
	array<string> blocksToTest;
	
	try {
		IO::File file(blockDataPath, IO::FileMode::Read);
		string line;
		while (!file.EOF()) {
			line = file.ReadLine();
			line = line.Trim();
			if (line.Length > 0) {
				blocksToTest.InsertLast(line);
			}
		}
		file.Close();
		TGprint("Loaded " + tostring(blocksToTest.Length) + " blocks to test from Phase 1.");
	} catch {
		TGprint("\\$f00Failed to read: " + blockDataPath);
		TGprint("\\$f00Make sure blocks_to_test_" + vistaLower + ".txt exists in block_data folder!");
		UI::ShowNotification("Phase 1 file not found! Check block_data folder.");
		return;
	}

	if (blocksToTest.Length == 0) {
		TGprint("\\$f00No blocks to test!");
		UI::ShowNotification("No blocks to test!");
		return;
	}

	// Limit to first N blocks if maxBlocks > 0
	if (maxBlocks > 0 && blocksToTest.Length > maxBlocks) {
		blocksToTest.RemoveRange(maxBlocks, blocksToTest.Length - maxBlocks);
		TGprint("Limited to first " + tostring(maxBlocks) + " block(s): " + blocksToTest[0]);
	}

	// Cross-Vista deduplication: Load all existing connectivity files from block_data to see which blocks were already tested
	dictionary alreadyTested;
	string[] vistaNames = {"stadium", "bluebay", "greencoast", "redisland", "whiteshore"};
	for (uint v = 0; v < vistaNames.Length; v++) {
		if (vistaNames[v] == vistaLower) continue; // Skip current Vista
		string existingFile = transitions::GetBlockDataPath() + "connectivity_" + vistaNames[v] + ".txt";
		try {
			IO::File existing(existingFile, IO::FileMode::Read);
			string line;
			while (!existing.EOF()) {
				line = existing.ReadLine();
				line = line.Trim();
				if (line.Length > 0 && line.IndexOf("|") >= 0) {
					// Format: BlockName|Follower1,Follower2,...
					string blockName = line.SubStr(0, line.IndexOf("|"));
					alreadyTested[blockName] = true;
				}
			}
			existing.Close();
		} catch {
			// File doesn't exist yet, skip
		}
	}
	TGprint("Found " + tostring(alreadyTested.GetSize()) + " blocks already tested in other Vistas (will skip).");

	// Match track generator setup: LoadMapSize, clear map, use same position logic as RandomPoint
	LoadMapSize();
	TGprint("\\$f80Clearing map (required for placement)...");
	map.RemoveAllBlocks();
	while (!map.IsEditorReadyForRequest) { yield(); }

	// Same position formula as track generator (RandomPoint center, no random offset)
	int3 testPos = int3(MAX_X / 2, int(Math::Floor(MAX_Y / 4)), MAX_Z / 2);
	TGprint("Using test position: " + tostring(testPos) + " (same as track generator)");

	// Results: parallel arrays for block names and their followers
	array<string> resultBlockNames;
	array<array<string>> resultFollowers;

	uint processed = 0;
	uint skipped = 0;
	uint failed = 0;

	for (uint i = 0; i < blocksToTest.Length; i++) {
		string blockName = blocksToTest[i];
		
		// Skip if already tested
		if (alreadyTested.Exists(blockName)) {
			skipped++;
			continue;
		}

		processed++;
		
		// Clear test position if there's already a block
		if (map.GetBlock(testPos) !is null) {
			map.RemoveBlock(testPos);
			while (!map.IsEditorReadyForRequest) { yield(); }
		}
		
		// Place block (same PlaceBlock as track generator)
		auto info = map.GetBlockModelFromName(blockName);
		if (info is null) {
			TGprint("\\$ff0Block not in map: " + blockName + " (skipping)");
			failed++;
			continue;
		}
		if (!PlaceBlock(map, blockName, DIR_NORTH, testPos)) {
			TGprint("\\$ff0Failed to place block: " + blockName + " (skipping)");
			failed++;
			continue;
		}

		// Test all track blocks against this block
		array<string> followers;
		for (uint j = 0; j < map.BlockModels.Length; j++) {
			auto model = map.BlockModels[j];
			if (model is null) continue;
			
			string candidateName = tostring(model.IdName);
			if (BlockKindFromIdName(candidateName) != "Track") continue;
			
			auto result = ConnectBlocks(map, testPos, candidateName);
			if (result !is null) {
				followers.InsertLast(candidateName);
			}
		}

		// Store results (only if we have followers)
		if (followers.Length > 0) {
			resultBlockNames.InsertLast(blockName);
			resultFollowers.InsertLast(followers);
		}

		// Remove test block
		map.RemoveBlock(testPos);
		while (!map.IsEditorReadyForRequest) { yield(); }

		if (processed % 500 == 0) {
			TGprint("Processed " + tostring(processed) + "/" + tostring(blocksToTest.Length) + " blocks...");
		}
	}

	TGprint("\\$0f0\\$s=== Phase 2 Results ===");
	TGprint("Vista: " + vistaName);
	TGprint("Blocks to test: " + tostring(blocksToTest.Length));
	TGprint("Skipped (already tested): " + tostring(skipped));
	TGprint("Failed to place: " + tostring(failed));
	TGprint("Processed: " + tostring(processed));
	TGprint("Connectivity data generated: " + tostring(resultBlockNames.Length) + " blocks");

	// Write connectivity data file to block_data folder (text format: BlockName|Follower1,Follower2,Follower3,...)
	string connectivityFile = "d:\\REPO\\tmmaps\\block_data\\connectivity_" + vistaLower + ".txt";
	try {
		IO::File outFile(connectivityFile, IO::FileMode::Write);
		for (uint i = 0; i < resultBlockNames.Length; i++) {
			string blockName = resultBlockNames[i];
			array<string>@ followers = resultFollowers[i];
			
			// Format: BlockName|Follower1,Follower2,Follower3,...
			string line = blockName + "|";
			for (uint f = 0; f < followers.Length; f++) {
				if (f > 0) line += ",";
				line += followers[f];
			}
			outFile.Write(line + "\n");
		}
		outFile.Close();
		TGprint("\\$0f0\\$sSaved: " + connectivityFile);
	} catch {
		TGprint("\\$f00Failed to write: " + connectivityFile);
		TGprint("\\$f00Make sure block_data folder exists and is writable!");
		UI::ShowNotification("Failed to save connectivity data!");
		return;
	}

	TGprint("\\$0f0\\$s=== Phase 2 Complete ===");
	TGprint("File saved to block_data folder: connectivity_" + vistaLower + ".txt");
	TGprint("\\$888Format: BlockName|Follower1,Follower2,Follower3,...");
	
	UI::ShowNotification("Phase 2 complete for " + vistaName + "! File saved to block_data folder.");
}

// If block direction is unknown, guess by finding which adjacent cell has a block (forward direction).
CGameEditorPluginMap::ECardinalDirections GuessForwardDirection(CGameEditorPluginMap@ map, int3 pos)
{
	for (int i = 0; i < 4; i++) {
		auto d = IntToDir(i);
		int3 next = pos.opAdd(MoveDir(d));
		if (map.GetBlock(next) !is null) return d;
		if (map.GetBlock(next.opAdd(int3(0,1,0))) !is null) return d;
		if (map.GetBlock(next.opAdd(int3(0,2,0))) !is null) return d;
	}
	return DIR_NORTH;
}

// Find the next block in the chain: any neighbor that has a block and is not prevPos. Handles turns and slopes.
int3 FindNextBlockInChain(CGameEditorPluginMap@ map, int3 currentPos, int3 prevPos)
{
	array<int3> offsets;
	offsets.InsertLast(int3(1,0,0)); offsets.InsertLast(int3(-1,0,0));
	offsets.InsertLast(int3(0,0,1)); offsets.InsertLast(int3(0,0,-1));
	offsets.InsertLast(int3(0,1,0)); offsets.InsertLast(int3(0,-1,0));
	offsets.InsertLast(int3(0,2,0)); offsets.InsertLast(int3(0,-2,0));
	for (uint i = 0; i < offsets.Length; i++) {
		int3 n = currentPos.opAdd(offsets[i]);
		if (n == prevPos) continue;
		if (map.GetBlock(n) !is null) return n;
	}
	return int3(-999, -999, -999); // no next
}

// User places up to 4 blocks (first = Start). Chain can turn left/right and use slopes. Optional: set testBlockPosX/Y/Z to pick the exact block to test.
void FindSuitableBlocksAfterPlacedChain()
{
	auto app = cast<CTrackMania>(GetApp());
	if (app is null) return;

	auto editor = cast<CGameCtnEditorFree>(app.Editor);
	if (editor is null) {
		UI::ShowNotification("Editor is not opened!");
		return;
	}

	auto map = cast<CGameEditorPluginMap>(editor.PluginMapType);
	if (map is null) return;

	int3 lastPos;
	int chainLen = 0;
	bool haveBlock = false;

	// Optional: user specified the block to test by position (e.g. L-shaped block – pick the free end’s block)
	if (testBlockPosX >= 0 && testBlockPosY >= 0 && testBlockPosZ >= 0) {
		lastPos = int3(testBlockPosX, testBlockPosY, testBlockPosZ);
		if (map.GetBlock(lastPos) !is null) {
			haveBlock = true;
			chainLen = 1;
			TGprint("\\$0f0\\$sUsing block at " + tostring(lastPos) + ": " + tostring(map.GetBlock(lastPos).BlockModel.IdName) + " (connection point is determined by the game).");
		} else {
			TGprint("\\$f00No block at (" + tostring(testBlockPosX) + "," + tostring(testBlockPosY) + "," + tostring(testBlockPosZ) + "). Ignoring and trying chain from Start.");
		}
	}

	// If no block selected by position, find chain from Start
	if (!haveBlock) {
		int3 startPos;
		CGameCtnBlock@ startBlock = FindStartBlock(map, startPos);
		if (startBlock is null) {
			TGprint("\\$f00No Start block found. Place a Start block and 1–3 more (max 4), or set the block position below.");
			UI::ShowNotification("No Start block found!");
			return;
		}
		lastPos = startPos;
		haveBlock = true;
		chainLen = 1;
		TGprint("\\$0f0\\$sStart: " + tostring(startBlock.BlockModel.IdName) + " at " + tostring(startPos));

		int3 prevPos = int3(-999, -999, -999);
		for (int step = 1; step < 4; step++) {
			int3 nextPos = FindNextBlockInChain(map, lastPos, prevPos);
			if (nextPos.x == -999) break;
			if (map.GetBlock(nextPos) is null) break;
			prevPos = lastPos;
			lastPos = nextPos;
			chainLen++;
			TGprint("Chain " + tostring(step + 1) + ": " + tostring(map.GetBlock(lastPos).BlockModel.IdName) + " at " + tostring(lastPos));
		}
	}

	string lastBlockName = (map.GetBlock(lastPos) !is null) ? tostring(map.GetBlock(lastPos).BlockModel.IdName) : "?";
	TGprint("\\$0f0\\$sLast block: " + lastBlockName + " (chain length " + tostring(chainLen) + "). Testing which blocks fit after it...");

	// Use ConnectResults: game says which blocks can follow lastBlock
	array<string> suitableBlocks;
	uint trackCount = 0;
	for (uint i = 0; i < map.BlockModels.Length; i++) {
		auto model = map.BlockModels[i];
		if (model is null) continue;
		string blockName = tostring(model.IdName);
		if (BlockKindFromIdName(blockName) != "Track") continue;
		trackCount++;
		auto result = ConnectBlocks(map, lastPos, blockName);
		if (result !is null) {
			suitableBlocks.InsertLast(blockName);
		}
		if (trackCount % 100 == 0) {
			TGprint("Tested " + tostring(trackCount) + " blocks...");
		}
	}

	TGprint("\\$0f0\\$s=== Results (suitable after your " + tostring(chainLen) + " blocks) ===");
	TGprint("Total track blocks tested: " + tostring(trackCount) + ", suitable: " + tostring(suitableBlocks.Length));
	TGprint("\\$0f0\\$s--- Suitable blocks ---");
	for (uint i = 0; i < suitableBlocks.Length; i++) {
		print(suitableBlocks[i]);
	}
	TGprint("\\$0f0\\$s=== End results ===");
	UI::ShowNotification("Found " + tostring(suitableBlocks.Length) + " suitable blocks (see log)");
}