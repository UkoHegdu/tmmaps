#!/usr/bin/env python3
"""
List all blocks that get role "Other" (blocks that are never used by the generator).
Shows block name and its Type.
"""
from pathlib import Path
from collections import defaultdict

REPO = Path(__file__).resolve().parent
BLOCKS_TXT = REPO / "blocks.txt"

def role_from_name(name: str) -> str:
    n = name
    if "Start" in n and "Slope2Start" not in n and "LoopStart" not in n:
        return "Start"
    if "Finish" in n:
        return "Finish"
    if "Checkpoint" in n:
        return "Checkpoint"
    if "Slope2" in n:
        return "Slope2"
    if "SlopeBase" in n or "Slope" in n:
        return "Slope"
    if "Curve5" in n:
        return "Turn5"
    if "Curve4" in n:
        return "Turn4"
    if "Curve3" in n:
        return "Turn3"
    if "Curve2" in n:
        return "Turn2"
    if "Curve1" in n:
        return "Turn1"
    if "TurboRoulette" in n:
        return "TurboR"
    if "SpecialTurbo2" in n:
        return "Turbo2"
    if "SpecialTurbo" in n:
        return "Turbo1"
    if "SpecialBoost2" in n:
        return "Booster2"
    if "SpecialBoost" in n:
        return "Booster1"
    if "NoEngine" in n:
        return "NoEngine"
    if "SlowMotion" in n:
        return "SlowMotion"
    if "Fragile" in n:
        return "Fragile"
    if "NoSteering" in n:
        return "NoSteer"
    if "Reset" in n and "Special" in n:
        return "Reset"
    if "Cruise" in n:
        return "Cruise"
    if "NoBrake" in n:
        return "NoBrake"
    if "TrackWallTo" in n:
        return "End"
    if "ToRoad" in n or "ToDecoWall" in n or "ToTrackWall" in n or "ToOpen" in n:
        return "Connector"
    if "Ramp" in n or "Narrow" in n or "Wave" in n:
        if "RampLow" in n or "RampMed" in n:
            return "Cool1"
        return "Cool2"
    if "Straight" in n or "Base" in n:
        return "Straight"
    return "Other"

def main():
    other_blocks = defaultdict(list)  # Type -> list of block names
    
    for line in BLOCKS_TXT.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("|", 2)
        if len(parts) < 3:
            continue
        id_name = parts[0].strip()
        kind = parts[1].strip()
        typ = parts[2].strip()
        
        # Only track blocks (scenery is separate)
        if kind == "Scenery" or typ == "Scenery":
            continue
            
        role = role_from_name(id_name)
        if role == "Other":
            other_blocks[typ].append(id_name)
    
    print(f"Blocks with role 'Other' (never used by generator): {sum(len(v) for v in other_blocks.values())} total\n")
    
    for typ in sorted(other_blocks.keys()):
        blocks = sorted(other_blocks[typ])
        print(f"Type '{typ}': {len(blocks)} blocks")
        # Group by pattern to see what kinds of blocks
        patterns = defaultdict(list)
        for b in blocks:
            if "Chicane" in b:
                patterns["Chicane"].append(b)
            elif "Branch" in b:
                patterns["Branch"].append(b)
            elif "Switch" in b:
                patterns["Switch"].append(b)
            elif "Transition" in b:
                patterns["Transition"].append(b)
            elif "Loop" in b:
                patterns["Loop"].append(b)
            elif "Multilap" in b:
                patterns["Multilap"].append(b)
            elif "Diag" in b:
                patterns["Diag (no Straight/Base/Curve)"].append(b)
            else:
                patterns["Other pattern"].append(b)
        
        for pattern, blist in sorted(patterns.items()):
            print(f"  {pattern}: {len(blist)}")
            for b in sorted(blist)[:10]:
                print(f"    - {b}")
            if len(blist) > 10:
                print(f"    ... and {len(blist) - 10} more")
        print()

if __name__ == "__main__":
    main()
