; PCWPIX.ASM
; Pixel-coordinate addressing diagnostic for the Amstrad PCW 9256.
;
; Uses the active 256-entry Roller-RAM table at bank 2 offset 3600h
; (CPU address B600h while bank 2 is mapped in slot F2h).
; Each entry is a little-endian 16-bit pointer:
;   bank   = (word >> 13) & 7
;   offset = (word & 7) + 2 * (word & 1FF8h)
;
; The standard 9256 screen uses physical banks 1 and 2. They are mapped
; simultaneously into CPU slots F1h and F2h. A decoded pointer in bank 1
; is accessed at 4000h+offset; a pointer in bank 2 at 8000h+offset.
; Each scanline contains 90 bytes at eight-byte address intervals.
;
; PLOT_SET input:
;   DE = x coordinate (0..719)
;   BC = y coordinate (0..255), with B=0
; Preserves DE and BC. Pixel masks are MSB-first; the test pattern checks
; this visually after the scanline address calculation is correct.
;
; The clear routine also follows Roller-RAM, clearing the 90 visible
; bytes on each of the 256 scanlines rather than clearing a guessed range.

        ORG     0100h

START:
        DI

        ; Map physical screen banks 1 and 2 into CPU slots F1 and F2.
        LD      A,081h
        OUT     (0F1h),A
        LD      A,082h
        OUT     (0F2h),A

        CALL    CLEAR_SCREEN

        ; Diagonal from (0,0) through (255,255).
        LD      DE,0000h
        LD      BC,0000h
DIAGONAL:
        CALL    PLOT_SET
        INC     DE
        INC     C
        JR      NZ,DIAGONAL

        ; Full-width horizontal line at y=128.
        LD      DE,0000h
        LD      BC,0080h
HORIZONTAL:
        CALL    PLOT_SET
        INC     DE
        LD      A,D
        CP      02h
        JR      NZ,HORIZONTAL
        LD      A,E
        CP      0D0h
        JR      NZ,HORIZONTAL

        ; Full-height vertical line at x=360.
        LD      DE,0168h
        LD      BC,0000h
VERTICAL:
        CALL    PLOT_SET
        INC     C
        JR      NZ,VERTICAL

        ; Mark the remaining three screen corners.
        LD      DE,02CFh
        LD      BC,0000h
        CALL    PLOT_SET

        LD      DE,0000h
        LD      BC,00FFh
        CALL    PLOT_SET

        LD      DE,02CFh
        LD      BC,00FFh
        CALL    PLOT_SET

        ; Filled rectangle: x=80..199, y=40..99.
        LD      C,40
RECT_ROW:
        LD      DE,80
        LD      B,120
RECT_COL:
        CALL    PLOT_SET
        INC     DE
        DJNZ    RECT_COL
        INC     C
        LD      A,C
        CP      100
        JR      NZ,RECT_ROW

        ; Clear a smaller rectangle inside it: x=112..151, y=60..79.
        LD      C,60
HOLE_ROW:
        LD      DE,112
        LD      B,40
HOLE_COL:
        CALL    PLOT_CLEAR
        INC     DE
        DJNZ    HOLE_COL
        INC     C
        LD      A,C
        CP      80
        JR      NZ,HOLE_ROW

        ; Filled patch at the lower-right edge. This exercises the last
        ; valid x and y coordinates (x=680..719, y=230..255).
        LD      C,230
EDGE_ROW:
        LD      DE,680
        LD      B,40
EDGE_COL:
        CALL    PLOT_SET
        INC     DE
        DJNZ    EDGE_COL
        INC     C
        JR      NZ,EDGE_ROW

        ; Restore the normal CP/M Plus F1/F2 mapping before BDOS.
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

        ; Clear the bitmap again using the same Roller-RAM addressing.
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

; Clear 90 visible bytes on each scanline. The controller's byte
; addresses are separated by eight, so advance HL by eight each time.
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

; Return the CPU address of the first visible byte for scanline A.
; Only physical banks 1 and 2 are expected in the standard 9256 table.
; Preserves DE and BC; returns HL as 4000h+offset or 8000h+offset.
GET_SCANLINE_PTR:
        PUSH    DE

        ; Roller-RAM word address = B600h + 2*y.
        LD      L,A
        LD      H,00h
        ADD     HL,HL
        LD      DE,0B600h
        ADD     HL,DE

        ; Read the little-endian word.
        LD      E,(HL)
        INC     HL
        LD      D,(HL)

        ; Save physical bank number (word bits 15..13).
        LD      A,D
        AND     0E0h
        SRL     A
        SRL     A
        SRL     A
        SRL     A
        SRL     A
        LD      (BANK_NO),A

        ; Decode offset = (word & 7) + 2 * (word & 1FF8h).
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

        ; Select the CPU slot into which that physical bank is mapped.
        LD      A,(BANK_NO)
        CP      01h
        JR      Z,POINTER_BANK1
        CP      02h
        JR      Z,POINTER_BANK2

        ; Unexpected bank: return zero rather than write to arbitrary RAM.
        LD      HL,0000h
        POP     DE
        RET

POINTER_BANK1:
        LD      DE,04000h
        ADD     HL,DE
        POP     DE
        RET

POINTER_BANK2:
        LD      DE,08000h
        ADD     HL,DE
        POP     DE
        RET

; Set or clear one pixel. Caller supplies valid screen coordinates.
PLOT_SET:
        LD      A,01h
        LD      (PIX_MODE),A
        JR      PLOT_PIXEL

PLOT_CLEAR:
        XOR     A
        LD      (PIX_MODE),A

PLOT_PIXEL:
        PUSH    DE
        PUSH    BC

        ; Save x modulo eight for the pixel mask.
        LD      A,E
        AND     07h
        LD      (PIX_MASK),A

        ; Get the first visible byte of this exact scanline.
        LD      A,C
        CALL    GET_SCANLINE_PTR

        ; Add x rounded down to the containing eight-pixel byte.
        PUSH    HL
        LD      H,D
        LD      L,E
        LD      A,L
        AND     0F8h
        LD      L,A
        POP     DE
        ADD     HL,DE
        PUSH    HL

        ; Fetch mask: bit 7 is leftmost, bit 0 is rightmost.
        LD      A,(PIX_MASK)
        LD      E,A
        LD      D,00h
        LD      HL,PIXEL_MASKS
        ADD     HL,DE
        LD      B,(HL)

        POP     HL
        LD      A,(PIX_MODE)
        OR      A
        JR      Z,PIXEL_DO_CLEAR
        LD      A,(HL)
        OR      B
        JR      PIXEL_STORE

PIXEL_DO_CLEAR:
        LD      A,B
        CPL
        LD      B,A
        LD      A,(HL)
        AND     B

PIXEL_STORE:
        LD      (HL),A

        POP     BC
        POP     DE
        RET

PIXEL_MASKS:
        DB      080h,040h,020h,010h,008h,004h,002h,001h

BANK_NO:
        DB      00h
LOW_BITS:
        DB      00h
PIX_MASK:
        DB      00h
PIX_MODE:
        DB      00h

        END
