# Building and testing the PCW port

## Requirements

- Fedora (or another Linux system) with z80asm version 1.8 or compatible.
- Python 3, used only for binary-layout checks.

On Fedora:

    sudo dnf install z80asm

## Assemble

From the repository root:

    cd pcw
    sh build.sh

The output files are placed in pcw/build/:

- PCWAYTST.COM — dK'Tronics AY sound and CP/M keyboard smoke test.
- PCWGFXT.COM — full-screen bitmap fill/clear test.
- PCWGRID.COM — 8x8 cell-grid addressing test.
- Matching .lst and .lbl files — assembler listing and labels.

The sources use ORG 0100h. In z80asm 1.8, ORG changes the address used for labels and branch references but does not write 256 padding bytes to the output. CP/M loads the first byte of a .COM file at address 0100h.

The build script checks the first machine-code bytes of each program and rejects implausibly large COM files. This verifies binary layout, not runtime behaviour.

## PCWAYTST

Run PCWAYTST under CP/M. It writes a tone configuration to the dK'Tronics AY-3-8912 ports, polls BDOS function 6, then mutes and warm-boots to CP/M. The user has confirmed that it assembles and runs in Joyce and exits cleanly. Joyce does not emulate the dK'Tronics board, so sound output remains untested.

## PCWGFXT

This test is intended for the standard 256 KB PCW CP/M Plus memory layout used by the PCW 9256. It assumes the transient program is running with banks 4, 5, 6 and 7 mapped at F0h, F1h, F2h and F3h respectively.

It temporarily maps screen banks 1 and 2 into the F1h/F2h address slots, writes an alternating bit pattern across the existing screen bitmap, restores the TPA banks 5 and 6, and waits for a key. On keypress it clears the bitmap and warm-boots CP/M.

The user has confirmed that PCWGFXT runs correctly in Joyce, displays its full-screen pattern, clears the bitmap and exits cleanly.

The test does **not** write to Roller-RAM or change the video-controller registers. It disables interrupts while the screen banks are mapped and restores the normal TPA mapping before calling BDOS.

## PCWGRID — next graphics test

PCWGRID writes the same distinctive 8-byte tile pattern to all 2,880 8x8 cells in the existing 720x256 bitmap (90 cells across by 32 down). The pattern has a border and a diagonal, so it should reveal whether groups of eight consecutive bytes correspond to 8x8 cells and show the bit order within each byte.

It uses the same screen-memory range as PCWGFXT: bank 1 offsets 1930h-3FFFh followed by bank 2 offsets 0000h-332Fh. It does not modify Roller-RAM or the video-controller registers. It clears the image after a keypress and returns to CP/M.

### Test procedure

1. Use a copy of your Joyce CP/M disk image.
2. Copy PCWGRID.COM onto it.
3. Boot CP/M and run:

       PCWGRID

4. Expect a full-screen grid of small 8x8 outlined cells with a diagonal detail in each. Press a key; the screen should clear and CP/M should return.

If the pattern is unexpected or CP/M does not return cleanly, report what appears. Do not test the new program on physical hardware until it has passed in Joyce.

**Status:** PCWAYTST and PCWGFXT have been confirmed by the user to assemble/run in Joyce and exit cleanly. PCWGRID is newly added and has not yet been assembled or runtime-tested by the user. None of these tests has yet been confirmed on the physical PCW 9256.
