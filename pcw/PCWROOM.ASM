; PCWROOM.ASM
; Full-screen 720x256 preview of the original first Rick Dangerous room.
; The build-time converter expands the original map and tiles, composites
; Rick's original right-facing idle frame, then resamples the playfield to
; the native PCW raster. The resulting image is copied via Roller-RAM.

        ORG     0100h

START:
        DI
        LD      A,081h
        OUT     (0F1h),A
        LD      A,082h
        OUT     (0F2h),A

        LD      HL,PCW_SCREEN
        LD      (SCREEN_SOURCE),HL
        XOR     A
        LD      (SCREEN_Y),A

; Copy 90 source bytes to each scanline, respecting the PCW's eight-byte
; horizontal address stride. The screen data itself is row-major.
SCREEN_LINE:
        LD      A,(SCREEN_Y)
        CALL    GET_SCANLINE_PTR
        LD      (SCREEN_DEST),HL
        LD      B,90

SCREEN_COPY_BYTE:
        LD      HL,(SCREEN_SOURCE)
        LD      A,(HL)
        INC     HL
        LD      (SCREEN_SOURCE),HL

        LD      HL,(SCREEN_DEST)
        LD      (HL),A
        LD      DE,0008h
        ADD     HL,DE
        LD      (SCREEN_DEST),HL
        DJNZ    SCREEN_COPY_BYTE

        LD      A,(SCREEN_Y)
        INC     A
        LD      (SCREEN_Y),A
        JP      NZ,SCREEN_LINE

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

SCREEN_SOURCE:
        DW      0000h
SCREEN_DEST:
        DW      0000h
SCREEN_Y:
        DB      00h
BANK_NO:
        DB      00h
LOW_BITS:
        DB      00h

        INCLUDE "build/PCWSCREEN.INC"

        END
