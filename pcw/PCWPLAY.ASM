; PCWPLAY.ASM
; First interactive Rick Dangerous room for the Amstrad PCW 9256.
;
; Controls:
;   S = move left (one original game step)
;   D = move right (one original game step)
;   I = stand still / restore idle pose
;   Q = clear the display and return to CP/M
;
; This first playable milestone deliberately uses the original PC game's
; walk cycle and coordinate step, but does not yet implement collision,
; scrolling, jumping or other entities. Each keypress advances one step;
; CP/M keyboard auto-repeat can be used for continuous movement.
;
; The room background and player frames are generated from the original
; Xrick PC assets. The 720x256 art is nearest-neighbour scaled from 256x192.
; All working code and buffers are kept below 4000h so the program can map
; either video bank into F1/F2 without hiding the code being executed.

        ORG     0100h

START:
        DI

        ; Snapshot the 256-entry Roller-RAM table while physical bank 2
        ; is mapped in F2. Keep the snapshot in low memory for later use.
        LD      A,082h
        OUT     (0F2h),A
        LD      HL,0B600h
        LD      DE,RRAM_TABLE
        LD      BC,0200h
        LDIR
        CALL    RESTORE_TPA

        LD      A,08h
        LD      (PLAYER_X),A
        XOR     A
        LD      (PLAYER_DIRECTION),A
        LD      A,01h
        LD      (WALK_FRAME),A
        CALL    SELECT_IDLE_SPRITE

        CALL    DRAW_BACKGROUND
        CALL    DRAW_PLAYER
        CALL    RESTORE_TPA
        EI

MAIN_LOOP:
        ; BDOS function 6 with E=FFh polls the console without waiting.
        LD      C,06h
        LD      E,0FFh
        CALL    0005h
        OR      A
        JP      Z,MAIN_LOOP

        CP      051h                  ; Q
        JP      Z,EXIT_TO_CPM
        CP      071h                  ; q
        JP      Z,EXIT_TO_CPM
        CP      053h                  ; S
        JP      Z,MOVE_LEFT
        CP      073h                  ; s
        JP      Z,MOVE_LEFT
        CP      044h                  ; D
        JP      Z,MOVE_RIGHT
        CP      064h                  ; d
        JP      Z,MOVE_RIGHT
        CP      049h                  ; I
        JP      Z,SELECT_IDLE
        CP      069h                  ; i
        JP      Z,SELECT_IDLE
        JP      MAIN_LOOP

MOVE_LEFT:
        LD      A,01h
        LD      (PLAYER_DIRECTION),A
        LD      A,(PLAYER_X)
        CP      02h
        JP      C,LEFT_STEP_DONE
        SUB     02h
        LD      (PLAYER_X),A
LEFT_STEP_DONE:
        CALL    ADVANCE_WALK_FRAME
        CALL    SELECT_WALK_SPRITE
        CALL    REDRAW_SCENE
        JP      MAIN_LOOP

MOVE_RIGHT:
        XOR     A
        LD      (PLAYER_DIRECTION),A
        LD      A,(PLAYER_X)
        CP      0E8h                  ; original game right-edge threshold = 232
        JP      NC,RIGHT_STEP_DONE
        ADD     A,02h
        CP      0E8h
        JP      C,RIGHT_STORE_X
        LD      A,0E8h
RIGHT_STORE_X:
        LD      (PLAYER_X),A
RIGHT_STEP_DONE:
        CALL    ADVANCE_WALK_FRAME
        CALL    SELECT_WALK_SPRITE
        CALL    REDRAW_SCENE
        JP      MAIN_LOOP

ADVANCE_WALK_FRAME:
        LD      A,(WALK_FRAME)
        INC     A
        CP      06h
        JP      C,WALK_FRAME_STORE
        LD      A,01h
WALK_FRAME_STORE:
        LD      (WALK_FRAME),A
        RET

SELECT_WALK_SPRITE:
        ; The original PC game uses frames 01..05 facing right and
        ; 0D..11 facing left (see e_rick.c's seq-to-sprite expression).
        LD      A,(PLAYER_DIRECTION)
        OR      A
        JP      NZ,SELECT_LEFT_WALK
        LD      HL,WALK_RIGHT_TABLE
        JP      SELECT_WALK_POINTER
SELECT_LEFT_WALK:
        LD      HL,WALK_LEFT_TABLE
SELECT_WALK_POINTER:
        LD      A,(WALK_FRAME)
        DEC     A
        ADD     A,A
        LD      E,A
        LD      D,00h
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)
        EX      DE,HL
        LD      (PLAYER_SPRITE_PTR),HL
        RET

SELECT_IDLE:
        CALL    SELECT_IDLE_SPRITE
        CALL    REDRAW_SCENE
        JP      MAIN_LOOP

