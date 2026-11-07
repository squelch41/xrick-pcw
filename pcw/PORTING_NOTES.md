# PCW porting notes

## Scope

Target: Amstrad PCW 9256, native Z80/CP/M program, using the dK'Tronics AY-3-8912 sound interface. Initial game target is Rick Dangerous I only. This is a native port, not an SDL build or emulator wrapper.

## Confirmed dK'Tronics interface

John Elliott's PCW hardware reference documents:

- `AAh`: select AY register
- `ABh`: write selected AY register
- `A9h`: read selected AY register

AY register 14 is the joystick input/output port. Keep bit 6 of AY register 7 clear when port A is to be read as input. `PCWAYTST.ASM` configures channel A and polls the CP/M keyboard. The user has confirmed that it assembles, runs and exits cleanly in Joyce. Joyce does not emulate the dK'Tronics interface, so sound output has not yet been verified.

## PCW display

The PCW display is 720 x 256 monochrome, equivalent to 90 x 32 cells of 8 x 8 pixels. The video controller uses a 256-entry Roller-RAM table; each scan line has its own start address, and screen bytes are fetched at eight-byte intervals. The eight-byte cell storage arrangement is useful for writing 8x8 character/tile patterns contiguously. See the PCW video-memory reference and `UPSTREAM_AUDIT.md`.

The initial screen-memory test maps physical banks 1 and 2 into CPU address slots F1h and F2h, writes the visible bitmap range, restores the TPA mapping and avoids changing Roller-RAM. The user has confirmed that `PCWGFXT.ASM` displays the full-screen alternating pattern and exits cleanly in Joyce.

`PCWGRID.ASM` is the next test: it writes an 8-byte border-and-diagonal pattern into each 8x8 cell. This should validate the cell grouping and pixel bit order. It has not yet been user-tested.

Do not alter Roller-RAM in the game until a separate diagnostic can save and restore the original video state.

## CPU and memory

The Z80 runs at approximately 4 MHz (with wait states depending on the machine). The machine has banked 16 KB memory blocks; the normal CP/M transient program area is not equivalent to all physical RAM being freely available.

Avoid assuming a full 320x200 byte-per-pixel framebuffer will fit in the TPA. A packed 1-bit 320x200 buffer requires 8,000 bytes; the display mapping and blitter still need measurement.

## Upstream source

The current upstream repository has an `xrick/` directory at its root. Common source is in `xrick/src/`; RD1 source is in `xrick/src/rd1/`; RD2 is separate in `xrick/src/rd2/`. The detailed audit is in `UPSTREAM_AUDIT.md`.

## Milestones

1. Verify sound hardware on the physical PCW; Joyce cannot verify dK'Tronics audio.
2. Validate 8x8 cell addressing and bit order with `PCWGRID`.
3. Implement and benchmark clipped 8x8 tile and sprite drawing routines in Z80 assembly.
4. Decide whether to render directly in native PCW memory or use a compact staging buffer.
5. Port a minimal playable RD1 room, initially with static map and one controllable Rick sprite.
6. Add collision, scrolling, sound effects and remaining game logic.

## References

- Upstream source: https://github.com/zpqrtbnk/xrick
- John Elliott, PCW hardware reference: https://www.seasip.info/Unix/Joyce/hardware.pdf
- PCW video memory notes: https://github.com/Zigazou/amstrad-pcw-technical-info/tree/master/video-memory
