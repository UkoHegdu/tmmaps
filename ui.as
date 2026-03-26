bool HAS_ADVANCED_EDITOR = false;

//vars
bool display = false, preloaded = false;
bool tabTrack = true, tabScenery = false, tabSettings = false, tabDev = false;
int st_maxBlocks = 45;
//--

void RenderMenu()
{
	HAS_ADVANCED_EDITOR = Permissions::OpenAdvancedMapEditor();

	if (UI::MenuItem("\\$f00" + Icons::Random + "\\$fff Track Generator") && CanDisplay()) {

		display = !display;
	}
}

void RenderInterface()
{
	if(!display)
	{
		return;
	}

	UI::SetNextWindowSize(686, 580);
	UI::SetNextWindowPos(300, 300, UI::Cond::Once);

	UI::Begin("Track Generator", display, UI::WindowFlags::NoResize);
	UI::BeginTabBar("yep", UI::TabBarFlags::None);

		UI::PushStyleColor(UI::Col::Tab, vec4(0.7f, 0.0f, 0.0f, 1) * vec4(0.5f, 0.5f, 0.5f, 0.75f));
		UI::PushStyleColor(UI::Col::TabHovered, vec4(0.7f, 0.0f, 0.0f, 1) * vec4(1.2f, 1.2f, 1.2f, 0.85f));
		UI::PushStyleColor(UI::Col::TabActive, vec4(0.7f, 0.0f, 0.0f, 1));
		if(UI::BeginTabItem("Track Generator", tabTrack, UI::TabItemFlags::NoCloseWithMiddleMouseButton))
		{
			UI::BeginChild("Tab");
			RenderTrackGenerator();
			UI::EndChild();
			UI::EndTabItem();
		}
		UI::PopStyleColor(3);

		UI::PushStyleColor(UI::Col::Tab, vec4(0.0f, 0.7f, 0.0f, 1) * vec4(0.5f, 0.5f, 0.5f, 0.75f));
		UI::PushStyleColor(UI::Col::TabHovered, vec4(0.0f, 0.7f, 0.0f, 1) * vec4(1.2f, 1.2f, 1.2f, 0.85f));
		UI::PushStyleColor(UI::Col::TabActive, vec4(0.0f, 0.7f, 0.0f, 1));
		if(UI::BeginTabItem("Scenery Generator", tabScenery, UI::TabItemFlags::None))
		{
			UI::BeginChild("Tab");
			RenderSceneryGenerator();
			UI::EndChild();
			UI::EndTabItem();
		}
		UI::PopStyleColor(3);

		UI::PushStyleColor(UI::Col::Tab, vec4(0.7f, 0.7f, 0.0f, 1) * vec4(0.5f, 0.5f, 0.5f, 0.75f));
		UI::PushStyleColor(UI::Col::TabHovered, vec4(0.7f, 0.7f, 0.0f, 1) * vec4(1.2f, 1.2f, 1.2f, 0.85f));
		UI::PushStyleColor(UI::Col::TabActive, vec4(0.7f, 0.7f, 0.0f, 1));
		if(UI::BeginTabItem("Settings", tabSettings, UI::TabItemFlags::None))
		{
			UI::BeginChild("Tab");
			RenderSettings();
			UI::EndChild();
			UI::EndTabItem();
		}
		UI::PopStyleColor(3);

		UI::PushStyleColor(UI::Col::Tab, vec4(0.5f, 0.5f, 0.5f, 1) * vec4(0.5f, 0.5f, 0.5f, 0.75f));
		UI::PushStyleColor(UI::Col::TabHovered, vec4(0.5f, 0.5f, 0.5f, 1) * vec4(1.2f, 1.2f, 1.2f, 0.85f));
		UI::PushStyleColor(UI::Col::TabActive, vec4(0.5f, 0.5f, 0.5f, 1));
		if(UI::BeginTabItem("Dev", tabDev, UI::TabItemFlags::None))
		{
			UI::BeginChild("Tab");
			RenderDev();
			UI::EndChild();
			UI::EndTabItem();
		}
		UI::PopStyleColor(3);

	UI::EndTabBar();
	UI::End();
}

