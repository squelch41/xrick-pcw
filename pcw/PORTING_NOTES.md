# PCW porting notes

## Scope

Target: Amstrad PCW 9256, native Z80/CP/M program, using the dK'Tronics AY-3-8912 sound interface. Initial game target is Rick Dangerous I only. This is a native port, not an SDL build or emulator wrapper.

## Confirmed dK'Tronics interface

John Elliott's PCW hardware reference documents:

- `AAh`: select AY register
- `ABh`: write selected AY register
- `A9h`: read selected AY register

AY register 14 is the joystick input/output port. Keep bit 6 of AY register 7 clear when port A is to be read as input. The current `PCWAYTST.ASM` is still an unassembled, untested smoke-test source; it must be built and tried on Joyce and real hardware before being treated as working.

## PCW display

The PCW display is 720 x 256 monochrome. Its video controller uses a 256-entry Roller-RAM table. Each scan line is mapped independently and the controller fetches screen bytes at eight-byte intervals. See `UPSTREAM_AUDIT.md` for the proposed first viewport and rendering strategy.

Do not alter Roller-RAM in the game until a separate diagnostic can save and restore the original video state.

## CPU and memory

The Z80 runs at approximately 4 MHz (with wait states depending on the machine). The machine has banked 16 KB memory blocks; the normal CP/M transient program area is not equivalent to all physical RAM being freely available.

Avoid assuming a full 320x200 byte-per-pixel framebuffer will fit in the TPA. A packed 1-bit 320x200 buffer requires 8,000 bytes; the display mapping and blitter still need measurement.

## Upstream source

The current upstream repository has an `xrick/` directory at its root. Common source is in `xrick/src/`; RD1 source is in `xrick/src/rd1/`; RD2 is separate in `xrick/src/rd2/`. The detailed audit is in `UPSTREAM_AUDIT.md`.

## Milestones

1. Verify the dK'Tronics tone test and CP/M keyboard polling in Joyce and on the real PCW.
2. Probe video-controller state and Roller-RAM safely.
3. Implement and benchmark a packed monochrome sprite/tile blitter.
4. Port a small playable RD1 room.
5. Add scrolling, sound effects and the remaining game logic.

## References

- Upstream source: https://github.com/zpqrtbnk/xrick
- John Elliott, PCW hardware reference: https://www.seasip.info/Unix/Joyce/hardware.pdf
- PCW video memory notes: https://github.com/Zigazou/amstrad-pcw-technical-info/tree/master/video-memory
