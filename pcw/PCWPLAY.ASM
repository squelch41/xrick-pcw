; PCWPLAY.ASM
; First interactive Rick Dangerous room for the Amstrad PCW 9256.
;
; Controls:
;   A = move left (also steers left in the air)
;   D = move right (also steers right in the air)
;   W = jump
;   S = crouch / stand; crawl with A or D while crouched
;   I = restore the idle pose
;   Q = clear the display and return to CP/M
;
; This milestone adds the original PC jump impulse and jump poses, plus
; S/D air steering and collision against first-room solid tiles. Rick now
; lands on tile surfaces and falls when walking off an edge.
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
        LD      A,00h
        CALL    SET_ROOM_DATA

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
        CP      041h                  ; A
        JP      Z,MOVE_LEFT
        CP      061h                  ; a
        JP      Z,MOVE_LEFT
        CP      053h                  ; S: crouch / stand
        JP      Z,TOGGLE_CROUCH
        CP      073h                  ; s
        JP      Z,TOGGLE_CROUCH
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
MOVE_LEFT:
        LD      A,01h
        LD      (PLAYER_DIRECTION),A
        LD      A,(CROUCHING)
        OR      A
        JP      NZ,CRAWL_LEFT
        LD      A,(PLAYER_X)
        CP      02h
        JP      C,GROUND_MOVE_BLOCKED
        JP      Z,GROUND_TRY_PREVIOUS_ROOM
        SUB     02h
        JP      GROUND_TRY_MOVE

MOVE_RIGHT:
        XOR     A
        LD      (PLAYER_DIRECTION),A
        LD      A,(CROUCHING)
        OR      A
        JP      NZ,CRAWL_RIGHT
        LD      A,(PLAYER_X)
        CP      0E6h                  ; crossing from x=230 enters next submap
        JP      NC,GROUND_TRY_NEXT_ROOM
        ADD     A,02h

GROUND_TRY_MOVE:
        ; Test the complete player box at the current height before moving.
        ; This prevents walking through solid room tiles, not just the room edge.
        LD      (CANDIDATE_X),A
        LD      A,(PLAYER_SCREEN_Y)
        LD      (AIR_CHECK_Y),A
        LD      A,(CANDIDATE_X)
        CALL    CHECK_AIR_POSITION
        JP      C,GROUND_MOVE_BLOCKED
        LD      A,(CANDIDATE_X)
        LD      (PLAYER_X),A

        ; Probe one original game pixel lower to determine whether Rick
        ; is still supported. The offset is 1 or 2 PCW scanlines depending
        ; on the resampling phase (exactly one source-game pixel).
        LD      A,(PLAYER_SCREEN_Y)
        AND     03h
        LD      A,(PLAYER_SCREEN_Y)
        JP      NZ,GROUND_SUPPORT_Y_NEXT
        ADD     A,02h
        JP      GROUND_SUPPORT_Y_READY
GROUND_SUPPORT_Y_NEXT:
        INC     A
GROUND_SUPPORT_Y_READY:
        LD      (AIR_CHECK_Y),A
        LD      A,(PLAYER_X)
        CALL    CHECK_AIR_POSITION
        JP      C,GROUND_HAS_SUPPORT
        CALL    START_FALL

GROUND_HAS_SUPPORT:
        CALL    ADVANCE_WALK_FRAME
        CALL    SELECT_WALK_SPRITE
        CALL    REDRAW_SCENE
        JP      MAIN_LOOP

GROUND_TRY_NEXT_ROOM:
        CALL    TRANSITION_RIGHT
        JP      C,GROUND_MOVE_BLOCKED
        CALL    ADVANCE_WALK_FRAME
        CALL    SELECT_WALK_SPRITE
        CALL    REDRAW_SCENE
        JP      MAIN_LOOP

GROUND_TRY_PREVIOUS_ROOM:
        CALL    TRANSITION_LEFT
        JP      C,GROUND_MOVE_BLOCKED
        CALL    ADVANCE_WALK_FRAME
        CALL    SELECT_WALK_SPRITE
        CALL    REDRAW_SCENE
        JP      MAIN_LOOP

GROUND_MOVE_BLOCKED:
        CALL    SELECT_IDLE_SPRITE
        CALL    REDRAW_SCENE
        JP      MAIN_LOOP

