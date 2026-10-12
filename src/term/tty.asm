; tty.asm - TTY emulation: printable characters and the C0 controls
;
; Printable is 20h-7Eh and 80h-FFh (CP437). The controls: BS, HT, LF/VT,
; FF (clear screen), CR. BEL waits for the sound driver (M3); the rest are
; ignored. Wrapping is VT100-style: a character in the last column leaves
; the cursor there with a wrap pending, and the next printable character
; starts a new line first. Any control cancels the pending wrap.

; term_reset: home, full scrolling region, no pending wrap.
term_reset:
        xor a
        ld (cur_col),a
        ld (cur_row),a
        ld (term_wrap),a
        ld (term_top),a
        ld a,VID_ROWS-1
        ld (term_bot),a
        ret

; term_puts: send the 0-terminated string at HL through term_putc.
term_puts:
        ld a,(hl)
        or a
        ret z
        push hl
        call term_putc
        pop hl
        inc hl
        jr term_puts

; term_putc: display byte A. Uses all but IX, IY.
term_putc:
        push af
        call vid_cursor_off
        pop af
        cp 20h
        jr c,term_control
        cp 7Fh
        ret z                       ; DEL
        ld e,a
        ld a,(term_wrap)
        or a
        jr z,.place
        xor a
        ld (term_wrap),a
        ld (cur_col),a
        push de
        call term_lf
        pop de
.place:
        ld a,e
        ld bc,(cur_col)
        call vid_put
        ld a,(vid_cols)
        dec a
        cp c
        jr z,.last
        inc c
        ld a,c
        ld (cur_col),a
        ret
.last:
        ld a,1
        ld (term_wrap),a
        ret

term_control:
        ld e,a
        xor a
        ld (term_wrap),a
        ld a,e
        cp 08h
        jr z,term_bs
        cp 09h
        jr z,term_tab
        cp 0Ah
        jr z,term_lf
        cp 0Bh
        jr z,term_lf
        cp 0Ch
        jr z,term_ff
        cp 0Dh
        jr z,term_cr
        ret                         ; BEL and the rest: nothing yet

term_bs:
        ld a,(cur_col)
        or a
        ret z
        dec a
        ld (cur_col),a
        ret

term_tab:
        ld a,(cur_col)
        or 07h
        inc a
        ld b,a
        ld a,(vid_cols)
        dec a
        cp b
        jr c,.edge
        ld a,b
.edge:
        ld (cur_col),a
        ret

term_cr:
        xor a
        ld (cur_col),a
        ret

; term_lf: down a row, scrolling at the bottom of the scrolling region.
term_lf:
        ld a,(term_bot)
        ld b,a
        ld a,(cur_row)
        cp b
        jr z,.scroll
        cp VID_ROWS-1
        ret z                       ; below the region, at the bottom
        inc a
        ld (cur_row),a
        ret
.scroll:
        ld a,(term_top)
        ld d,a
        ld e,b
        jp vid_scroll_up

term_ff:
        call term_reset
        ld de,0+VID_ROWS-1
        jp vid_clear_rows

; --- state ----------------------------------------------------------------

term_wrap:      db 0                ; 1 = the next printable starts a new line
term_top:       db 0                ; scrolling region, inclusive
term_bot:       db VID_ROWS-1
