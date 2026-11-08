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
- PCWPIX.COM — pixel-coordinate addressing test.\n- PCWRRAM.COM — read-only dump of the default Roller-RAM pointer table.
- Matching .lst and .lbl files — assembler listing and labels.

The sources use ORG 0100h. In z80asm 1.8, ORG changes the address used for labels and branch references but does not write 256 padding bytes to the output. CP/M loads the first byte of a .COM file at address 0100h.

The build script checks the first machine-code bytes of each program and rejects implausibly large COM files. This verifies binary layout, not runtime behaviour.

## PCWAYTST

The user has confirmed that PCWAYTST assembles, runs and exits cleanly in Joyce. It writes a tone configuration to the dK'Tronics AY-3-8912 ports and polls BDOS function 6. Joyce does not emulate the dK'Tronics board, so sound output has not been verified.

## PCWGFXT

The user has confirmed that PCWGFXT displays the full-screen alternating pattern, clears the bitmap and exits cleanly in Joyce.

It temporarily maps screen banks 1 and 2 into F1h/F2h, writes the existing bitmap area, restores the CP/M Plus TPA banks, and does not modify Roller-RAM or video-controller registers.

## PCWGRID

The user has confirmed that PCWGRID draws the repeated 8x8 border-and-diagonal cells, clears the bitmap and exits cleanly in Joyce.

The 720x256 screen is organised as 90 columns x 32 rows of 8x8 cells. Each cell is eight consecutive bytes; the video controller fetches successive horizontal character cells at an eight-byte stride.

## PCWPIX — pixel-coordinate test

PCWPIX introduces a PLOT_SET routine. The caller supplies x in DE and y in BC (B=0). The routine calculates:

    offset = (y >> 3) * 720 + (x & 0xFFF8) + (y & 7)
    address = 0x5930 + offset

It then sets one pixel using an MSB-first mask table. The routine preserves DE and BC, and expects the caller to clip coordinates to x=0..719 and y=0..255. It runs while physical screen banks 1 and 2 are mapped into the F1h/F2h CPU slots; the code and stack remain in the other CP/M banks.

The test clears the screen, draws a 256-pixel diagonal, a full-width horizontal line at y=128, a full-height vertical line at x=360, and marks the remaining screen corners. It then waits for a key, clears the screen and returns to CP/M.

The diagonal helps verify bit order; the long cross checks the coordinate-to-address calculation; the corner marks exercise the lower/right limits. The test does not modify Roller-RAM or video-controller registers.

### Test procedure

1. Use a copy of your Joyce CP/M disk image.
2. Copy PCWPIX.COM onto it.
3. Boot CP/M and run:

       PCWPIX

4. Expect a diagonal in the upper-left portion of the display, a horizontal line through the middle, a vertical line through the middle, and white pixels at the screen corners. Press a key; the screen should clear and CP/M should return.

**Status:** PCWAYTST, PCWGFXT and PCWGRID have been confirmed by the user to assemble/run in Joyce and exit cleanly. PCWPIX is new and has not yet been assembled or runtime-tested by the user. None of these tests has yet been confirmed on physical PCW 9256 hardware.


## PCWDECO — decoded Roller-RAM diagnostic

Run `PCWDECO` in Joyce. It reads the same default 512-byte Roller-RAM table as PCWRRAM, but decodes each 16-bit entry and prints 256 values in the form:

    01:3550 01:3551 ...

The first field is the physical 16 KB memory block. The second is the decoded byte offset within that block. The decode is:

    block = word >> 13
    offset = (word & 7) + 2 * (word & 0x1FF8)

The program only reads the table and prints the results; it does not alter Roller-RAM, screen memory, or video-controller registers. The decoded list is needed before replacing PCWPIX's fixed-base calculation with per-scanline Roller-RAM addressing.
