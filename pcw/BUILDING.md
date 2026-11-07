# Building the PCW hardware smoke test

## Requirements

- Fedora (or another Linux system) with z80asm version 1.8 or compatible.
- Python 3, used only for a small binary-layout check.

On Fedora:

    sudo dnf install z80asm

## Assemble

From the repository root:

    cd pcw
    sh build.sh

The output files are placed in pcw/build/:

- PCWAYTST.COM — CP/M transient program.
- PCWAYTST.lst — assembler listing.
- PCWAYTST.lbl — assembler label file.

The source uses ORG 0100h. In this assembler, ORG changes the address used for labels and branch references but does not write 256 padding bytes to the output. CP/M loads the first byte of a .COM file at address 0100h.

The build script checks that the generated file begins with the expected machine-code bytes for the first two AY register writes. This catches accidental file-offset/prefix problems. It is not an emulator test and does not verify the AY interface.

## First runtime test

1. Make a copy of your Joyce CP/M disk image before adding test files.
2. Add PCWAYTST.COM to that copied disk image using Joyce's disk-image/file tools, or another CP/M disk utility.
3. Boot CP/M in Joyce and run:

       PCWAYTST

4. The program is intended to produce a steady tone until a key is pressed, then mute the AY and return to CP/M.

The dK'Tronics ports in the source are AAh (register select) and ABh (data write), as documented in the PCW hardware reference. An emulator may not emulate the dK'Tronics board, so a silent result in Joyce would not by itself prove that the program is faulty. Keyboard exit/return behaviour can still be tested.

Status: the build script has not yet been run in the user's environment; no runtime test is claimed. Test on a copied disk image first, then on the real PCW with the dK'Tronics interface fitted.
