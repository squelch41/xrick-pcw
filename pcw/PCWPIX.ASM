; PCWPIX.ASM
; Pixel-coordinate addressing diagnostic for the Amstrad PCW 9256.
;
; Uses the normal PCW screen layout: 90 columns x 32 rows of 8x8 cells.
; Each cell occupies eight consecutive bytes, one byte per pixel scanline.
; The byte address for pixel (x,y) is:
;   screen_base + (y >> 3)*720 + (x & 0FFF8h) + (y & 7)
; screen_base is CPU address 5930h while banks 1 and 2 are mapped at F1/F2.
;
; PLOT_SET input:
;   DE = x coordinate (0..719)
;   BC = y coordinate (0..255), with B=0
; It preserves DE and BC. Pixels are assumed MSB-first within each byte;
; the displayed diagonal is intended to confirm this visually.
;
; Does not alter Roller-RAM or video-controller registers.

        ORG     0100h

START:
        DI

        LD      A,081h
        OUT     (0F1h),A
        LD      A,082h
        OUT     (0F2h),A

        ; Clear the 23,040-byte visible bitmap.
        LD      HL,05930h
        LD      BC,05A00h
        LD      D,00h
CLEAR_SCREEN:
        LD      (HL),D
        INC     HL
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,CLEAR_SCREEN

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

        ; Restore the CP/M Plus TPA banks before using BDOS.
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

        ; Clear the bitmap again.
        DI
        LD      A,081h
        OUT     (0F1h),A
        LD      A,082h
        OUT     (0F2h),A

        LD      HL,05930h
        LD      BC,05A00h
        LD      D,00h
CLEAR_EXIT:
        LD      (HL),D
        INC     HL
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,CLEAR_EXIT

        LD      A,085h
        OUT     (0F1h),A
        LD      A,086h
        OUT     (0F2h),A
        EI
        JP      0000h

; Set one pixel. Caller clips coordinates to x=0..719, y=0..255.
; Stack use is safe: F3 remains the normal TPA bank while F1/F2
; temporarily expose the video banks.
PLOT_SET:
        PUSH    DE
        PUSH    BC

        ; Save x modulo 8 for the pixel mask.
        LD      A,E
        AND     07h
        LD      (PIX_MASK),A

        ; Horizontal byte offset = x & 0FFF8h.
        LD      A,E
        AND     0F8h
        LD      L,A
        LD      H,D
        PUSH    HL

        ; Look up (y >> 3) * 720.
        LD      A,C
        AND     0F8h
        RRCA
        RRCA
        RRCA
        ADD     A,A
        LD      E,A
        LD      D,00h
        LD      HL,ROW_OFFSETS
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)

        POP     HL
        ADD     HL,DE

        ; Add scanline within the 8-line character cell.
        LD      A,C
        AND     07h
        LD      E,A
        LD      D,00h
        ADD     HL,DE

        ; Convert screen-relative offset to mapped CPU address.
        LD      DE,05930h
        ADD     HL,DE
        PUSH    HL

        ; Fetch mask: bit 7 is the leftmost pixel, bit 0 the rightmost.
        LD      A,(PIX_MASK)
        LD      E,A
        LD      D,00h
        LD      HL,PIXEL_MASKS
        ADD     HL,DE
        LD      A,(HL)
        LD      B,A

        POP     HL
        LD      A,(HL)
        OR      B
        LD      (HL),A

        POP     BC
        POP     DE
        RET

; Row-base offsets: n * 720 for n=0..31, little-endian.
ROW_OFFSETS:
        DB      00h,00h, 0D0h,02h, 0A0h,05h, 70h,08h
        DB      40h,0Bh, 10h,0Eh, 0E0h,10h, 0B0h,13h
        DB      80h,16h, 50h,19h, 20h,1Ch, 0F0h,1Eh
        DB      0C0h,21h, 90h,24h, 60h,27h, 30h,2Ah
        DB      00h,2Dh, 0D0h,2Fh, 0A0h,32h, 70h,35h
        DB      40h,38h, 10h,3Bh, 0E0h,3Dh, 0B0h,40h
        DB      80h,43h, 50h,46h, 20h,49h, 0F0h,4Bh
        DB      0C0h,4Eh, 90h,51h, 60h,54h, 30h,57h

PIXEL_MASKS:
        DB      080h,040h,020h,010h,008h,004h,002h,001h

PIX_MASK:
        DB      00h

        END
