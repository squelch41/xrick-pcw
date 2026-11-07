; PCWGRID.ASM
; 8x8 tile-grid / screen-addressing test for the PCW 9256.
;
; Writes a distinctive 8-byte tile pattern to every 8x8 cell in the
; existing 720x256 screen bitmap (90 columns x 32 rows of 8x8 cells).
; Waits for a key, clears the bitmap, and warm-boots CP/M.
;
; Does not modify Roller-RAM or video-controller registers.
; Uses the same screen-bank mapping already exercised by PCWGFXT.
;
; IMPORTANT: this is still an emulator-first diagnostic. Test in Joyce
; before considering physical-hardware use.

        ORG     0100h

START:
        DI
        LD      A,081h
        OUT     (0F1h),A
        LD      A,082h
        OUT     (0F2h),A

        ; Screen bitmap is 23040 bytes = 2880 contiguous 8-byte cells.
        ; Begin at bank 1 offset 1930h (visible screen start) mapped at 5930h.
        ; The destination naturally crosses from F1h to F2h at 8000h.
        LD      HL,00B40h
        LD      (TILE_COUNT),HL
        LD      DE,05930h

DRAW_TILES:
        LD      HL,TILE_PATTERN
        LD      BC,00008h
        LDIR
        LD      HL,(TILE_COUNT)
        DEC     HL
        LD      (TILE_COUNT),HL
        LD      A,H
        OR      L
        JR      NZ,DRAW_TILES

        ; Restore CP/M Plus TPA banks before using BDOS.
        LD      A,085h
        OUT     (0F1h),A
        LD      A,086h
        OUT     (0F2h),A
        EI

WAIT_KEY:
        LD      C,06h
        LD      E,0FFh
        CALL    0005h
        OR      A
        JR      Z,WAIT_KEY

        ; Clear the screen bitmap with a zero-filled 8-byte tile.
        DI
        LD      A,081h
        OUT     (0F1h),A
        LD      A,082h
        OUT     (0F2h),A

        LD      HL,00B40h
        LD      (TILE_COUNT),HL
        LD      DE,05930h

CLEAR_TILES:
        LD      HL,BLANK_TILE
        LD      BC,00008h
        LDIR
        LD      HL,(TILE_COUNT)
        DEC     HL
        LD      (TILE_COUNT),HL
        LD      A,H
        OR      L
        JR      NZ,CLEAR_TILES

        LD      A,085h
        OUT     (0F1h),A
        LD      A,086h
        OUT     (0F2h),A
        EI
        JP      0000h

; Eight scanline bytes for one 8x8 cell. The outer border and diagonal
; make both the 8-byte cell grouping and bit order visible.
TILE_PATTERN:
        DB      0FFh,081h,082h,084h,088h,090h,0A0h,0FFh

BLANK_TILE:
        DB      00h,00h,00h,00h,00h,00h,00h,00h

; Writable counter in the program's own TPA bank.
TILE_COUNT:
        DW      0000h

        END
