; PCWBMP.ASM
; Variable-size transparent bitmap blitter for the Amstrad PCW 9256.
;
; DRAW_MASKED_BITMAP input:
;   HL = source data
;   DE = destination x in pixels (0..719)
;   C  = destination y in scanlines (0..255)
;   B  = bitmap width in bytes (each byte represents 8 pixels)
;   A  = bitmap height in scanlines (1..255)
;
; Source data is row-major. Each scanline contains B pairs:
;   MASK,PIXELS
; A mask bit of 1 preserves the existing screen pixel; a mask bit of 0
; replaces it with the corresponding bit from PIXELS. Bits are MSB-first.
; Width is a whole number of bytes (8-pixel groups); height is arbitrary.
;
; The destination x may be any pixel coordinate. Each source byte is
; shifted into one or two destination screen bytes. Right and bottom
; clipping are performed by the routine.
;
; This monochrome format is intended as the PCW-side sprite format.
; The original Xrick PC sprite data is 32x21 pixels (four 8-pixel columns
; by 21 rows) but is stored column-major and uses two-bit CGA pixels;
; a conversion step will be needed before feeding that original data here.

        ORG     0100h

START:
        DI
        LD      A,081h
        OUT     (0F1h),A
        LD      A,082h
        OUT     (0F2h),A

        CALL    CLEAR_SCREEN
        CALL    FILL_CHECKER_PANEL

        ; 24x13 bitmap at an x position with alignment 3.
        LD      HL,SPRITE_SMALL_24X13
        LD      DE,00CBh
        LD      BC,005Ah
        LD      B,03h
        LD      A,0Dh
        CALL    DRAW_MASKED_BITMAP

        ; 32x21 bitmap (the dimensions used by the original Xrick sprite
        ; cells) at an x position with alignment 4.
        LD      HL,SPRITE_LARGE_32X21
        LD      DE,00F4h
        LD      BC,0070h
        LD      B,04h
        LD      A,15h
        CALL    DRAW_MASKED_BITMAP

        ; Reuse the 32x21 source near the right edge. Its last 23 pixels
        ; remain visible, allowing us to see the right-edge clipping.
        LD      HL,SPRITE_LARGE_32X21
        LD      DE,02B9h
        LD      BC,00B4h
        LD      B,04h
        LD      A,15h
        CALL    DRAW_MASKED_BITMAP

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
        JP      Z,WAIT_KEY

        DI
        LD      A,081h
        OUT     (0F1h),A
        LD      A,082h
        OUT     (0F2h),A
        CALL    CLEAR_SCREEN
        LD      A,085h
        OUT     (0F1h),A
        LD      A,086h
        OUT     (0F2h),A
        EI
        JP      0000h

; Clear exactly the 90 visible bytes of each of the 256 scanlines.
CLEAR_SCREEN:
        LD      C,00h
CLEAR_LINE:
        LD      A,C
        CALL    GET_SCANLINE_PTR
        LD      B,90
        LD      DE,0008h
CLEAR_BYTE:
        LD      (HL),00h
        ADD     HL,DE
        DJNZ    CLEAR_BYTE
        INC     C
        JP      NZ,CLEAR_LINE
        RET

; Fill a 128x64 checkerboard panel at (160,80), using aligned 8x8 tiles.
FILL_CHECKER_PANEL:
        LD      A,80
        LD      (PANEL_Y),A
        LD      A,08h
        LD      (PANEL_ROWS),A
PANEL_ROW:
        LD      HL,00A0h
        LD      (PANEL_X),HL
        LD      A,10h
        LD      (PANEL_COLS),A
PANEL_COL:
        LD      HL,TILE_CHECK
        LD      DE,(PANEL_X)
        LD      A,(PANEL_Y)
        LD      C,A
        LD      B,00h
        CALL    DRAW_OPAQUE_TILE

        LD      HL,(PANEL_X)
        LD      DE,0008h
        ADD     HL,DE
        LD      (PANEL_X),HL
        LD      A,(PANEL_COLS)
        DEC     A
        LD      (PANEL_COLS),A
        JP      NZ,PANEL_COL

        LD      A,(PANEL_Y)
        ADD     A,08h
        LD      (PANEL_Y),A
        LD      A,(PANEL_ROWS)
        DEC     A
        LD      (PANEL_ROWS),A
        JP      NZ,PANEL_ROW
        RET

; Opaque, byte-aligned 8x8 tile used only for the test background.
DRAW_OPAQUE_TILE:
        LD      (TILE_SOURCE),HL
        LD      (TILE_X),DE
        LD      A,C
        LD      (TILE_Y),A
        LD      B,08h
