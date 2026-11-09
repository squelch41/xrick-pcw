# PCW porting notes

## Scope

Target: Amstrad PCW 9256, native Z80/CP/M program, using the dK'Tronics AY-3-8912 sound interface. Initial game target is Rick Dangerous I only. This is a native port, not an SDL build or emulator wrapper.

## Confirmed dK'Tronics interface

John Elliott's PCW hardware reference documents:

- `AAh`: select AY register
- `ABh`: write selected AY register
- `A9h`: read selected AY register

AY register 14 is the joystick input/output port. Keep bit 6 of AY register 7 clear when port A is to be read as input. `PCWAYTST.ASM` has been confirmed by the user to assemble, run and exit cleanly in Joyce. Joyce does not emulate the dK'Tronics interface, so sound output has not yet been verified.

## PCW display memory and Roller-RAM

The 50 Hz PCW display is 720x256 monochrome pixels (90x32 character cells). The video controller has a 256-entry Roller-RAM table, one 16-bit pointer per displayed scanline. For each scanline it fetches 90 pixel bytes, taking successive bytes at an interval of eight addresses. Thus the byte for horizontal pixel coordinate x is at:

    decoded_scanline_pointer + (x & 0xFFF8)

The pixel within that byte is selected by x's low three bits. Confirm the bit polarity/order against a physical display test before relying on the mask table.

### Roller-RAM pointer decoding

The words are stored little-endian in memory. Given the 16-bit word value:

    physical_bank = (word >> 13) & 7
    offset_in_bank = (word & 7) + 2 * (word & 1FF8h)

The top three bits select the physical 16 KB bank. The remaining bits encode the byte offset using the formula above. The pointer table is at physical bank 2, offset 3600h by default (CPU address B600h when bank 2 is mapped into slot F2h).

The user's PCW 9256 dump confirms this format. Examples:

- `3238h` -> bank 1, offset 2470h
- `33A0h` -> bank 1, offset 2740h
- `4048h` -> bank 2, offset 0090h
- `56C8h` -> bank 2, offset 2D90h
- `2C98h` -> bank 1, offset 1930h
- `5830h` -> bank 2, offset 3060h

The dump shows the expected eight-line interleave: within each group of eight Roller-RAM entries, the decoded starting addresses increment by one. The next group advances by 720 bytes. The full table must be treated as authoritative; do not replace it with a guessed linear base or assume that the displayed scanlines map monotonically through one CPU address range.

The standard 9256 memory map places screen memory in bank 1 offsets 1930h-3FFFh and bank 2 offsets 0000h-332Fh. The default Roller-RAM is in bank 2 offsets 3600h-37FFh. These regions are documented in the PCW hardware reference. Keep Roller-RAM unchanged during normal drawing; use its entries as read-only pointers unless a separate diagnostic explicitly saves and restores it.

### Pixel addressing procedure

For a pixel coordinate (x,y), with x=0..719 and y=0..255:

1. Read Roller-RAM entry y (word at table + 2*y).
2. Decode its physical bank and offset using the formula above.
3. Access the corresponding physical bank and calculate offset + (x & 0FFF8h).
4. Set or clear the bit selected by x & 7, after confirming the PCW's left-to-right bit order.

`PCWPIX.ASM` has now been rewritten to look up and decode the Roller-RAM entry for every scanline. It maps physical bank 1 into CPU slot F1h and bank 2 into F2h, then selects the matching CPU address window for each pointer. This implementation is committed but still needs to be assembled and visually checked in Joyce; in particular, the pixel bit order and the table's runtime location should be confirmed.

## CPU and memory

The Z80 runs at approximately 4 MHz (with wait states depending on the machine). The machine has banked 16 KB memory blocks; the normal CP/M transient program area is not equivalent to all physical RAM being freely available.

Avoid assuming a full 320x200 byte-per-pixel framebuffer will fit in the TPA. A packed 1-bit 320x200 buffer requires 8,000 bytes; the display mapping and blitter still need measurement.

## Upstream source

The current upstream repository has an `xrick/` directory at its root. Common source is in `xrick/src/`; RD1 source is in `xrick/src/rd1/`; RD2 is separate in `xrick/src/rd2/`. The detailed audit is in `UPSTREAM_AUDIT.md`.

## Milestones

1. Verify sound hardware on the physical PCW; Joyce cannot verify dK'Tronics audio.
2. Use the captured Roller-RAM table to implement and verify per-scanline pixel addressing and bit order. The user has confirmed the `PCWPIX` diagnostic visually in Joyce, including drawing, clearing, and the lower/right screen edges.
3. Extend and benchmark the tile and sprite blitters. The user has confirmed `PCWBLIT`, `PCWTRANS`, `PCWSUB` and `PCWBMP` in Joyce, including arbitrary horizontal alignment and clipping.
4. Render original game artwork. The user has confirmed that `PCWROOM` displays the first original PC room and Rick's idle sprite correctly across the full 720x256 PCW raster.
5. Add the first interactive movement test. `PCWPLAY` uses the original two-pixel left/right step and the original five-frame walk cycles, with the background restored before each move. Its build and Joyce test are pending.
6. Add jumping and tile-based collision, then replace full-screen redraws with a faster dirty-rectangle background restore.
7. Add scrolling, ladders, entities, sound effects and the remaining game logic.

## References

- Upstream source: https://github.com/zpqrtbnk/xrick
- John Elliott, PCW hardware reference: https://www.seasip.info/Unix/Joyce/hardware.pdf
- PCW hardware guide: https://pcwwiki2.com/doku.php?id=en:hardware_guide
- PCW video memory notes: https://github.com/Zigazou/amstrad-pcw-technical-info/tree/master/video-memory