SELECT_IDLE_SPRITE:
        LD      A,(PLAYER_DIRECTION)
        OR      A
        JP      NZ,IDLE_LEFT
        LD      HL,PCW_PLAYER_0B
        JP      IDLE_STORE
IDLE_LEFT:
        LD      HL,PCW_PLAYER_17
IDLE_STORE:
        LD      (PLAYER_SPRITE_PTR),HL
        RET

REDRAW_SCENE:
        ; This first test redraws the static background before each actor
        ; update. It is intentionally simple and makes background restoration
        ; exact; a dirty-rectangle update can replace it after movement works.
        CALL    RESTORE_TPA
        CALL    DRAW_BACKGROUND
        CALL    DRAW_PLAYER
        CALL    RESTORE_TPA
        RET

DRAW_BACKGROUND:
        LD      HL,PCW_BACKGROUND
        LD      (BACKGROUND_SOURCE),HL
        XOR     A
        LD      (SCREEN_Y),A

BACKGROUND_LINE:
        ; Read the source row while both normal CP/M TPA banks are mapped.
        LD      HL,(BACKGROUND_SOURCE)
        LD      DE,ROW_BUFFER
        LD      BC,90
        LDIR
        LD      (BACKGROUND_SOURCE),HL

        LD      A,(SCREEN_Y)
        CALL    GET_SCANLINE_PTR
        LD      (SCREEN_DEST),HL

        LD      HL,ROW_BUFFER
        LD      B,90
BACKGROUND_COPY_BYTE:
        LD      A,(HL)
        INC     HL
        PUSH    HL
        LD      HL,(SCREEN_DEST)
        LD      (HL),A
        LD      DE,0008h
        ADD     HL,DE
        LD      (SCREEN_DEST),HL
        POP     HL
        DJNZ    BACKGROUND_COPY_BYTE

        CALL    RESTORE_TPA
        LD      A,(SCREEN_Y)
        INC     A
        LD      (SCREEN_Y),A
        JP      NZ,BACKGROUND_LINE
        RET

DRAW_PLAYER:
        ; Copy the selected 96x28 masked sprite into low memory before
        ; any screen bank is mapped over the upper TPA address windows.
        CALL    RESTORE_TPA
        LD      HL,(PLAYER_SPRITE_PTR)
        LD      DE,PLAYER_BUFFER
        LD      BC,0672
        LDIR

        ; Screen x = ceil(original_x * 720 / 256).
        ; 720/256 = 45/16. Multiply by 45, add 15, then divide by 16.
        LD      A,(PLAYER_X)
        LD      L,A
        LD      H,00h
        PUSH    HL
        ADD     HL,HL                 ; 2x
        ADD     HL,HL                 ; 4x
        POP     DE                    ; x
        ADD     HL,DE                 ; 5x
        LD      D,H
        LD      E,L                   ; DE = 5x
        ADD     HL,HL                 ; 10x
        ADD     HL,HL                 ; 20x
        ADD     HL,HL                 ; 40x
        ADD     HL,DE                 ; 45x
        LD      DE,000Fh
        ADD     HL,DE
        SRL     H
        RR      L
        SRL     H
        RR      L
        SRL     H
        RR      L
        SRL     H
        RR      L
        LD      (PLAYER_SCREEN_X),HL

        LD      HL,PLAYER_BUFFER
        LD      DE,(PLAYER_SCREEN_X)
        LD      C,100                 ; original map y=75 -> screen y=100
        LD      B,12                  ; 96 source pixels, six transparent pad
        LD      A,28
        CALL    DRAW_MASKED_BITMAP
        CALL    RESTORE_TPA
        RET

EXIT_TO_CPM:
        DI
        CALL    RESTORE_TPA
        CALL    CLEAR_SCREEN
        CALL    RESTORE_TPA
        EI
        JP      0000h

; Clear the 90 visible bytes on all 256 scanlines.
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
        CALL    RESTORE_TPA
        INC     C
        JP      NZ,CLEAR_LINE
        RET

; Restore the normal CP/M Plus program banks.
RESTORE_TPA:
        LD      A,085h
        OUT     (0F1h),A
        LD      A,086h
        OUT     (0F2h),A
        RET

; Input A = scanline y. Return HL = CPU address of the first visible byte.
; The cached Roller-RAM table means banked video can be mapped independently
; while code and working buffers remain accessible below 4000h.
GET_SCANLINE_PTR:
        PUSH    DE
        LD      L,A
        LD      H,00h
        ADD     HL,HL
        LD      DE,RRAM_TABLE
        ADD     HL,DE
        LD      E,(HL)
        INC     HL
        LD      D,(HL)

        ; Physical bank = (Roller-RAM word >> 13) & 7.
        LD      A,D
        AND     0E0h
        SRL     A
        SRL     A
        SRL     A
        SRL     A
        SRL     A
        LD      (BANK_NO),A

        ; Offset = (word & 7) + 2 * (word & 1FF8h).
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
        CALL    RESTORE_TPA
        POP     DE
        RET