OPAQUE_ROW:
        LD      HL,(TILE_SOURCE)
        LD      A,(HL)
        LD      (PIXELS),A
        INC     HL
        LD      (TILE_SOURCE),HL
        LD      A,(TILE_Y)
        CALL    GET_SCANLINE_PTR
        LD      DE,(TILE_X)
        ADD     HL,DE
        LD      A,(PIXELS)
        LD      (HL),A
        LD      A,(TILE_Y)
        INC     A
        LD      (TILE_Y),A
        DJNZ    OPAQUE_ROW
        RET

; Variable-width, variable-height masked bitmap routine.
; The source pointer advances through width_bytes pairs on every row.
DRAW_MASKED_BITMAP:
        PUSH    BC
        PUSH    DE
        LD      (BITMAP_SOURCE),HL
        LD      (BITMAP_X),DE
        LD      (HEIGHT_LEFT),A
        LD      A,C
        LD      (BITMAP_Y),A
        LD      A,B
        LD      (WIDTH_BYTES),A

        ; Empty dimensions or x outside the 720-pixel screen: do nothing.
        LD      A,(HEIGHT_LEFT)
        OR      A
        JP      Z,BITMAP_DONE
        LD      A,(WIDTH_BYTES)
        OR      A
        JP      Z,BITMAP_DONE

        LD      A,D
        CP      02h
        JP      C,BITMAP_X_VALID
        JP      NZ,BITMAP_DONE
        LD      A,E
        CP      0D0h
        JP      NC,BITMAP_DONE

BITMAP_X_VALID:
        LD      A,E
        AND     07h
        LD      (ALIGNMENT),A

        LD      HL,(BITMAP_X)
        LD      A,L
        AND     0F8h
        LD      L,A
        LD      (BASE_X),HL

        ; RIGHT_SHIFT = 8 - horizontal pixel alignment.
        LD      A,08h
        LD      B,A
        LD      A,(ALIGNMENT)
        LD      C,A
        LD      A,B
        SUB     C
        LD      (RIGHT_SHIFT),A

BITMAP_ROW:
        LD      A,(WIDTH_BYTES)
        LD      (COLS_LEFT),A
        LD      HL,(BASE_X)
        LD      (DEST_X),HL

BITMAP_COLUMN:
        ; Fetch one source mask/pixel byte pair.
        LD      HL,(BITMAP_SOURCE)
        LD      A,(HL)
        LD      (SOURCE_MASK),A
        INC     HL
        LD      A,(HL)
        LD      (SOURCE_PIXELS),A
        INC     HL
        LD      (BITMAP_SOURCE),HL

        ; Skip screen writes once this source byte begins at x >= 720.
        ; The source pointer still advances so the following row stays
        ; correctly aligned in the row-major source data.
        LD      HL,(DEST_X)
        LD      DE,02D0h
        OR      A
        SBC     HL,DE
        JP      NC,BITMAP_NEXT_COLUMN

        ; Left destination mask = (source mask >> alignment) | left pad.
        LD      A,(ALIGNMENT)
        OR      A
        JP      Z,LEFT_MASK_NO_SHIFT
        LD      B,A
        LD      A,(SOURCE_MASK)
LEFT_MASK_SHIFT:
        SRL     A
        DJNZ    LEFT_MASK_SHIFT
        JP      LEFT_MASK_SHIFTED
LEFT_MASK_NO_SHIFT:
        LD      A,(SOURCE_MASK)
LEFT_MASK_SHIFTED:
        LD      (LEFT_MASK),A

        LD      A,(ALIGNMENT)
        LD      E,A
        LD      D,00h
        LD      HL,LEFT_PAD_MASK
        ADD     HL,DE
        LD      A,(HL)
        LD      D,A
        LD      A,(LEFT_MASK)
        OR      D
        LD      (LEFT_MASK),A

        ; Left destination pixel data = source pixels >> alignment.
        LD      A,(ALIGNMENT)
        OR      A
        JP      Z,LEFT_PIXELS_NO_SHIFT
        LD      B,A
        LD      A,(SOURCE_PIXELS)
LEFT_PIXELS_SHIFT:
        SRL     A
        DJNZ    LEFT_PIXELS_SHIFT
        JP      LEFT_PIXELS_SHIFTED
LEFT_PIXELS_NO_SHIFT:
        LD      A,(SOURCE_PIXELS)
