#!/bin/sh
# Build and sanity-check the PCW CP/M smoke tests.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$HERE"

Z80ASM=${Z80ASM:-z80asm}
if ! command -v "$Z80ASM" >/dev/null 2>&1; then
    echo "Error: z80asm was not found. Install it with: sudo dnf install z80asm" >&2
    exit 1
fi

mkdir -p build

python3 tools/convert_pc_sprites.py ../xrick/src/rd1/dat_spritesPC.c build/PCWSPRITES.INC
python3 tools/convert_pc_room.py ../xrick/src/rd1/dat_maps.c ../xrick/src/rd1/dat_tilesPC.c ../xrick/src/rd1/dat_spritesPC.c build/PCWSCREEN.INC
python3 tools/convert_pc_room.py ../xrick/src/rd1/dat_maps.c ../xrick/src/rd1/dat_tilesPC.c ../xrick/src/rd1/dat_spritesPC.c build/PCWPLAYBG.INC --background-only
python3 tools/convert_pc_player.py ../xrick/src/rd1/dat_spritesPC.c build/PCWPLAYSPRITES.INC
python3 tools/convert_pc_collision.py ../xrick/src/rd1/dat_maps.c build/PCWPLAYCOLLISION.INC
python3 tools/convert_pc_room_set.py ../xrick/src/rd1/dat_maps.c build/PCWROOMSET.INC

python3 - build/PCWROOMSET.INC <<'PY'
from pathlib import Path
import re
source = Path(__import__('sys').argv[1]).read_text(encoding='ascii')
for room in range(3):
    for kind in ('TILES', 'FLAGS'):
        label = f'PCW_ROOM{room}_{kind}:'
        if source.count(label) != 1:
            raise SystemExit(f'missing or duplicate {label}')
        start = source.index(label)
        end = source.find('\\nPCW_', start + len(label))
        section = source[start:] if end < 0 else source[start:end]
        values = re.findall(r'\\b([0-9A-F]{2})h\\b', section, re.IGNORECASE)
        if len(values) != 768:
            raise SystemExit(f'{label}: expected 768 bytes, found {len(values)}')
print('Room set OK: three 32x24 tile maps and collision maps.')
PY

python3 - build/PCWPLAYCOLLISION.INC <<'PY'
from pathlib import Path
import re
path = Path("build/PCWPLAYCOLLISION.INC")
source = path.read_text(encoding="ascii")
values = []
for line in source.splitlines():
    line = line.split(";", 1)[0]
    if re.match(r"^\s*DB\s+", line, re.IGNORECASE):
        values.extend(int(value, 16) for value in re.findall(r"\b([0-9A-F]{2})h\b", line, re.IGNORECASE))
if len(values) != 32 * 24:
    raise SystemExit(f"{path}: expected 768 collision flags, found {len(values)}")
print(f"Collision data OK: {len(values)} first-room tile flags.")
PY

for name in PCWAYTST PCWGFXT PCWGRID PCWPIX PCWRRAM PCWDECO PCWBLIT PCWTRANS PCWSUB PCWBMP PCWREAL PCWROOM PCWPLAY; do
    "$Z80ASM" \
        --list="build/$name.lst" \
        --label="build/$name.lbl" \
        --output="build/$name.COM" \
        "$name.ASM"
done

python3 - build/PCWAYTST.COM build/PCWGFXT.COM build/PCWGRID.COM build/PCWPIX.COM build/PCWRRAM.COM build/PCWDECO.COM build/PCWBLIT.COM build/PCWTRANS.COM build/PCWSUB.COM build/PCWBMP.COM build/PCWREAL.COM build/PCWROOM.COM build/PCWPLAY.COM <<'PY'
from pathlib import Path
import sys

