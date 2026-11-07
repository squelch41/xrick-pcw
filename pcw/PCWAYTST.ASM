; PCWAYTST.ASM
; Proposed CP/M transient-program test for the dK'Tronics AY-3-8912.
; Assemble as a flat binary with ORG 0100h and name it PCWAYTST.COM.
;
; Expected behaviour:
;   - Set channel A tone period to 500.
;   - Enable channel A tone and set fixed amplitude to 15.
;   - Poll CP/M BDOS direct console input until a key is pressed.
;   - Mute channel A and return to CP/M.
;
; dK'Tronics AY-3-8912 ports (per John Elliott's PCW hardware reference):
; AAh = AY register select; ABh = AY data write.
; Runtime behaviour still needs testing on the interface.

        ORG     0100h

START:
        ; Channel A tone period = 01F4h (500)
        LD      A,00h
        OUT     (0AAh),A
        LD      A,0F4h
        OUT     (0ABh),A

        LD      A,01h
        OUT     (0AAh),A
        LD      A,01h
        OUT     (0ABh),A

        ; Mixer: channel A tone enabled, its noise disabled;
        ; channels B and C tone/noise disabled.
        ; Register 7 bit 6 = 0 keeps AY port A configured as input.
        LD      A,07h
        OUT     (0AAh),A
        LD      A,03Eh
        OUT     (0ABh),A

        ; Channel A fixed amplitude = 15
        LD      A,08h
        OUT     (0AAh),A
        LD      A,0Fh
        OUT     (0ABh),A

WAIT_KEY:
        ; BDOS function 6: direct console I/O.
        ; E=FFh polls without waiting; A=00h means no key is ready.
        LD      C,06h
        LD      E,0FFh
        CALL    0005h
        OR      A
        JR      Z,WAIT_KEY

        ; Mute channel A and disable all tone/noise generators.
        LD      A,08h
        OUT     (0AAh),A
        XOR     A
        OUT     (0ABh),A

        LD      A,07h
        OUT     (0AAh),A
        LD      A,03Fh
        OUT     (0ABh),A

        ; Warm boot to CP/M CCP.
        JP      0000h

        END