LEFT_PIXELS_SHIFTED:
        LD      (LEFT_PIXELS),A

        ; Right destination mask = (source mask << RIGHT_SHIFT) | right pad.
        LD      A,(RIGHT_SHIFT)
        LD      B,A
        LD      A,(SOURCE_MASK)
RIGHT_MASK_SHIFT:
        SLA     A
        DJNZ    RIGHT_MASK_SHIFT
        LD      (RIGHT_MASK),A

        LD      A,(ALIGNMENT)
        LD      E,A
        LD      D,00h
        LD      HL,RIGHT_PAD_MASK
        ADD     HL,DE
        LD      A,(HL)
        LD      D,A
        LD      A,(RIGHT_MASK)
        OR      D
        LD      (RIGHT_MASK),A

        ; Right destination pixel data = source pixels << RIGHT_SHIFT.
        LD      A,(RIGHT_SHIFT)
        LD      B,A
        LD      A,(SOURCE_PIXELS)
RIGHT_PIXELS_SHIFT:
        SLA     A
        DJNZ    RIGHT_PIXELS_SHIFT
        LD      (RIGHT_PIXELS),A

        ; Combine the left part with the existing screen byte.
        LD      A,(BITMAP_Y)
        CALL    GET_SCANLINE_PTR
        LD      DE,(DEST_X)
        ADD     HL,DE
        LD      A,(HL)
        LD      D,A
        LD      A,(LEFT_MASK)
        AND     D
        LD      D,A
        LD      A,(LEFT_PIXELS)
        OR      D
        LD      (HL),A

        ; If unaligned, combine the spill into the next screen byte too.
        LD      A,(ALIGNMENT)
        OR      A
        JP      Z,BITMAP_NEXT_COLUMN

        ; The next byte is visible only when DEST_X < 712.
        LD      HL,(DEST_X)
        LD      DE,02C8h
        OR      A
        SBC     HL,DE
        JP      NC,BITMAP_NEXT_COLUMN

        ; Fetch the scanline pointer again before addressing the right byte.
        LD      A,(BITMAP_Y)
        CALL    GET_SCANLINE_PTR
        LD      DE,(DEST_X)
        ADD     HL,DE
        LD      DE,0008h
        ADD     HL,DE

        LD      A,(HL)
        LD      D,A
        LD      A,(RIGHT_MASK)
        AND     D
        LD      D,A
        LD      A,(RIGHT_PIXELS)
        OR      D
        LD      (HL),A

BITMAP_NEXT_COLUMN:
        LD      HL,(DEST_X)
        LD      DE,0008h
        ADD     HL,DE
        LD      (DEST_X),HL

        LD      A,(COLS_LEFT)
        DEC     A
        LD      (COLS_LEFT),A
        JP      NZ,BITMAP_COLUMN

        ; Stop at y=255 instead of allowing the 8-bit y counter to wrap.
        LD      A,(BITMAP_Y)
        CP      0FFh
        JP      Z,BITMAP_DONE
        INC     A
        LD      (BITMAP_Y),A

        LD      A,(HEIGHT_LEFT)
        DEC     A
        LD      (HEIGHT_LEFT),A
        JP      NZ,BITMAP_ROW

BITMAP_DONE:
        POP     DE
        POP     BC
        RET

; Input A = scanline y. Return HL = CPU address of its first visible byte.
; Physical bank 1 maps at 4000h and bank 2 maps at 8000h.
GET_SCANLINE_PTR:
        PUSH    DE
        LD      L,A
        LD      H,00h
        ADD     HL,HL
        LD      DE,0B600h
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)

        LD      A,D
        AND     0E0h
        SRL     A
        SRL     A
        SRL     A
        SRL     A
        SRL     A
        LD      (BANK_NO),A

        LD      A,E
        AND     07h
        LD      (LOW_BITS),A
        LD      A,D
        AND     01Fh
        LD      H,A
        LD      L,E
        LD      A,L
        AND     0F8h
        LD      L,A
        SLA     L
        RL      H
        LD      A,(LOW_BITS)
        LD      E,A
        LD      D,00h
        ADD     HL,DE

        LD      A,(BANK_NO)
        CP      01h
        JP      Z,PTR_BANK1
        CP      02h
        JP      Z,PTR_BANK2
        LD      HL,0000h
        POP     DE
        RET
PTR_BANK1:
        LD      DE,04000h
        ADD     HL,DE
        POP     DE
        RET
PTR_BANK2:
        LD      DE,08000h
        ADD     HL,DE
        POP     DE
        RET

