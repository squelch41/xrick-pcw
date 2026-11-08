; PCWDECO.ASM
; Read-only Roller-RAM decoder for the Amstrad PCW 9256.
;
; Reads the default 512-byte Roller-RAM table at bank 2, offset 3600h,
; then prints all 256 entries as:
;   block:decoded-offset
;
; Roller-RAM word format:
;   bits 15..13 = physical 16K block number
;   bits 12..0  = encoded offset
;   decoded offset = (word & 7) + 2 * (word & 1FF8h)
;
; The VDU fetches 90 bytes per scanline at 8-byte intervals from
; the decoded start address. This program does not write to the table,
; screen memory, or video-controller registers.

        ORG     0100h

START:
        DI
        LD      A,081h
        OUT     (0F1h),A
        LD      A,082h
        OUT     (0F2h),A

        LD      HL,0B600h
        LD      DE,RRAM_DUMP
        LD      BC,0200h
        LDIR

        LD      A,085h
        OUT     (0F1h),A
        LD      A,086h
        OUT     (0F2h),A
        EI

        LD      HL,RRAM_DUMP
        LD      C,10h

PRINT_ROW:
        LD      B,10h

PRINT_ENTRY:
        PUSH    HL
        LD      E,(HL)
        INC     HL
        LD      D,(HL)

        ; Extract physical block number (word bits 15..13).
        LD      A,D
        AND     0E0h
        SRL     A
        SRL     A
        SRL     A
        SRL     A
        SRL     A
        LD      (BLOCK_NO),A

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

        ; Print block:offset (all hexadecimal).
        LD      A,(BLOCK_NO)
        CALL    PRINT_HEX_BYTE
        LD      A,3Ah
        CALL    PRINT_CHAR
        LD      A,H
        CALL    PRINT_HEX_BYTE
        LD      A,L
        CALL    PRINT_HEX_BYTE
        LD      A,20h
        CALL    PRINT_CHAR

        POP     HL
        INC     HL
        INC     HL
        DJNZ    PRINT_ENTRY

        LD      A,0Dh
        CALL    PRINT_CHAR
        LD      A,0Ah
        CALL    PRINT_CHAR
        DEC     C
        JR      NZ,PRINT_ROW

        JP      0000h

PRINT_HEX_BYTE:
        PUSH    AF
        RRCA
        RRCA
        RRCA
        RRCA
        CALL    PRINT_NIBBLE
        POP     AF
        AND     0Fh
        CALL    PRINT_NIBBLE
        RET

PRINT_NIBBLE:
        AND     0Fh
        ADD     A,30h
        CP      3Ah
        JR      C,PRINT_CHAR
        ADD     A,07h

PRINT_CHAR:
        PUSH    AF
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      E,A
        LD      C,02h
        CALL    0005h
        POP     HL
        POP     DE
        POP     BC
        POP     AF
        RET

BLOCK_NO:
        DB      00h
LOW_BITS:
        DB      00h
RRAM_DUMP:
        DEFS    0200h

        END
