; vid.asm - the screen, independent of the column mode
;
; Keeps the shadow (a character and an attribute per cell, at SHADOW_CHR and
; SHADOW_ATR, row-major) and calls the driver for the pixels. M1 has only the
; 32-column driver; M4 makes the vid32_ calls below go through a table.
;
; Anything that draws must hide the cursor first (vid_cursor_off): scrolling
; would otherwise carry its inverted line along.

VID_ROWS        equ 24
MAX_COLS        equ 80
MAX_CELLS       equ MAX_COLS*VID_ROWS

; vid_init: set up for vid_cols columns and clear the screen.
vid_init:
        ld a,(vid_cols)
        ld e,a
        ld d,0
        ld hl,0
        ld ix,vid_rowoff
        ld b,VID_ROWS+1
.off:
        ld (ix+0),l
        ld (ix+1),h
        inc ix
        inc ix
        add hl,de
        djnz .off
        xor a
        ld (vid_cursor_shown),a
        ld de,0+VID_ROWS-1          ; D = 0, E = 23
        jp vid_clear_rows

; vid_rowstart: HL = the shadow offset of row A (0-24; 24 = the end).
; Uses A.
vid_rowstart:
        add a,a
        ld l,a
        ld h,0
        push de
        ld de,vid_rowoff
        add hl,de
        pop de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ret

; vid_offset: HL = the shadow offset of B,C. Uses A.
vid_offset:
        ld a,b
        call vid_rowstart
        ld a,c
        add a,l
        ld l,a
        adc a,h
        sub l
        ld h,a
        ret

; vid_put: character A at B,C in cur_attr. Keeps BC.
vid_put:
        push af
        call vid_offset
        ld de,SHADOW_CHR
        add hl,de
        pop af
        ld (hl),a
        ld de,SHADOW_ATR-SHADOW_CHR
        add hl,de
        ld e,a
        ld a,(cur_attr)
        ld (hl),a
        ld d,a
        ld a,e
        ld e,d
        jp vid32_draw

; vid_clear_rows: blank rows D to E in cur_attr. Uses all.
vid_clear_rows:
        push de
        ld a,e
        inc a
        call vid_rowstart
        push hl                     ; end
        ld a,d
        call vid_rowstart           ; HL = start
        pop bc
        ld a,c                      ; BC = end - start
        sub l
        ld c,a
        ld a,b
        sbc a,h
        ld b,a
        call vid_fill_shadow
        pop de
        ld a,(cur_attr)
        jp vid32_clear_rows

; vid_clear_cells: blank D cells from B,C along one row, in cur_attr.
vid_clear_cells:
        ld a,d
        or a
        ret z
        push bc
        push de
        call vid_offset
        pop de
        push de
        ld c,d
        ld b,0
        call vid_fill_shadow
        pop de
        pop bc
        ld a,(cur_attr)
        ld e,a
.cell:
        push de
        ld a,' '
        call vid32_draw
        pop de
        inc c
        dec d
        jr nz,.cell
        ret

; vid_fill_shadow: BC (> 0) cells from offset HL: ' ' in cur_attr.
vid_fill_shadow:
        push hl
        push bc
        ld de,SHADOW_CHR
        add hl,de
        ld (hl),' '
        call .fill
        pop bc
        pop hl
        ld de,SHADOW_ATR
        add hl,de
        ld a,(cur_attr)
        ld (hl),a
.fill:
        dec bc
        ld a,b
        or c
        ret z
        ld d,h
        ld e,l
        inc de
        ldir
        ret

; vid_scroll_up: rows D..E up one; row E becomes blank. Uses all.
vid_scroll_up:
        ld a,d
        cp e
        jr nc,.blank                ; a one-row region just clears
        push de
        ld a,e
        inc a
        call vid_rowstart
        push hl                     ; end of row E
        ld a,d
        inc a
        call vid_rowstart           ; HL = source: row D+1
        pop bc
        ld a,c                      ; BC = end - source
        sub l
        ld c,a
        ld a,b
        sbc a,h
        ld b,a
        push hl
        ld a,d
        call vid_rowstart
        ex de,hl                    ; DE = destination: row D
        pop hl
        xor a
        call vid_shadow_copy
        pop de
        push de
        call vid32_scroll_up
        pop de
.blank:
        ld d,e
        jp vid_clear_rows

; vid_scroll_down: rows D..E down one; row D becomes blank. Uses all.
vid_scroll_down:
        ld a,d
        cp e
        jr nc,.blank
        push de
        ld a,d
        call vid_rowstart
        push hl                     ; start of row D
        ld a,e
        call vid_rowstart           ; HL = start of row E: end of the block
        pop bc
        push hl
        or a
        sbc hl,bc
        ld b,h
        ld c,l                      ; BC = cells to move
        pop hl
        dec hl                      ; last source cell
        push hl
        ld a,e
        inc a
        call vid_rowstart
        dec hl
        ex de,hl                    ; DE = last destination cell
        pop hl
        ld a,1
        call vid_shadow_copy
        pop de
        push de
        call vid32_scroll_down
        pop de