PTR_BANK1:
        LD      A,081h
        OUT     (0F1h),A
        LD      A,086h
        OUT     (0F2h),A
        LD      DE,04000h
        ADD     HL,DE
        POP     DE
        RET

PTR_BANK2:
        LD      A,085h
        OUT     (0F1h),A
        LD      A,082h
        OUT     (0F2h),A
        LD      DE,08000h
        ADD     HL,DE
        POP     DE
        RET

; Draw a variable-size masked bitmap at any pixel x.
; Input: HL=source MASK/PIXELS rows, DE=x, C=y, B=width bytes, A=height.
; The source is in PLAYER_BUFFER below 4000h, so it remains visible while
; either video bank is mapped. Each source byte can spill across two cells.
DRAW_MASKED_BITMAP:
        PUSH    BC
        PUSH    DE
        LD      (BITMAP_SOURCE),HL
        LD      (BITMAP_X),DE
        LD      (HEIGHT_LEFT),A
        LD      A,C
        LD      (BITMAP_Y),A
        LD      A,B
        LD      (WIDTH_BYTES),A

        LD      A,(HEIGHT_LEFT)
        OR      A
        JP      Z,BITMAP_DONE
        LD      A,(WIDTH_BYTES)
        OR      A
        JP      Z,BITMAP_DONE

        LD      A,D
        CP      02h
        JP      C,BITMAP_X_VALID
        JP      NZ,BITMAP_DONE
        LD      A,E
        CP      0D0h
        JP      NC,BITMAP_DONE

BITMAP_X_VALID:
        LD      A,E
        AND     07h
        LD      (ALIGNMENT),A
        LD      HL,(BITMAP_X)
        LD      A,L
        AND     0F8h
        LD      L,A
        LD      (BASE_X),HL
        LD      A,08h
        LD      B,A
        LD      A,(ALIGNMENT)
        LD      C,A
        LD      A,B
        SUB     C
        LD      (RIGHT_SHIFT),A

BITMAP_ROW:
        LD      A,(WIDTH_BYTES)
        LD      (COLS_LEFT),A
        LD      HL,(BASE_X)
        LD      (DEST_X),HL

BITMAP_COLUMN:
        LD      HL,(BITMAP_SOURCE)
        LD      A,(HL)
        LD      (SOURCE_MASK),A
        INC     HL
        LD      A,(HL)
        LD      (SOURCE_PIXELS),A
        INC     HL
        LD      (BITMAP_SOURCE),HL

        LD      HL,(DEST_X)
        LD      DE,02D0h
        OR      A
        SBC     HL,DE
        JP      NC,BITMAP_NEXT_COLUMN

        LD      A,(ALIGNMENT)
        OR      A
        JP      Z,LEFT_MASK_NO_SHIFT
        LD      B,A
        LD      A,(SOURCE_MASK)
LEFT_MASK_SHIFT:
        SRL     A
        DJNZ    LEFT_MASK_SHIFT
        JP      LEFT_MASK_SHIFTED
LEFT_MASK_NO_SHIFT:
        LD      A,(SOURCE_MASK)
LEFT_MASK_SHIFTED:
        LD      (LEFT_MASK),A
        LD      A,(ALIGNMENT)
        LD      E,A
        LD      D,00h
        LD      HL,LEFT_PAD_MASK
        ADD     HL,DE
        LD      A,(HL)
        LD      D,A
        LD      A,(LEFT_MASK)
        OR      D
        LD      (LEFT_MASK),A

        LD      A,(ALIGNMENT)
        OR      A
        JP      Z,LEFT_PIXELS_NO_SHIFT
        LD      B,A
        LD      A,(SOURCE_PIXELS)
LEFT_PIXELS_SHIFT:
        SRL     A
        DJNZ    LEFT_PIXELS_SHIFT
        JP      LEFT_PIXELS_SHIFTED
LEFT_PIXELS_NO_SHIFT:
        LD      A,(SOURCE_PIXELS)
LEFT_PIXELS_SHIFTED:
        LD      (LEFT_PIXELS),A

        LD      A,(RIGHT_SHIFT)
        LD      B,A
        LD      A,(SOURCE_MASK)