; S toggles crouching. Rick uses the original crawl frames while moving.
TOGGLE_CROUCH:
        LD      A,(CROUCHING)
        OR      A
        JP      NZ,STAND_UP
        LD      A,01h
        LD      (CROUCHING),A
        LD      A,00h
        LD      (CRAWL_FRAME),A
        CALL    SELECT_CRAWL_SPRITE
        CALL    REDRAW_SCENE
        JP      MAIN_LOOP

STAND_UP:
        ; Temporarily use the standing collision box. Do not stand if the
        ; full-height player box would overlap a ceiling or other solid tile.
        XOR     A
        LD      (CROUCHING),A
        LD      A,(PLAYER_SCREEN_Y)
        LD      (AIR_CHECK_Y),A
        LD      A,(PLAYER_X)
        CALL    CHECK_AIR_POSITION
        JP      NC,STAND_UP_CLEAR
        LD      A,01h
        LD      (CROUCHING),A
        CALL    SELECT_CRAWL_SPRITE
        CALL    REDRAW_SCENE
        JP      MAIN_LOOP
STAND_UP_CLEAR:
        CALL    SELECT_IDLE_SPRITE
        CALL    REDRAW_SCENE
        JP      MAIN_LOOP

CRAWL_LEFT:
        LD      A,(PLAYER_X)
        CP      02h
        JP      C,CRAWL_BLOCKED
        SUB     02h
        JP      CRAWL_TRY_MOVE

CRAWL_RIGHT:
        LD      A,(PLAYER_X)
        CP      0E6h
        JP      NC,CRAWL_BLOCKED
        ADD     A,02h

CRAWL_TRY_MOVE:
        LD      (CANDIDATE_X),A
        LD      A,(PLAYER_SCREEN_Y)
        LD      (AIR_CHECK_Y),A
        LD      A,(CANDIDATE_X)
        CALL    CHECK_AIR_POSITION
        JP      C,CRAWL_BLOCKED
        LD      A,(CANDIDATE_X)
        LD      (PLAYER_X),A
        LD      A,(CRAWL_FRAME)
        XOR     01h
        LD      (CRAWL_FRAME),A
        CALL    SELECT_CRAWL_SPRITE
        CALL    REDRAW_SCENE
        JP      MAIN_LOOP

CRAWL_BLOCKED:
        CALL    SELECT_CRAWL_SPRITE
        CALL    REDRAW_SCENE
        JP      MAIN_LOOP

SELECT_CRAWL_SPRITE:
        LD      A,(PLAYER_DIRECTION)
        OR      A
        JP      NZ,CRAWL_LEFT_SPRITE
        LD      A,(CRAWL_FRAME)
        OR      A
        JP      NZ,CRAWL_RIGHT_FRAME_2
        LD      HL,PCW_PLAYER_07
        JP      CRAWL_SPRITE_STORE
CRAWL_RIGHT_FRAME_2:
        LD      HL,PCW_PLAYER_08
        JP      CRAWL_SPRITE_STORE
CRAWL_LEFT_SPRITE:
        LD      HL,PCW_PLAYER_13
CRAWL_SPRITE_STORE:
        LD      (PLAYER_SPRITE_PTR),HL
        RET

; Begin falling with zero initial vertical speed. JUMP_UPDATE supplies gravity,
; collision and air steering, but unlike START_JUMP this has no upward impulse.
START_FALL:
        LD      A,(PLAYER_DIRECTION)
        OR      A
        JP      NZ,START_FALL_LEFT
        LD      HL,PCW_PLAYER_06
        JP      START_FALL_FRAME
START_FALL_LEFT:
        LD      HL,PCW_PLAYER_15
START_FALL_FRAME:
        LD      (PLAYER_SPRITE_PTR),HL
        LD      HL,0000h
        LD      (JUMP_VELOCITY),HL
        JP      JUMP_UPDATE

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

; Start a complete jump from the current standing height, using the
; original PC game's initial impulse and gravity scaled to the PCW display.
; S/D can steer in the air; first-room tiles stop movement and support landing.
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

        ; The first submap extends below this viewport. In the right-hand
        ; drop shaft, scroll to the next pre-rendered eight-tile view before
        ; Rick reaches the lower edge. After the fourth view, row 38h is the
        ; connector into submap 1.
        LD      A,(ROOM_INDEX)
        OR      A
        JP      NZ,JUMP_SCROLL_THRESHOLD
        LD      A,(ROOM_SCROLL)
        CP      03h
        JP      NZ,JUMP_SCROLL_THRESHOLD
        LD      A,H
        CP      0ABh                  ; connector row 38h in the fourth view
        JP      C,JUMP_SCROLL_THRESHOLD
        CALL    TRY_DROP_ROOM_TRANSITION
        JP      C,JUMP_SCROLL_THRESHOLD
        JP      MAIN_LOOP

