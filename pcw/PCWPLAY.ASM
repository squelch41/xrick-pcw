; PCWPLAY.ASM
; First interactive Rick Dangerous room for the Amstrad PCW 9256.
;
; Controls:
;   S = move left (one original game step; also steers left in the air)
;   D = move right (one original game step; also steers right in the air)
;   W = jump (runs the full jump arc and lands)
;   I = stand still / restore idle pose
;   B = redraw background only (diagnostic)
;   P = draw the current player only (diagnostic; use after B)
;   1..5 = display an individual left-facing walk frame at the start position
;   V = draw left-facing frame 5 directly, bypassing frame selection
;   Q = clear the display and return to CP/M
;
; This milestone adds the original PC jump impulse and jump poses, plus
; S/D air steering and collision against first-room solid tiles. Landing
; still returns to the initial fixed floor height; gaps, falling and scrolling
; are not implemented yet.
; Walking remains one original game step per keypress.
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
        LD      A,100
        LD      (PLAYER_SCREEN_Y),A
        LD      HL,06400h
        LD      (PLAYER_Y_FP),HL
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
        CP      057h                  ; W
        JP      Z,START_JUMP
        CP      077h                  ; w
        JP      Z,START_JUMP
        CP      049h                  ; I
        JP      Z,SELECT_IDLE
        CP      069h                  ; i
        JP      Z,SELECT_IDLE
        CP      042h                  ; B: background only, for diagnosis
        JP      Z,REDRAW_BACKGROUND_ONLY
        CP      062h                  ; b
        JP      Z,REDRAW_BACKGROUND_ONLY
        CP      050h                  ; P: player only, for diagnosis
        JP      Z,DRAW_PLAYER_ONLY
        CP      070h                  ; p
        JP      Z,DRAW_PLAYER_ONLY
        CP      056h                  ; V: draw left-walk frame 5 directly
        JP      Z,TEST_LEFT_FRAME_5
        CP      076h                  ; v
        JP      Z,TEST_LEFT_FRAME_5
        CP      031h                  ; 1..5: inspect individual left walk frames
        JP      C,MAIN_LOOP
        CP      036h                  ; accept 1 through 5 inclusive
        JP      NC,MAIN_LOOP
        SUB     030h
        LD      (WALK_FRAME),A
        LD      A,01h
        LD      (PLAYER_DIRECTION),A
        LD      A,08h
        LD      (PLAYER_X),A
        CALL    SELECT_WALK_SPRITE
        CALL    REDRAW_SCENE
        JP      MAIN_LOOP

; Bypass the numeric diagnostic and frame lookup table completely.
; This checks whether sprite 0x11 itself can be copied and drawn.
TEST_LEFT_FRAME_5:
        LD      A,01h
        LD      (PLAYER_DIRECTION),A
        LD      A,08h
        LD      (PLAYER_X),A
        LD      HL,PCW_PLAYER_11
        LD      (PLAYER_SPRITE_PTR),HL
        CALL    REDRAW_SCENE
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
        CP      0E6h                  ; final in-room position = 230
        JP      NC,RIGHT_STEP_DONE
        ADD     A,02h
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

; Start a complete jump using the original PC game's initial impulse and
; gravity, scaled from 256x192 game coordinates to the 720x256 PCW display.
; S/D can steer in the air; first-room solid tiles stop head/side movement.
; Landing still uses the fixed initial floor height in this milestone.
START_JUMP:
        LD      A,(PLAYER_DIRECTION)
        OR      A
        JP      NZ,START_JUMP_LEFT
        LD      HL,PCW_PLAYER_06
        JP      START_JUMP_FRAME
START_JUMP_LEFT:
        LD      HL,PCW_PLAYER_15
START_JUMP_FRAME:
        LD      (PLAYER_SPRITE_PTR),HL
        LD      HL,06400h              ; screen y=100 in 8.8 fixed point
        LD      (PLAYER_Y_FP),HL
        LD      HL,0F8ABh              ; -7.332 PCW pixels/update (~ -5.5 game px)
        LD      (JUMP_VELOCITY),HL

JUMP_UPDATE:
        ; Poll once per airborne frame so S/D can steer Rick in mid-air.
        CALL    JUMP_POLL_INPUT

        ; Integrate vertical position, retaining the old value for collision.
        LD      HL,(PLAYER_Y_FP)
        LD      (OLD_PLAYER_Y_FP),HL
        LD      DE,(JUMP_VELOCITY)
        ADD     HL,DE
        LD      (PLAYER_Y_FP),HL

        ; Reaching or passing the original standing height means landing.
        LD      A,H
        CP      100
        JP      NC,JUMP_LANDED

        ; Check the candidate body against the first room's real tile flags.
        LD      (NEW_SCREEN_Y),A
        LD      (AIR_CHECK_Y),A
        LD      A,(PLAYER_X)
        CALL    CHECK_AIR_POSITION
        JP      C,JUMP_HIT_OBSTACLE
        LD      A,(NEW_SCREEN_Y)
        LD      (PLAYER_SCREEN_Y),A
        JP      JUMP_DRAW_FRAME

