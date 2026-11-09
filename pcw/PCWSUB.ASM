; PCWSUB.ASM
; Arbitrary horizontal-position transparent 8x8 sprite diagnostic.
;
; DRAW_MASKED_SPRITE input:
;   HL = 16-byte source (MASK,PIXELS pairs for eight rows)
;   DE = x coordinate (0..719)
;   C  = y coordinate (0..255)
;
; x need not be divisible by eight. Each source row is shifted across
; the two destination character-cell bytes as necessary. Pixels outside
; the 8x8 sprite are preserved. The right edge is clipped at x=719 and
; rows below y=255 are clipped.
;
; Roller-RAM table: physical bank 2, offset 3600h (CPU B600h while
; physical bank 2 is mapped into CPU slot F2h).

        ORG     0100h

START:
        DI
        LD      A,081h
        OUT     (0F1h),A
        LD      A,082h
        OUT     (0F2h),A

        CALL    CLEAR_SCREEN
        CALL    FILL_CHECKER_PANEL

        ; These x coordinates deliberately have different bit offsets:
        ; 203 mod 8 = 3; 245 mod 8 = 5.
        LD      HL,SPRITE_DIAMOND
        LD      DE,00CBh
        LD      BC,0068h
        CALL    DRAW_MASKED_SPRITE

        LD      HL,SPRITE_CROSS
        LD      DE,00F5h
        LD      BC,0080h
        CALL    DRAW_MASKED_SPRITE

        ; Exercise right-edge clipping: only the last three pixels of
        ; this sprite are on-screen (x=717..719).
        LD      HL,SPRITE_DIAMOND
        LD      DE,02CDh
        LD      BC,00B4h
        CALL    DRAW_MASKED_SPRITE

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
        JR      NZ,CLEAR_LINE
        RET

; Fill a 128x64 checkerboard panel at (160,80), using aligned tiles.
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
        JR      NZ,PANEL_COL

        LD      A,(PANEL_Y)
        ADD     A,08h
        LD      (PANEL_Y),A
        LD      A,(PANEL_ROWS)
        DEC     A
        LD      (PANEL_ROWS),A
        JR      NZ,PANEL_ROW
        RET

; Opaque, byte-aligned 8x8 tile used for the background only.
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

; Transparent 8x8 blitter with arbitrary horizontal pixel alignment.
DRAW_MASKED_SPRITE:
        PUSH    BC
        PUSH    DE
        LD      (SPRITE_SOURCE),HL
        LD      (SPRITE_X),DE
        LD      A,C
        LD      (SPRITE_Y),A

        ; Reject x coordinates outside the 720-pixel display.
        LD      A,D
        CP      02h
        JP      C,SPRITE_X_VALID
        JP      NZ,SPRITE_DONE
        LD      A,E
        CP      0D0h
        JR      NC,SPRITE_DONE

SPRITE_X_VALID:
        ; Save x modulo 8 and the aligned base byte coordinate.
        LD      A,E
        AND     07h
        LD      (ALIGNMENT),A
        LD      HL,(SPRITE_X)
        LD      A,L
        AND     0F8h
        LD      L,A
        LD      (SPRITE_BASE_X),HL

        ; Determine whether a second destination byte is on-screen.
        LD      A,(ALIGNMENT)
        OR      A
        JR      Z,NO_RIGHT_BYTE
        LD      HL,(SPRITE_BASE_X)
        LD      DE,0008h
        ADD     HL,DE
        LD      DE,02D0h
        OR      A
        SBC     HL,DE
        JR      NC,NO_RIGHT_BYTE
        LD      A,01h
        LD      (RIGHT_VISIBLE),A
        JR      RIGHT_FLAG_DONE
NO_RIGHT_BYTE:
        XOR     A
        LD      (RIGHT_VISIBLE),A
RIGHT_FLAG_DONE:

        ; Precompute the right-shift count (8 - alignment).
        LD      A,08h
        LD      B,A
        LD      A,(ALIGNMENT)
        LD      C,A
        LD      A,B
        SUB     C
        LD      (RIGHT_SHIFT),A

        ; Clip the sprite vertically to scanline 255.
        LD      A,(SPRITE_Y)
        CP      0F9h
        JR      C,SPRITE_EIGHT_ROWS
        LD      E,A
        LD      A,0FFh
        SUB     E
        INC     A
        LD      (ROWS_LEFT),A
        JR      SPRITE_ROW_START