JUMP_SCROLL_THRESHOLD:
        LD      A,H
        CP      0BBh                  ; scroll when Rick reaches y=187
        JP      C,JUMP_CHECK_BOTTOM
        CP      0E4h
        JP      NC,JUMP_BOTTOM_LIMIT
        ; Scroll only if the candidate body is clear of platforms and walls.
        LD      (AIR_CHECK_Y),A
        LD      A,(PLAYER_X)
        CALL    CHECK_AIR_POSITION
        JP      C,JUMP_HIT_OBSTACLE
        CALL    TRY_ROOM_SCROLL
        JP      C,JUMP_DRAW_FRAME

JUMP_CHECK_BOTTOM:
        LD      A,H
        CP      0E4h                  ; keep the 28-pixel sprite on-screen
        JP      NC,JUMP_BOTTOM_LIMIT
        LD      (NEW_SCREEN_Y),A
        LD      (AIR_CHECK_Y),A
        LD      A,(PLAYER_X)
        CALL    CHECK_AIR_POSITION
        JP      C,JUMP_HIT_OBSTACLE
        LD      A,(NEW_SCREEN_Y)
        LD      (PLAYER_SCREEN_Y),A
        JP      JUMP_DRAW_FRAME

JUMP_BOTTOM_LIMIT:
        ; Fallback bottom limit. The normal first-room connector is handled
        ; earlier, after the fourth viewport has scrolled into place.
        CALL    TRY_DROP_ROOM_TRANSITION
        JP      C,JUMP_LANDED
        JP      MAIN_LOOP

JUMP_HIT_OBSTACLE:
        ; A collision while rising is a ceiling bonk; while falling it is
        ; a landing. In both cases retain the last non-overlapping position.
        LD      HL,(JUMP_VELOCITY)
        BIT     7,H
        JP      Z,JUMP_LANDED
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
        ; Keep the last safe position rather than snapping back to y=100.
        LD      HL,(OLD_PLAYER_Y_FP)
        LD      (PLAYER_Y_FP),HL
        LD      A,H
        LD      (PLAYER_SCREEN_Y),A
        LD      HL,0000h
        LD      (JUMP_VELOCITY),HL
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
        CP      041h                  ; A
        JP      Z,AIR_TURN_LEFT
        CP      061h                  ; a
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
        JP      Z,AIR_TRY_PREVIOUS_ROOM
        SUB     02h
        JP      AIR_TRY_MOVE

AIR_TURN_RIGHT:
        XOR     A
        LD      (PLAYER_DIRECTION),A
        LD      HL,PCW_PLAYER_06
        LD      (PLAYER_SPRITE_PTR),HL
        LD      A,(PLAYER_X)
        CP      0E6h
        JP      NC,AIR_TRY_NEXT_ROOM
        ADD     A,02h
        JP      AIR_TRY_MOVE

AIR_TRY_NEXT_ROOM:
        CALL    TRANSITION_RIGHT
        RET

AIR_TRY_PREVIOUS_ROOM:
        CALL    TRANSITION_LEFT
        RET

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

        ; Match the original PC probe: start at X+4, checking two columns
        ; when aligned to an 8-pixel tile or three when unaligned.
        ADD     A,04h
        LD      B,A
        AND     07h
        LD      A,02h
        JP      Z,AIR_COLUMN_COUNT_READY
        INC     A
