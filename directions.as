int3 MoveDir(CGameEditorPluginMap::ECardinalDirections dir)
{
	switch(dir)
	{
		case CGameEditorPluginMap::ECardinalDirections::North:
			return int3(0,0,1);
		case CGameEditorPluginMap::ECardinalDirections::East:
			return int3(-1,0,0);
		case CGameEditorPluginMap::ECardinalDirections::South:
			return int3(0,0,-1);
		case CGameEditorPluginMap::ECardinalDirections::West:
			return int3(1,0,0);			
	}
	
	return int3(1,0,1);
}

CGameEditorPluginMap::ECardinalDirections TurnDirLeft(CGameEditorPluginMap::ECardinalDirections dir)
{
	switch(dir)
	{
		case CGameEditorPluginMap::ECardinalDirections::North:
			return CGameEditorPluginMap::ECardinalDirections::West;
		case CGameEditorPluginMap::ECardinalDirections::East:
			return CGameEditorPluginMap::ECardinalDirections::North;
		case CGameEditorPluginMap::ECardinalDirections::South:
			return CGameEditorPluginMap::ECardinalDirections::East;
		case CGameEditorPluginMap::ECardinalDirections::West:
			return CGameEditorPluginMap::ECardinalDirections::South;			
	}
	
	return CGameEditorPluginMap::ECardinalDirections::North;
}

CGameEditorPluginMap::ECardinalDirections TurnDirRight(CGameEditorPluginMap::ECardinalDirections dir)
{
	switch(dir)
	{
		case CGameEditorPluginMap::ECardinalDirections::North:
			return CGameEditorPluginMap::ECardinalDirections::East;
		case CGameEditorPluginMap::ECardinalDirections::East:
			return CGameEditorPluginMap::ECardinalDirections::South;
		case CGameEditorPluginMap::ECardinalDirections::South:
			return CGameEditorPluginMap::ECardinalDirections::West;
		case CGameEditorPluginMap::ECardinalDirections::West:
			return CGameEditorPluginMap::ECardinalDirections::North;
	}
	
	return CGameEditorPluginMap::ECardinalDirections::North;
}

int DirToInt(CGameEditorPluginMap::ECardinalDirections dir)
{
	switch(dir)
	{
		case CGameEditorPluginMap::ECardinalDirections::North: return 0;
		case CGameEditorPluginMap::ECardinalDirections::East:  return 1;
		case CGameEditorPluginMap::ECardinalDirections::South: return 2;
		case CGameEditorPluginMap::ECardinalDirections::West:  return 3;
	}
	return 0;
}

CGameEditorPluginMap::ECardinalDirections IntToDir(int i)
{
	switch(i)
	{
		case 0: return CGameEditorPluginMap::ECardinalDirections::North;
		case 1: return CGameEditorPluginMap::ECardinalDirections::East;
		case 2: return CGameEditorPluginMap::ECardinalDirections::South;
		case 3: return CGameEditorPluginMap::ECardinalDirections::West;
	}
	return CGameEditorPluginMap::ECardinalDirections::North;
}

CGameEditorPluginMap::ECardinalDirections ConvertDir(CGameEditorPluginMapConnectResults::ECardinalDirections dir)
{
	switch(dir)
	{
		case CGameEditorPluginMapConnectResults::ECardinalDirections::North:
			return CGameEditorPluginMap::ECardinalDirections::North;	
		case CGameEditorPluginMapConnectResults::ECardinalDirections::East:
			return CGameEditorPluginMap::ECardinalDirections::East;
		case CGameEditorPluginMapConnectResults::ECardinalDirections::South:
			return CGameEditorPluginMap::ECardinalDirections::South;
		case CGameEditorPluginMapConnectResults::ECardinalDirections::West:
			return CGameEditorPluginMap::ECardinalDirections::West;
	}
	
	return CGameEditorPluginMap::ECardinalDirections::North;
}

// Overload for when res.Dir is already the map enum (TM2020 API)
CGameEditorPluginMap::ECardinalDirections ConvertDir(CGameEditorPluginMap::ECardinalDirections dir)
{
	return dir;
}