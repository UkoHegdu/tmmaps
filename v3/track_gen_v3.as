// Track Generator v3: connectivity-based placement using GetConnectResults.
// User places Start block; script finds it and chains blocks from it.
// Block pool: all Track blocks except Platform.

namespace v3 {

const int RETRY_CAP = 100;

// Build block pool: all Track blocks except Platform.
array<string>@ BuildBlockPool(CGameEditorPluginMap@ map)
{
	array<string>@ pool = array<string>();
	for (uint i = 0; i < map.BlockModels.Length; i++) {
		auto model = map.BlockModels[i];
		if (model is null) continue;
		string blockName = tostring(model.IdName);
		if (BlockKindFromIdName(blockName) != "Track") continue;
		if (blockName.IndexOf("Platform") >= 0) continue;
		pool.InsertLast(blockName);
	}
	return pool;
}

// Pick random block from pool.
string RandomBlockFromPool(array<string>@ pool)
{
	if (pool.Length == 0) return "";
	return pool[MathRand(0, int(pool.Length) - 1)];
}

void Run()
{
	uint64 before = Time::get_Now();

	auto app = cast<CTrackMania>(GetApp());
	if (app is null) return;

	auto editor = cast<CGameCtnEditorFree>(app.Editor);
	if (editor is null) {
		UI::ShowNotification("Editor is not opened!");
		warn("editor is not opened!");
		return;
	}

	auto map = cast<CGameEditorPluginMap>(editor.PluginMapType);
	if (map is null) return;

	LoadMapSize();
	seedDouble = ConvertSeed(seedText);

	TGprint("\\$0f0\\$sGenerating track (v3 connectivity-based)!");

	int3 startPos;
	CGameCtnBlock@ startBlock = FindStartBlock(map, startPos);
	if (startBlock is null) {
		TGprint("\\$f00No Start block found! Place a Start block (e.g. RoadTechStart) first.");
		UI::ShowNotification("Place a Start block first!");
		return;
	}

	TGprint("Using Start: " + tostring(startBlock.BlockModel.IdName) + " at " + tostring(startPos));

	array<string>@ blockPool = BuildBlockPool(map);
	if (blockPool.Length == 0) {
		TGprint("\\$f00No track blocks in pool (excluding Platform).");
		UI::ShowNotification("No track blocks available!");
		return;
	}
	TGprint("Block pool: " + tostring(blockPool.Length) + " blocks");

	int3 prevPos = startPos;
	int blocksPlaced = 0;
	int effectiveMax = blocks::extendedSlopes ? Math::Min(st_maxBlocks, 100) : st_maxBlocks;

	for (int i = 0; i < effectiveMax; i++)
	{
		CGameCtnBlock@ prevBlock = map.GetBlock(prevPos);
		if (prevBlock is null) {
			TGprint("\\$f00No block at " + tostring(prevPos) + ", stopping");
			break;
		}

		int retries = 0;
		bool placed = false;
		string lastAttempted = "";

		while (retries < RETRY_CAP)
		{
			string blockName = RandomBlockFromPool(blockPool);
			lastAttempted = blockName;

			auto info = map.GetBlockModelFromName(blockName);
			if (info is null) {
				retries++;
				continue;
			}

			while (!map.IsEditorReadyForRequest) { yield(); }
			map.GetConnectResults(prevBlock, info);
			while (!map.IsEditorReadyForRequest) { yield(); }

			// Find first result with CanPlace
			for (uint r = 0; r < map.ConnectResults.Length; r++) {
				auto res = map.ConnectResults[r];
				if (res is null) continue;
				if (!res.CanPlace) continue;

				auto coord = res.Coord;
				auto dir = ConvertDir(res.Dir);

				if (CanPlaceBlock(map, blockName, dir, coord)) {
					if (PlaceBlock(map, blockName, dir, coord)) {
						blocksPlaced++;
						prevPos = coord;
						placed = true;
						TGprint("Placed " + blockName + " at " + tostring(coord) + " (#" + tostring(blocksPlaced) + ")");
					}
				}
				if (placed) break;
			}
			if (placed) break;
			retries++;
		}

		if (!placed)
		{
			TGprint("\\$f00Dead end: last attempted " + lastAttempted + " after " + tostring(retries) + " retries, trying fallback positions");

			// Dead-end fallback: try placing below current road (1–2 levels)
			array<int3> fallbackOffsets = { int3(0, -1, 0), int3(0, -2, 0) };
			bool fallbackPlaced = false;

			for (uint f = 0; f < fallbackOffsets.Length && !fallbackPlaced; f++)
			{
				int3 tryPos = prevPos.opAdd(fallbackOffsets[f]);
				for (uint r = 0; r < blockPool.Length && !fallbackPlaced; r++)
				{
					string blockName = blockPool[r];
					auto info = map.GetBlockModelFromName(blockName);
					if (info is null) continue;

					while (!map.IsEditorReadyForRequest) { yield(); }
					map.GetConnectResults(prevBlock, info);
					while (!map.IsEditorReadyForRequest) { yield(); }

					for (uint cr = 0; cr < map.ConnectResults.Length; cr++) {
						auto res = map.ConnectResults[cr];
						if (res is null || !res.CanPlace) continue;
						if (res.Coord != tryPos) continue;

						auto dir = ConvertDir(res.Dir);
						if (CanPlaceBlock(map, blockName, dir, tryPos) && PlaceBlock(map, blockName, dir, tryPos)) {
							blocksPlaced++;
							prevPos = tryPos;
							fallbackPlaced = true;
							TGprint("Dead end escape: placed " + blockName + " at " + tostring(tryPos));
							break;
						}
					}
				}
			}

			if (!fallbackPlaced) {
				TGprint("\\$f00Cannot continue after " + tostring(blocksPlaced) + " blocks. Placing Finish.");
				break;
			}
		}
	}

	// Place Finish - derive from Start block (e.g. RoadTechStart -> RoadTechFinish)
	string finishName = "";
	string startName = tostring(startBlock.BlockModel.IdName);
	int startIdx = startName.IndexOf("Start");
	if (startIdx >= 0) {
		finishName = startName.SubStr(0, startIdx) + "Finish";
	} else {
		finishName = blocks::RD_FINISH.Length > 0 ? blocks::RD_FINISH : "RoadTechFinish";
	}
	CGameCtnBlockInfo@ finishInfo = map.GetBlockModelFromName(finishName) !is null
		? map.GetBlockModelFromName(finishName) : map.GetBlockModelFromName("RoadTechFinish");

	CGameCtnBlock@ prevBlock = map.GetBlock(prevPos);
	if (finishInfo !is null && prevBlock !is null) {
		while (!map.IsEditorReadyForRequest) { yield(); }
		map.GetConnectResults(prevBlock, finishInfo);
		while (!map.IsEditorReadyForRequest) { yield(); }

		for (uint r = 0; r < map.ConnectResults.Length; r++) {
			auto res = map.ConnectResults[r];
			if (res is null || !res.CanPlace) continue;
			auto coord = res.Coord;
			auto dir = ConvertDir(res.Dir);
			if (CanPlaceBlock(map, finishName, dir, coord)) {
				PlaceBlock(map, finishName, dir, coord);
				TGprint("Placed Finish at " + tostring(coord));
			}
			break;
		}
	} else {
		TGprint("\\$ff0Could not get Finish block model");
	}

	uint64 elapsed = Time::get_Now() - before;
	TGprint("\\$0f0\\$sV3 done: " + tostring(blocksPlaced) + " blocks in " + tostring(elapsed) + " ms");
	UI::ShowNotification("V3 Track: " + tostring(blocksPlaced) + " blocks");
}

} // namespace v3