AIR_COLUMN_COUNT_READY:
        LD      (AIR_COL_COUNT),A
        LD      A,B
        SRL     A
        SRL     A
        SRL     A
        LD      (AIR_COL_LEFT),A
        INC     A
        LD      (AIR_COL_MID),A
        INC     A
        LD      (AIR_COL_RIGHT),A

        ; Convert the PCW scanline to source-game Y = floor(3*Y/4).
        ; The original probe changes height depending on source Y bit 2.
        LD      A,(AIR_CHECK_Y)
        LD      L,A
        LD      H,00h
        LD      D,H
        LD      E,L
        ADD     HL,HL
        ADD     HL,DE
        SRL     H
        RR      L
        SRL     H
        RR      L
        LD      A,L
        LD      B,A
        AND     04h
        LD      C,A
        LD      A,B
        SRL     A
        SRL     A
        SRL     A
        LD      (AIR_TEST_ROW),A

        ; Standing checks three/four rows. Crawling skips the upper
        ; clearance row and checks only two/three, as u_envtest() does.
        LD      A,(CROUCHING)
        OR      A
        JP      Z,AIR_STANDING_ROW_START
        LD      A,(AIR_TEST_ROW)
        INC     A
        LD      (AIR_TEST_ROW),A
        LD      A,02h
        JP      AIR_ROW_COUNT_BASE
AIR_STANDING_ROW_START:
        LD      A,03h
AIR_ROW_COUNT_BASE:
        LD      B,A
        LD      A,C
        OR      A
        JP      Z,AIR_ROW_COUNT_READY
        INC     B
AIR_ROW_COUNT_READY:
        LD      A,B
        LD      (AIR_ROWS_LEFT),A

AIR_POSITION_ROW_LOOP:
        LD      A,(AIR_TEST_ROW)
        CALL    CHECK_AIR_ROW
        RET     C
        LD      A,(AIR_TEST_ROW)
        INC     A
        LD      (AIR_TEST_ROW),A
        LD      A,(AIR_ROWS_LEFT)
        DEC     A
        LD      (AIR_ROWS_LEFT),A
        JP      NZ,AIR_POSITION_ROW_LOOP
        OR      A
        RET

; Check two/three columns on one tile row. Input A=row index.
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
        LD      A,(AIR_COL_COUNT)
        CP      03h
        RET     NZ
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
        LD      H,00h
        LD      L,B
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL                 ; row * 32
        LD      E,C
        LD      D,00h
        ADD     HL,DE
        LD      DE,(ROOM_FLAGS_PTR)
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

; Select the connector table belonging to the current room.
GET_ROOM_CONNECTORS:
        LD      A,(ROOM_INDEX)
        OR      A
        JP      Z,ROOM0_CONNECTORS_PTR
        CP      01h
        JP      Z,ROOM1_CONNECTORS_PTR
        LD      HL,PCW_ROOM2_CONNECTORS
        RET
ROOM0_CONNECTORS_PTR:
        LD      HL,PCW_ROOM0_CONNECTORS
        RET
ROOM1_CONNECTORS_PTR:
        LD      HL,PCW_ROOM1_CONNECTORS
        RET

; The right connector is record 1 (destination at offset 6); the left
; connector is record 0 (destination at offset 2). FF means no connection.
TRANSITION_RIGHT:
        CALL    GET_ROOM_CONNECTORS
        LD      DE,0006h
        ADD     HL,DE
        LD      A,(HL)
        CP      03h                  ; only the first three rooms are loaded
        JP      NC,ROOM_TRANSITION_BLOCKED
        CALL    SET_ROOM_DATA
        LD      A,04h                 ; original PC re-entry X from the left
        LD      (PLAYER_X),A
        OR      A
        RET

TRANSITION_LEFT:
        CALL    GET_ROOM_CONNECTORS
        LD      DE,0002h
        ADD     HL,DE
        LD      A,(HL)
        CP      03h                  ; includes FF sentinel / no previous room
        JP      NC,ROOM_TRANSITION_BLOCKED
        CALL    SET_ROOM_DATA
        LD      A,0E2h                ; original PC re-entry X from the right
        LD      (PLAYER_X),A
        OR      A
        RET

ROOM_TRANSITION_BLOCKED:
        SCF
        RET