JUMP_HIT_OBSTACLE:
        ; Stop upward movement at a solid tile. Gravity then makes Rick fall.
        LD      HL,(OLD_PLAYER_Y_FP)
        LD      (PLAYER_Y_FP),HL
        LD      HL,0000h
        LD      (JUMP_VELOCITY),HL

JUMP_DRAW_FRAME:
        CALL    REDRAW_SCENE

        ; Original PC gravity is +0.5 game pixels/update, scaled for the PCW.
        LD      HL,(JUMP_VELOCITY)
        LD      DE,000AAh
        ADD     HL,DE
        LD      (JUMP_VELOCITY),HL
        CALL    JUMP_DELAY
        JP      JUMP_UPDATE

JUMP_LANDED:
        LD      HL,06400h
        LD      (PLAYER_Y_FP),HL
        LD      A,100
        LD      (PLAYER_SCREEN_Y),A
        CALL    SELECT_IDLE_SPRITE
        CALL    REDRAW_SCENE
        JP      MAIN_LOOP

; A short pause keeps successive jump poses visible in Joyce and on hardware.
JUMP_DELAY:
        LD      BC,0800h
JUMP_DELAY_LOOP:
        DEC     BC
        LD      A,B
        OR      C
        JP      NZ,JUMP_DELAY_LOOP
        RET

; Read one key during each jump frame. S/D adjust X by the original two-pixel
; game step and select the matching jump pose. Tile flags reject blocked moves.
JUMP_POLL_INPUT:
        LD      C,06h
        LD      E,0FFh
        CALL    0005h
        OR      A
        RET     Z
        CP      053h                  ; S
        JP      Z,AIR_TURN_LEFT
        CP      073h                  ; s
        JP      Z,AIR_TURN_LEFT
        CP      044h                  ; D
        JP      Z,AIR_TURN_RIGHT
        CP      064h                  ; d
        JP      Z,AIR_TURN_RIGHT
        RET

AIR_TURN_LEFT:
        LD      A,01h
        LD      (PLAYER_DIRECTION),A
        LD      HL,PCW_PLAYER_15
        LD      (PLAYER_SPRITE_PTR),HL
        LD      A,(PLAYER_X)
        CP      02h
        RET     C
        SUB     02h
        JP      AIR_TRY_MOVE

AIR_TURN_RIGHT:
        XOR     A
        LD      (PLAYER_DIRECTION),A
        LD      HL,PCW_PLAYER_06
        LD      (PLAYER_SPRITE_PTR),HL
        LD      A,(PLAYER_X)
        CP      0E6h
        RET     NC
        ADD     A,02h

AIR_TRY_MOVE:
        LD      (CANDIDATE_X),A
        LD      A,(PLAYER_SCREEN_Y)
        LD      (AIR_CHECK_Y),A
        LD      A,(CANDIDATE_X)
        CALL    CHECK_AIR_POSITION
        RET     C
        LD      A,(CANDIDATE_X)
        LD      (PLAYER_X),A
        RET

; Check the player's approximate original PC collision box against the
; first room's 32x24 tile flags. Input A=candidate game X and AIR_CHECK_Y
; is the candidate top scanline. Carry means blocked.
CHECK_AIR_POSITION:
        LD      (CANDIDATE_X),A

        ; Collision box spans game X+5 through X+17. Check left, middle,
        ; and right tile columns to cover the full 13-pixel body width.
        LD      L,A
        LD      H,00h
        LD      DE,0005h
        ADD     HL,DE
        SRL     H
        RR      L
        SRL     H
        RR      L
        SRL     H
        RR      L
        LD      A,L
        LD      (AIR_COL_LEFT),A
        INC     A
        LD      (AIR_COL_MID),A

        LD      A,(CANDIDATE_X)
        LD      L,A
        LD      H,00h
        LD      DE,0011h
        ADD     HL,DE
        SRL     H
        RR      L
        SRL     H
        RR      L
        SRL     H
        RR      L
        LD      A,L
        LD      (AIR_COL_RIGHT),A

        ; The original body is 21 scanlines high; the PCW sprite is 28.
        LD      A,(AIR_CHECK_Y)
        CALL    SCREEN_TO_MAP_ROW
        LD      (AIR_ROW_TOP),A
        LD      A,(AIR_CHECK_Y)
        ADD     A,14
        CALL    SCREEN_TO_MAP_ROW
        LD      (AIR_ROW_MID),A
        LD      A,(AIR_CHECK_Y)
        ADD     A,27
        CALL    SCREEN_TO_MAP_ROW
        LD      (AIR_ROW_BOTTOM),A

        LD      A,(AIR_ROW_TOP)
        CALL    CHECK_AIR_ROW
        RET     C
        LD      A,(AIR_ROW_MID)
        CALL    CHECK_AIR_ROW
        RET     C
        LD      A,(AIR_ROW_BOTTOM)
        CALL    CHECK_AIR_ROW
        RET