TILE_CHECK:
        DB      0AAh,055h,0AAh,055h,0AAh,055h,0AAh,055h

SPRITE_SMALL_24X13:
        DB      0FFh,00h,0FFh,00h,0FFh,00h
        DB      0FCh,03h,00h,0FFh,03Fh,0C0h
        DB      0F0h,00Fh,00h,0FFh,00Fh,0F0h
        DB      0E0h,01Fh,00h,0FFh,007h,0F8h
        DB      0C0h,03Fh,00h,0FFh,003h,0FCh
        DB      080h,07Fh,00h,0FFh,001h,0FEh
        DB      080h,07Fh,00h,0FFh,001h,0FEh
        DB      080h,07Fh,00h,0FFh,001h,0FEh
        DB      0C0h,03Fh,00h,0FFh,003h,0FCh
        DB      0E0h,01Fh,00h,0FFh,007h,0F8h
        DB      0F0h,00Fh,00h,0FFh,00Fh,0F0h
        DB      0FCh,03h,00h,0FFh,03Fh,0C0h
        DB      0FFh,00h,0FFh,00h,0FFh,00h

SPRITE_LARGE_32X21:
        DB      0FFh,00h,0FEh,01h,03Fh,0C0h,0FFh,00h
        DB      0FFh,00h,0FCh,03h,01Fh,0E0h,0FFh,00h
        DB      0FFh,00h,0F8h,07h,00Fh,0F0h,0FFh,00h
        DB      0FFh,00h,0F8h,07h,00Fh,0F0h,0FFh,00h
        DB      0FFh,00h,0F8h,07h,00Fh,0F0h,0FFh,00h
        DB      0FFh,00h,0FCh,03h,01Fh,0E0h,0FFh,00h
        DB      0FFh,00h,0FEh,01h,03Fh,0C0h,0FFh,00h
        DB      0FFh,00h,0FFh,00h,0FFh,00h,0FFh,00h
        DB      0FFh,00h,0E0h,01Fh,007h,0F8h,0FFh,00h
        DB      0FEh,01h,00h,0FFh,00h,0FFh,07Fh,080h
        DB      0FEh,01h,00h,0FFh,00h,0FFh,07Fh,080h
        DB      0FEh,01h,00h,0FFh,00h,0FFh,07Fh,080h
        DB      0FFh,00h,0E0h,01Fh,007h,0F8h,0FFh,00h
        DB      0FFh,00h,0E0h,01Fh,007h,0F8h,0FFh,00h
        DB      0FFh,00h,0E0h,01Fh,007h,0F8h,0FFh,00h
        DB      0FFh,00h,0F0h,00Fh,087h,078h,0FFh,00h
        DB      0FFh,00h,0F0h,00Fh,087h,078h,0FFh,00h
        DB      0FFh,00h,0F0h,00Fh,087h,078h,0FFh,00h
        DB      0FFh,00h,0F0h,00Fh,087h,078h,0FFh,00h
        DB      0FFh,00h,0F0h,00Fh,087h,078h,0FFh,00h
        DB      0FFh,00h,0F0h,00Fh,087h,078h,0FFh,00h

LEFT_PAD_MASK:
        DB      00h,080h,0C0h,0E0h,0F0h,0F8h,0FCh,0FEh
RIGHT_PAD_MASK:
        DB      0FFh,07Fh,03Fh,01Fh,00Fh,007h,003h,001h

PANEL_X:
        DW      0000h
PANEL_Y:
        DB      00h
PANEL_ROWS:
        DB      00h
PANEL_COLS:
        DB      00h
TILE_SOURCE:
        DW      0000h
TILE_X:
        DW      0000h
TILE_Y:
        DB      00h
PIXELS:
        DB      00h
BITMAP_SOURCE:
        DW      0000h
BITMAP_X:
        DW      0000h
BASE_X:
        DW      0000h
DEST_X:
        DW      0000h
BITMAP_Y:
        DB      00h
HEIGHT_LEFT:
        DB      00h
WIDTH_BYTES:
        DB      00h
COLS_LEFT:
        DB      00h
ALIGNMENT:
        DB      00h
RIGHT_SHIFT:
        DB      00h
SOURCE_MASK:
        DB      00h
SOURCE_PIXELS:
        DB      00h
LEFT_MASK:
        DB      00h
LEFT_PIXELS:
        DB      00h
RIGHT_MASK:
        DB      00h
RIGHT_PIXELS:
        DB      00h
BANK_NO:
        DB      00h
LOW_BITS:
        DB      00h

        END