; At connector row 38h in the fourth view, the drop shaft occupies original
; game X 192..223 (tile columns 24..27). Rick's collision box is X+5..X+17,
; so his origin must be 187..206 to fit the sampled body inside the shaft.
TRY_DROP_ROOM_TRANSITION:
        LD      A,(ROOM_INDEX)
        OR      A
        JP      NZ,DROP_EXIT_NOT_FOUND
        LD      A,(ROOM_SCROLL)
        CP      03h                  ; connector row 38h is in the fourth view
        JP      NZ,DROP_EXIT_NOT_FOUND
        LD      A,(PLAYER_X)
        CP      0BBh                  ; first possible origin: 192 - 5
        JP      C,DROP_EXIT_NOT_FOUND
        CP      0CFh                  ; exclusive end: 223 - 17 + 1
        JP      NC,DROP_EXIT_NOT_FOUND

        ; Enter the next submap at its normal starting height. The original
        ; game keeps Rick in the playfield while the map scrolls underneath him;
        ; our fixed-screen version represents that with the standard entry Y.
        LD      HL,06400h
        LD      (PLAYER_Y_FP),HL
        LD      A,100
        LD      (PLAYER_SCREEN_Y),A
        LD      HL,0000h
        LD      (JUMP_VELOCITY),HL
        CALL    TRANSITION_RIGHT
        RET     C
        CALL    SELECT_IDLE_SPRITE
        CALL    REDRAW_SCENE
        OR      A                       ; report successful transition
        RET

DROP_EXIT_NOT_FOUND:
        SCF
        RET

; Advance the tall first submap by eight source tile rows. The PCW version
; switches between pre-rendered views but shifts Rick upward by the same
; 85 screen pixels, preserving his position relative to the map.
TRY_ROOM_SCROLL:
        LD      A,(ROOM_INDEX)
        OR      A
        JP      NZ,ROOM_SCROLL_NOT_DONE
        LD      A,(ROOM_SCROLL)
        CP      03h
        JP      NC,ROOM_SCROLL_NOT_DONE
        INC     A
        LD      (ROOM_SCROLL),A
        LD      HL,(PLAYER_Y_FP)
        ; PLAYER_Y_FP is 8.8 fixed point. Eight source tile rows scale
        ; to 85.333 PCW pixels, so use 85, 86, 85 to keep cumulative
        ; displacement at exactly 256 pixels across the three scrolls.
        LD      DE,0AB00h              ; -85.0 pixels
        LD      A,(ROOM_SCROLL)
        CP      02h
        JP      NZ,ROOM_SCROLL_SHIFT_READY
        LD      DE,0AA00h              ; -86.0 pixels on the second scroll
ROOM_SCROLL_SHIFT_READY:
        ADD     HL,DE
        LD      (PLAYER_Y_FP),HL
        LD      A,H
        LD      (PLAYER_SCREEN_Y),A

        ; Move the existing 256-line raster up 85 lines, then unpack only
        ; the newly exposed 85-line strip into its bottom.
        LD      HL,PCW_BACKGROUND+01DE2h
        LD      DE,PCW_BACKGROUND
        LD      BC,03C1Eh
        LDIR

        ; Keep the collision viewport aligned: shift up eight tile rows,
        ; then append the next eight-row collision strip.
        LD      HL,ROOM_FLAGS_BUFFER+0100h
        LD      DE,ROOM_FLAGS_BUFFER
        LD      BC,0200h
        LDIR
        LD      A,(ROOM_SCROLL)
        CP      01h
        JP      Z,ROOM_SCROLL_FLAGS_1
        CP      02h
        JP      Z,ROOM_SCROLL_FLAGS_2
        LD      HL,PCW_ROOM0_SCROLL3_FLAGS
        JP      ROOM_SCROLL_FLAGS_COPY
ROOM_SCROLL_FLAGS_1:
        LD      HL,PCW_ROOM0_SCROLL1_FLAGS
        JP      ROOM_SCROLL_FLAGS_COPY
ROOM_SCROLL_FLAGS_2:
        LD      HL,PCW_ROOM0_SCROLL2_FLAGS
ROOM_SCROLL_FLAGS_COPY:
        LD      DE,ROOM_FLAGS_BUFFER+0200h
        LD      BC,0100h
        CALL    UNPACK_COLLISION_FLAGS

        CALL    DECOMPRESS_ROOM_SCROLL_STRIP
        SCF
        RET
ROOM_SCROLL_NOT_DONE:
        OR      A                       ; clear carry: no viewport change
        RET

; A = destination submap. Select its collision flags and decompress its
; pre-rendered 720x256 background into the reusable PCW_BACKGROUND buffer.
SET_ROOM_DATA:
        LD      (ROOM_INDEX),A
        XOR     A
        LD      (ROOM_SCROLL),A
        CALL    SELECT_ROOM_FLAGS
        ; Expand the packed 4-bit collision classes into the writable
        ; one-byte-per-tile viewport used by the movement checks.
        LD      A,(ROOM_INDEX)
        OR      A
        JP      Z,ROOM0_COLLISION_SOURCE
        CP      01h
        JP      Z,ROOM1_COLLISION_SOURCE
        LD      HL,PCW_ROOM2_FLAGS
        JP      ROOM_COLLISION_SOURCE_READY
