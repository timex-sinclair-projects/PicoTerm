; term.asm - the terminal: printing, C0 controls, the cursor, and the
; dispatcher that hands escape sequences to the emulation
;
; set_emul picks the emulation: TTY ignores ESC; VT52 and ANSI install a
; handler (term_handler) that sees every byte until its sequence ends.
; (docs/DESIGN.md section 6.)
;
; Printable is 20h-7Eh and 80h-FFh (CP437). The C0 controls: BEL, BS, HT,
; LF/VT, FF (clear screen), CR, and ESC; the rest are ignored. Wrapping is
; VT100-style: a character in the last column leaves the cursor there with
; a wrap pending, and the next printable character starts a new line first.
; Cursor movement and controls cancel the pending wrap.

EMU_TTY         equ 0
EMU_VT52        equ 1
EMU_ANSI        equ 2

; term_reset: home, full scrolling region, default colors, no sequence.
term_reset:
        xor a
        ld (cur_col),a
        ld (cur_row),a
        ld (term_wrap),a
        ld (term_top),a
        ld hl,0
        ld (term_handler),hl
        ld a,VID_ROWS-1
        ld (term_bot),a
        ld a,1
        ld (term_autowrap),a
        ld (term_cursor),a
        call sgr_reset
        jp term_save

; term_full_reset: term_reset and clear the screen (ESC c, FF in TTY).
term_full_reset:
        call term_reset
        ld de,0+VID_ROWS-1
        jp vid_clear_rows

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

; term_fresh_line: start a new line unless the cursor is at its start.
term_fresh_line:
        ld a,(cur_col)
        ld b,a
        ld a,(term_wrap)
        or b
        ret z
        ld hl,crlf
        jr term_puts

crlf:   db 13,10,0

; term_putc: handle byte A. Uses all but IX, IY.
term_putc:
        ld c,a
        call vid_cursor_off
        ld hl,(term_handler)
        ld a,h
        or l
        ld a,c
        jr z,term_ground
        jp (hl)

; term_ground: A outside any sequence.
term_ground:
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
        ld a,(term_autowrap)
        ld (term_wrap),a            ; with autowrap off, stay and overwrite
        ret

; term_control: a C0 control, A < 20h.
term_control:
        cp 1Bh
        jr z,.esc
        ld e,a
        xor a
        ld (term_wrap),a
        ld a,e
        cp 07h
        jp z,bell_start
        cp 08h
        jr z,term_bs
        cp 09h
        jr z,term_tab
        cp 0Ah
        jr z,term_lf
        cp 0Bh
        jr z,term_lf
        cp 0Ch
        jp z,term_ff
        cp 0Dh
        jr z,term_cr
        ret
.esc:
        ld a,(set_emul)
        or a
        ret z                       ; TTY: ESC means nothing
        ld hl,vt52_esc
        dec a
        jr z,.set
        ld hl,ansi_esc
.set:
        ld (term_handler),hl
        ret

; term_seq_control: a C0 control inside a sequence. It acts at once and the
; sequence carries on; ESC starts a new one; CAN and SUB abandon it.
term_seq_control:
        cp 18h
        jr z,term_to_ground
        cp 1Ah
        jr z,term_to_ground
        cp 1Bh
        jr z,term_control
        ld hl,(term_handler)
        push hl
        call term_control
        pop hl
        ld (term_handler),hl
        ret

term_to_ground:
        ld hl,0
        ld (term_handler),hl
        ret

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

; term_nel: CR and LF (ESC E).
term_nel:
        call term_cr
        ; fall through

; term_lf: down a row, scrolling at the bottom of the scrolling region.
term_lf:
        xor a
        ld (term_wrap),a
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

; term_ri: up a row, scrolling down at the top of the region (ESC M).
term_ri:
        xor a
        ld (term_wrap),a
        ld a,(term_top)
        ld d,a
        ld a,(cur_row)
        cp d
        jr z,.scroll
        or a
        ret z
        dec a
        ld (cur_row),a
        ret
.scroll:
        ld a,(term_bot)
        ld e,a
        jp vid_scroll_down

term_ff:
        ld a,(set_emul)
        cp EMU_ANSI
        jp nz,term_full_reset
        ld de,0+VID_ROWS-1          ; ANSI-BBS: clear and home, keep colors
        call vid_clear_rows
        ld bc,0
        ; fall through

; term_set_cursor: move to row B, column C, kept on the screen.
term_set_cursor:
        ld a,b
        cp VID_ROWS
        jr c,.row
        ld b,VID_ROWS-1
.row:
        ld a,(vid_cols)
        dec a
        cp c
        jr nc,.col
        ld c,a
.col:
        ld (cur_col),bc
        xor a
        ld (term_wrap),a
        ret

; term_up / term_down / term_left / term_right: move E places. Up and down
; stop at the region's margin when they start inside it.
term_up:
        ld a,(term_top)
        ld d,a
        ld a,(cur_row)
        cp d
        jr nc,.limit
        ld d,0
