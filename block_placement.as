// Timing accumulators for PlaceBlock — declared here (root file) so PlaceBlock can see them;
// read/reset by the V4 generator's timing diagnostics (track_gen_v4.as).
uint64 g_tPlace = 0; int g_nPlace = 0;

bool PlaceBlock(CGameEditorPluginMap@ map, const string blockName, CGameEditorPluginMap::ECardinalDirections dir, int3 point)
{
    auto info = map.GetBlockModelFromName(blockName);
	
	if(!(map.GetBlock(point) is null) && (blockName != blocks::RD_TURN2 && blockName != blocks::RD_UP2) && (map.GetBlock(point).BlockModel.IdName == blocks::WALL_STRAIGHT || map.GetBlock(point).BlockModel.IdName == blocks::WALL_FULL))
	{
		ClearPath(map, point);
	}

    uint64 _t = Time::get_Now();
    while (!map.IsEditorReadyForRequest) {
        yield();
    }
    bool _ok = map.PlaceBlock(info, point, dir);
    g_tPlace += Time::get_Now() - _t; g_nPlace++;
    return _ok;
}

bool CanPlaceBlock(CGameEditorPluginMap@ map, const string blockName, CGameEditorPluginMap::ECardinalDirections dir, int3 point)
{
	auto info = map.GetBlockModelFromName(blockName);

	if(!(map.GetBlock(point) is null) && (blockName != blocks::RD_TURN2 && blockName != blocks::RD_UP2) && (map.GetBlock(point).BlockModel.IdName == blocks::WALL_STRAIGHT || map.GetBlock(point).BlockModel.IdName == blocks::WALL_FULL))
	{
		auto upPoint = point.opAdd(int3(0,1,0));
		if(!(map.GetBlock(upPoint) is null) && (map.GetBlock(upPoint).BlockModel.IdName == blocks::WALL_STRAIGHT || map.GetBlock(upPoint).BlockModel.IdName == blocks::WALL_FULL))
		{
			return true;
		}		
		return false;
	}

    while (!map.IsEditorReadyForRequest) {
        yield();
    }

    return map.CanPlaceBlock(info, point, dir, true, 0);
}

bool PlaceGhostBlock(CGameEditorPluginMap@ map, const string blockName, CGameEditorPluginMap::ECardinalDirections dir, int3 point)
{
	auto info = map.GetBlockModelFromName(blockName);
	
    while (!map.IsEditorReadyForRequest) {
        yield();
    }

    return map.PlaceGhostBlock(info, point, dir);	
}

bool CanPlaceGhostBlock(CGameEditorPluginMap@ map, const string blockName, CGameEditorPluginMap::ECardinalDirections dir, int3 point)
{
	auto info = map.GetBlockModelFromName(blockName);
	
    while (!map.IsEditorReadyForRequest) {
        yield();
    }

    return map.CanPlaceGhostBlock(info, point, dir);	
}

CGameEditorPluginMapConnectResults@ ConnectBlocks(CGameEditorPluginMap@ map, int3 blockPos, const string nBlock)
{
	try
    {
		if (map.GetBlock(blockPos) is null) return null;

		auto info = map.GetBlockModelFromName(nBlock);
		if (info is null) return null;

		while (!map.IsEditorReadyForRequest) {
			yield();
		}
		map.GetConnectResults(map.GetBlock(blockPos), info);
		
		while (!map.IsEditorReadyForRequest) {
			yield();
		}
		
		if (map.ConnectResults.Length > 0 && !(map.ConnectResults[map.ConnectResults.Length-1] is null))
		{
			return map.ConnectResults[map.ConnectResults.Length-1];
		}
		return null;
    }
    catch
    {
		return null;
    }
}

void ClearPath(CGameEditorPluginMap@ map, int3 point)
{
	TGprint("removing a wall from " + tostring(point));
	while (!map.IsEditorReadyForRequest) {
		yield();
	}
	map.RemoveBlock(point);
	
	auto upPoint = point.opAdd(int3(0,1,0));
	if(!(map.GetBlock(upPoint) is null) && (map.GetBlock(upPoint).BlockModel.IdName == blocks::WALL_STRAIGHT || map.GetBlock(upPoint).BlockModel.IdName == blocks::WALL_FULL))
	{
		while (!map.IsEditorReadyForRequest) {
			yield();
		}
		map.RemoveBlock(upPoint);
	}
}