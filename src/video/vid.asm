; vid.asm - the screen, independent of the column mode
;
; Keeps the shadow (a character and an attribute per cell, at SHADOW_CHR and
; SHADOW_ATR, row-major, vid_cols cells a row) and calls the current driver
; for the pixels through the drv_ jumps, which vid_set_mode rewrites. A mode
; change re-lays the shadow out for the new width (keeping what fits) and
; redraws from it. Rows only as wide as the mode keep scrolling cheap.
;
; Anything that draws must hide the cursor first (vid_cursor_off): scrolling
; would otherwise carry its inverted line along.

VID_ROWS        equ 24
MAX_COLS        equ 80
MAX_CELLS       equ MAX_COLS*VID_ROWS

; vid_init: mode A (VM_32, VM_64, VM_80) on a clear screen.
vid_init:
        call vid_select
        call vid_rows_table
        xor a
        ld (vid_cursor_shown),a
        ld de,0+VID_ROWS-1          ; D = 0, E = 23
        jp vid_clear_rows

; vid_set_mode: change to mode A and redraw from the shadow. The cursor
; stays where it was, pulled in to the last column if the mode is narrower.
vid_set_mode:
        push af
        call vid_cursor_off
        ld a,(vid_cols)
        ld (vid_old_cols),a
        pop af
        call vid_select
        call vid_relayout
        call vid_rows_table
        ld a,(vid_cols)
        ld b,a
        ld a,(cur_col)
        cp b
        jr c,.col
        ld a,b
        dec a
        ld (cur_col),a
.col:
        jp vid_redraw

; vid_rows_table: each row's shadow offset for vid_cols, and the end.
vid_rows_table:
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
        ret

; vid_relayout: rows of vid_old_cols cells become rows of vid_cols, in both
; planes. Narrower: each row keeps its first vid_cols cells (rows move
; down in memory, so top first). Wider: blanks in cur_attr fill the new
; cells (rows move up, so bottom first).
vid_relayout:
        ld hl,SHADOW_CHR
        ld a,' '
        call .plane
        ld hl,SHADOW_ATR
        ld a,(cur_attr)
.plane:
        ld (.base),hl
        ld (.fill),a
        ld a,(vid_old_cols)
        ld hl,vid_cols
        cp (hl)
        ret z
        jr c,.wider
        ld b,1                      ; narrower: rows 1 to 23
.down:
        push bc
        call .addrs                 ; HL = old row, DE = new row
        ld a,(vid_cols)
        ld c,a
        ld b,0
        ldir
        pop bc
        inc b
        ld a,b
        cp VID_ROWS
        jr c,.down
        ret
.wider:
        ld b,VID_ROWS-1             ; wider: rows 23 to 0
.up:
        push bc
        call .addrs
        ld a,b
        or a
        jr z,.moved                 ; row 0 stays put
        ld a,(vid_old_cols)
        dec a
        call vid_add_a
        ex de,hl
        ld a,(vid_old_cols)
        dec a
        call vid_add_a
        ex de,hl                    ; HL, DE = the last cells
        ld a,(vid_old_cols)
        ld c,a
        ld b,0
        lddr
.moved:
        pop bc
        push bc
        call .addrs
        ex de,hl
        ld a,(vid_old_cols)
        call vid_add_a              ; HL = the first new cell
        ld a,(vid_old_cols)
        ld b,a
        ld a,(vid_cols)
        sub b
        ld b,a
        ld a,(.fill)
.blank:
        ld (hl),a
        inc hl
        djnz .blank
        pop bc
        dec b
        jp p,.up
        ret
; .addrs: row B: HL = .base + B x old cols, DE = .base + B x new cols
.addrs:
        ld a,(vid_old_cols)
        call .times
        push hl
        ld a,(vid_cols)
        call .times
        ex de,hl
        pop hl
        ret
.times:                             ; HL = .base + B x A
        ld hl,(.base)
        ld e,a
        ld d,0
        ld a,b
        or a
        ret z
        push bc
.add:
        add hl,de
        djnz .add
        pop bc
        ret
.base:  dw 0
.fill:  db 0

; vid_select: point the drv_ jumps at mode A's driver, set vid_cols and the
; DECR. The 64-column mode is PicoVideo's mode 7 (a colour per cell) when
; set_picovideo says the board is there, else the SCLD's mode 6 in
; set_ink64.
vid_select:
        ld (vid_mode),a
        ld l,a
        add a,a
        ld h,a
        add a,a
        add a,a
        add a,h
        add a,l                     ; x 11
        ld hl,vid_modes
        call vid_add_a
        ld a,(hl)
        ld (vid_cols),a
        inc hl
        ld de,drv_draw+1
        ld b,5
.jump:
        ld a,(hl)
        ld (de),a
        inc hl
        inc de
        ld a,(hl)
        ld (de),a
        inc hl
        inc de
        inc de                      ; past the next JP opcode
        djnz .jump
        ld a,(vid_mode)
        cp VM_64
        jr nz,.decr
        ld a,(set_picovideo)
        or a
        ld a,DECR_64COLOUR
        jp nz,decr_mode
        ld a,(set_ink64)
        add a,a
        add a,a
        add a,a
        or DECR_64COL
        jp decr_mode
.decr:
        ld a,(vid_mode)
        ld hl,vid_decr
        call vid_add_a
        ld a,(hl)
        jp decr_mode

VM_32           equ 0
VM_64           equ 1
VM_80           equ 2

; per mode: columns, then draw, clear_rows, scroll_up, scroll_down, cursor
vid_modes:
        db 32
        dw vid32_draw, vid32_clear_rows, vid32_scroll_up, vid32_scroll_down, vid32_cursor
        db 64
        dw vid64_draw, vid64_clear_rows, vid64_scroll_up, vid64_scroll_down, vid64_cursor
        db 80
        dw vid80_draw, vid80_clear_rows, vid80_scroll_up, vid80_scroll_down, vid80_cursor
        ASSERT $ - vid_modes == 3*11
vid_decr:       db DECR_STANDARD, DECR_64COL, DECR_TEXT80

; The driver: rewritten by vid_select.
;   drv_draw         A = character, E = attribute, at B,C. Keeps BC.
;   drv_clear_rows   rows D to E, attribute A.
;   drv_scroll_up    move rows D+1..E up one (row E is redrawn after).
;   drv_scroll_down  move rows D..E-1 down one (row D is redrawn after).
;   drv_cursor       flip the cursor's look at B,C.
drv_draw:         jp vid32_draw
drv_clear_rows:   jp vid32_clear_rows
drv_scroll_up:    jp vid32_scroll_up
drv_scroll_down:  jp vid32_scroll_down
drv_cursor:       jp vid32_cursor

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
        jp drv_draw

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
        jp drv_clear_rows

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
        call drv_draw
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
        call drv_scroll_up
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
        call drv_scroll_down
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
        call drv_cursor
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
        call drv_draw
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
vid_mode:       db VM_32
vid_old_cols:   db 32
cur_col:        db 0                ; cur_col then cur_row: LD BC,(cur_col)
cur_row:        db 0
cur_attr:       db 07h              ; white ink on black paper
vid_cursor_shown: db 0
vid_n:          db 0
vid_cnt:        db 0
vid_rowoff:     ds (VID_ROWS+1)*2   ; shadow offset of each row, and the end
