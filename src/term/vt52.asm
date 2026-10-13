; vt52.asm - VT52 emulation
;
; ESC A B C D (cursor up, down, right, left), H (home), I (reverse line
; feed), J (erase to the end of the screen), K (erase to the end of the
; line), Y row col (each + 20h), Z (identify: ESC / Z). F G (graphics
; character set), = > (keypad modes) and < (ANSI mode) are accepted and
; ignored. (docs/DESIGN.md section 6.)

vt52_esc:
        cp 20h
        jr nc,.go
        jp term_seq_control
.go:
        ld hl,0
        ld (term_handler),hl
        ld e,1
        cp 'A'
        jp z,term_up
        cp 'B'
        jp z,term_down
        cp 'C'
        jp z,term_right
        cp 'D'
        jp z,term_left
        cp 'I'
        jp z,term_ri
        ld e,0
        cp 'J'
        jp z,term_erase_screen
        cp 'K'
        jp z,term_erase_line
        cp 'H'
        jr z,.home
        cp 'Y'
        jr z,.y
        cp 'Z'
        ret nz
        ld hl,reply_vt52_id
        jp send_string
.home:
        ld bc,0
        jp term_set_cursor
.y:
        ld hl,vt52_row
        ld (term_handler),hl
        ret

vt52_row:
        cp 20h
        jp c,term_seq_control
        sub 20h
        ld (vt52_y),a
        ld hl,vt52_col
        ld (term_handler),hl
        ret

vt52_col:
        cp 20h
        jp c,term_seq_control
        sub 20h
        ld c,a
        ld a,(vt52_y)
        ld b,a
        call term_to_ground
        jp term_set_cursor

reply_vt52_id:  db 1Bh,"/Z",0

vt52_y:         db 0
