; PCWROOM.ASM
; Render the actual first Rick Dangerous PC room and a static Rick sprite.
; The map is expanded from the original 4x4 block data at build time.
;
; The 256x192 game area is displayed 1:1, centred at PCW x=232, y=32.
; Original map 0 starts Rick at map x=8, y=139. The PC viewport begins at
; x=-32, y=64, then is centred on the PCW: Rick is at x=272, y=107.
; Sprite 0x0B is the PC game's right-facing stopped Rick frame.

        ORG     0100h

START:
        DI
        LD      A,081h
        OUT     (0F1h),A
        LD      A,082h
        OUT     (0F2h),A

        CALL    CLEAR_SCREEN
        CALL    DRAW_ROOM0

        LD      HL,PCW_SPRITE_011
        LD      DE,0110h
        LD      BC,006Bh
        LD      B,04h
        LD      A,15h
        CALL    DRAW_MASKED_BITMAP

        EI
WAIT_KEY:
        LD      C,06h
        LD      E,0FFh
        CALL    0005h
        OR      A
        JP      Z,WAIT_KEY

        DI
        LD      A,081h
        OUT     (0F1h),A
        LD      A,082h
        OUT     (0F2h),A
        CALL    CLEAR_SCREEN
        LD      A,085h
        OUT     (0F1h),A
        LD      A,086h
        OUT     (0F2h),A
        EI
        JP      0000h

; Render 24 rows x 32 columns of original PC map tiles.
; Resolve Roller-RAM once per output scanline, not once per tile.
DRAW_ROOM0:
        LD      HL,PCW_MAP0
        LD      (ROOM_MAP_ROW_PTR),HL
        LD      A,24
        LD      (ROOM_ROWS_LEFT),A
        LD      A,32
        LD      (ROOM_SCREEN_Y),A

ROOM_TILE_ROW:
        XOR     A
        LD      (ROOM_SUBROW),A

ROOM_SCANLINE:
        LD      A,(ROOM_SCREEN_Y)
        CALL    GET_SCANLINE_PTR
        LD      DE,00E8h
        ADD     HL,DE
        LD      (ROOM_SCREEN_DEST),HL

        LD      HL,(ROOM_MAP_ROW_PTR)
        LD      (ROOM_MAP_PTR),HL
        LD      B,32

ROOM_TILE:
        LD      HL,(ROOM_MAP_PTR)
        LD      A,(HL)
        INC     HL
        LD      (ROOM_MAP_PTR),HL

        ; Tile address = bank base + tile_number * 8 + tile scanline.
        LD      L,A
        LD      H,00h
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      DE,PCW_TILE_BANK2
        ADD     HL,DE
        LD      A,(ROOM_SUBROW)
        LD      E,A
        LD      D,00h
        ADD     HL,DE
        LD      A,(HL)

        LD      HL,(ROOM_SCREEN_DEST)
        LD      (HL),A
        LD      DE,0008h
        ADD     HL,DE
        LD      (ROOM_SCREEN_DEST),HL
        DJNZ    ROOM_TILE

        LD      A,(ROOM_SCREEN_Y)
        INC     A
        LD      (ROOM_SCREEN_Y),A
        LD      A,(ROOM_SUBROW)
        INC     A
        LD      (ROOM_SUBROW),A
        CP      08h
        JP      NZ,ROOM_SCANLINE

        LD      HL,(ROOM_MAP_ROW_PTR)
        LD      DE,0020h
        ADD     HL,DE
        LD      (ROOM_MAP_ROW_PTR),HL
        LD      A,(ROOM_ROWS_LEFT)
        DEC     A
        LD      (ROOM_ROWS_LEFT),A
        JP      NZ,ROOM_TILE_ROW
        RET

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
        INC     C
        JP      NZ,CLEAR_LINE
        RET


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

        ; Empty dimensions or x outside the 720-pixel screen: do nothing.
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

        ; RIGHT_SHIFT = 8 - horizontal pixel alignment.
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
        ; Fetch one source mask/pixel byte pair.
        LD      HL,(BITMAP_SOURCE)
        LD      A,(HL)
        LD      (SOURCE_MASK),A
        INC     HL
        LD      A,(HL)
        LD      (SOURCE_PIXELS),A
        INC     HL
        LD      (BITMAP_SOURCE),HL

        ; Skip screen writes once this source byte begins at x >= 720.
        ; The source pointer still advances so the following row stays
        ; correctly aligned in the row-major source data.
        LD      HL,(DEST_X)
        LD      DE,02D0h
        OR      A
        SBC     HL,DE
        JP      NC,BITMAP_NEXT_COLUMN

        ; Left destination mask = (source mask >> alignment) | left pad.
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

        ; Left destination pixel data = source pixels >> alignment.
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

        ; Right destination mask = (source mask << RIGHT_SHIFT) | right pad.
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

        ; Right destination pixel data = source pixels << RIGHT_SHIFT.
        LD      A,(RIGHT_SHIFT)
        LD      B,A
        LD      A,(SOURCE_PIXELS)
RIGHT_PIXELS_SHIFT:
        SLA     A
        DJNZ    RIGHT_PIXELS_SHIFT
        LD      (RIGHT_PIXELS),A

        ; Combine the left part with the existing screen byte.
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

        ; If unaligned, combine the spill into the next screen byte too.
        LD      A,(ALIGNMENT)
        OR      A
        JP      Z,BITMAP_NEXT_COLUMN

        ; The next byte is visible only when DEST_X < 712.
        LD      HL,(DEST_X)
        LD      DE,02C8h
        OR      A
        SBC     HL,DE
        JP      NC,BITMAP_NEXT_COLUMN

        ; Fetch the scanline pointer again before addressing the right byte.
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

        ; Stop at y=255 instead of allowing the 8-bit y counter to wrap.
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


TILE_CHECK:
        DB      0AAh,055h,0AAh,055h,0AAh,055h,0AAh,055h

LEFT_PAD_MASK:
        DB      00h,080h,0C0h,0E0h,0F0h,0F8h,0FCh,0FEh
RIGHT_PAD_MASK:
        DB      0FFh,07Fh,03Fh,01Fh,00Fh,007h,003h,001h

PANEL_X:
        DW      0000h
PANEL_Y:
        DB      00h
PANEL_ROWS:
        DB      00h
PANEL_COLS:
        DB      00h
TILE_SOURCE:
        DW      0000h
TILE_X:
        DW      0000h
TILE_Y:
        DB      00h
PIXELS:
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
BANK_NO:
        DB      00h
LOW_BITS:
        DB      00h


ROOM_MAP_ROW_PTR:
        DW      0000h
ROOM_MAP_PTR:
        DW      0000h
ROOM_SCREEN_DEST:
        DW      0000h
ROOM_ROWS_LEFT:
        DB      00h
ROOM_SCREEN_Y:
        DB      00h
ROOM_SUBROW:
        DB      00h

        INCLUDE "build/PCWROOM.INC"
        INCLUDE "build/PCWSPRITES.INC"

        END