; Convert a PCW scanline to the visible room's tile-row index:
; floor(scanline * 3 / 32). Input/output A.
SCREEN_TO_MAP_ROW:
        LD      L,A
        LD      H,00h
        LD      D,H
        LD      E,L                   ; DE = y
        ADD     HL,HL                 ; 2*y
        ADD     HL,DE                 ; 3*y
        LD      B,05h
SCREEN_ROW_SHIFT:
        SRL     H
        RR      L
        DJNZ    SCREEN_ROW_SHIFT
        LD      A,L
        RET

; Check three columns on one tile row. Input A=row index.
CHECK_AIR_ROW:
        LD      (AIR_TEST_ROW),A
        LD      A,(AIR_COL_LEFT)
        LD      C,A
        LD      A,(AIR_TEST_ROW)
        LD      B,A
        CALL    CHECK_AIR_TILE
        RET     C
        LD      A,(AIR_COL_MID)
        LD      C,A
        LD      A,(AIR_TEST_ROW)
        LD      B,A
        CALL    CHECK_AIR_TILE
        RET     C
        LD      A,(AIR_COL_RIGHT)
        LD      C,A
        LD      A,(AIR_TEST_ROW)
        LD      B,A
        JP      CHECK_AIR_TILE

; Input B=row, C=column. SOLID, SPAD and WAYUP all block this simple
; first-room movement test. Out-of-grid positions are treated as blocked.
CHECK_AIR_TILE:
        LD      A,B
        CP      24
        JP      NC,AIR_TILE_BLOCKED
        LD      A,C
        CP      32
        JP      NC,AIR_TILE_BLOCKED
        LD      H,B
        LD      L,00h
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL                 ; row * 32
        LD      E,C
        LD      D,00h
        ADD     HL,DE
        LD      DE,PCW_ROOM_FLAGS
        ADD     HL,DE
        LD      A,(HL)
        AND     070h
        JP      Z,AIR_TILE_CLEAR
AIR_TILE_BLOCKED:
        SCF
        RET
AIR_TILE_CLEAR:
        OR      A
        RET

; Diagnostic split: B redraws only the room, P draws only the current
; player over that room. This distinguishes background banking from the
; masked-sprite renderer without changing the normal D/S/I behaviour.
REDRAW_BACKGROUND_ONLY:
        ; Video-bank remapping and writes must be atomic with respect to the
        ; PCW interrupt handler. PCWROOM keeps interrupts disabled throughout.
        DI
        CALL    RESTORE_TPA
        CALL    DRAW_BACKGROUND
        CALL    RESTORE_TPA
        EI
        JP      MAIN_LOOP

DRAW_PLAYER_ONLY:
        DI
        CALL    RESTORE_TPA
        CALL    DRAW_PLAYER
        CALL    RESTORE_TPA
        EI
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
        ; Keep interrupts disabled while the video banks are remapped and
        ; written. This matches the working PCWROOM renderer.
        DI
        CALL    RESTORE_TPA
        CALL    DRAW_BACKGROUND
        CALL    DRAW_PLAYER
        CALL    RESTORE_TPA
        EI
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
        LD      BC,672
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
        LD      A,(PLAYER_SCREEN_Y)
        LD      C,A
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
        ; Match the proven PCWROOM renderer: map only the window that
        ; contains this scanline. Leave the other bank window untouched.
        LD      A,081h
        OUT     (0F1h),A
        LD      DE,04000h
        ADD     HL,DE
        POP     DE
        RET

PTR_BANK2:
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
PLAYER_SCREEN_Y:
        DB      100
PLAYER_Y_FP:
        DW      06400h
OLD_PLAYER_Y_FP:
        DW      06400h
JUMP_VELOCITY:
        DW      0000h
NEW_SCREEN_Y:
        DB      100
AIR_CHECK_Y:
        DB      100
CANDIDATE_X:
        DB      08h
AIR_COL_LEFT:
        DB      00h
AIR_COL_MID:
        DB      00h
AIR_COL_RIGHT:
        DB      00h
AIR_ROW_TOP:
        DB      00h
AIR_ROW_MID:
        DB      00h
AIR_ROW_BOTTOM:
        DB      00h
AIR_TEST_ROW:
        DB      00h
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
        INCLUDE "build/PCWPLAYCOLLISION.INC"

        END