checks = {
    "PCWAYTST.COM": bytes((0x3E, 0x00, 0xD3, 0xAA, 0x3E, 0xF4, 0xD3, 0xAB)),
    "PCWGFXT.COM": bytes((0xF3, 0x3E, 0x81, 0xD3, 0xF1, 0x3E, 0x82, 0xD3, 0xF2)),
    "PCWGRID.COM": bytes((0xF3, 0x3E, 0x81, 0xD3, 0xF1, 0x3E, 0x82, 0xD3, 0xF2,
                         0x21, 0x40, 0x0B)),
    "PCWPIX.COM": bytes((0xF3, 0x3E, 0x81, 0xD3, 0xF1, 0x3E, 0x82, 0xD3, 0xF2)),
    "PCWRRAM.COM": bytes((0xF3, 0x3E, 0x81, 0xD3, 0xF1, 0x3E, 0x82, 0xD3, 0xF2,
                         0x21, 0x00, 0xB6)),
    "PCWDECO.COM": bytes((0xF3, 0x3E, 0x81, 0xD3, 0xF1, 0x3E, 0x82, 0xD3, 0xF2,
                         0x21, 0x00, 0xB6)),
    "PCWBLIT.COM": bytes((0xF3, 0x3E, 0x81, 0xD3, 0xF1, 0x3E, 0x82, 0xD3, 0xF2)),
    "PCWTRANS.COM": bytes((0xF3, 0x3E, 0x81, 0xD3, 0xF1, 0x3E, 0x82, 0xD3, 0xF2)),
    "PCWSUB.COM": bytes((0xF3, 0x3E, 0x81, 0xD3, 0xF1, 0x3E, 0x82, 0xD3, 0xF2)),
    "PCWBMP.COM": bytes((0xF3, 0x3E, 0x81, 0xD3, 0xF1, 0x3E, 0x82, 0xD3, 0xF2)),
    "PCWREAL.COM": bytes((0xF3, 0x3E, 0x81, 0xD3, 0xF1, 0x3E, 0x82, 0xD3, 0xF2)),
    "PCWROOM.COM": bytes((0xF3, 0x3E, 0x82, 0xD3, 0xF2)),
    "PCWPLAY.COM": bytes((0xF3, 0x3E, 0x82, 0xD3, 0xF2)),
}

for filename in sys.argv[1:]:
    path = Path(filename)
    data = path.read_bytes()
    expected = checks[path.name]

    if not data.startswith(expected):
        actual = " ".join(f"{b:02X}" for b in data[:len(expected)])
        wanted = " ".join(f"{b:02X}" for b in expected)
        raise SystemExit(
            f"{path.name}: binary sanity check failed.\n"
            f"Expected: {wanted}\nActual:   {actual}"
        )

    if path.name == "PCWREAL.COM" and len(data) < 26040:
        raise SystemExit(f"{path.name}: converted sprite data is missing or incomplete ({len(data)} bytes)")

    if path.name == "PCWROOM.COM" and len(data) < 23040:
        raise SystemExit(f"{path.name}: full-screen image data is missing or incomplete ({len(data)} bytes)")

    if path.name == "PCWPLAY.COM" and len(data) < 32448:
        raise SystemExit(f"{path.name}: room background or scaled player frames are missing ({len(data)} bytes)")

    if path.name == "PCWPLAY.COM":
        labels = Path(f"build/{path.stem}.lbl").read_text(encoding="ascii")
        import re
        match = re.search(r"(?im)^\s*PCW_PLAYER_10:\s*equ\s*\$([0-9a-f]+)", labels)
        if not match or int(match.group(1), 16) != 0x8400:
            actual = match.group(1) if match else "missing"
            raise SystemExit(
                f"{path.name}: PCW_PLAYER_10 must start at 8400h "
                f"to avoid crossing a TPA bank boundary (found {actual})."
            )

        def label_address(name):
            found = re.search(
                rf"(?im)^\s*{re.escape(name)}:\s*equ\s*\$([0-9a-f]+)",
                labels,
            )
            if not found:
                raise SystemExit(f"{path.name}: missing {name} label")
            return int(found.group(1), 16)

        # The two jump poses are copied with LDIR before either video bank is
        # mapped over the TPA. Ensure neither 672-byte source crosses a 16KB
        # CPU window boundary.
        right_jump = label_address("PCW_PLAYER_06")
        left_jump = label_address("PCW_PLAYER_15")
        if not (0x4000 <= right_jump and right_jump + 672 <= 0x8000):
            raise SystemExit(
                f"{path.name}: right jump sprite crosses the F1 window ({right_jump:04X}h)"
            )
        if not (0x8000 <= left_jump and left_jump + 672 <= 0xC000):
            raise SystemExit(
                f"{path.name}: left jump sprite crosses the F2 window ({left_jump:04X}h)"
            )

    if len(data) >= 0xFF00:
        raise SystemExit(f"{path.name}: too large for a conventional CP/M COM file ({len(data)} bytes)")

    print(f"Built {path} ({len(data)} bytes); binary header OK.")

print("ORG 0100h has not introduced a 256-byte file prefix.")
print("These checks verify assembly layout only, not runtime behaviour.")
PY
