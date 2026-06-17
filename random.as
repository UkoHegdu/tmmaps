bool seedEnabled = false;
string seedText = "OPENPLANET";
double seedDouble = 0;

// Returns a random int in [a, b] — INCLUSIVE of both ends. All call sites use the
// inclusive convention (e.g. MathRand(0, len-1) for indexing, MathRand(0, 1) for a
// coin flip). Openplanet's Math::Rand(min, max) is max-EXCLUSIVE, so we pass b + 1.
// (Without the +1 the top value was never produced: the last pool entry was never
// picked — e.g. the last surface in a switch list — and MathRand(0,1) was always 0,
// freezing every coin flip to one side.)
int MathRand(int a, int b)
{
	if (seedEnabled)
	{
		return RandomFromSeed(a, b + 1);
	}

	return Math::Rand(a, b + 1);
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