void RenderTrackGenerator()
{
	if(!HAS_ADVANCED_EDITOR) {UI::Text("\\$f00\\$s" + Icons::ExclamationTriangle +" Some blocks are not available with Starter Edition!");}

	if (UI::Button(Icons::Random + " Generate Random Track")) {
		Begin();
	}
	UI::SameLine();
	if (UI::Button(Icons::Trash + " Clear Track")) {
		startnew(v4::ClearLastRun);
	}

	UI::Separator();
	UI::Markdown("**Block Count**");
	st_maxBlocks = UI::SliderInt("\\$bbbblocks (excluding start and finish)", st_maxBlocks, 5, 100);

	UI::Separator();
	UI::Markdown("**Surface Types**");
	UI::TextDisabled("Place a RoadTechStart block first, then Generate.");
	st_v4Slope = UI::Checkbox("Slopes", st_v4Slope);
	UI::SameLine();
	st_v4Tilt = UI::Checkbox("Tilt / Banking", st_v4Tilt);
	if (!st_v4Slope && !st_v4Tilt) UI::TextDisabled("Flat only.");
	st_v4Special = UI::Checkbox("Special blocks \\$bbb(turbo, boost, no-engine, etc.)", st_v4Special);
	st_v4Ramps   = UI::Checkbox("Ramp blocks", st_v4Ramps);

	UI::Separator();
	UI::Text("\\$999\\$sRandom Track Generator V4 " + Icons::Copyright);
}

void RenderDev()
{
	UI::Markdown("**Flat blocks list**");
	UI::Text("\\$bbbPlace a Start block (e.g. RoadTechStart), then Create. Place another (e.g. RoadDirtStart), then Append.");
	UI::Separator();
	UI::Text("Create (overwrite):");
	if (UI::Button("Create: Stadium")) { GenerateFlatBlocks("Stadium", false); }
	UI::SameLine();
	if (UI::Button("Create: Blue Bay")) { GenerateFlatBlocks("BlueBay", false); }
	UI::SameLine();
	if (UI::Button("Create: Green Coast")) { GenerateFlatBlocks("GreenCoast", false); }
	UI::SameLine();
	if (UI::Button("Create: Red Island")) { GenerateFlatBlocks("RedIsland", false); }
	UI::SameLine();
	if (UI::Button("Create: White Shore")) { GenerateFlatBlocks("WhiteShore", false); }
	UI::Text("Append:");
	if (UI::Button("Append: Stadium")) { GenerateFlatBlocks("Stadium", true); }
	UI::SameLine();
	if (UI::Button("Append: Blue Bay")) { GenerateFlatBlocks("BlueBay", true); }
	UI::SameLine();
	if (UI::Button("Append: Green Coast")) { GenerateFlatBlocks("GreenCoast", true); }
	UI::SameLine();
	if (UI::Button("Append: Red Island")) { GenerateFlatBlocks("RedIsland", true); }
	UI::SameLine();
	if (UI::Button("Append: White Shore")) { GenerateFlatBlocks("WhiteShore", true); }
	UI::Separator();
	UI::Markdown("**Flat blocks by Road subcategory**");
	UI::Text("\\$bbbPlace Start block (e.g. RoadTechStart), then click matching button. Writes flat + transition blocks within that subcategory.");
	UI::Separator();
	if (UI::Button("Flat blocks: Road Tech")) { GenerateFlatBlocksBySubcategory("RoadTech"); }
	UI::SameLine();
	if (UI::Button("Flat blocks: Road Dirt")) { GenerateFlatBlocksBySubcategory("RoadDirt"); }
	UI::SameLine();
	if (UI::Button("Flat blocks: Road Bump")) { GenerateFlatBlocksBySubcategory("RoadBump"); }
	UI::SameLine();
	if (UI::Button("Flat blocks: Road Ice")) { GenerateFlatBlocksBySubcategory("RoadIce"); }
	UI::SameLine();
	if (UI::Button("Flat blocks: Road Water")) { GenerateFlatBlocksBySubcategory("RoadWater"); }
	UI::Separator();
	UI::Markdown("**Connectivity Data Generation (Phase 2)**");
	UI::Text("\\$bbbGenerates connectivity data for blocks from Phase 1. Tests which blocks can connect after each block.");
	UI::Text("\\$888Requires blocks_to_test_<vista>.txt files in block_data folder. Skips blocks already tested in other Vistas.");
	UI::Text("\\$888Open a map in the Vista you want, then click the matching button.");
	UI::Separator();
	if (UI::Button("Check first block")) {
		GenerateConnectivityPhase2FirstBlock();
	}
	UI::SameLine();
	if (UI::Button("Phase 2: Stadium")) {
		GenerateConnectivityPhase2("Stadium");
	}
	UI::SameLine();
	if (UI::Button("Phase 2: Blue Bay")) {
		GenerateConnectivityPhase2("BlueBay");
	}
	UI::SameLine();
	if (UI::Button("Phase 2: Green Coast")) {
		GenerateConnectivityPhase2("GreenCoast");
	}
	if (UI::Button("Phase 2: Red Island")) {
		GenerateConnectivityPhase2("RedIsland");
	}
	UI::SameLine();
	if (UI::Button("Phase 2: White Shore")) {
		GenerateConnectivityPhase2("WhiteShore");
	}
	UI::Separator();
	UI::Markdown("**Visual inspection**");
	if (UI::Button("Place Transition blocks")) {
		PlaceTransitionBlocks();
	}
	UI::SameLine();
	UI::TextDisabled("Places Transition + overlap blocks for visual inspection.");
	UI::Separator();
	if (UI::Button(Icons::Download + " Dump block names to log")) {
		DumpBlockNames();
	}
	UI::SameLine();
	UI::TextDisabled("Writes all loaded block IdNames + kind to the OpenPlanet log.");
	UI::Separator();
	UI::TextDisabled("Requires editor open. Reads from and writes to: d:\\REPO\\tmmaps\\block_data\\");
	UI::TextDisabled("Phase 2 clears the map then places blocks one by one.");
	UI::TextDisabled("Progress every 500 blocks. Output: connectivity_<vista>.txt (overwrites)");
}

