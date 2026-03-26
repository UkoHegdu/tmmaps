# Track Generator (fork)

OpenPlanet plugin for Trackmania that generates random tracks in the map editor.

**Original plugin:** [Track Generator](https://trackmania.exchange/mapsearch?siteid=156) by **AvondaleZPR** (no updates since ~2022). This repo is a maintained fork with the same core behavior plus a block-name dump feature.

## Features

- Generate a random track (start → blocks → finish) from the editor.
- Multiple block styles (Tech, Dirt, Ice, Platform, etc.), checkpoints, seed support, special blocks.
- **Dump block names to log** – writes all loaded block `IdName`s (and a **kind**: Scenery / Track / Other, guessed from name prefix) to the OpenPlanet log. The list includes both default and custom blocks; the game API does not expose which are custom.

## Requirements

- [OpenPlanet](https://openplanet.dev/) for Trackmania (2020).
- Map editor open in-game.

## Load in game (no publishing)

You can run this plugin **without adding it to the OpenPlanet website**. Everything is local.

### 1. Install OpenPlanet

- Download and install [OpenPlanet](https://openplanet.dev/docs/tutorials/installation) for Trackmania.
- Start Trackmania with OpenPlanet enabled.

### 2. Enable Developer Mode (for local/unsigned plugins)

- In-game, press **F3** to open the OpenPlanet overlay.
- Go to **Developer → Signature Mode** and select **Developer**.
- This allows plugins that are not published or signed to load.

### 3. Put the plugin in the Plugins folder

- Find your OpenPlanet user folder:
  - **Trackmania (2020):** `C:\Users\<YourUsername>\OpenplanetNext`
  - (It may be named `Openplanet4` or similar; you can open the folder from the overlay: F3 → click the folder icon.)
- Open the **Plugins** folder inside it.
- Copy this project **as a folder** into Plugins. The folder must contain `info.toml` and all `.as` files. The folder name can be anything (e.g. `TrackGenerator`, `tmmaps`).

Example:

```
OpenplanetNext/
  Plugins/
    tmmaps/             ← folder name is up to you
      info.toml
      main.as
      ui.as
      blocks.as
      ... (all other .as files)
```

So: clone or download this repo, then copy the **contents** of the repo into `Plugins/<YourFolderName>/`, or copy the whole repo folder and rename it as you like.

### 4. Load the plugin

- Press **F3** → **Developer**.
- Find **Track Generator** in the list and click it to load (or use **Reload script engine** to reload all plugins).
- Restart the game if you don’t see it.

### 5. Use it

- Open the **map editor** in Trackmania.
- Open the Track Generator window (menu or plugin list, e.g. **Track Generator**).
- Generate a track or use **Dump block names to log**; the log is in your OpenPlanet user folder.

You never have to publish or submit anything to OpenPlanet; the plugin runs from your local folder only.

If loading fails, check the **OpenPlanet log** (F3 → Log) for the exact error. Install behaviour can depend on your OpenPlanet version (folder vs .op, signature mode, etc.); we haven’t verified all setups.

## Create your own repo from this base

1. **Create a new repo on GitHub** (no initial commit, or with a README – you can overwrite it).
2. **Clone this worktree/repo locally** (or download as ZIP), then:

   ```bash
   cd /path/to/this/folder
   git remote set-url origin https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git
   # or: git remote add origin ... if no remote yet
   git add .
   git commit -m "Initial commit: Track Generator fork with block dump"
   git push -u origin main
   ```

3. **Set your identity in the plugin:**
   - In `info.toml`: set `author` to your name or nickname.
   - In `ui.as`: search for the footer text and set the “Maintained by” / credit line to your name.
   - Optionally remove or change `siteid` in `info.toml` if you publish a new plugin entry on a site (e.g. OpenPlanet / TMX).

## License and credits

- Original Track Generator: **AvondaleZPR** (OpenPlanet / TMX site ID 156).
- This fork: see `info.toml` and the in-game plugin footer for maintainer credit.

