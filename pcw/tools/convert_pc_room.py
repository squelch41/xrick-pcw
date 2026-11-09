#!/usr/bin/env python3
"""Build a full-screen 720x256 monochrome image of the original first PC room."""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

SPRITE_COUNT = 0x9B
SPRITE_WIDTH = 32
SPRITE_HEIGHT = 0x15
SCREEN_WIDTH = 720
SCREEN_HEIGHT = 256
ROOM_WIDTH = 256
ROOM_HEIGHT = 192
SPRITE_ID = 0x0B


def strip_comments(source: str) -> str:
    source = re.sub(r"/\*[\s\S]*?\*/", "", source)
    return re.sub(r"//[^\n]*", "", source)


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


def parse_c_integer(token: str) -> int:
    token = token.strip()
    if token.lower().startswith("0x"):
        return int(token, 16)
    if len(token) > 1 and token.startswith("0"):
        return int(token, 8)
    return int(token, 10)


def parse_values(initializer: str) -> list[int]:
    tokens = re.findall(r"0[xX][0-9a-fA-F]+|0[0-7]+|[0-9]+", initializer)
    return [parse_c_integer(token) for token in tokens]


def fmt_byte(value: int) -> str:
    digits = f"{value:02X}"
    if digits[0] in "ABCDEF":
        digits = "0" + digits
    return f"{digits}h"


def convert_word_low_bit(word: int) -> int:
    """Project eight 2-bit CGA pixels to one bit, preserving left-to-right order."""
    result = 0
    for x in range(8):
        result |= ((word >> (14 - 2 * x)) & 1) << (7 - x)
    return result


def load_room(map_source: str, tile_source: str) -> list[list[int]]:
    maps = strip_comments(map_source)
    tiles = strip_comments(tile_source)
    blocks = parse_values(extract_initializer(maps, "map_blocks"))
    block_numbers = parse_values(extract_initializer(maps, "map_bnums"))
    submaps = parse_values(extract_initializer(maps, "map_submaps"))
    map_starts = parse_values(extract_initializer(maps, "map_maps"))
    tile_words = parse_values(extract_initializer(tiles, "tiles_banks"))

    if len(blocks) != 256 * 16:
        raise ValueError(f"map_blocks has {len(blocks)} entries; expected 4096")
    if len(tile_words) != 4 * 256 * 8:
        raise ValueError(f"tiles_banks has {len(tile_words)} words; expected 8192")
    if len(map_starts) < 5 or len(submaps) < 4:
        raise ValueError("map metadata is incomplete")

    # The first PC map's fields are {start_x, start_y, map_frow, submap, tune}.
    start_x, start_y, map_frow, submap_number, _tune = map_starts[:5]
    submap_base = submap_number * 4
    if submap_base + 3 >= len(submaps):
        raise ValueError("first map refers to a missing submap")
    page, block_base = submaps[submap_base], submaps[submap_base + 1]
    tile_bank = 3 if page == 1 else 2
    if tile_bank != 2:
        raise ValueError(f"first room unexpectedly selects tile bank {tile_bank}")

    # This is the original map_expand() traversal, including its 11x8 block loop.
    block_index = block_base + ((2 * map_frow) & 0xFFF8)
    tile_map = [[0] * 32 for _ in range(44)]
    row = col = 0
    for _block_row in range(11):
        for _block_col in range(8):
            if block_index >= len(block_numbers):
                raise ValueError("map block-number table is too short")
            block_id = block_numbers[block_index]
            block_index += 1
            if not 0 <= block_id < 256:
                raise ValueError(f"invalid block number {block_id}")
            block = blocks[block_id * 16:(block_id + 1) * 16]
            pos = 0
            for _ in range(4):
                tile_map[row][col] = block[pos]
                col += 1
                pos += 1
                tile_map[row][col] = block[pos]
                col += 1
                pos += 1
                tile_map[row][col] = block[pos]
                col += 1
                pos += 1
                tile_map[row][col] = block[pos]
                row += 1
                col -= 3
                pos += 1
            row -= 4
            col += 4
        row += 4
        col = 0

    # maps_paint() displays map_map rows 8..31, i.e. 24 rows of 32 tiles.
    visible = tile_map[8:32]
    if len(visible) != 24 or any(len(line) != 32 for line in visible):
        raise ValueError("expanded visible room is not 32x24 tiles")
    if any(tile < 0 or tile > 255 for line in visible for tile in line):
        raise ValueError("room contains an invalid tile number")
    return visible


def load_sprite_words(sprite_source: str) -> list[tuple[int, int]]:
    source = strip_comments(sprite_source)
    pair_re = re.compile(
        r"\{\s*(0[xX][0-9a-fA-F]+|0[0-7]+|[0-9]+)\s*,\s*"
        r"(0[xX][0-9a-fA-F]+|0[0-7]+|[0-9]+)\s*\}"
    )
    pairs = [
        (parse_c_integer(mask), parse_c_integer(picture))
        for mask, picture in pair_re.findall(source)
    ]
    expected = SPRITE_COUNT * 4 * SPRITE_HEIGHT
    if len(pairs) != expected:
        raise ValueError(
            f"sprite source has {len(pairs)} mask/picture pairs; expected {expected}"
        )
    if any(mask > 0xFFFF or picture > 0xFFFF for mask, picture in pairs):
        raise ValueError("sprite source contains a value wider than 16 bits")
    return pairs


