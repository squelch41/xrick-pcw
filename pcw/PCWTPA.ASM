; PCWTPA.ASM
; Small CP/M Plus diagnostic: print the highest address available to a
; transient program, as read from the page-zero BDOS/LOADER jump at 0006h.
; The four hexadecimal digits are printed high byte first, then low byte.
;
; Compare this with PCWPLAY.COM's last byte: 0100h + file_size - 1.

        ORG     0100h

START:
        LD      HL,(0006h)
        DEC     HL
        PUSH    HL
        LD      A,H
        CALL    PRINT_HEX_BYTE
        POP     HL
        PUSH    HL
        LD      A,L
        CALL    PRINT_HEX_BYTE
        POP     HL

        LD      E,00Dh
        LD      C,02h
        CALL    0005h
        LD      E,00Ah
        LD      C,02h
        CALL    0005h
        JP      0000h

PRINT_HEX_BYTE:
        PUSH    AF
        RRCA
        RRCA
        RRCA
        RRCA
        AND     00Fh
        CALL    PRINT_HEX_NIBBLE
        POP     AF
        AND     00Fh

PRINT_HEX_NIBBLE:
        ADD     A,030h
        CP      03Ah
        JP      C,PRINT_HEX_READY
        ADD     A,007h
PRINT_HEX_READY:
        LD      E,A
        LD      C,02h
        CALL    0005h
        RET

        END
