; PCWDECO.ASM
; Export the raw 256-entry Roller-RAM table to RRAM.TXT.
;
; Each text line contains 16 raw 16-bit entries, printed high byte first
; as four hexadecimal digits followed by a space. This preserves the
; exact table contents without assuming a particular pointer decode.
; One 128-byte CP/M sequential record is written per line.
;
; Reads the default table at physical bank 2, offset 3600h. Does not
; write to Roller-RAM, screen memory, or video-controller registers.
; Creates/replaces RRAM.TXT on the logged-in CP/M drive.

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

        ; Remove an earlier copy, then create a fresh text file.
        LD      DE,FILE_FCB
        LD      C,19
        CALL    0005h
        LD      DE,FILE_FCB
        LD      C,22
        CALL    0005h
        CP      0FFh
        JR      Z,FILE_ERROR

        ; Set the DMA address used by sequential file writes.
        LD      DE,FILE_BUFFER
        LD      C,26
        CALL    0005h

        LD      HL,RRAM_DUMP
        LD      (SOURCE_PTR),HL
        LD      C,16

WRITE_LINE:
        ; Prepare a 128-byte CP/M record, initially all spaces.
        LD      HL,FILE_BUFFER
        LD      B,128
        LD      A,20h
FILL_RECORD:
        LD      (HL),A
        INC     HL
        DJNZ    FILL_RECORD

        LD      HL,FILE_BUFFER
        LD      (OUTPUT_PTR),HL

        ; Sixteen raw words per line, high byte first.
        LD      B,16
WRITE_ENTRY:
        LD      HL,(SOURCE_PTR)
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        INC     HL
        LD      (SOURCE_PTR),HL

        LD      A,D
        CALL    WRITE_HEX_BYTE
        LD      A,E
        CALL    WRITE_HEX_BYTE
        LD      A,20h
        CALL    WRITE_CHAR

        DJNZ    WRITE_ENTRY

        LD      A,0Dh
        CALL    WRITE_CHAR
        LD      A,0Ah
        CALL    WRITE_CHAR

        ; Write the complete 128-byte record.
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      DE,FILE_FCB
        LD      C,21
        CALL    0005h
        OR      A
        JR      NZ,WRITE_ERROR
        POP     HL
        POP     DE
        POP     BC

        DEC     C
        JR      NZ,WRITE_LINE

        LD      DE,FILE_FCB
        LD      C,16
        CALL    0005h

        LD      DE,DONE_MESSAGE
        LD      C,9
        CALL    0005h
        JP      0000h

WRITE_ERROR:
        POP     HL
        POP     DE
        POP     BC
        LD      DE,ERROR_MESSAGE
        LD      C,9
        CALL    0005h
        JP      0000h

FILE_ERROR:
        LD      DE,ERROR_MESSAGE
        LD      C,9
        CALL    0005h
        JP      0000h

; Write A as two hexadecimal characters at OUTPUT_PTR.
WRITE_HEX_BYTE:
        PUSH    AF
        RRCA
        RRCA
        RRCA
        RRCA
        CALL    WRITE_NIBBLE
        POP     AF
        AND     0Fh
        CALL    WRITE_NIBBLE
        RET

WRITE_NIBBLE:
        AND     0Fh
        ADD     A,30h
        CP      3Ah
        JR      C,WRITE_CHAR
        ADD     A,07h

WRITE_CHAR:
        PUSH    HL
        LD      HL,(OUTPUT_PTR)
        LD      (HL),A
        INC     HL
        LD      (OUTPUT_PTR),HL
        POP     HL
        RET

SOURCE_PTR:
        DW      0000h
OUTPUT_PTR:
        DW      0000h

DONE_MESSAGE:
        DB      'RRAM.TXT written to the current drive.$'
ERROR_MESSAGE:
        DB      'File error: check disk space and write protection.$'

FILE_FCB:
        DB      00h
        DB      'RRAM    TXT'
        DEFS    24,00h

RRAM_DUMP:
        DEFS    0200h
FILE_BUFFER:
        DEFS    0080h

        END
