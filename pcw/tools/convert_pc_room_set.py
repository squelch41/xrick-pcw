#!/usr/bin/env python3
"""Generate the first three connected PC rooms, collision flags and compressed rasters."""
from __future__ import annotations
import re
import sys
from pathlib import Path

ROOMS = 3
SCREEN_WIDTH, SCREEN_HEIGHT = 720, 256
ROOM_WIDTH, ROOM_HEIGHT = 256, 192
SCREEN_BYTES = SCREEN_WIDTH * SCREEN_HEIGHT // 8

def strip_comments(source: str) -> str:
    source = re.sub(r"/\*[\s\S]*?\*/", "", source)
    return re.sub(r"//[^\n]*", "", source)

def extract(source: str, name: str) -> str:
    m = re.search(r"\b" + re.escape(name) + r"\s*(?:\[[^\]]*\]\s*)*=\s*\{", source)
    if not m:
        raise ValueError(f"could not find initializer for {name}")
    start, depth = source.find("{", m.start()), 0
    for i in range(start, len(source)):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return source[start + 1:i]
    raise ValueError(f"unterminated initializer for {name}")

def values(text: str) -> list[int]:
    tokens = re.findall(r"0[xX][0-9a-fA-F]+|0[0-7]+|[0-9]+", text)
    return [int(t, 16) if t.lower().startswith("0x") else
            int(t, 8) if len(t) > 1 and t.startswith("0") else int(t)
            for t in tokens]

def visible_tiles(src: str, submap: int, frow: int) -> tuple[list[int], int]:
    blocks = values(extract(src, "map_blocks"))
    bnums = values(extract(src, "map_bnums"))
    submaps = values(extract(src, "map_submaps"))
    page, base = submaps[submap * 4:submap * 4 + 2]
    index = base + ((2 * frow) & 0xfff8)
    grid = [[0] * 32 for _ in range(44)]
    for br in range(11):
        for bc in range(8):
            if index >= len(bnums):
                raise ValueError(f"submap {submap}: block table overrun")
            block = bnums[index]
            index += 1
            chunk = blocks[block * 16:(block + 1) * 16]
            if len(chunk) != 16:
                raise ValueError(f"submap {submap}: invalid block {block}")
            for ty in range(4):
                for tx in range(4):
                    grid[br * 4 + ty][bc * 4 + tx] = chunk[ty * 4 + tx]
    return [v for row in grid[8:32] for v in row], page

def tile_flags(src: str, page: int) -> list[int]:
    matches = list(re.finditer(r"\bmap_eflg_c\s*\[[^\]]*\]\s*=\s*\{([^}]*)\}", src))
    if len(matches) < 2:
        raise ValueError("could not locate ST and PC tile-flag tables")
    enc = values(matches[-1].group(1))
    offset = 0x10 if page == 1 else 0
    result: list[int] = []
    for p in range(offset, offset + 16, 2):
        count, value = enc[p:p + 2]
        if not count:
            raise ValueError("zero-length tile flag run")
        result.extend([value] * count)
    if len(result) != 256:
        raise ValueError(f"expanded tile flags have {len(result)} entries")
    return result

