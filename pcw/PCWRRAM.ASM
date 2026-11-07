; PCWRRAM.ASM
; Read-only dump of the PCW's default Roller-RAM table.
;
; Copies the 512-byte table from physical bank 2, offset 3600h
; (CPU address B600h while bank 2 is mapped at F2h) into the
; program's TPA, restores the CP/M banks, then prints 256 words.
;
; No writes are made to Roller-RAM or the video-controller ports.
; Output is 16 little-endian words per line, displayed high byte first.

        ORG     0100h

START:
        DI
        LD      A,081h
        OUT     (0F1h),A
        LD      A,082h
        OUT     (0F2h),A

        ; Snapshot the default Roller-RAM table.
        LD      HL,0B600h
        LD      DE,RRAM_DUMP
        LD      BC,0200h
        LDIR

        ; Restore the CP/M Plus TPA banks before using BDOS.
        LD      A,085h
        OUT     (0F1h),A
        LD      A,086h
        OUT     (0F2h),A
        EI

        LD      HL,RRAM_DUMP
        LD      C,10h

PRINT_ROW:
        LD      B,10h

PRINT_WORD:
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        INC     HL

        LD      A,D
        CALL    PRINT_HEX_BYTE
        LD      A,E
        CALL    PRINT_HEX_BYTE

        LD      A,20h
        CALL    PRINT_CHAR
        DJNZ    PRINT_WORD

        LD      A,0Dh
        CALL    PRINT_CHAR
        LD      A,0Ah
        CALL    PRINT_CHAR
        DEC     C
        JR      NZ,PRINT_ROW

        JP      0000h

; Print A as two uppercase hexadecimal digits.
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

; BDOS function 2: output character in E. Preserve caller registers.
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

; 512-byte snapshot buffer in the program's own TPA.
RRAM_DUMP:
        DEFS    0200h

        END