def render_source_room(
    room: list[list[int]],
    tile_source: str,
    sprite_pairs: list[tuple[int, int]],
    include_rick: bool = True,
) -> list[bytearray]:
    tiles = strip_comments(tile_source)
    tile_words = parse_values(extract_initializer(tiles, "tiles_banks"))
    bank_start = 2 * 256 * 8
    bank = tile_words[bank_start:bank_start + 256 * 8]
    if len(bank) != 256 * 8:
        raise ValueError("PC tile bank 2 is incomplete")

    # Original room tiles are 8x8, 2bpp CGA words. Retain the low colour bit.
    pixels = [[0] * ROOM_WIDTH for _ in range(ROOM_HEIGHT)]
    for tile_y in range(24):
        for tile_x in range(32):
            tile_number = room[tile_y][tile_x]
            for scanline in range(8):
                word = bank[tile_number * 8 + scanline]
                for x in range(8):
                    pixels[tile_y * 8 + scanline][tile_x * 8 + x] = (
                        (word >> (14 - 2 * x)) & 1
                    )

    if include_rick:
        # Original map 0 begins at (x=8,y=139). The viewport's map origin is
        # (x=0,y=64), so this places the 32x21 Rick frame at source pixel (8,75).
        # Sprite data is sprite -> four 8-pixel columns -> 21 scanlines.
        sprite_base = SPRITE_ID * 4 * SPRITE_HEIGHT
        sprite_x, sprite_y = 8, 139 - 64
        for column in range(4):
            for scanline in range(SPRITE_HEIGHT):
                mask_word, picture_word = sprite_pairs[
                    sprite_base + column * SPRITE_HEIGHT + scanline
                ]
                for x in range(8):
                    dest_x = sprite_x + column * 8 + x
                    dest_y = sprite_y + scanline
                    if 0 <= dest_x < ROOM_WIDTH and 0 <= dest_y < ROOM_HEIGHT:
                        shift = 14 - 2 * x
                        mask = (mask_word >> shift) & 1
                        picture = (picture_word >> shift) & 1
                        pixels[dest_y][dest_x] = (
                            (pixels[dest_y][dest_x] & mask) | picture
                        )
    return [bytearray(line) for line in pixels]


def scale_to_pcw(source: list[bytearray]) -> bytearray:
    """Nearest-neighbour resample the 256x192 playfield to 720x256 monochrome."""
    output = bytearray(SCREEN_WIDTH * SCREEN_HEIGHT // 8)
    for y in range(SCREEN_HEIGHT):
        source_y = (y * ROOM_HEIGHT) // SCREEN_HEIGHT
        for x in range(SCREEN_WIDTH):
            source_x = (x * ROOM_WIDTH) // SCREEN_WIDTH
            if source[source_y][source_x]:
                output[y * (SCREEN_WIDTH // 8) + (x // 8)] |= 1 << (7 - (x & 7))
    return output


def generate_include(screen: bytearray, background_only: bool = False) -> str:
    if len(screen) != SCREEN_WIDTH * SCREEN_HEIGHT // 8:
        raise ValueError("rendered screen has an unexpected byte count")
    lines = [
        "; Generated by tools/convert_pc_room.py -- do not edit.",
        "; Full 720x256 PCW raster, row-major at 90 bytes per scanline.",
        ("; Original first PC room without the player sprite, resampled from 256x192."
         if background_only else
         "; Original first PC room and right-facing idle Rick, resampled from 256x192."),
        "; One bit per pixel, MSB first; each scanline contains 90 bytes.",
        "",
        ("PCW_BACKGROUND:" if background_only else "PCW_SCREEN:"),
    ]
    for y in range(SCREEN_HEIGHT):
        row = screen[y * 90:(y + 1) * 90]
        lines.append(f"; screen row {y:03d}")
        for start in range(0, 90, 15):
            lines.append(
                "        DB      " + ",".join(fmt_byte(v) for v in row[start:start + 15])
            )
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("maps", type=Path, help="path to xrick/src/rd1/dat_maps.c")
    parser.add_argument("tiles", type=Path, help="path to xrick/src/rd1/dat_tilesPC.c")
    parser.add_argument("sprites", type=Path, help="path to xrick/src/rd1/dat_spritesPC.c")
    parser.add_argument("output", type=Path, help="output Z80 assembler include")
    parser.add_argument("--background-only", action="store_true",
                        help="omit Rick so the player can be drawn dynamically")
    args = parser.parse_args()

    try:
        map_source = args.maps.read_text(encoding="utf-8")
        tile_source = args.tiles.read_text(encoding="utf-8")
        sprite_source = args.sprites.read_text(encoding="utf-8")
        room = load_room(map_source, tile_source)
        sprite_pairs = load_sprite_words(sprite_source)
        source_pixels = render_source_room(
            room, tile_source, sprite_pairs, include_rick=not args.background_only
        )
        screen = scale_to_pcw(source_pixels)
        output = generate_include(screen, background_only=args.background_only)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(output, encoding="ascii", newline="\n")
    except (OSError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    white = sum(screen)
    description = (
        "without Rick" if args.background_only
        else f"with Rick sprite {SPRITE_ID:#04x}"
    )
    print(
        f"Rendered original map 0 {description}: "
        f"{SCREEN_WIDTH}x{SCREEN_HEIGHT}, {len(screen)} screen bytes -> {args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
