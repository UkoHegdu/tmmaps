#!/usr/bin/env python3
"""
Clean blocks.txt: strip log prefix (ScriptRuntime, LOG, time, tmmaps),
add Type column (Tech, Dirt, Ice, Water, Plastic, Grass, Snow, Rally, Bump, Scenery, Other).
Reads from blocks.txt, overwrites it with cleaned data.
"""
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent
BLOCKS_TXT = REPO / "blocks.txt"

# After "[tmmaps]  " we have either header text or "IdName | Kind"
# Headers to skip: --- Block names dump, Format:, --- End
LOG_PREFIX = re.compile(r"^\[\s*ScriptRuntime\]\s*\[\s*LOG\]\s*\[\d+:\d+:\d+\]\s*\[tmmaps\]\s*")
ESCAPE_PREFIX = re.compile(r"^\\?\$0f0\\?\$s")  # optional \ before $


def block_type_from_name(name: str) -> str:
    """Derive theme/surface Type from block IdName. Order matters."""
    n = name
    if "Snow" in n or n.startswith("Snow"):
        return "Snow"
    if "Rally" in n or "Castle" in n:
        return "Rally"
    if "Water" in n:  # RoadWater, TrackWallWater, DecoWallWater, PlatformWater
        return "Water"
    if "Plastic" in n:
        return "Plastic"
    if "Grass" in n:
        return "Grass"
    if "Dirt" in n:
        return "Dirt"
    if "Ice" in n or "WithWall" in n:  # ice road / ice wall
        return "Ice"
    if "Bump" in n or "Sausage" in n:
        return "Bump"
    if "RoadTech" in n or "OpenTech" in n or "PlatformTech" in n or "TrackWall" in n:
        return "Tech"
    if n.startswith("Deco") or "Obstacle" in n or "Structure" in n or "StageTechnics" in n:
        return "Scenery"
    return "Other"


def main() -> None:
    if not BLOCKS_TXT.exists():
        print(f"Not found: {BLOCKS_TXT}", file=sys.stderr)
        sys.exit(1)

    lines = BLOCKS_TXT.read_text(encoding="utf-8", errors="replace").splitlines()
    out = []
    out.append("# IdName | Kind | Type  (Type: Tech, Dirt, Ice, Water, Plastic, Grass, Snow, Rally, Bump, Scenery, Other)")

    for line in lines:
        if "[tmmaps]" not in line:
            continue
        # Strip log prefix
        m = LOG_PREFIX.match(line)
        if m:
            rest = line[m.end() :].strip()
        else:
            rest = line.strip()
        rest = ESCAPE_PREFIX.sub("", rest).strip()
        if not rest or rest.startswith("---") or "Format:" in rest:
            continue
        # Expect "IdName | Kind"
        parts = rest.split("|", 1)
        if len(parts) != 2:
            continue
        id_name = parts[0].strip()
        kind = parts[1].strip()
        if not id_name:
            continue
        typ = block_type_from_name(id_name)
        out.append(f"{id_name} | {kind} | {typ}")

    BLOCKS_TXT.write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"Cleaned {len(out) - 1} blocks -> {BLOCKS_TXT}")


if __name__ == "__main__":
    main()
