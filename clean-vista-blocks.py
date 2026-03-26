#!/usr/bin/env python3
"""
Clean Vista block files: strip log prefix, add Type column (same format as blocks.txt).
Reads blocks_blue_bay.txt, blocks_green_coast.txt, blocks_red_island.txt, blocks_white_shore.txt.
Overwrites each with: IdName | Kind | Type
"""
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent
LOG_PREFIX = re.compile(r"^\[\s*ScriptRuntime\]\s*\[\s*LOG\]\s*\[\d+:\d+:\d+\]\s*\[tmmaps\]\s*")
ESCAPE_PREFIX = re.compile(r"^\\?\$0f0\\?\$s")

VISTA_FILES = [
    "blocks_blue_bay.txt",
    "blocks_green_coast.txt",
    "blocks_red_island.txt",
    "blocks_white_shore.txt",
]


def block_type_from_name(name: str) -> str:
    n = name
    if "Snow" in n or n.startswith("Snow"):
        return "Snow"
    if "Rally" in n or "Castle" in n:
        return "Rally"
    if "Water" in n:
        return "Water"
    if "Plastic" in n:
        return "Plastic"
    if "Grass" in n:
        return "Grass"
    if "Dirt" in n:
        return "Dirt"
    if "Ice" in n or "WithWall" in n:
        return "Ice"
    if "Bump" in n or "Sausage" in n:
        return "Bump"
    if "RoadTech" in n or "OpenTech" in n or "PlatformTech" in n or "TrackWall" in n:
        return "Tech"
    if n.startswith("Deco") or "Obstacle" in n or "Structure" in n or "StageTechnics" in n:
        return "Scenery"
    return "Other"


def clean_file(path: Path) -> int:
    if not path.exists():
        print(f"Skip (not found): {path}", file=sys.stderr)
        return 0
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    out = [
        "# IdName | Kind | Type  (Type: Tech, Dirt, Ice, Water, Plastic, Grass, Snow, Rally, Bump, Scenery, Other)"
    ]
    for line in lines:
        if "[tmmaps]" not in line:
            continue
        m = LOG_PREFIX.match(line)
        rest = line[m.end() :].strip() if m else line.strip()
        rest = ESCAPE_PREFIX.sub("", rest).strip()
        if not rest or rest.startswith("---") or "Format:" in rest:
            continue
        parts = rest.split("|", 1)
        if len(parts) != 2:
            continue
        id_name = parts[0].strip()
        kind = parts[1].strip()
        if not id_name:
            continue
        typ = block_type_from_name(id_name)
        out.append(f"{id_name} | {kind} | {typ}")
    path.write_text("\n".join(out) + "\n", encoding="utf-8")
    return len(out) - 1


def main() -> None:
    for name in VISTA_FILES:
        path = REPO / name
        n = clean_file(path)
        if n:
            print(f"Cleaned {n} blocks -> {path}")


if __name__ == "__main__":
    main()
