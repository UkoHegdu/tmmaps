#!/usr/bin/env python3
"""
Analyze block files per Vista: which blocks are Vista-specific vs common.
Expects: blocks.txt (Stadium), blocks_blue_bay.txt, blocks_green_coast.txt,
         blocks_red_island.txt, blocks_white_shore.txt in IdName | Kind | Type format.
Run clean-vista-blocks.py first if Vista files still have log format.
"""
from pathlib import Path
from collections import defaultdict

REPO = Path(__file__).resolve().parent

VISTA_FILES = {
    "Stadium": REPO / "blocks.txt",
    "Blue Bay": REPO / "blocks_blue_bay.txt",
    "Green Coast": REPO / "blocks_green_coast.txt",
    "Red Island": REPO / "blocks_red_island.txt",
    "White Shore": REPO / "blocks_white_shore.txt",
}


def parse_blocks(path: Path) -> set[str]:
    if not path.exists():
        return set()
    out = set()
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("|", 2)
        if len(parts) >= 1:
            out.add(parts[0].strip())
    return out


def main() -> None:
    vista_blocks = {}
    all_ids = set()
    for vista, path in VISTA_FILES.items():
        blocks = parse_blocks(path)
        vista_blocks[vista] = blocks
        all_ids |= blocks

    # Per-Vista counts
    print("Blocks per Vista (from dumps; these are loaded in that environment):")
    for vista, blocks in vista_blocks.items():
        print(f"  {vista}: {len(blocks)}")
    print()

    # IdName -> list of Vistas that have it
    id_to_vistas = defaultdict(list)
    for vista, blocks in vista_blocks.items():
        for bid in blocks:
            id_to_vistas[bid].append(vista)

    # Vista-specific: only in one Vista
    print("Vista-specific blocks (only in one environment):")
    for vista, blocks in vista_blocks.items():
        only_here = [bid for bid in blocks if len(id_to_vistas[bid]) == 1]
        print(f"  {vista}: {len(only_here)} blocks only here")
    print()

    # Common: in more than one Vista
    common = {bid for bid, vlist in id_to_vistas.items() if len(vlist) > 1}
    print(f"Common blocks (in 2+ Vistas): {len(common)}")
    # How many Vistas each common block appears in
    vista_count = defaultdict(int)
    for bid in common:
        vista_count[len(id_to_vistas[bid])] += 1
    for n in sorted(vista_count.keys(), reverse=True):
        print(f"  in {n} Vistas: {vista_count[n]} blocks")
    print()

    # Blocks in all 5 Vistas
    in_all = [bid for bid, vlist in id_to_vistas.items() if len(vlist) == 5]
    print(f"Blocks in all 5 Vistas: {len(in_all)}")
    if in_all and len(in_all) <= 30:
        for bid in sorted(in_all)[:30]:
            print(f"  {bid}")
    elif in_all:
        for bid in sorted(in_all)[:15]:
            print(f"  {bid}")
        print(f"  ... and {len(in_all) - 15} more")
    print()

    # Blocks in exactly 2 Vistas: list each block and which 2 Vistas
    in_two = [(bid, id_to_vistas[bid]) for bid, vlist in id_to_vistas.items() if len(vlist) == 2]
    in_two.sort(key=lambda x: (sorted(x[1]), x[0]))
    print(f"Blocks in exactly 2 Vistas ({len(in_two)}):")
    for bid, vlist in in_two:
        print(f"  {bid}")
        print(f"    -> {', '.join(sorted(vlist))}")
    print()

    # Blocks in exactly 4 Vistas: list each block and which 4 Vistas
    in_four = [(bid, id_to_vistas[bid]) for bid, vlist in id_to_vistas.items() if len(vlist) == 4]
    in_four.sort(key=lambda x: (sorted(x[1]), x[0]))
    print(f"Blocks in exactly 4 Vistas ({len(in_four)}):")
    for bid, vlist in in_four:
        print(f"  {bid}")
        print(f"    -> {', '.join(sorted(vlist))}")


if __name__ == "__main__":
    main()
