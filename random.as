bool seedEnabled = false;
string seedText = "OPENPLANET";
double seedDouble = 0;

int MathRand(int a, int b)
{
	if (seedEnabled)
	{
		return RandomFromSeed(a, b);
	}
	
	return Math::Rand(a, b);
}

string RandomSeed(int length)
{
	string result = "";
	string chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
	
	for(int i = 0; i < length; i++)
	{
		result = result.opAdd(chars.SubStr(Math::Rand(0, chars.Length), 1));
	}
	
	return result;
}

double ConvertSeed(const string seed)
{
	string newSeed = "";
	
	int length = seed.Length;
	if (length > 10) {length = 10;}
	for(int i = 0; i < length; i++)
	{
		newSeed = newSeed + tostring(seed[i]);
	}
	
	return Text::ParseDouble(newSeed + ".0000");
}

int RandomFromSeed(int min, int max)
{
	return int(Math::Floor(rnd_Next() * (max-min) + min));
}

float rnd_A = 45.0001;
float rnd_LEET = 1337.0000;
float rnd_M = 69.9999;
float rnd_Next()
{
	seedDouble = (rnd_A * seedDouble + rnd_LEET) % rnd_M; 
	return seedDouble % 1;
}

CGameEditorPluginMap::ECardinalDirections RandomDirection()
{
	switch(MathRand(1,5))
	{
		case 1:
			return DIR_NORTH;
		case 2:
			return DIR_EAST;
		case 3:
			return DIR_SOUTH;
		case 4:
			return DIR_WEST;		
	}
	return DIR_NORTH;
}

int3 RandomPoint()
{
	return int3(MAX_X / 2 + MathRand(-(MAX_X / 2 - (MAX_X / 2 / 6)), (MAX_X / 2 - (MAX_X / 2 / 6))), (Math::Floor(MAX_Y / 4)), MAX_Z / 2 + MathRand(-(MAX_Z / 2 - (MAX_Z / 2 / 6)), (MAX_Z / 2 - (MAX_Z / 2 / 6)))).opAdd(int3(0, MathRand(0,7)*MathRand(0,4), 0));
}

string RandomBlock()
{
	int randomInt = MathRand(1, 101);
	if (randomInt <= 6 && blocks::IsMultipleBlockTypesSelected())
	{
		return blocks::RD_CONNECT;
	}
	else if (randomInt <= 7 && blocks::coolblocks)
	{
		return blocks::GetBlockFromPool("Cool1");
	}
	else if (randomInt <= 8 && blocks::coolblocks)
	{
		return blocks::GetBlockFromPool("Cool2");
	}
	
	else if (randomInt <= 43)
	{
		return blocks::GetBlockFromPool("Straight");
	}
	else if(randomInt <= 55) // special blocks
	{
		if(randomInt <= 44)
		{	
			if(!blocks::nobrake) {return blocks::GetBlockFromPool("Straight");}
			return blocks::GetBlockFromPool("NoBrake");
		}
		else if(randomInt <= 45)
		{
			if(!blocks::cruise) {return blocks::GetBlockFromPool("Straight");}
			return blocks::GetBlockFromPool("Cruise");
		}
		else if(randomInt <= 46)
		{	
			if(!blocks::fragile) {return blocks::GetBlockFromPool("Straight");}
			return blocks::GetBlockFromPool("Fragile");
		}
		else if(randomInt <= 47)
		{
			if(!blocks::nosteer) {return blocks::GetBlockFromPool("Straight");}
			return blocks::GetBlockFromPool("NoSteer");
		}
		else if(randomInt <= 48)
		{
			if(!blocks::slowmotion) {return blocks::GetBlockFromPool("Straight");}
			return blocks::GetBlockFromPool("SlowMotion");
		}	
		else if(randomInt <= 49)
		{
			if(!blocks::noengine) {return blocks::GetBlockFromPool("Straight");}
			return blocks::GetBlockFromPool("NoEngine");
		}			
		else if(randomInt <= 50)
		{
			if(!blocks::booster1) {return blocks::GetBlockFromPool("Straight");}
			return blocks::GetBlockFromPool("Booster1");
		}		
		else if(randomInt <= 51 && blocks::booster2)
		{
			return blocks::GetBlockFromPool("Booster2");
		}				
		else if(randomInt <= 52 && blocks::turbo2)
		{
			return blocks::GetBlockFromPool("Turbo2");
		}	
		else if(randomInt <= 53 && blocks::turbor)
		{
			return blocks::GetBlockFromPool("TurboR");
		}		
		else if(randomInt <= 54 && blocks::reset)
		{
			return blocks::GetBlockFromPool("Reset");
		}
		else if(blocks::turbo1)
		{
			return blocks::GetBlockFromPool("Turbo1");
		}			
		else 
		{
			return blocks::GetBlockFromPool("Straight");
		}
	}
	else if(randomInt <= 60)
	{
		if(st_useCpBlocks)
		{
			return blocks::GetBlockFromPool("Straight");
		}
	
		return blocks::GetBlockFromPool("Checkpoint");
	}
	else if(randomInt <= (blocks::extendedSlopes ? 80 : 70))
	{
		return blocks::GetBlockFromPool("Slope");
	}
	else if(randomInt <= (blocks::extendedSlopes ? 88 : 77))
	{
		return blocks::GetBlockFromPool("Slope2");
	}
	else if(randomInt <= 92)
	{
		return blocks::GetBlockFromPool("Turn2");
	}
	else
	{
		return blocks::GetBlockFromPool("Turn1");
	}
}

void RandomBlocks()
{
	if (blocks::IsMultipleBlockTypesSelected())
	{
		bool ready = false;
		while(!ready)
		{
			// Exclude Snow (16) and Rally (17) - not supported with transition logic
			ready = blocks::SetBlockType(MathRand(1, 15));
		}
	}
}

CGameEditorPluginMap::EMapElemColor RandomColor()
{
	int randomInt = Math::Rand(1,7);
	if(randomInt == 1)
	{
		return CGameEditorPluginMap::EMapElemColor::Default;
	}
	else if(randomInt == 2)
	{
		return CGameEditorPluginMap::EMapElemColor::White;
	}
	else if(randomInt == 3)
	{
		return CGameEditorPluginMap::EMapElemColor::Green;
	}
	else if(randomInt == 4)
	{
		return CGameEditorPluginMap::EMapElemColor::Blue;
	}
	else if(randomInt == 5)
	{
		return CGameEditorPluginMap::EMapElemColor::Red;
	}
	else if(randomInt == 6)
	{
		return CGameEditorPluginMap::EMapElemColor::Black;
	}	
	
	return CGameEditorPluginMap::EMapElemColor::Default;
}

string RandomSceneryBlock()
{
	auto arr = blocks::GetSceneryBlocks();
	if (arr.Length == 0) return "";
	return arr[Math::Rand(0, int(arr.Length) - 1)];
}