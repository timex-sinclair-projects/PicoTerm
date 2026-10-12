; font.asm - the 256-character 8x8 font at FONT (page-aligned, 2 KB)
;
; M1: built at start-up from the ROM font for 32-127, with ^ and ` drawn as
; ASCII (the ROM has an up-arrow and a pound sign there). 0-31 are blank,
; and 128-255 show a small box until the CP437 font arrives in M4.

font_init:
        ld hl,FONT
        ld de,FONT+1
        ld bc,32*8-1
        ld (hl),0
        ldir
        ld hl,(SV_CHARS)
        inc h                       ; CHARS + 256 = the glyph for 32
        ld de,FONT+32*8
        ld bc,96*8
        ldir
        ld de,FONT+128*8
        ld b,128
.high:
        push bc
        ld hl,glyph_box
        ld bc,8
        ldir
        pop bc
        djnz .high
        ld hl,glyph_caret
        ld de,FONT+'^'*8
        ld bc,8
        ldir
        ld hl,glyph_backtick
        ld de,FONT+'`'*8
        ld bc,8
        ldir
        ret

glyph_caret:    db 00h,10h,28h,44h,00h,00h,00h,00h
glyph_backtick: db 00h,20h,10h,08h,00h,00h,00h,00h
glyph_box:      db 00h,00h,3Ch,24h,24h,3Ch,00h,00h
