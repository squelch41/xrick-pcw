; PCWGFXT.ASM
; Experimental PCW 9256 video-memory smoke test for standard 256K CP/M Plus.
;
; Fills the existing screen bitmap with an alternating 10101010 pattern,
; waits for a key, clears the bitmap, restores the standard TPA bank map,
; and warm-boots CP/M.
;
; IMPORTANT:
; - Does not modify Roller-RAM or the video-controller registers.
; - Assumes standard PCW CP/M Plus transient-program mapping:
;     F0=bank 4, F1=bank 5, F2=bank 6, F3=bank 7 (common).
; - Temporarily maps screen banks 1 and 2 into F1/F2, then restores 5/6.
; - No CALL/PUSH/POP is made while the TPA banks are switched out.
; - Intended first for Joyce, then a real PCW 9256. Not yet runtime-tested.

        ORG     0100h

START:
        ; Map the two screen-memory banks into the 4000h and 8000h slots.
        ; Keep interrupts disabled while the TPA banks are switched out.
        DI
        LD      A,081h
        OUT     (0F1h),A
        LD      A,082h
        OUT     (0F2h),A

        ; Bank 2 screen area: 0000h..332Fh -> 8000h..B32Fh.
        LD      HL,08000h
        LD      BC,03330h
        LD      D,0AAh
FILL_BANK2:
        LD      (HL),D
        INC     HL
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,FILL_BANK2

        ; Bank 1 screen area: 1930h..3FFFh -> 5930h..7FFFh.
        LD      HL,05930h
        LD      BC,026D0h
FILL_BANK1:
        LD      (HL),D
        INC     HL
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,FILL_BANK1

        ; Restore standard CP/M Plus TPA banks before calling BDOS.
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

        ; Clear the same screen bitmap areas.
        DI
        LD      A,081h
        OUT     (0F1h),A
        LD      A,082h
        OUT     (0F2h),A

        LD      HL,08000h
        LD      BC,03330h
        LD      D,00h
CLEAR_BANK2:
        LD      (HL),D
        INC     HL
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,CLEAR_BANK2

        LD      HL,05930h
        LD      BC,026D0h
CLEAR_BANK1:
        LD      (HL),D
        INC     HL
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,CLEAR_BANK1

        LD      A,085h
        OUT     (0F1h),A
        LD      A,086h
        OUT     (0F2h),A
        EI

        JP      0000h

        END
