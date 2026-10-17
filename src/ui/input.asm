; input.asm - a one-line text field
;
; ui_input edits the 0-terminated string at HL in place: printable ASCII
; adds, DELETE takes away, ENTER keeps the change, BREAK or EDIT (Esc)
; drops it. The field is E cells wide at window row B, column C, and holds
; up to D characters; longer text scrolls so the end shows. With ui_mask
; set, the text shows as asterisks (passwords).

INPUT_MAX       equ 64

; ui_input: NC = accepted (HL's string changed), C = canceled.
ui_input:
        ld (in_target),hl
        ld (in_pos),bc
        ld a,d
        ld (in_max),a
        ld a,e
        ld (in_width),a
        ld de,in_buf                ; work on a copy
        ld b,0
.copy:
        ld a,(hl)
        ld (de),a
        or a
        jr z,.copied
        inc hl
        inc de
        inc b
        jr .copy
.copied:
        ld a,b
        ld (in_len),a
.show:
        call in_draw
        call ui_getkey_raw
        cp K_ENTER
        jr z,.accept
        call ui_is_back
        jr z,.cancel
        cp K_BACKSPACE
        jr z,.delete
        cp 20h
        jr c,.show
        cp 7Fh
        jr nc,.show
        ld c,a
        ld a,(in_max)
        ld b,a
        ld a,(in_len)
        cp b
        jr nc,.show                 ; full
        ld hl,in_buf
        call vid_add_a
        ld (hl),c
        inc hl
        ld (hl),0
        ld hl,in_len
        inc (hl)
        jr .show
.delete:
        ld a,(in_len)
        or a
        jr z,.show
        dec a
        ld (in_len),a
        ld hl,in_buf
        call vid_add_a
        ld (hl),0
        jr .show
.accept:
        ld hl,in_buf
        ld de,(in_target)
.back:
        ld a,(hl)
        ld (de),a
        inc hl
        inc de
        or a
        jr nz,.back
        or a                        ; NC
        ret
.cancel:
        scf
        ret

; in_draw: the field, its visible part, and a "_" where the next
; character goes.
in_draw:
        ld a,(in_width)
        dec a                       ; one cell for the "_"
        ld b,a
        ld a,(in_len)
        sub b
        jr nc,.from
        xor a
.from:
        ld hl,in_buf
        call vid_add_a              ; HL = the first visible character
        ld bc,(in_pos)
        ld a,(in_width)
        ld d,a
        ld e,ATTR_FIELD
.cell:
        ld a,(hl)
        or a
        jr z,.end
        ld a,(ui_mask)
        or a
        ld a,'*'
        jr nz,.put
        ld a,(hl)
.put:
        call ui_put
        inc hl
        inc c
        dec d
        jr nz,.cell
        ret
.end:
        ld a,'_'
        call ui_put
        inc c
        dec d
        ret z
        ld a,' '
        jp ui_fill

; ui_getkey_raw: a key, letters as typed.
ui_getkey_raw:
        call pump_rx
        call kbd_get
        jr z,ui_getkey_raw
        ret

; --- state ----------------------------------------------------------------

ui_mask:        db 0
in_target:      dw 0
in_pos:         dw 0
in_max:         db 0
in_width:       db 0
in_len:         db 0
in_buf:         ds INPUT_MAX+1
