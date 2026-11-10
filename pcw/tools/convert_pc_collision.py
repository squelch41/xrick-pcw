#!/usr/bin/env python3
"""Generate tile collision flags for a selected PC map submap."""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

MAP_ROWS = 24
MAP_COLS = 32
BLOCK_ROWS = 11
BLOCK_COLS = 8


def strip_comments(source: str) -> str:
    source = re.sub(r"/\*[\s\S]*?\*/", "", source)
    return re.sub(r"//[^\n]*", "", source)


def parse_c_integer(token: str) -> int:
    token = token.strip()
    if token.lower().startswith("0x"):
        return int(token, 16)
    if len(token) > 1 and token.startswith("0"):
        return int(token, 8)
    return int(token, 10)


def extract_initializer(source: str, name: str) -> str:
    pattern = re.compile(
        rf"\b{re.escape(name)}\s*(?:\[[^\]]*\]\s*)*=\s*\{{"
    )
    match = pattern.search(source)
    if not match:
        raise ValueError(f"could not find initializer for {name}")
    start = source.find("{", match.start())
    depth = 0
    for pos in range(start, len(source)):
        if source[pos] == "{":
            depth += 1
        elif source[pos] == "}":
            depth -= 1
            if depth == 0:
                return source[start + 1:pos]
    raise ValueError(f"unterminated initializer for {name}")


def parse_values(initializer: str) -> list[int]:
    tokens = re.findall(r"0[xX][0-9a-fA-F]+|0[0-7]+|[0-9]+", initializer)
    return [parse_c_integer(token) for token in tokens]


def load_pc_tile_flags(source: str, page: int) -> list[int]:
    # The source contains separate ST and PC initializers. Comments have
    # already been stripped, so choose the final declaration (the PC table)
    # instead of relying on the removed PLATFORM_PC comment.
    matches = list(re.finditer(
        r"\bmap_eflg_c\s*\[[^\]]*\]\s*=\s*\{([^}]*)\}",
        source,
    ))
    if len(matches) < 2:
        raise ValueError("could not locate both ST and PC map_eflg_c tables")
    encoded = parse_values(matches[-1].group(1))
    if len(encoded) != 32:
        raise ValueError(f"PC map_eflg_c has {len(encoded)} bytes; expected 32")

    offset = 0x10 if page == 1 else 0x00
    expanded: list[int] = []
    for pos in range(offset, offset + 16, 2):
        count, value = encoded[pos], encoded[pos + 1]
        if count == 0:
            raise ValueError("tile-flag table contains a zero-length run")
        expanded.extend([value] * count)
    if len(expanded) != 256:
        raise ValueError(
            f"expanded PC tile flags contain {len(expanded)} entries; expected 256"
        )
    return expanded


def load_visible_tile_map(source: str, submap_number: int | None = None, frow: int | None = None) -> tuple[list[list[int]], int]:
    clean = strip_comments(source)
    blocks = parse_values(extract_initializer(clean, "map_blocks"))
    block_numbers = parse_values(extract_initializer(clean, "map_bnums"))
    submaps = parse_values(extract_initializer(clean, "map_submaps"))
    map_starts = parse_values(extract_initializer(clean, "map_maps"))

    if len(blocks) != 256 * 16:
        raise ValueError(f"map_blocks has {len(blocks)} entries; expected 4096")
    if len(map_starts) < 5 or len(submaps) < 4:
        raise ValueError("first-map metadata is incomplete")

    _start_x, _start_y, map_frow, map_submap_number, _tune = map_starts[:5]
    if submap_number is None:
        submap_number = map_submap_number
    if frow is None:
        frow = map_frow
    if submap_number < 0:
        raise ValueError("submap number must be non-negative")
    submap_base = submap_number * 4
    page = submaps[submap_base]
    block_base = submaps[submap_base + 1]
    if page not in (0, 1):
        raise ValueError(f"selected submap uses unexpected tile page {page}")

    block_index = block_base + ((2 * frow) & 0xFFF8)
    tile_map = [[0] * MAP_COLS for _ in range(44)]
    row = col = 0
    for _block_row in range(BLOCK_ROWS):
        for _block_col in range(BLOCK_COLS):
            if block_index >= len(block_numbers):
                raise ValueError("map_bnums is too short")
            block_id = block_numbers[block_index]
            block_index += 1
            if not 0 <= block_id < 256:
                raise ValueError(f"invalid block number {block_id}")
            block = blocks[block_id * 16:(block_id + 1) * 16]
            pos = 0
            for _ in range(4):
                tile_map[row][col] = block[pos]
                col += 1
                tile_map[row][col] = block[pos + 1]
                col += 1
                tile_map[row][col] = block[pos + 2]
                col += 1
                tile_map[row][col] = block[pos + 3]
                row += 1
                col -= 3
                pos += 4
            row -= 4
            col += 4
        row += 4
        col = 0

    visible = tile_map[8:32]
    if len(visible) != MAP_ROWS or any(len(line) != MAP_COLS for line in visible):
        raise ValueError("visible room is not 32x24 tiles")
    return visible, page


def generate_include(flags: list[int]) -> str:
    if len(flags) != MAP_ROWS * MAP_COLS:
        raise ValueError("collision grid must contain exactly 768 bytes")
    lines = [
        "; Generated by tools/convert_pc_collision.py -- do not edit.",
        "; Visible 32x24 map tile cells, row-major.",
        "; Values are original PC map_eflg flags for each tile.",
        "; Bits 6/5/4 = SOLID/SPAD/WAYUP; bit 2 = LETHAL.",
        "",
        "PCW_ROOM_FLAGS:",
    ]
    for row in range(MAP_ROWS):
        values = flags[row * MAP_COLS:(row + 1) * MAP_COLS]
        for start in range(0, MAP_COLS, 16):
            chunk = values[start:start + 16]
            lines.append("        DB      " + ",".join(f"{v:02X}h" for v in chunk))
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="path to xrick/src/rd1/dat_maps.c")
    parser.add_argument("output", type=Path, help="output Z80 assembler include")
    parser.add_argument("--submap", type=int, default=None,
                        help="select a submap number instead of map 0's starting submap")
    parser.add_argument("--frow", type=lambda value: int(value, 0), default=None,
                        help="override the map's first-row offset (e.g. 0xA0)")
    args = parser.parse_args()
    source_path, output_path = args.source, args.output

    try:
        source = source_path.read_text(encoding="utf-8")
        visible, page = load_visible_tile_map(source, args.submap, args.frow)
        tile_flags = load_pc_tile_flags(strip_comments(source), page)
        collision = [tile_flags[tile] for row in visible for tile in row]
        output = generate_include(collision)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(output, encoding="ascii", newline="\n")
    except (OSError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    solid = sum(bool(value & 0x70) for value in collision)
    lethal = sum(bool(value & 0x04) for value in collision)
    print(
        f"Generated map 0 submap {args.submap if args.submap is not None else 'default'} "
        f"(frow {args.frow if args.frow is not None else 'default'}) collision grid: 32x24, "
        f"{solid} blocking cells, {lethal} lethal cells -> {output_path}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
