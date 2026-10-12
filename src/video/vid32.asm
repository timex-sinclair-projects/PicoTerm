; vid32.asm - 32-column driver: the standard SCLD screen
;
; Bitmap and attributes only; the shadow is vid.asm's job. Rows and columns
; arrive in B (row 0-23) and C (column 0-31). The font is page-aligned.

; COPY32: 32 x LDI. LDI counts BC down, so callers keep B and C elsewhere.
        MACRO COPY32
        DUP 32
        ldi
        EDUP
        ENDM

; FILL32: A into 32 bytes from HL, within one 256-byte page. HL ends at +31.
        MACRO FILL32
        DUP 31
        ld (hl),a
        inc l
        EDUP
        ld (hl),a
        ENDM

; vid32_cell: HL = the cell's top pixel line. Uses A.
vid32_cell:
        ld a,b
        and 18h
        or high DF1
        ld h,a
        ld a,b
        and 07h
        rrca
        rrca
        rrca
        or c
        ld l,a
        ret

; vid32_attr: HL = the cell's attribute. Uses A.
vid32_attr:
        ld a,b
        rrca
        rrca
        rrca
        ld l,a
        and 03h
        or high ATTR1
        ld h,a
        ld a,l
        and 0E0h
        or c
        ld l,a
        ret

; vid32_draw: character A with attribute E at B,C. Keeps BC.
vid32_draw:
        push bc
        ld d,e
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld a,h
        add a,high FONT
        ld h,a
        ex de,hl                    ; DE = glyph, H = attribute
        ld a,h
        push af
        call vid32_cell
        DUP 7
        ld a,(de)
        ld (hl),a
        inc e
        inc h
        EDUP
        ld a,(de)
        ld (hl),a
        call vid32_attr
        pop af
        ld (hl),a
        pop bc
        ret

; vid32_clear_rows: rows D to E: bitmap 0, attributes A. Uses all.
vid32_clear_rows:
        ld (.attr),a
        ld a,e
        ld (.bot),a
        ld b,d
        ld c,0
.row:
        call vid32_cell
        ld e,8
.line:
        push hl
        xor a
        FILL32
        pop hl
        inc h
        dec e
        jr nz,.line
        call vid32_attr
        ld a,(.attr)
        FILL32
        ld a,b
        inc b
        ld hl,.bot
        cp (hl)
        jp c,.row
        ret
.attr:  db 0
.bot:   db 0

; vid32_scroll_up: move rows D+1..E up one row. Row E is left as it was.
vid32_scroll_up:
        ld b,d
.row:
        ld a,b
        cp e
        ret nc
        ld c,0
        push bc
        push de
        inc b
        call vid32_cell
        push hl
        dec b
        call vid32_cell
        ex de,hl
        pop hl                      ; HL = row B+1, DE = row B
        call vid32_copy_lines
        pop de
        pop bc
        push bc
        push de
        call vid32_attr
        ex de,hl
        inc b
        call vid32_attr             ; HL = row B+1, DE = row B
        COPY32
        pop de
        pop bc
        inc b
        jr .row

; vid32_scroll_down: move rows D..E-1 down one row. Row D is left as it was.
vid32_scroll_down:
        ld b,e
.row:
        ld a,d
        cp b
        ret nc
        ld c,0
        push bc
        push de
        dec b
        call vid32_cell
        push hl
        inc b
        call vid32_cell
        ex de,hl
        pop hl                      ; HL = row B-1, DE = row B
        call vid32_copy_lines
        pop de
        pop bc
        push bc
        push de
        call vid32_attr
        ex de,hl
        dec b
        call vid32_attr             ; HL = row B-1, DE = row B
        COPY32
        pop de
        pop bc
        dec b
        jr .row

; vid32_copy_lines: the 8 pixel lines of a row, HL to DE.
vid32_copy_lines:
        ld a,8
.line:
        push hl
        push de
        COPY32
        pop de
        pop hl
        inc h
        inc d
        dec a
        jr nz,.line
        ret

; vid32_cursor: invert the bottom pixel line of B,C.
vid32_cursor:
        call vid32_cell
        ld a,h
        add a,7
        ld h,a
        ld a,(hl)
        cpl
        ld (hl),a
        ret