RIGHT_MASK_SHIFT:
        SLA     A
        DJNZ    RIGHT_MASK_SHIFT
        LD      (RIGHT_MASK),A
        LD      A,(ALIGNMENT)
        LD      E,A
        LD      D,00h
        LD      HL,RIGHT_PAD_MASK
        ADD     HL,DE
        LD      A,(HL)
        LD      D,A
        LD      A,(RIGHT_MASK)
        OR      D
        LD      (RIGHT_MASK),A

        LD      A,(RIGHT_SHIFT)
        LD      B,A
        LD      A,(SOURCE_PIXELS)
RIGHT_PIXELS_SHIFT:
        SLA     A
        DJNZ    RIGHT_PIXELS_SHIFT
        LD      (RIGHT_PIXELS),A

        LD      A,(BITMAP_Y)
        CALL    GET_SCANLINE_PTR
        LD      DE,(DEST_X)
        ADD     HL,DE
        LD      A,(HL)
        LD      D,A
        LD      A,(LEFT_MASK)
        AND     D
        LD      D,A
        LD      A,(LEFT_PIXELS)
        OR      D
        LD      (HL),A

        LD      A,(ALIGNMENT)
        OR      A
        JP      Z,BITMAP_NEXT_COLUMN

        LD      HL,(DEST_X)
        LD      DE,02C8h
        OR      A
        SBC     HL,DE
        JP      NC,BITMAP_NEXT_COLUMN

        LD      A,(BITMAP_Y)
        CALL    GET_SCANLINE_PTR
        LD      DE,(DEST_X)
        ADD     HL,DE
        LD      DE,0008h
        ADD     HL,DE

        LD      A,(HL)
        LD      D,A
        LD      A,(RIGHT_MASK)
        AND     D
        LD      D,A
        LD      A,(RIGHT_PIXELS)
        OR      D
        LD      (HL),A

BITMAP_NEXT_COLUMN:
        LD      HL,(DEST_X)
        LD      DE,0008h
        ADD     HL,DE
        LD      (DEST_X),HL
        LD      A,(COLS_LEFT)
        DEC     A
        LD      (COLS_LEFT),A
        JP      NZ,BITMAP_COLUMN

        LD      A,(BITMAP_Y)
        CP      0FFh
        JP      Z,BITMAP_DONE
        INC     A
        LD      (BITMAP_Y),A
        LD      A,(HEIGHT_LEFT)
        DEC     A
        LD      (HEIGHT_LEFT),A
        JP      NZ,BITMAP_ROW

BITMAP_DONE:
        POP     DE
        POP     BC
        RET

WALK_RIGHT_TABLE:
        DW      PCW_PLAYER_01,PCW_PLAYER_02,PCW_PLAYER_03
        DW      PCW_PLAYER_04,PCW_PLAYER_05
WALK_LEFT_TABLE:
        DW      PCW_PLAYER_0D,PCW_PLAYER_0E,PCW_PLAYER_0F
        DW      PCW_PLAYER_10,PCW_PLAYER_11

; Variables and buffers are part of the low-memory program code/data area.
BACKGROUND_SOURCE:
        DW      0000h
SCREEN_SOURCE:
        DW      0000h
SCREEN_DEST:
        DW      0000h
SCREEN_Y:
        DB      00h
PLAYER_X:
        DB      08h
PLAYER_DIRECTION:
        DB      00h                    ; 0=right, 1=left
WALK_FRAME:
        DB      01h                    ; 1..5
PLAYER_SPRITE_PTR:
        DW      0000h
PLAYER_SCREEN_X:
        DW      0000h
BANK_NO:
        DB      00h
LOW_BITS:
        DB      00h
BITMAP_SOURCE:
        DW      0000h
BITMAP_X:
        DW      0000h
BASE_X:
        DW      0000h
DEST_X:
        DW      0000h
BITMAP_Y:
        DB      00h
HEIGHT_LEFT:
        DB      00h
WIDTH_BYTES:
        DB      00h
COLS_LEFT:
        DB      00h
ALIGNMENT:
        DB      00h
RIGHT_SHIFT:
        DB      00h
SOURCE_MASK:
        DB      00h
SOURCE_PIXELS:
        DB      00h
LEFT_MASK:
        DB      00h
LEFT_PIXELS:
        DB      00h
RIGHT_MASK:
        DB      00h
RIGHT_PIXELS:
        DB      00h

LEFT_PAD_MASK:
        DB      00h,080h,0C0h,0E0h,0F0h,0F8h,0FCh,0FEh
RIGHT_PAD_MASK:
        DB      0FFh,07Fh,03Fh,01Fh,00Fh,007h,003h,001h

ROW_BUFFER:
        DS      90
PLAYER_BUFFER:
        DS      672
RRAM_TABLE:
        DS      512

        INCLUDE "build/PCWPLAYBG.INC"
        INCLUDE "build/PCWPLAYSPRITES.INC"

        END
