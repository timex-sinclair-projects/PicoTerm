; vid32.asm - 32-column driver (standard SCLD screen)
;
; M0 version: no scrolling, no shadow, and the ROM font (through CHARS) for
; 32-127. The full driver (docs/DESIGN.md section 5) replaces this in M1.

VID32_COLS      equ 32
VID32_ROWS      equ 24

; vid32_cls: clear the bitmap, fill the attributes with cur_attr, home.
vid32_cls:
        ld hl,DF1
        ld de,DF1+1
        ld bc,1800h-1
        ld (hl),0
        ldir
        ld hl,ATTR1
        ld de,ATTR1+1
        ld bc,300h-1
        ld a,(cur_attr)
        ld (hl),a
        ldir
        xor a
        ld (cur_row),a
        ld (cur_col),a
        ret

; vid32_at: B = row, C = column
vid32_at:
        ld a,b
        ld (cur_row),a
        ld a,c
        ld (cur_col),a
        ret

; vid32_putc: draw A at the cursor and advance. 13 = new line.
; Characters outside 32-127 show as '?'. Keeps BC, DE, HL.
vid32_putc:
        push bc
        push de
        push hl
        cp 13
        jr z,.newline
        cp 32
        jr c,.unknown
        cp 128
        jr c,.draw
.unknown:
        ld a,'?'
.draw:
        ; glyph address: (CHARS) + A * 8
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,(SV_CHARS)
        add hl,de
        ex de,hl                    ; DE = glyph
        ; screen address: 010r r000 rrrc cccc
        ld a,(cur_row)
        ld b,a
        and 18h
        or high DF1
        ld h,a
        ld a,b
        and 07h
        rrca
        rrca
        rrca
        ld l,a
        ld a,(cur_col)
        or l
        ld l,a
        push hl                     ; for the attribute
        ld b,8
.line:
        ld a,(de)
        ld (hl),a
        inc de
        inc h
        djnz .line
        ; attribute: 5800h + row * 32 + col
        pop hl
        ld a,h
        rrca
        rrca
        rrca
        and 03h
        or high ATTR1
        ld h,a
        ld a,(cur_attr)
        ld (hl),a
        ; advance
        ld a,(cur_col)
        inc a
        cp VID32_COLS
        jr c,.samerow
.newline:
        ld a,(cur_row)
        inc a
        cp VID32_ROWS
        jr c,.rowok
        xor a                       ; no scroll yet: wrap to the top
.rowok:
        ld (cur_row),a
        xor a
.samerow:
        ld (cur_col),a
        pop hl
        pop de
        pop bc
        ret

; vid32_puts: print the 0-terminated string at HL.
vid32_puts:
        ld a,(hl)
        or a
        ret z
        call vid32_putc
        inc hl
        jr vid32_puts

; vid32_hex16: print HL as four hex digits.
vid32_hex16:
        ld a,h
        call vid32_hex8
        ld a,l
; vid32_hex8: print A as two hex digits.
vid32_hex8:
        push af
        rrca
        rrca
        rrca
        rrca
        call .digit
        pop af
.digit:
        and 0Fh
        add a,'0'
        cp '9'+1
        jr c,.out
        add a,'A'-'0'-10
.out:
        jp vid32_putc

cur_row:        db 0
cur_col:        db 0
cur_attr:       db 07h              ; white ink on black paper