SPRITE_EIGHT_ROWS:
        LD      A,08h
        LD      (ROWS_LEFT),A

SPRITE_ROW_START:
        ; Fetch one MASK,PIXELS pair.
        LD      HL,(SPRITE_SOURCE)
        LD      A,(HL)
        LD      (SOURCE_MASK),A
        INC     HL
        LD      A,(HL)
        LD      (SOURCE_PIXELS),A
        INC     HL
        LD      (SPRITE_SOURCE),HL

        ; Left destination byte: shift source right by alignment.
        LD      A,(ALIGNMENT)
        OR      A
        JR      Z,LEFT_MASK_NO_SHIFT
        LD      B,A
        LD      A,(SOURCE_MASK)
LEFT_MASK_SHIFT_LOOP:
        SRL     A
        DJNZ    LEFT_MASK_SHIFT_LOOP
        JR      LEFT_MASK_SHIFTED
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

        LD      A,(ALIGNMENT)
        OR      A
        JR      Z,LEFT_PIXELS_NO_SHIFT
        LD      B,A
        LD      A,(SOURCE_PIXELS)
LEFT_PIXELS_SHIFT_LOOP:
        SRL     A
        DJNZ    LEFT_PIXELS_SHIFT_LOOP
        JR      LEFT_PIXELS_SHIFTED
LEFT_PIXELS_NO_SHIFT:
        LD      A,(SOURCE_PIXELS)
LEFT_PIXELS_SHIFTED:
        LD      (LEFT_PIXELS),A

        ; Right destination byte: the low source bits move to its top.
        LD      A,(RIGHT_SHIFT)
        LD      B,A
        LD      A,(SOURCE_MASK)
RIGHT_MASK_SHIFT_LOOP:
        SLA     A
        DJNZ    RIGHT_MASK_SHIFT_LOOP
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

        LD      A,(RIGHT_SHIFT)
        LD      B,A
        LD      A,(SOURCE_PIXELS)
RIGHT_PIXELS_SHIFT_LOOP:
        SLA     A
        DJNZ    RIGHT_PIXELS_SHIFT_LOOP
        LD      (RIGHT_PIXELS),A

        ; Get this scanline's first visible byte and draw the left part.
        LD      A,(SPRITE_Y)
        CALL    GET_SCANLINE_PTR
        LD      DE,(SPRITE_BASE_X)
        ADD     HL,DE
        LD      A,(HL)
        LD      D,A
        LD      A,(LEFT_MASK)
        AND     D
        LD      D,A
        LD      A,(LEFT_PIXELS)
        OR      D
        LD      (HL),A

        ; Draw the spill into the next character-cell byte when visible.
        LD      A,(RIGHT_VISIBLE)
        OR      A
        JR      Z,SPRITE_ROW_DONE
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

SPRITE_ROW_DONE:
        LD      A,(SPRITE_Y)
        INC     A
        LD      (SPRITE_Y),A
        LD      A,(ROWS_LEFT)
        DEC     A
        LD      (ROWS_LEFT),A
        JP      NZ,SPRITE_ROW_START

SPRITE_DONE:
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
        JR      Z,PTR_BANK1
        CP      02h
        JR      Z,PTR_BANK2
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

SPRITE_DIAMOND:
        DB      0E7h,018h
        DB      0C3h,03Ch
        DB      081h,07Eh
        DB      000h,0FFh
        DB      000h,0FFh
        DB      081h,07Eh
        DB      0C3h,03Ch
        DB      0E7h,018h

SPRITE_CROSS:
        DB      0E7h,000h
        DB      0E7h,018h
        DB      0E7h,018h
        DB      000h,0E7h
        DB      000h,0E7h
        DB      0E7h,018h
        DB      0E7h,018h
        DB      0E7h,000h

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
SPRITE_SOURCE:
        DW      0000h
SPRITE_X:
        DW      0000h
SPRITE_BASE_X:
        DW      0000h
SPRITE_Y:
        DB      00h
ALIGNMENT:
        DB      00h
RIGHT_SHIFT:
        DB      00h
RIGHT_VISIBLE:
        DB      00h
ROWS_LEFT:
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
