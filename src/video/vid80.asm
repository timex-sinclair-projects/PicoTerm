; vid80.asm - 80-column driver: PicoVideo's text mode (mode 5)
;
; Character codes at TEXT80_CHR (4000h) and attributes at TEXT80_ATR
; (4780h), 80 a row, row-major: the shadow's own layout in this mode, so a
; cell's offset is its shadow offset. PicoVideo draws the characters from its CP437 font
; and reads the attributes in the Spectrum format (FLASH, BRIGHT, PAPER,
; INK) - PicoVideo v4.2, displayProc80.c. The SCLD has no mode 5, so the
; 2068's own video output shows nothing useful in this mode.
;
; Scrolling copies the rows back from the shadow, which vid.asm has already
; moved.

; vid80_draw: A at B,C with attribute E. Keeps BC.
vid80_draw:
        push bc
        ld d,a
        call vid_offset
        push hl
        ld bc,TEXT80_CHR
        add hl,bc
        ld (hl),d
        pop hl
        ld bc,TEXT80_ATR
        add hl,bc
        ld (hl),e
        pop bc
        ret

; vid80_clear_rows: rows D to E: spaces in attribute A.
vid80_clear_rows:
        ld (.attr),a
        ld a,e
        inc a
        call vid_rowstart
        push hl                     ; end
        ld a,d
        call vid_rowstart           ; start
        pop bc
        ld a,c
        sub l
        ld c,a
        ld a,b
        sbc a,h
        ld b,a                      ; BC = cells
        push hl
        push bc
        ld de,TEXT80_CHR
        add hl,de
        ld a,' '
        call .fill
        pop bc
        pop hl
        ld de,TEXT80_ATR
        add hl,de
        ld a,(.attr)
.fill:
        ld (hl),a
        dec bc
        ld a,b
        or c
        ret z
        ld d,h
        ld e,l
        inc de
        ldir
        ret
.attr:  db 0

; vid80_scroll_up / vid80_scroll_down: copy the moved rows from the shadow.
vid80_scroll_up:
        dec e
        jr vid80_copy_rows

vid80_scroll_down:
        inc d
        ; fall through

; vid80_copy_rows: rows D to E, shadow to screen, both planes.
vid80_copy_rows:
        ld a,e
        inc a
        call vid_rowstart
        push hl
        ld a,d
        call vid_rowstart
        pop bc
        ld a,c
        sub l
        ld c,a
        ld a,b
        sbc a,h
        ld b,a                      ; BC = cells
        push hl
        push bc
        ld de,SHADOW_CHR
        add hl,de
        ex de,hl
        ld hl,TEXT80_CHR-SHADOW_CHR
        add hl,de
        ex de,hl                    ; HL = shadow, DE = screen
        ldir
        pop bc
        pop hl
        ld de,SHADOW_ATR
        add hl,de
        ex de,hl
        ld hl,TEXT80_ATR-SHADOW_ATR
        add hl,de
        ex de,hl
        ldir
        ret

; vid80_cursor: swap INK and PAPER in the cell's attribute.
vid80_cursor:
        call vid_offset
        ld de,TEXT80_ATR
        add hl,de
        ld a,(hl)
        and 0C0h
        ld d,a
        ld a,(hl)
        and 07h
        rlca
        rlca
        rlca
        or d
        ld d,a
        ld a,(hl)
        rrca
        rrca
        rrca
        and 07h
        or d
        ld (hl),a
        ret