ROOM0_COLLISION_SOURCE:
        LD      HL,PCW_ROOM0_FLAGS
        JP      ROOM_COLLISION_SOURCE_READY
ROOM1_COLLISION_SOURCE:
        LD      HL,PCW_ROOM1_FLAGS
ROOM_COLLISION_SOURCE_READY:
        LD      DE,ROOM_FLAGS_BUFFER
        LD      BC,0300h
        CALL    UNPACK_COLLISION_FLAGS
        CALL    DECOMPRESS_ROOM_BACKGROUND
        RET

SELECT_ROOM_FLAGS:
        LD      HL,ROOM_FLAGS_BUFFER
        LD      (ROOM_FLAGS_PTR),HL
        RET

; Expand two 4-bit collision classes per source byte into full flag bytes.
; Input HL=packed source, DE=destination, BC=number of output cells (even).
UNPACK_COLLISION_FLAGS:
COLLISION_UNPACK_LOOP:
        LD      A,(HL)
        INC     HL
        LD      (COLLISION_PACKED),A
        AND     00Fh
        RLCA
        RLCA
        RLCA
        RLCA
        LD      (DE),A
        INC     DE
        DEC     BC
        LD      A,B
        OR      C
        RET     Z
        LD      A,(COLLISION_PACKED)
        RRCA
        RRCA
        RRCA
        RRCA
        AND     00Fh
        RLCA
        RLCA
        RLCA
        RLCA
        LD      (DE),A
        INC     DE
        DEC     BC
        LD      A,B
        OR      C
        JP      NZ,COLLISION_UNPACK_LOOP
        RET

; Full-room images are decoded into the 720x256 background buffer.
DECOMPRESS_ROOM_BACKGROUND:
        LD      A,(ROOM_INDEX)
        OR      A
        JP      Z,ROOM0_BG_PTR
        CP      01h
        JP      Z,ROOM1_BG_PTR
        LD      HL,PCW_ROOM2_BG_COMP
        JP      ROOM_BG_PTR_STORE
ROOM0_BG_PTR:
        LD      HL,PCW_ROOM0_BG_COMP
        JP      ROOM_BG_PTR_STORE
ROOM1_BG_PTR:
        LD      HL,PCW_ROOM1_BG_COMP
ROOM_BG_PTR_STORE:
        LD      (BG_COMP_SOURCE),HL
        LD      DE,PCW_BACKGROUND
        LD      BC,05A00h              ; 23,040 bytes = 720x256 / 8
        XOR     A
        LD      (BG_BITS_LEFT),A
        JP      BG_NEXT_TOKEN

; Scroll strips contain 85 lines (7,650 bytes) and are appended at line 171.
DECOMPRESS_ROOM_SCROLL_STRIP:
        LD      A,(ROOM_SCROLL)
        CP      01h
        JP      Z,ROOM0_SCROLL1_BG_PTR
        CP      02h
        JP      Z,ROOM0_SCROLL2_BG_PTR
        LD      HL,PCW_ROOM0_SCROLL3_BG_COMP
        JP      ROOM_SCROLL_BG_PTR_STORE
ROOM0_SCROLL1_BG_PTR:
        LD      HL,PCW_ROOM0_SCROLL1_BG_COMP
        JP      ROOM_SCROLL_BG_PTR_STORE
ROOM0_SCROLL2_BG_PTR:
        LD      HL,PCW_ROOM0_SCROLL2_BG_COMP
ROOM_SCROLL_BG_PTR_STORE:
        LD      (BG_COMP_SOURCE),HL
        LD      DE,PCW_BACKGROUND+03C1Eh
        LD      BC,01DE2h              ; 85 * 90 bytes
        XOR     A
        LD      (BG_BITS_LEFT),A
        JP      BG_NEXT_TOKEN

