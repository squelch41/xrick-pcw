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
- PCWGFXT.COM — experimental PCW screen-memory smoke test.
- Matching .lst and .lbl files — assembler listing and labels.

The sources use ORG 0100h. In z80asm 1.8, ORG changes the address used for labels and branch references but does not write 256 padding bytes to the output. CP/M loads the first byte of a .COM file at address 0100h.

The build script checks the first machine-code bytes of each program and rejects implausibly large COM files. This verifies binary layout, not runtime behaviour.

## PCWAYTST

Run PCWAYTST under CP/M. It writes a tone configuration to the dK'Tronics AY-3-8912 ports, polls BDOS function 6, then mutes and warm-boots to CP/M. Joyce does not emulate the dK'Tronics board, so silence in Joyce is expected; the keyboard exit path can still be checked.

## PCWGFXT — experimental

This test is intended for the standard 256 KB PCW CP/M Plus memory layout used by the PCW 9256. It assumes the transient program is running with banks 4, 5, 6 and 7 mapped at F0h, F1h, F2h and F3h respectively.

It temporarily maps screen banks 1 and 2 into the F1h/F2h address slots, writes an alternating bit pattern across the existing screen bitmap, restores the TPA banks 5 and 6, and waits for a key. On keypress it clears the bitmap, restores the TPA map again, and warm-boots CP/M.

The test does **not** write to Roller-RAM, change the video-controller registers, or use CALL/PUSH/POP while the TPA banks are switched out. It disables interrupts during each bank-switching section and restores the normal TPA mapping before calling BDOS.

### Test procedure

1. Use a copy of your Joyce CP/M disk image.
2. Copy PCWGFXT.COM onto it.
3. Boot CP/M and run:

       PCWGFXT

4. You should see a full-screen alternating vertical pattern. Press a key; the program should clear the bitmap and return to CP/M.

The program writes to the display's existing screen-memory areas (bank 1: 1930h-3FFFh; bank 2: 0000h-332Fh). It deliberately leaves the default Roller-RAM at bank 2: 3600h-37FFh untouched.

If the display does not change, or CP/M does not return cleanly, stop testing and report exactly what happened. Do not try it on physical hardware until it behaves correctly in Joyce.

**Status:** PCWAYTST has been reported to assemble and run in Joyce. PCWGFXT is new experimental code and has not yet been assembled or runtime-tested by the user.
