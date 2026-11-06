# PCW porting notes

## Source audit

The upstream project has common code plus separate RD1 and RD2 engines. The
desktop platform layer and audio backend are not suitable dependencies for a
3.4 MHz Z80 / CP/M target. The PCW version should be a native implementation
of the necessary game logic and data formats, not an attempt to compile the
SDL desktop application unchanged.

Initial upstream areas to inspect in detail:

- `src/sysvid.c` — video presentation/platform boundary
- `src/syskbd.c` — keyboard mapping
- `src/system.c` — startup, timing and shutdown
- `src/xrick.c` — game selection/startup
- `src/rd1/` — first game's engine and data
- `src/rd2/` — second game's engine and data

The first target should be Rick Dangerous I only.

## Display

The PCW display is 720 x 256 monochrome. Its video controller uses a
256-entry roller-RAM table rather than a conventional linear framebuffer.
A native renderer must understand the screen memory layout and the current
CP/M screen environment before taking over video.

The roller RAM may make vertical scrolling useful, but horizontal scrolling
is constrained. Likely strategies include a reduced viewport, tile redraw,
dirty rectangles and software scrolling. These need measurement on hardware.

## CPU and memory

The Z80 runs at approximately 3.4 MHz. The machine uses banked 16 KB memory
blocks; the normal CP/M transient program area is not equivalent to all
physical RAM being freely available.

The first prototype should remain within the normal TPA and avoid paging
memory until a bank manager and a safe restoration strategy have been
designed. Rendering should favour preconverted sprite masks, bounded redraws
and compact data structures.

## dK'Tronics sound

The current prototype assumes the following AY-3-8912 interface:

- A9h: read selected register
- AAh: select AY register
- ABh: write selected register

Treat this mapping as provisional until checked against reliable board
documentation and the actual interface. AY register 14 is associated with
the joystick interface; joystick reads should be kept separate from sound
playback. Preserve the correct port-direction setting in register 7.

## Milestones

1. Verify the dK'Tronics tone test in Joyce and on real hardware.
2. Verify CP/M Plus keyboard polling and clean exit.
3. Probe the screen-memory and roller-RAM setup without leaving the machine
   in a broken display state.
4. Implement and benchmark a tiny monochrome sprite blitter.
5. Audit RD1 game logic, graphics and level data for feasible conversion.
6. Build a small playable room before attempting a full game.

## References

- https://github.com/zpqrtbnk/xrick
- https://wiki.retrotechcollection.com/Amstrad_PCW_Hardware_Reference_%28John_Elliott%29
- https://www.systemed.net/pcw/hardware.html