; 12-bit LZSS decoder. Control bits are consumed MSB first; a set bit is
; one literal byte, otherwise the token is a backward copy of 3..18 bytes.
BG_NEXT_TOKEN:
        LD      A,(BG_BITS_LEFT)
        OR      A
        JP      NZ,BG_HAVE_CONTROL
        LD      HL,(BG_COMP_SOURCE)
        LD      A,(HL)
        INC     HL
        LD      (BG_COMP_SOURCE),HL
        LD      (BG_CONTROL),A
        LD      A,08h
        LD      (BG_BITS_LEFT),A
BG_HAVE_CONTROL:
        LD      A,(BG_CONTROL)
        RLCA
        LD      (BG_CONTROL),A
        LD      A,(BG_BITS_LEFT)
        DEC     A
        LD      (BG_BITS_LEFT),A
        JP      C,BG_LITERAL

        ; Back-reference: low offset byte, then high offset nibble / length nibble.
        LD      HL,(BG_COMP_SOURCE)
        LD      A,(HL)
        INC     HL
        LD      (BG_OFFSET_LOW),A
        LD      A,(HL)
        INC     HL
        LD      (BG_COMP_SOURCE),HL
        LD      (BG_TOKEN_META),A
        AND     00Fh
        ADD     A,03h
        LD      (BG_RUN_LEFT),A
        LD      A,(BG_TOKEN_META)
        AND     0F0h
        RRCA
        RRCA
        RRCA
        RRCA
        LD      (BG_OFFSET_HIGH),A

        ; Source = current destination - (encoded offset + 1).
        LD      A,(BG_OFFSET_LOW)
        LD      L,A
        LD      A,(BG_OFFSET_HIGH)
        LD      H,A
        INC     HL
        PUSH    DE
        EX      DE,HL
        OR      A
        SBC     HL,DE
        LD      (BG_COPY_SOURCE),HL
        POP     DE

BG_COPY_LOOP:
        LD      HL,(BG_COPY_SOURCE)
        LD      A,(HL)
        INC     HL
        LD      (BG_COPY_SOURCE),HL
        LD      (DE),A
        INC     DE
        DEC     BC
        LD      A,B
        OR      C
        JP      Z,BG_DECOMPRESS_DONE
        LD      A,(BG_RUN_LEFT)
        DEC     A
        LD      (BG_RUN_LEFT),A
        JP      NZ,BG_COPY_LOOP
        JP      BG_NEXT_TOKEN

BG_LITERAL:
        LD      HL,(BG_COMP_SOURCE)
        LD      A,(HL)
        INC     HL
        LD      (BG_COMP_SOURCE),HL
        LD      (DE),A
        INC     DE
        DEC     BC
        LD      A,B
        OR      C
        JP      NZ,BG_NEXT_TOKEN
BG_DECOMPRESS_DONE:
        RET

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
AIR_COL_COUNT:
        DB      00h
AIR_ROWS_LEFT:
        DB      00h
AIR_TEST_ROW:
        DB      00h
PLAYER_DIRECTION:
        DB      00h                    ; 0=right, 1=left
WALK_FRAME:
        DB      01h                    ; 1..5
CROUCHING:
        DB      00h                    ; 1=crouched
CRAWL_FRAME:
        DB      00h                    ; 0/1 crawl pose
PLAYER_SPRITE_PTR:
        DW      0000h
ROOM_INDEX:
        DB      00h
ROOM_SCROLL:
        DB      00h                    ; first-room viewport: 0..3
ROOM_FLAGS_PTR:
        DW      0000h
BG_COMP_SOURCE:
        DW      0000h
BG_COPY_SOURCE:
        DW      0000h
BG_CONTROL:
        DB      00h
BG_BITS_LEFT:
        DB      00h
BG_OFFSET_LOW:
        DB      00h
BG_OFFSET_HIGH:
        DB      00h
BG_TOKEN_META:
        DB      00h
BG_RUN_LEFT:
        DB      00h
COLLISION_PACKED:
        DB      00h
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

; Reusable full-screen raster, rebuilt from a compressed room image on entry.
PCW_BACKGROUND:
        DS      23040

        INCLUDE "build/PCWPLAYSPRITES.INC"
        INCLUDE "build/PCWROOMSET.INC"
        INCLUDE "build/PCWROOMBACKGROUND.INC"

; Writable collision-map workspace. Keep it after the fixed-address sprites
; and generated assets so adding it cannot move PCW_PLAYER_10 from 8400h.
ROOM_FLAGS_BUFFER:
        DS      768

        END
