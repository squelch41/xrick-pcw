# Amstrad PCW port work

This directory contains the native Z80/CP/M port work for
[ xrick ](https://github.com/zpqrtbnk/xrick).

**Status:** the PCW screen, sprite renderer and first original level room are
being brought up. PCWROOM draws the original map and a static Rick sprite;
this is not yet a playable Rick Dangerous port.

## First target

- Amstrad PCW 9256
- CP/M Plus (to be confirmed against the actual test environment)
- 720 x 256 monochrome display
- dK'Tronics AY-3-8912 sound interface
- Rick Dangerous I first

## Files

- `PCWAYTST.ASM` — minimal CP/M transient-program sound test.
- `PCWROOM.ASM` — full-screen first-room render using the original map, tiles and Rick sprite.
- `tools/convert_pc_room.py` — expands the original map, converts the PC tiles and composites Rick into a full-screen image.
- `PORTING_NOTES.md` — initial source audit and proposed architecture.

## Sound-test status

The assembly is a proposed smoke test, not yet assembled or verified.
Build it as a flat binary with origin 0100h, name it `PCWAYTST.COM`, and
test first in Joyce, then on the real PCW with the dK'Tronics interface.

The assumed dK'Tronics AY ports (A9h read, AAh register select, ABh data
write) and the board's register-7 behaviour must be verified before treating
this as validated hardware code.

## Development principles

- Keep all PCW work on the `pcw-port` branch.
- Do not change upstream xrick code until the game-engine and data dependencies
  have been audited.
- Prefer a small native Z80 implementation over trying to port SDL or the
  desktop audio backend.
- Keep the first milestone deliberately small: prove sound, keyboard input,
  screen access and a sprite blitter independently.
