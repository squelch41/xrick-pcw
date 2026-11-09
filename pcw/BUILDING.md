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
- PCWPIX.COM — Roller-RAM pixel, filled-rectangle, clearing and edge-clipping test.
- PCWRRAM.COM — read-only dump of the default Roller-RAM pointer table.
- PCWDECO.COM — exports the raw Roller-RAM table to RRAM.TXT.
- PCWBLIT.COM — Roller-RAM-based, byte-aligned 8x8 tile blitter test.
- PCWTRANS.COM — byte-aligned transparent 8x8 masked-sprite test.
- PCWSUB.COM — arbitrary-pixel-position transparent 8x8 sprite test.
- PCWBMP.COM — variable-size transparent bitmap test.
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

PCWPIX introduces a PLOT_SET routine. The caller supplies x in DE and y in BC (B=0). For every pixel, it reads the corresponding 16-bit Roller-RAM entry at B600h+2*y, decodes its physical bank and byte offset, and adds the horizontal byte offset (x & 0FFF8h). Physical bank 1 is mapped into F1h and bank 2 into F2h, so the decoded pointer is accessed through the matching CPU address window. The routine sets one pixel using an MSB-first mask table and preserves DE and BC. The caller must clip coordinates to x=0..719 and y=0..255.

The clear routine also follows the Roller-RAM pointers, clearing the 90 visible bytes of each scanline at eight-byte address intervals. It does not assume that the bitmap occupies one contiguous CPU address range. The test draws a filled rectangle, clears a smaller rectangle inside it, and draws a rectangle whose requested bounds extend beyond the right and bottom edges; the test loop clips those bounds to x=719 and y=255.

The test clears the screen, draws a 256-pixel diagonal, a full-width horizontal line at y=128, a full-height vertical line at x=360, and marks the remaining screen corners. It then waits for a key, clears the screen and returns to CP/M.

The diagonal helps verify bit order; the long cross checks the coordinate-to-address calculation; the corner marks exercise the lower/right limits. The test does not modify Roller-RAM or video-controller registers.

### Test procedure

1. Use a copy of your Joyce CP/M disk image.
2. Copy PCWPIX.COM onto it.
3. Boot CP/M and run:

       PCWPIX

4. Expect a diagonal in the upper-left portion of the display, a horizontal line through the middle, a vertical line through the middle, and white pixels at the screen corners. Press a key; the screen should clear and CP/M should return.

**Status:** PCWAYTST, PCWGFXT and PCWGRID have been confirmed by the user to assemble/run in Joyce and exit cleanly. PCWPIX is new and has not yet been assembled or runtime-tested by the user. None of these tests has yet been confirmed on physical PCW 9256 hardware.


## PCWDECO — Roller-RAM export

Run `PCWDECO` in Joyce. It creates or replaces `RRAM.TXT` on the currently logged-in CP/M drive and returns to CP/M. The file contains all 256 raw 16-bit Roller-RAM words, 16 per line, printed high byte first as four hexadecimal digits followed by a space. This deliberately preserves the original values without assuming a pointer-decoding formula.

The program uses CP/M sequential file operations and writes complete 128-byte records. The unused end of each record is padded with spaces, so the file remains readable as ordinary text. Copy `RRAM.TXT` from the CP/M disk image to the host and paste its contents into the chat.

The program snapshots the table before restoring the normal CP/M Plus bank mapping. It does not modify Roller-RAM, screen memory, or video-controller registers. If file creation or writing fails, it displays an error message; check that the disk is not write-protected and has free directory entries and space.

## PCWBLIT — 8x8 tile blitter test

Run `PCWBLIT` in Joyce. It clears the display and draws several opaque 8x8 patterns using `DRAW_TILE`. The routine accepts a pointer to eight source bytes, an x coordinate aligned to eight pixels, and a y coordinate. For each of the eight output rows it looks up and decodes that scanline's Roller-RAM entry, then writes one byte at the appropriate horizontal cell address.

The test includes diamond, outline, cross, checkerboard and diagonal patterns. It also draws an 8x8 tile at x=712, y=248, the bottom-right valid tile origin. Press a key to clear the screen and return to CP/M.

This first blitter is intentionally limited to opaque tiles aligned on an eight-pixel boundary. It is not yet a general transparent or arbitrarily positioned sprite renderer. The build check verifies the COM file's initial machine-code layout, not its runtime behaviour.


## PCWTRANS — transparent 8x8 sprite test

Run `PCWTRANS` in Joyce. It clears the display, draws an 80x64 checkerboard panel, then overlays two masked sprites. The mask convention is 1 = preserve the existing destination pixel and 0 = replace it with the corresponding pixel from the sprite. Each output byte is calculated as:

    destination = (destination AND mask) OR pixels

The routine uses the same Roller-RAM lookup as the opaque blitter, so each sprite row is written through the correct physical screen bank. Coordinates remain byte-aligned and the test uses complete 8x8 tiles. Press a key to clear the display and return to CP/M.

The user has confirmed that the revised test displays the checkerboard panel and both sprites in Joyce. The build script checks the COM header and file size; it does not verify runtime behaviour. This diagnostic has not been tested on physical PCW hardware.


## PCWSUB — arbitrary-position transparent sprite test

Run `PCWSUB` in Joyce. It draws a 128x64 checkerboard panel and overlays transparent 8x8 sprites at x=203 and x=245, deliberately using horizontal alignments of three and five pixels rather than byte boundaries. A third sprite begins at x=717 to exercise clipping at the right edge of the 720-pixel display.

For each source row, `DRAW_MASKED_SPRITE` shifts the mask and pixel data into the left destination byte and, when needed, the adjacent byte eight addresses later. It combines each part with the existing screen using `(old AND mask) OR pixels`, preserving pixels outside the sprite. The routine clips the sprite at the right and bottom edges and skips x coordinates outside the screen.

This is a new diagnostic and has not yet been assembled or run by the user. The build script's binary checks verify only the COM header and file size, not the shifting or clipping behaviour. Test in Joyce before using the routine in the game.


## PCWBMP — variable-size transparent bitmap test

Run `PCWBMP` in Joyce. It draws a checkerboard panel, then overlays a 24x13 bitmap and a 32x21 bitmap at non-byte-aligned x positions. A third 32x21 bitmap is placed at x=697, so its rightmost nine pixels are clipped at the screen edge while the remaining 23 pixels stay visible. Press a key to clear the screen and return to CP/M.

The reusable routine is `DRAW_MASKED_BITMAP`. Its inputs are HL=source address, DE=x in pixels, C=y in scanlines, B=width in bytes (each byte represents eight pixels), and A=height in scanlines. The bitmap width is therefore a multiple of eight pixels; height can be any non-zero value from 1 to 255. Source data is row-major, with each scanline containing one MASK,PIXELS byte pair for each source byte. Mask bits set to 1 preserve the destination; mask bits set to 0 draw the corresponding pixel bit. Pixel bit 7 is the leftmost pixel.

The routine shifts each source byte across one or two Roller-RAM-addressed screen bytes, preserving pixels outside the bitmap. It clips at the right edge (x=719) and bottom edge (y=255). The original Xrick PC sprite data is arranged as four 8-pixel columns by 21 rows (32x21) and uses two-bit CGA mask/picture values; it is not directly compatible with this monochrome row-major format. A conversion step will be needed to translate the original sprite assets into the PCW format.

This diagnostic is new and has not yet been assembled or run by the user. The build script verifies the COM header and file size only; it does not prove runtime correctness. Test it in Joyce before using this routine in the game.
