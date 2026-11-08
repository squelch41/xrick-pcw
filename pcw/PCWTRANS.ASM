; PCWTRANS.ASM
; Transparent 8x8 sprite diagnostic for the Amstrad PCW 9256.
;
; DRAW_MASKED_TILE input:
;   HL = 16-byte source (mask,pixels) pairs for eight rows
;   DE = x coordinate, aligned to 8 pixels (0..712)
;   C  = y coordinate (0..248)
;
; Mask bit 1 preserves the destination; mask bit 0 is replaced by the
; corresponding pixel bit. The final byte is (old AND mask) OR pixels.
; Pixels should be zero wherever the mask is one.
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

        ; Checkerboard background.
        LD      HL,TILE_CHECK
        LD      DE,0100h
        LD      BC,0050h
        CALL    DRAW_OPAQUE_TILE

        ; White diamond, with transparent pixels around it.
        LD      HL,SPRITE_DIAMOND
        LD      DE,0100h
        LD      BC,0050h
        CALL    DRAW_MASKED_TILE

        ; A second sprite tests transparent black pixels over the same
        ; background: a black cross inside a white outline.
        LD      HL,SPRITE_CROSS
        LD      DE,0108h
        LD      BC,0050h
        CALL    DRAW_MASKED_TILE

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

; Draw one opaque byte-aligned 8x8 tile.
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

; Draw one transparent byte-aligned 8x8 tile.
DRAW_MASKED_TILE:
        LD      (TILE_SOURCE),HL
        LD      (TILE_X),DE
        LD      A,C
        LD      (TILE_Y),A
        LD      B,08h
MASKED_ROW:
        LD      HL,(TILE_SOURCE)
        LD      A,(HL)
        LD      (MASK),A
        INC     HL
        LD      A,(HL)
        LD      (PIXELS),A
        INC     HL
        LD      (TILE_SOURCE),HL

        LD      A,(TILE_Y)
        CALL    GET_SCANLINE_PTR
        LD      DE,(TILE_X)
        ADD     HL,DE
        LD      A,(HL)
        LD      D,A
        LD      A,(MASK)
        AND     D
        LD      D,A
        LD      A,(PIXELS)
        OR      D
        LD      (HL),A

        LD      A,(TILE_Y)
        INC     A
        LD      (TILE_Y),A
        DJNZ    MASKED_ROW
        RET

; Input A = scanline y. Return HL = CPU address of its first visible byte.
; Preserves DE and BC. Standard screen bank 1 maps at 4000h and bank 2
; maps at 8000h. Other physical banks return HL=0000h.
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

; Each row is MASK,PIXELS. A 1 in MASK preserves the background.
SPRITE_DIAMOND:
        DB      0E7h,018h
        DB      0C3h,03Ch
        DB      081h,07Eh
        DB      000h,0FFh
        DB      000h,0FFh
        DB      081h,07Eh
        DB      0C3h,03Ch
        DB      0E7h,018h

; Transparent black cross, with a white outline around it.
SPRITE_CROSS:
        DB      0E7h,000h
        DB      0E7h,018h
        DB      0E7h,018h
        DB      000h,0E7h
        DB      000h,0E7h
        DB      0E7h,018h
        DB      0E7h,018h
        DB      0E7h,000h

TILE_SOURCE:
        DW      0000h
TILE_X:
        DW      0000h
TILE_Y:
        DB      00h
MASK:
        DB      00h
PIXELS:
        DB      00h
BANK_NO:
        DB      00h
LOW_BITS:
        DB      00h

        END
