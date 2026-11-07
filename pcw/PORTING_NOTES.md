# PCW porting notes

## Scope

Target: Amstrad PCW 9256, native Z80/CP/M program, using the dK'Tronics AY-3-8912 sound interface. Initial game target is Rick Dangerous I only. This is a native port, not an SDL build or emulator wrapper.

## Confirmed dK'Tronics interface

John Elliott's PCW hardware reference documents:

- `AAh`: select AY register
- `ABh`: write selected AY register
- `A9h`: read selected AY register

AY register 14 is the joystick input/output port. Keep bit 6 of AY register 7 clear when port A is to be read as input. `PCWAYTST.ASM` has been confirmed by the user to assemble, run and exit cleanly in Joyce. Joyce does not emulate the dK'Tronics interface, so sound output has not yet been verified.

## PCW display memory

The 720x256 screen is monochrome and can be treated as 90 columns x 32 rows of 8x8 cells. The controller fetches the 8 pixel bytes for a cell contiguously, then advances by eight bytes to the next horizontal cell. The complete visible bitmap is 23,040 bytes.

For normal CP/M Plus mapping on the 256 KB PCW 9256, the smoke tests map physical screen bank 1 into CPU slot F1h and physical bank 2 into slot F2h. The visible bitmap begins at bank 1 offset 1930h and continues into bank 2 offset 0000h, ending at bank 2 offset 332Fh. The default Roller-RAM at bank 2 offset 3600h is left untouched.

For a pixel coordinate (x,y), with x=0..719 and y=0..255, the planned byte offset from the bitmap start is:

    (y >> 3) * 720 + (x & 0xFFF8) + (y & 7)

The low three bits of x select a pixel mask. `PCWPIX.ASM` tests this formula using an MSB-first pixel-mask table. The diagonal is intended to verify bit order visually. It is not yet confirmed by the user.

Do not alter Roller-RAM in the game until a separate diagnostic can save and restore the original video state.

## CPU and memory

The Z80 runs at approximately 4 MHz (with wait states depending on the machine). The machine has banked 16 KB memory blocks; the normal CP/M transient program area is not equivalent to all physical RAM being freely available.

Avoid assuming a full 320x200 byte-per-pixel framebuffer will fit in the TPA. A packed 1-bit 320x200 buffer requires 8,000 bytes; the display mapping and blitter still need measurement.

## Upstream source

The current upstream repository has an `xrick/` directory at its root. Common source is in `xrick/src/`; RD1 source is in `xrick/src/rd1/`; RD2 is separate in `xrick/src/rd2/`. The detailed audit is in `UPSTREAM_AUDIT.md`.

## Milestones

1. Verify sound hardware on the physical PCW; Joyce cannot verify dK'Tronics audio.
2. Confirm pixel addressing and bit order with `PCWPIX`.
3. Implement and benchmark clipped 8x8 tile and sprite drawing routines in Z80 assembly.
4. Decide how to scale/convert the source game's 320x200 image to the PCW's 720x256 display.
5. Port a minimal playable RD1 room, initially with static map and one controllable Rick sprite.
6. Add collision, scrolling, sound effects and remaining game logic.

## References

- Upstream source: https://github.com/zpqrtbnk/xrick
- John Elliott, PCW hardware reference: https://www.seasip.info/Unix/Joyce/hardware.pdf
- PCW video memory notes: https://github.com/Zigazou/amstrad-pcw-technical-info/tree/master/video-memory
