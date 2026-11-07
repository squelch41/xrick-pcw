#!/bin/sh
# Build and sanity-check the PCW AY sound/keyboard smoke test.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$HERE"

Z80ASM=${Z80ASM:-z80asm}
if ! command -v "$Z80ASM" >/dev/null 2>&1; then
    echo "Error: z80asm was not found. Install it with: sudo dnf install z80asm" >&2
    exit 1
fi

mkdir -p build
"$Z80ASM" \
    --list=build/PCWAYTST.lst \
    --label=build/PCWAYTST.lbl \
    --output=build/PCWAYTST.COM \
    PCWAYTST.ASM

python3 - build/PCWAYTST.COM <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
data = path.read_bytes()
expected = bytes((0x3E, 0x00, 0xD3, 0xAA, 0x3E, 0xF4, 0xD3, 0xAB))

if not data.startswith(expected):
    actual = " ".join(f"{b:02X}" for b in data[:8])
    wanted = " ".join(f"{b:02X}" for b in expected)
    raise SystemExit(
        f"Binary sanity check failed.\nExpected first 8 bytes: {wanted}\n"
        f"Actual first bytes:       {actual}"
    )

if len(data) >= 0xFF00:
    raise SystemExit(f"Binary is too large for a conventional CP/M COM file ({len(data)} bytes)")

print(f"Built {path} ({len(data)} bytes)")
print("Binary header OK; ORG 0100h has not introduced a 256-byte file prefix.")
print("This verifies assembly layout only; it does not prove the program works on a PCW.")
PY