.limit:
        sub e
        jr c,.clamp
        cp d
        jr nc,.set
.clamp:
        ld a,d
.set:
        ld (cur_row),a
        xor a
        ld (term_wrap),a
        ret

term_down:
        ld a,(term_bot)
        ld d,a
        ld a,(cur_row)
        cp d
        jr z,.limit
        jr c,.limit
        ld d,VID_ROWS-1
.limit:
        add a,e
        jr c,.clamp
        cp d
        jr c,term_up.set
.clamp:
        ld a,d
        jr term_up.set

term_left:
        ld a,(cur_col)
        sub e
        jr nc,.set
        xor a
.set:
        ld (cur_col),a
        xor a
        ld (term_wrap),a
        ret

term_right:
        ld a,(vid_cols)
        dec a
        ld d,a
        ld a,(cur_col)
        add a,e
        jr c,.clamp
        cp d
        jr c,term_left.set
.clamp:
        ld a,d
        jr term_left.set

; term_erase_line: E = 0 cursor to end, 1 start to cursor, 2 the whole row.
term_erase_line:
        ld bc,(cur_col)
        ld a,e
        or a
        jr nz,.not0
        ld a,(vid_cols)
        sub c
        ld d,a
        jp vid_clear_cells
.not0:
        dec a
        jr nz,.whole
        ld d,c
        inc d
        ld c,0
        jp vid_clear_cells
.whole:
        ld c,0
        ld a,(vid_cols)
        ld d,a
        jp vid_clear_cells

; term_erase_screen: E = 0 cursor to end, 1 start to cursor, 2 all.
term_erase_screen:
        ld a,e
        or a
        jr nz,.not0
        call term_erase_line        ; E = 0
        ld a,(cur_row)
        cp VID_ROWS-1
        ret z
        inc a
        ld d,a
        ld e,VID_ROWS-1
        jp vid_clear_rows
.not0:
        dec a
        jr nz,.all
        call term_erase_line        ; E = 1
        ld a,(cur_row)
        or a
        ret z
        dec a
        ld e,a
        ld d,0
        jp vid_clear_rows
.all:
        ld de,0+VID_ROWS-1
        jp vid_clear_rows

; term_save / term_restore: the cursor and the colors (ESC 7 / ESC 8).
term_save:
        ld hl,cur_col
        ld de,term_saved
        ld bc,2
        ldir
        ld hl,sgr_state
        ld bc,SGR_SIZE
        ldir
        ret

term_restore:
        ld hl,term_saved
        ld de,cur_col
        ld bc,2
        ldir
        ld de,sgr_state
        ld bc,SGR_SIZE
        ldir
        xor a
        ld (term_wrap),a
        jp sgr_apply

; --- colors (SGR) ----------------------------------------------------------
;
; The ANSI colors map onto the 2068's: n -> [0,2,4,6,1,3,5,7][n]. Bold is
; BRIGHT, blink is FLASH (if set_blink), reverse swaps INK and PAPER. The
; 2068's BRIGHT covers the whole cell, so a bright background can't be
; shown on its own.

sgr_reset:
        ld hl,sgr_defaults
        ld de,sgr_state
        ld bc,SGR_SIZE
        ldir
        ; fall through

; sgr_apply: cur_attr from the SGR state.
sgr_apply:
        ld a,(sgr_fg)
        call sgr_map
        ld c,a                      ; ink
        ld a,(sgr_bg)
        call sgr_map
        ld b,a                      ; paper
        ld a,(sgr_rev)
        or a
        jr z,.norev
        ld a,b
        ld b,c
        ld c,a
.norev:
        ld a,b
        add a,a
        add a,a
        add a,a
        or c
        ld c,a
        ld a,(sgr_bold)
        or a
        jr z,.nobold
        set 6,c
.nobold:
        ld a,(sgr_blink)
        ld b,a
        ld a,(set_blink)
        and b
        jr z,.noflash
        set 7,c
.noflash:
        ld a,c
        ld (cur_attr),a
        ret

sgr_map:
        and 07h
        ld hl,ansi_to_zx
        add a,l
        ld l,a
        adc a,h
        sub l
        ld h,a
        ld a,(hl)
        ret

ansi_to_zx:     db 0, 2, 4, 6, 1, 3, 5, 7
sgr_defaults:   db 7, 0, 0, 0, 0    ; fg, bg, bold, blink, reverse

; --- state ----------------------------------------------------------------

term_handler:   dw 0                ; 0 = not in a sequence
term_wrap:      db 0                ; 1 = the next printable starts a new line
term_top:       db 0                ; scrolling region, inclusive
term_bot:       db VID_ROWS-1
term_autowrap:  db 1
term_cursor:    db 1                ; 0 = hidden (ESC [ ? 25 l)
sgr_state:
sgr_fg:         db 7
sgr_bg:         db 0
sgr_bold:       db 0
sgr_blink:      db 0
sgr_rev:        db 0
SGR_SIZE        equ $-sgr_state
term_saved:     ds 2+SGR_SIZE
