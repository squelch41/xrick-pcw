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

for name in PCWAYTST PCWGFXT PCWGRID; do
    "$Z80ASM" \
        --list="build/$name.lst" \
        --label="build/$name.lbl" \
        --output="build/$name.COM" \
        "$name.ASM"
done

python3 - build/PCWAYTST.COM build/PCWGFXT.COM build/PCWGRID.COM <<'PY'
from pathlib import Path
import sys

checks = {
    "PCWAYTST.COM": bytes((0x3E, 0x00, 0xD3, 0xAA, 0x3E, 0xF4, 0xD3, 0xAB)),
    "PCWGFXT.COM": bytes((0xF3, 0x3E, 0x81, 0xD3, 0xF1, 0x3E, 0x82, 0xD3, 0xF2)),
    "PCWGRID.COM": bytes((0xF3, 0x3E, 0x81, 0xD3, 0xF1, 0x3E, 0x82, 0xD3, 0xF2,
                         0x21, 0x40, 0x0B)),
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

    if len(data) >= 0xFF00:
        raise SystemExit(f"{path.name}: too large for a conventional CP/M COM file ({len(data)} bytes)")

    print(f"Built {path} ({len(data)} bytes); binary header OK.")

print("ORG 0100h has not introduced a 256-byte file prefix.")
print("These checks verify assembly layout only, not runtime behaviour.")
PY