void RenderSettings()
{
	UI::Markdown("**Environment / Vista**");
	int vistaIdx = 0;
	if (blocks::CURR_VISTA == "Stadium") vistaIdx = 0;
	else if (blocks::CURR_VISTA == "BlueBay") vistaIdx = 1;
	else if (blocks::CURR_VISTA == "GreenCoast") vistaIdx = 2;
	else if (blocks::CURR_VISTA == "RedIsland") vistaIdx = 3;
	else if (blocks::CURR_VISTA == "WhiteShore") vistaIdx = 4;
	string vistaLabel = vistaIdx == 0 ? "Stadium" : (vistaIdx == 1 ? "Blue Bay" : (vistaIdx == 2 ? "Green Coast" : (vistaIdx == 3 ? "Red Island" : "White Shore")));
	if (UI::BeginCombo("Vista (only blocks for this environment)", vistaLabel)) {
		if (UI::Selectable("Stadium", vistaIdx == 0)) { blocks::CURR_VISTA = "Stadium"; }
		if (UI::Selectable("Blue Bay", vistaIdx == 1)) { blocks::CURR_VISTA = "BlueBay"; }
		if (UI::Selectable("Green Coast", vistaIdx == 2)) { blocks::CURR_VISTA = "GreenCoast"; }
		if (UI::Selectable("Red Island", vistaIdx == 3)) { blocks::CURR_VISTA = "RedIsland"; }
		if (UI::Selectable("White Shore", vistaIdx == 4)) { blocks::CURR_VISTA = "WhiteShore"; }
		UI::EndCombo();
	}
	UI::TextDisabled("Match the map's environment so only valid blocks are used.");
	UI::Separator();

	UI::Markdown("**Block Style / Type**");
	UI::Text("\\$bbbSelect which block types to use. Multiple types can be selected for variety.");
	UI::Text("\\$ff0\\$s" + Icons::ExclamationCircle + " Block types are categorized by surface/material (Tech, Dirt, Ice, Snow, Rally, etc.).");
	UI::Separator();

	UI::Markdown("**Road Types**");
	blocks::roadblocks = UI::Checkbox("Tech Road", blocks::roadblocks);
	if (blocks::roadblocks) {blocks::TechBlocks();}
	UI::SameLine();
	blocks::dirtblocks = UI::Checkbox("Dirt Road", blocks::dirtblocks);
	if (blocks::dirtblocks) {blocks::DirtBlocks();}
	UI::SameLine();
	blocks::iceblocks = UI::Checkbox("Ice Road", blocks::iceblocks) && HAS_ADVANCED_EDITOR;
	if (blocks::iceblocks) {blocks::IceBlocks();}
	UI::SameLine();
	blocks::icewallblocks = UI::Checkbox("Ice Road With Wall", blocks::icewallblocks);
	if (blocks::icewallblocks) {blocks::IceWallBlocks();}
	UI::SameLine();
	blocks::sausageblocks = UI::Checkbox("Sausage Road (Bump)", blocks::sausageblocks);
	if (blocks::sausageblocks) {blocks::SausageBlocks();}
	blocks::waterblocks = UI::Checkbox("Water Road", blocks::waterblocks) && HAS_ADVANCED_EDITOR;
	if (blocks::waterblocks) {blocks::WaterBlocks();}

	UI::Separator();
	UI::Markdown("**Platform Types**");
	blocks::platformtechblocks = UI::Checkbox("Tech Platform", blocks::platformtechblocks) && HAS_ADVANCED_EDITOR;
	if (blocks::platformtechblocks) {blocks::PlatformTechBlocks();}
	UI::SameLine();
	blocks::platformdirtblocks = UI::Checkbox("Dirt Platform", blocks::platformdirtblocks) && HAS_ADVANCED_EDITOR;
	if (blocks::platformdirtblocks) {blocks::PlatformDirtBlocks();}
	UI::SameLine();
	blocks::platformiceblocks = UI::Checkbox("Ice Platform", blocks::platformiceblocks) && HAS_ADVANCED_EDITOR;
	if (blocks::platformiceblocks) {blocks::PlatformIceBlocks();}
	UI::SameLine();
	blocks::platformgrassblocks = UI::Checkbox("Grass Platform", blocks::platformgrassblocks) && HAS_ADVANCED_EDITOR;
	if (blocks::platformgrassblocks) {blocks::PlatformGrassBlocks();}
	UI::SameLine();
	blocks::plasticblocks = UI::Checkbox("Plastic Platform", blocks::plasticblocks) && HAS_ADVANCED_EDITOR;
	if (blocks::plasticblocks) {blocks::PlasticBlocks();}

	UI::Separator();
	UI::Markdown("**Open Road Types**");
	blocks::opentechroadblocks = UI::Checkbox("Open Tech Road", blocks::opentechroadblocks) && HAS_ADVANCED_EDITOR;
	if (blocks::opentechroadblocks) {blocks::OpenTechRoadBlocks();}
	UI::SameLine();
	blocks::opendirtroadblocks = UI::Checkbox("Open Dirt Road", blocks::opendirtroadblocks) && HAS_ADVANCED_EDITOR;
	if (blocks::opendirtroadblocks) {blocks::OpenDirtRoadBlocks();}
	UI::SameLine();
	blocks::openiceroadblocks = UI::Checkbox("Open Ice Road", blocks::openiceroadblocks) && HAS_ADVANCED_EDITOR;
	if (blocks::openiceroadblocks) {blocks::OpenIceRoadBlocks();}
	UI::SameLine();
	blocks::opengrassroadblocks = UI::Checkbox("Open Grass Road", blocks::opengrassroadblocks) && HAS_ADVANCED_EDITOR;
	if (blocks::opengrassroadblocks) {blocks::OpenGrassRoadBlocks();}

	UI::Separator();
	if(blocks::IsMultipleBlockTypesSelected()) {
		UI::Text("\\$ff0\\$s" + Icons::ExclamationTriangle +" Using multiple styles will sometimes cause the generator to get stuck.");
	}
}

void RenderSceneryGenerator()
{
	if (UI::Button(Icons::Random + " Generate Random Scenery") && HAS_ADVANCED_EDITOR) {
		BeginScenery();
	}
	UI::SameLine();
	if (UI::Button(Icons::Trash + " Undo Last Scenery")) {
		CancelScenery();
	}
	UI::Separator();

	blocks::randomcolors = UI::Checkbox("Paint blocks with random colors \\$bbb", blocks::randomcolors);

	UI::Separator();
	UI::Text("\\$999\\$sRandom Track Generator V4 " + Icons::Copyright);
}

void Main()
{
	auto app = cast<CTrackMania>(GetApp());
	if(app is null)
	{
		return;
	}
	CGamePlayerInfo@ playerInfo = cast<CTrackManiaNetwork@>(app.Network).PlayerInfo;
	if(playerInfo is null)
	{
		return;
	}
	seedText = playerInfo.Name;
	seedText = seedText.ToUpper();

	blocks::TechBlocks();

	MainThinker();
}

void MainThinker()
{
	if (display && !CanDisplay())
	{
		display = false;
	}

	if (display)
	{
		LoadMapSize();
	}

	sleep(1000);
	MainThinker();
}
