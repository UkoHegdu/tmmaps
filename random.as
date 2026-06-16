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