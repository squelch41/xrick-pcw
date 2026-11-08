; PCWBLIT.ASM
; 8x8 tile blitter diagnostic for the Amstrad PCW 9256.
;
; DRAW_TILE input:
;   HL = address of eight source bytes (one byte per pixel row)
;   DE = x coordinate, aligned to 8 pixels (0..712)
;   C  = y coordinate (0..248)
;
; The eight source bytes are copied directly to the eight Roller-RAM
; scanline addresses. This is an opaque, byte-aligned 8x8 tile operation;
; transparent and non-byte-aligned sprites are later extensions.
;
; Roller-RAM table: physical bank 2, offset 3600h (CPU B600h while
; physical bank 2 is mapped into CPU slot F2h).
; Pointer decode:
;   bank   = (word >> 13) & 7
;   offset = (word & 7) + 2 * (word & 1FF8h)
;
; Only decoded physical banks 1 and 2 are accepted. They are mapped into
; CPU slots F1h and F2h. The test clears the display, draws sample tiles
; at ordinary positions and at the bottom-right boundary, waits for a key,
; clears again, restores the CP/M Plus TPA map and warm-boots CP/M.

        ORG     0100h

START:
        DI
        LD      A,081h
        OUT     (0F1h),A
        LD      A,082h
        OUT     (0F2h),A

        CALL    CLEAR_SCREEN

        ; A small row of different 8x8 patterns.
        LD      HL,TILE_DIAMOND
        LD      DE,0080h
        LD      BC,0040h
        CALL    DRAW_TILE

        LD      HL,TILE_BOX
        LD      DE,0090h
        LD      BC,0040h
        CALL    DRAW_TILE

        LD      HL,TILE_CROSS
        LD      DE,00A0h
        LD      BC,0040h
        CALL    DRAW_TILE

        LD      HL,TILE_CHECK
        LD      DE,00B0h
        LD      BC,0040h
        CALL    DRAW_TILE

        LD      HL,TILE_DIAG
        LD      DE,00C0h
        LD      BC,0040h
        CALL    DRAW_TILE

        ; Exercise the last complete tile at x=712, y=248.
        LD      HL,TILE_BOX
        LD      DE,02C8h
        LD      BC,00F8h
        CALL    DRAW_TILE

        ; Restore normal CP/M Plus TPA mapping before BDOS.
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
; The 90 horizontal byte positions are eight addresses apart.
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

; Draw one opaque, byte-aligned 8x8 tile through the active Roller-RAM.
; Caller guarantees x is a multiple of 8 and that x<=712, y<=248.
DRAW_TILE:
        PUSH    DE
        PUSH    BC
        LD      (TILE_SOURCE),HL
        LD      (TILE_X),DE
        LD      A,C
        LD      (TILE_Y),A
        LD      B,08h

DRAW_TILE_ROW:
        ; Fetch the next source row before the pointer lookup.
        LD      HL,(TILE_SOURCE)
        LD      A,(HL)
        LD      (TILE_BYTE),A
        INC     HL
        LD      (TILE_SOURCE),HL

        ; Get the first visible byte for this scanline.
        LD      A,(TILE_Y)
        CALL    GET_SCANLINE_PTR

        ; For x aligned to eight pixels, byte offset equals x.
        LD      DE,(TILE_X)
        ADD     HL,DE
        LD      A,(TILE_BYTE)
        LD      (HL),A

        LD      A,(TILE_Y)
        INC     A
        LD      (TILE_Y),A
        DJNZ    DRAW_TILE_ROW

        POP     BC
        POP     DE
        RET

; Input A = scanline y. Return HL = CPU address of its first visible byte.
; Preserves DE and BC. Standard screen bank 1 maps at 4000h and bank 2
; maps at 8000h. Reject any other physical bank by returning HL=0000h.
GET_SCANLINE_PTR:
        PUSH    DE

        ; Roller-RAM word address = B600h + 2*y.
        LD      L,A
        LD      H,00h
        ADD     HL,HL
        LD      DE,0B600h
        ADD     HL,DE

        ; Fetch little-endian pointer word.
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

        ; Convert physical bank to the mapped CPU window.
        LD      A,(BANK_NO)
        CP      01h
        JR      Z,POINTER_BANK1
        CP      02h
        JR      Z,POINTER_BANK2

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

TILE_DIAMOND:
        DB      18h,3Ch,7Eh,0FFh,0FFh,7Eh,3Ch,18h
TILE_BOX:
        DB      0FFh,081h,081h,081h,081h,081h,081h,0FFh
TILE_CROSS:
        DB      18h,18h,18h,0FFh,0FFh,18h,18h,18h
TILE_CHECK:
        DB      0AAh,055h,0AAh,055h,0AAh,055h,0AAh,055h
TILE_DIAG:
        DB      080h,040h,020h,010h,008h,004h,002h,001h

TILE_SOURCE:
        DW      0000h
TILE_X:
        DW      0000h
TILE_Y:
        DB      00h
TILE_BYTE:
        DB      00h
BANK_NO:
        DB      00h
LOW_BITS:
        DB      00h

        END