def render_background(tile_ids: list[int], page: int, tile_source: str, flags: list[int]) -> bytearray:
    words = values(extract(tile_source, "tiles_banks"))
    bank_no = 3 if page == 1 else 2
    bank = words[bank_no * 256 * 8:(bank_no + 1) * 256 * 8]
    if len(bank) != 256 * 8:
        raise ValueError(f"tile bank {bank_no} is incomplete")
    pixels = [bytearray(ROOM_WIDTH) for _ in range(ROOM_HEIGHT)]
    for ty in range(24):
        for tx in range(32):
            tile = tile_ids[ty * 32 + tx]
            tile_flag = flags[tile]
            for sy in range(8):
                word = bank[tile * 8 + sy]
                row = pixels[ty * 8 + sy]
                for x in range(8):
                    colour = (word >> (14 - 2 * x)) & 3
                    # Keep the compact 0/2 -> black, 1/3 -> white mapping
                    # generally. Reveal red (index 2) on climbable ladder
                    # and one-way platform tiles, where it carries structure.
                    white = (colour & 1) != 0
                    if colour == 2 and (tile_flag & 0x12):
                        white = True
                    row[tx * 8 + x] = int(white)
    output = bytearray(SCREEN_BYTES)
    for y in range(SCREEN_HEIGHT):
        sy = (y * ROOM_HEIGHT) // SCREEN_HEIGHT
        source_row = pixels[sy]
        dest = y * (SCREEN_WIDTH // 8)
        for x in range(SCREEN_WIDTH):
            if source_row[(x * ROOM_WIDTH) // SCREEN_WIDTH]:
                output[dest + (x >> 3)] |= 1 << (7 - (x & 7))
    return output

def lzss_compress(data: bytes) -> bytes:
    """8-token groups: control bit 1=literal, 0=12-bit distance + 4-bit length."""
    positions: dict[int, list[int]] = {}
    output = bytearray()
    pos = 0
    while pos < len(data):
        control = 0
        tokens = bytearray()
        for bit in range(7, -1, -1):
            if pos >= len(data):
                break
            best_len = 0
            best_distance = 0
            if pos + 2 < len(data):
                key = (data[pos] << 16) | (data[pos + 1] << 8) | data[pos + 2]
                candidates = positions.get(key, ())
                for candidate in reversed(candidates):
                    distance = pos - candidate
                    if distance > 4096:
                        break
                    length = 3
                    while (length < 18 and pos + length < len(data)
                           and data[candidate + length] == data[pos + length]):
                        length += 1
                    if length > best_len:
                        best_len, best_distance = length, distance
                        if length == 18:
                            break
            if best_len >= 3:
                encoded = best_distance - 1
                tokens.append(encoded & 0xff)
                tokens.append(((encoded >> 8) << 4) | (best_len - 3))
                count = best_len
            else:
                control |= 1 << bit
                tokens.append(data[pos])
                count = 1
            for p in range(pos, pos + count):
                if p + 2 >= len(data):
                    continue
                key = (data[p] << 16) | (data[p + 1] << 8) | data[p + 2]
                bucket = positions.setdefault(key, [])
                bucket.append(p)
                if len(bucket) > 64:
                    del bucket[0]
            pos += count
        output.append(control)
        output.extend(tokens)
    return bytes(output)

def lzss_decompress(data: bytes, expected_size: int) -> bytes:
    output = bytearray()
    pos = 0
    while len(output) < expected_size:
        if pos >= len(data):
            raise ValueError("compressed background ended before the raster was complete")
        control = data[pos]
        pos += 1
        for bit in range(7, -1, -1):
            if len(output) >= expected_size:
                break
            if control & (1 << bit):
                if pos >= len(data):
                    raise ValueError("truncated LZSS literal")
                output.append(data[pos])
                pos += 1
            else:
                if pos + 1 >= len(data):
                    raise ValueError("truncated LZSS back-reference")
                low, meta = data[pos], data[pos + 1]
                pos += 2
                distance = (((meta & 0xf0) << 4) | low) + 1
                length = (meta & 0x0f) + 3
                if distance > len(output):
                    raise ValueError("LZSS back-reference precedes the raster")
                for _ in range(length):
                    output.append(output[-distance])
                    if len(output) == expected_size:
                        break
    if pos != len(data):
        raise ValueError("compressed background has unused trailing bytes")
    return bytes(output)

def db(label: str, data: bytes | list[int]) -> list[str]:
    lines = [label + ":"]
    for i in range(0, len(data), 16):
        lines.append("        DB      " + ",".join(f"0{v:02X}h" for v in data[i:i + 16]))
    return lines

def main() -> int:
    if len(sys.argv) != 5:
        print("usage: convert_pc_room_set.py dat_maps.c dat_tilesPC.c roomset.inc backgrounds.inc", file=sys.stderr)
        return 2
    try:
        maps = strip_comments(Path(sys.argv[1]).read_text(encoding="utf-8"))
        tiles = strip_comments(Path(sys.argv[2]).read_text(encoding="utf-8"))
        map_meta = values(extract(maps, "map_maps"))
        connectors = values(extract(maps, "map_connect"))
        if len(map_meta) < 5 or len(connectors) < ROOMS * 12:
            raise ValueError("map 0 metadata or connector records are incomplete")
        frow = map_meta[2]
        room_lines = [
            "; Generated by tools/convert_pc_room_set.py -- do not edit.",
            "; Collision flags and three 4-byte connector slots for each room."
        ]
        bg_lines = [
            "; Generated by tools/convert_pc_room_set.py -- do not edit.",
            "; Full screens and first-room scroll strips use 12-bit LZSS."
        ]
        compressed_sizes = []
        room_frows = []
        scroll_frows = []
        for room in range(ROOMS):
            room_frows.append(frow)
            records = connectors[room * 12:room * 12 + 12]

            # The first submap is taller than one viewport. The PC game scrolls
            # it in eight-tile steps while Rick falls down the right-hand shaft.
            # Pre-render the four successive viewports so the PCW version can
            # change both its background and collision grid at each scroll.
            scroll_count = 4 if room == 0 else 1
            for scroll in range(scroll_count):
                view_frow = (frow + scroll * 8) & 0xff
                if room == 0:
                    scroll_frows.append(view_frow)
                tile_ids, page = visible_tiles(maps, room, view_frow)
                if page not in (0, 1):
                    raise ValueError(f"room {room}: unsupported tile page {page}")
                flags = tile_flags(maps, page)
                collision = [flags[tile] for tile in tile_ids]
                if len(collision) != 768:
                    raise ValueError(f"room {room}: expected 768 collision cells")

                # The game only tests bits 4..6 (three collision flags).
                # Store two 4-bit values per byte; the Z80 expands them into
                # the writable one-byte-per-tile viewport at runtime.
                def pack_collision(cells: list[int]) -> bytes:
                    packed = bytearray()
                    for i in range(0, len(cells), 2):
                        low = (cells[i] & 0x70) >> 4
                        high = (cells[i + 1] & 0x70) >> 4
                        packed.append(low | (high << 4))
                    return bytes(packed)

                suffix = "" if scroll == 0 else f"_SCROLL{scroll}"
                flag_label = f"PCW_ROOM{room}{suffix}_FLAGS"
                bg_label = f"PCW_ROOM{room}{suffix}_BG_COMP"
                raster = render_background(tile_ids, page, tiles, flags)

                if room == 0 and scroll > 0:
                    # A viewport scrolls by eight 8-pixel tiles. Store only
                    # the newly exposed 85-line strip, not a duplicate full
                    # 720x256 raster. The Z80 shifts the existing image up
                    # and decompresses this strip into its bottom 85 lines.
                    collision_data = pack_collision(collision[-(8 * 32):])
                    raster_data = raster[(256 - 85) * 90:]
                    expected_bytes = 85 * 90
                else:
                    collision_data = pack_collision(collision)
                    raster_data = raster
                    expected_bytes = SCREEN_BYTES

                room_lines += db(flag_label, collision_data)
                compressed = lzss_compress(raster_data)
                if lzss_decompress(compressed, expected_bytes) != raster_data:
                    raise ValueError(
                        f"room {room} scroll {scroll}: compressed background "
                        "failed round-trip validation"
                    )
                bg_lines += db(bg_label, compressed)
                bg_lines.append(f"{bg_label}_END:")
                compressed_sizes.append(len(compressed))

            room_lines += db(f"PCW_ROOM{room}_CONNECTORS", records)
            if room < ROOMS - 1:
                direction, _rowout, destination, rowin = records[4:8]
                if direction != 0 or destination != room + 1:
                    raise ValueError(
                        f"room {room}: expected right connector to room {room + 1}, "
                        f"got direction {direction:#04x}, destination {destination:#04x}"
                    )
                # Direct submap entry uses the original game's start viewport:
                # rowin - 0x10, with Rick positioned at local y=0x80.
                frow = (rowin - 0x10) & 0xff
        Path(sys.argv[3]).parent.mkdir(parents=True, exist_ok=True)
        Path(sys.argv[4]).parent.mkdir(parents=True, exist_ok=True)
        Path(sys.argv[3]).write_text("\n".join(room_lines) + "\n", encoding="ascii")
        Path(sys.argv[4]).write_text("\n".join(bg_lines) + "\n", encoding="ascii")
        print(
            f"Generated {ROOMS} rooms: packed collision maps and scroll strips, "
            f"{ROOMS * 12} connector bytes; compressed screens/scroll strips "
            + ", ".join(str(n) for n in compressed_sizes)
            + f" bytes (total {sum(compressed_sizes)}); "
            + "room entry frows " + ", ".join(f"{value:#04x}" for value in room_frows)
            + "; first-room scroll frows "
            + ", ".join(f"{value:#04x}" for value in scroll_frows) + "."
        )
    except (OSError, ValueError, IndexError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