.blank:
        ld e,d
        jp vid_clear_rows

; vid_shadow_copy: BC (> 0) cells from offset HL to offset DE in both
; planes; A = 0 copies forward (LDIR), else backward from the last cells
; (LDDR). Uses all.
vid_shadow_copy:
        ld (.dir),a
        ld (.count),bc
        push hl
        push de
        ld bc,SHADOW_CHR
        call .plane
        pop de
        pop hl
        ld bc,SHADOW_ATR
.plane:
        add hl,bc
        ex de,hl
        add hl,bc
        ex de,hl
        ld bc,(.count)
        ld a,(.dir)
        or a
        jr nz,.down
        ldir
        ret
.down:
        lddr
        ret
.dir:   db 0
.count: dw 0

; vid_cursor_on / vid_cursor_off: show or hide the cursor at cur_row,
; cur_col. Keep BC, DE.
vid_cursor_on:
        ld a,(vid_cursor_shown)
        or a
        ret nz
        cpl
        jr vid_cursor_flip
vid_cursor_off:
        ld a,(vid_cursor_shown)
        or a
        ret z
        xor a
vid_cursor_flip:
        ld (vid_cursor_shown),a
        push bc
        ld bc,(cur_col)             ; C = column, B = row
        call vid32_cursor
        pop bc
        ret

; vid_redraw: draw every cell from the shadow.
vid_redraw:
        ld b,0
.row:
        ld c,0
        ld a,(vid_cols)
        ld d,a
        push bc
        call vid_redraw_cells
        pop bc
        inc b
        ld a,b
        cp VID_ROWS
        jr nz,.row
        ret

; vid_redraw_cells: draw D cells from B,C along one row, from the shadow.
vid_redraw_cells:
        ld a,d
        or a
        ret z
.cell:
        push de
        call vid_offset
        push hl
        ld de,SHADOW_ATR
        add hl,de
        ld e,(hl)
        pop hl
        push de
        ld de,SHADOW_CHR
        add hl,de
        ld a,(hl)
        pop de                      ; E = attribute
        call vid32_draw
        pop de
        inc c
        dec d
        jr nz,.cell
        ret

; vid_insert_cells: D (1 or more) blank cells at B,C; the rest of the row
; moves right, and what goes past the end is lost. C + D <= vid_cols.
vid_insert_cells:
        ld a,d
        ld (vid_n),a
        ld a,(vid_cols)
        sub c
        sub d
        jr z,.blank                 ; nothing left to move
        ld (vid_cnt),a
        push bc
        ld a,b
        call vid_rowstart
        ld a,(vid_cols)
        dec a
        call vid_add_a
        ld d,h
        ld e,l                      ; DE = the row's last cell
        ld a,(vid_n)
        ld c,a
        ld b,0
        or a
        sbc hl,bc                   ; HL = the last cell that moves
        ld a,(vid_cnt)
        ld c,a
        ld a,1
        call vid_shadow_copy
        pop bc
        push bc
        ld a,(vid_n)
        add a,c
        ld c,a
        ld a,(vid_cnt)
        ld d,a
        call vid_redraw_cells
        pop bc
.blank:
        ld a,(vid_n)
        ld d,a
        jp vid_clear_cells

; vid_delete_cells: remove D (1 or more) cells at B,C; the rest of the row
; moves left, and blanks fill the end. C + D <= vid_cols.
vid_delete_cells:
        ld a,d
        ld (vid_n),a
        ld a,(vid_cols)
        sub c
        sub d
        jp z,vid_clear_cells        ; everything from B,C goes
        ld (vid_cnt),a
        push bc
        call vid_offset
        ld d,h
        ld e,l                      ; DE = B,C
        ld a,(vid_n)
        call vid_add_a              ; HL = the first cell that moves
        ld a,(vid_cnt)
        ld c,a
        ld b,0
        xor a
        call vid_shadow_copy
        pop bc
        push bc
        ld a,(vid_cnt)
        ld d,a
        call vid_redraw_cells
        pop bc
        ld hl,vid_n
        ld a,(vid_cols)
        sub (hl)
        ld c,a
        ld d,(hl)
        jp vid_clear_cells

; vid_add_a: HL += A. Uses A.
vid_add_a:
        add a,l
        ld l,a
        adc a,h
        sub l
        ld h,a
        ret

; --- state ----------------------------------------------------------------

vid_cols:       db 32
cur_col:        db 0                ; cur_col then cur_row: LD BC,(cur_col)
cur_row:        db 0
cur_attr:       db 07h              ; white ink on black paper
vid_cursor_shown: db 0
vid_n:          db 0
vid_cnt:        db 0
vid_rowoff:     ds (VID_ROWS+1)*2   ; shadow offset of each row, and the end
