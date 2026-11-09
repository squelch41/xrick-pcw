; PCWROOM.ASM
; Full-screen 720x256 preview of the original first Rick Dangerous room.
; The build-time converter expands the original map and tiles, composites
; Rick's original right-facing idle frame, then resamples the playfield to
; the native PCW raster. The resulting image is copied via Roller-RAM.

        ORG     0100h

START:
        DI

        ; Keep physical screen bank 2 mapped in F2 so the Roller-RAM
        ; table at B600h remains readable. Leave F1 on its normal CP/M
        ; bank while fetching each source scanline.
        LD      A,082h
        OUT     (0F2h),A

        LD      HL,PCW_SCREEN
        LD      (SCREEN_SOURCE),HL
        XOR     A
        LD      (SCREEN_Y),A

; Read one complete source row into the low-memory buffer before mapping
; F1 to screen bank 1. The image extends beyond 4000h, so reading directly
; while F1 is mapped to bank 1 would corrupt the final part of the image.
SCREEN_LINE:
        LD      HL,(SCREEN_SOURCE)
        LD      DE,ROW_BUFFER
        LD      BC,90
        LDIR
        LD      (SCREEN_SOURCE),HL

        LD      A,(SCREEN_Y)
        CALL    GET_SCANLINE_PTR
        LD      (SCREEN_DEST),HL

        ; Bank 2 is already mapped in F2. Map bank 1 in F1 only for
        ; scanlines whose Roller-RAM entry selects physical bank 1.
        LD      A,(BANK_NO)
        CP      01h
        JR      NZ,SCREEN_COPY
        LD      A,081h
        OUT     (0F1h),A

SCREEN_COPY:
        LD      HL,ROW_BUFFER
        LD      B,90

SCREEN_COPY_BYTE:
        LD      A,(HL)
        INC     HL
        PUSH    HL
        LD      HL,(SCREEN_DEST)
        LD      (HL),A
        LD      DE,0008h
        ADD     HL,DE
        LD      (SCREEN_DEST),HL
        POP     HL
        DJNZ    SCREEN_COPY_BYTE

        ; Restore the source/TPA bank before reading the next row.
        LD      A,085h
        OUT     (0F1h),A

        LD      A,(SCREEN_Y)
        INC     A
        LD      (SCREEN_Y),A
        JP      NZ,SCREEN_LINE

        ; Restore the normal CP/M mapping before calling BDOS.
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
        LD      A,082h
        OUT     (0F2h),A
        CALL    CLEAR_SCREEN
        LD      A,085h
        OUT     (0F1h),A
        LD      A,086h
        OUT     (0F2h),A
        EI
        JP      0000h

; Clear the 90 visible bytes on all 256 scanlines. As above, map F1 to
; screen bank 1 only while clearing a line whose Roller-RAM pointer uses it.
CLEAR_SCREEN:
        LD      C,00h
CLEAR_LINE:
        LD      A,C
        CALL    GET_SCANLINE_PTR
        LD      A,(BANK_NO)
        CP      01h
        JR      NZ,CLEAR_BYTES
        LD      A,081h
        OUT     (0F1h),A
CLEAR_BYTES:
        LD      B,90
        LD      DE,0008h
CLEAR_BYTE:
        LD      (HL),00h
        ADD     HL,DE
        DJNZ    CLEAR_BYTE
        LD      A,085h
        OUT     (0F1h),A
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
ROW_BUFFER:
        DS      90

        INCLUDE "build/PCWSCREEN.INC"

        END
