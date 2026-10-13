; ansi.asm - ANSI-BBS emulation: a VT100 subset with colour (ECMA-48)
;
; ESC sequences: [ (CSI), ] (OSC, skipped to BEL or ST), ( ) # (one more
; byte, skipped), 7 8 (save/restore), D E M (index, next line, reverse
; index), c (reset). CSI: up to 8 numeric parameters (each kept to 255), a
; private marker (< = > ?) and intermediates; sequences with intermediates
; are parsed and ignored. Finals handled are in ansi_finals.
; (docs/DESIGN.md section 6.)

ANSI_MAXP       equ 8

ansi_esc:
        cp 20h
        jr nc,.go
        jp term_seq_control         ; the handler stays: still after ESC
.go:
        ld hl,0
        ld (term_handler),hl
        cp '['
        jr z,.csi
        cp ']'
        jr z,.osc
        cp '('
        jr z,.skip1
        cp ')'
        jr z,.skip1
        cp '#'
        jr z,.skip1
        cp '7'
        jp z,term_save
        cp '8'
        jp z,term_restore
        cp 'D'
        jp z,term_lf
        cp 'E'
        jp z,term_nel
        cp 'M'
        jp z,term_ri
        cp 'c'
        jp z,term_full_reset
        ret
.csi:
        ld hl,ansi_p
        ld b,ANSI_MAXP+3            ; parameters, count, private, intermediate
.clear:
        ld (hl),0
        inc hl
        djnz .clear
        ld hl,ansi_csi
        jr .set
.osc:
        ld hl,ansi_osc
        jr .set
.skip1:
        ld hl,term_to_ground        ; takes the next byte, whatever it is
.set:
        ld (term_handler),hl
        ret

; ansi_osc: an OSC string, ended by BEL or ESC (ESC \ is ST).
ansi_osc:
        cp 07h
        jp z,term_to_ground
        cp 18h
        jp z,term_to_ground
        cp 1Ah
        jp z,term_to_ground
        cp 1Bh
        ret nz
        ld hl,term_to_ground        ; the byte after ESC is dropped
        ld (term_handler),hl
        ret

; ansi_csi: parameters, then the final byte.
ansi_csi:
        cp 20h
        jp c,term_seq_control
        cp 30h
        jr c,.inter                 ; 20h-2Fh
        cp 3Ah
        jr nc,.notdigit
        sub '0'
        ld c,a
        ld a,(ansi_n)
        ld hl,ansi_p
        add a,l
        ld l,a
        adc a,h
        sub l
        ld h,a
        ld a,(hl)
        cp 26
        jr nc,.sat                  ; 26 x 10 > 255
        ld b,a
        add a,a
        add a,a
        add a,b
        add a,a                     ; x 10
        add a,c
        jr c,.sat
        ld (hl),a
        ret
.sat:
        ld (hl),255
        ret
.notdigit:
        cp ';'
        jr nz,.notsep
        ld a,(ansi_n)
        cp ANSI_MAXP-1
        ret nc                      ; more than 8: the rest are dropped
        inc a
        ld (ansi_n),a
        ret
.notsep:
        cp 40h
        jr nc,.final
        cp 3Ch
        ret c                       ; ':' sub-parameters: ignored
        ld (ansi_priv),a            ; < = > ?
        ret
.inter:
        ld a,1
        ld (ansi_inter),a
        ret
.final:
        cp 7Fh
        ret z                       ; DEL is ignored, even here
        ld hl,0
        ld (term_handler),hl
        ld c,a
        ld a,(ansi_inter)
        or a
        ret nz
        ld a,(ansi_priv)
        or a
        jr z,.lookup
        cp '?'
        ret nz
        ld a,c
        cp 'h'
        jp z,ansi_decset
        cp 'l'
        jp z,ansi_decset
        ret
.lookup:
        ld hl,ansi_finals
.find:
        ld a,(hl)
        or a
        ret z
        inc hl
        cp c
        jr z,.found
        inc hl
        inc hl
        jr .find
.found:
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        jp (hl)

ansi_finals:
        db 'A' : dw ansi_cuu
        db 'B' : dw ansi_cud
        db 'e' : dw ansi_cud
        db 'C' : dw ansi_cuf
        db 'a' : dw ansi_cuf
        db 'D' : dw ansi_cub
        db 'E' : dw ansi_cnl
        db 'F' : dw ansi_cpl
        db 'G' : dw ansi_cha
        db '`' : dw ansi_cha
        db 'H' : dw ansi_cup
        db 'f' : dw ansi_cup
        db 'd' : dw ansi_vpa
        db 'J' : dw ansi_ed
        db 'K' : dw ansi_el
        db 'L' : dw ansi_il
        db 'M' : dw ansi_dl
        db '@' : dw ansi_ich
        db 'P' : dw ansi_dch
        db 'X' : dw ansi_ech
        db 'S' : dw ansi_su
        db 'T' : dw ansi_sd
        db 'm' : dw ansi_sgr
        db 'r' : dw ansi_stbm
        db 's' : dw term_save
        db 'u' : dw term_restore
        db 'n' : dw ansi_dsr
        db 'c' : dw ansi_da
        db 0

; ansi_p1: E = the first parameter, 1 if it was 0 or missing.
ansi_p1:
        ld a,(ansi_p)
ansi_or1:
        or a
        jr nz,.e
        inc a
.e:
        ld e,a
        ret

ansi_cuu:
        call ansi_p1
        jp term_up

ansi_cud:
        call ansi_p1
        jp term_down

ansi_cuf:
        call ansi_p1
        jp term_right

ansi_cub:
        call ansi_p1
        jp term_left

ansi_cnl:
        call ansi_cud
        jp term_cr

ansi_cpl:
        call ansi_cuu
        jp term_cr

ansi_cha:
        call ansi_p1
        dec e
        ld c,e
        ld a,(cur_row)
        ld b,a
        jp term_set_cursor

ansi_vpa:
        call ansi_p1
        dec e
        ld b,e
        ld a,(cur_col)
        ld c,a
        jp term_set_cursor

ansi_cup:
        call ansi_p1
        dec e
        ld b,e
        ld a,(ansi_p+1)
        call ansi_or1
        dec e
        ld c,e
        jp term_set_cursor

; ED: 0 to the end, 1 to the start, 2 all and home (ANSI.SYS, which BBS
; screens expect), 3 all.
ansi_ed:
        ld a,(ansi_p)
        cp 3
        jr z,.all
        ld e,a
        cp 2
        jp nz,term_erase_screen
        call term_erase_screen
        ld bc,0
        jp term_set_cursor
.all:
        ld e,2
        jp term_erase_screen

ansi_el:
        ld a,(ansi_p)
        cp 3
        ret nc
        ld e,a
        jp term_erase_line

; ansi_in_region: C if the cursor's row is inside the scrolling region.
ansi_in_region:
        ld a,(term_top)
        ld b,a
        ld a,(cur_row)
        cp b
        ccf
        ret nc                      ; above the region
        ld b,a
        ld a,(term_bot)
        cp b                        ; C if bot < row
        ccf
        ret

; ansi_count: B = the first parameter (at least 1), at most the rows from
; the cursor to the bottom of the region.
ansi_count:
        call ansi_p1
        ld a,(cur_row)
        ld b,a
        ld a,(term_bot)
        sub b
        inc a
        cp e
        jr c,.max
        ld a,e
.max:
        ld b,a
        ret

ansi_il:
        call ansi_in_region
        ret nc
        call ansi_count
.line:
        push bc
        ld a,(cur_row)
        ld d,a
        ld a,(term_bot)
        ld e,a
        call vid_scroll_down
        pop bc
        djnz .line
        jp term_cr

ansi_dl:
        call ansi_in_region
        ret nc
        call ansi_count
.line:
        push bc
        ld a,(cur_row)
        ld d,a
        ld a,(term_bot)
        ld e,a
        call vid_scroll_up
        pop bc
        djnz .line
        jp term_cr

; ansi_cells: D = the first parameter (at least 1), at most the cells from
; the cursor to the end of the row; BC = the cursor.
ansi_cells:
        call ansi_p1
        ld bc,(cur_col)
        ld a,(vid_cols)
        sub c
        cp e
        jr c,.max
        ld a,e
.max:
        ld d,a
        xor a
        ld (term_wrap),a
        ret

ansi_ich:
        call ansi_cells
        jp vid_insert_cells

ansi_dch:
        call ansi_cells
        jp vid_delete_cells

ansi_ech:
        call ansi_cells
        jp vid_clear_cells

ansi_su:
        call ansi_p1
        ld b,e
.line:
        push bc
        ld a,(term_top)
        ld d,a
        ld a,(term_bot)
        ld e,a
        call vid_scroll_up
        pop bc
        djnz .line
        ret

ansi_sd:
        call ansi_p1
        ld b,e
.line:
        push bc
        ld a,(term_top)
        ld d,a
        ld a,(term_bot)
        ld e,a
        call vid_scroll_down
        pop bc
        djnz .line
        ret

; DECSTBM: the scrolling region, then home.
ansi_stbm:
        call ansi_p1
        dec e
        ld d,e                      ; top
        ld a,(ansi_p+1)
        or a
        jr z,.bottom
        cp VID_ROWS+1
        jr c,.given
.bottom:
        ld a,VID_ROWS
.given:
        dec a
        ld e,a                      ; bottom
        ld a,d
        cp e
        ret nc                      ; needs at least two rows
        ld (term_top),a
        ld a,e
        ld (term_bot),a
        ld bc,0
        jp term_set_cursor

; SGR: every parameter in turn; 38 and 48 take their extra ones.
ansi_sgr:
        ld hl,ansi_p
        ld a,(ansi_n)
        inc a
        ld b,a
.next:
        ld a,b
        or a
        jp z,sgr_apply
        ld a,(hl)
        inc hl
        dec b
        cp 38
        jr z,.ext
        cp 48
        jr z,.ext
        push hl
        push bc
        call sgr_one
        pop bc
        pop hl
        jr .next
.ext:
        ld c,a                      ; 38 = ink, 48 = paper
        ld a,b
        or a
        jp z,sgr_apply
        ld a,(hl)
        inc hl
        dec b
        cp 5
        jr z,.indexed
        cp 2
        jr nz,.next
        ld a,b                      ; 2;r;g;b: no way to show it, skip it
        sub 3
        jp c,sgr_apply
        ld b,a
        inc hl
        inc hl
        inc hl
        jr .next
.indexed:
        ld a,b                      ; 5;n: the first 16 are the ANSI colours
        or a
        jp z,sgr_apply
        ld a,(hl)
        inc hl
        dec b
        cp 16
        jr nc,.next
        push hl
        push bc
        ld e,a
        and 07h
        ld d,a
        ld a,c
        cp 48
        jr z,.paper
        ld a,d
        ld (sgr_fg),a
        bit 3,e
        jr z,.done
        ld a,1
        ld (sgr_bold),a
        jr .done
.paper:
        ld a,d
        ld (sgr_bg),a
.done:
        pop bc
        pop hl
        jr .next

; sgr_one: one SGR parameter A.
sgr_one:
        or a
        jp z,sgr_reset_state
        ld hl,sgr_bold
        cp 1
        jr z,.set
        cp 22
        jr z,.clear
        ld hl,sgr_blink
        cp 5
        jr z,.set
        cp 6
        jr z,.set
        cp 25
        jr z,.clear
        ld hl,sgr_rev
        cp 7
        jr z,.set
        cp 27
        jr z,.clear
        cp 39
        jr z,.fgdef
        cp 49
        jr z,.bgdef
        cp 30
        ret c
        cp 38
        jr c,.fg
        cp 40
        ret c
        cp 48
        jr c,.bg
        cp 90
        ret c
        cp 98
        jr c,.brightfg
        cp 100
        ret c
        cp 108
        ret nc
        sub 100-40                  ; bright paper: the colour only
.bg:
        sub 40
        ld (sgr_bg),a
        ret
.brightfg:
        sub 90-30
        ld hl,sgr_bold
        ld (hl),1
.fg:
        sub 30
        ld (sgr_fg),a
        ret
.fgdef:
        ld a,7
        ld (sgr_fg),a
        ret
.bgdef:
        xor a
        ld (sgr_bg),a
        ret
.set:
        ld (hl),1
        ret
.clear:
        ld (hl),0
        ret

sgr_reset_state:
        ld hl,sgr_defaults
        ld de,sgr_state
        ld bc,SGR_SIZE
        ldir
        ret

; DECSET / DECRST (CSI ? n h / l): 25 shows/hides the cursor, 7 wrapping.
ansi_decset:
        sub 'l'                     ; h -> FCh (NZ), l -> 0
        jr z,.val
        ld a,1
.val:
        ld e,a
        ld hl,ansi_p
        ld a,(ansi_n)
        inc a
        ld b,a
.each:
        ld a,(hl)
        inc hl
        cp 25
        jr nz,.not25
        ld a,e
        ld (term_cursor),a
.not25:
        cp 7
        jr nz,.not7
        ld a,e
        ld (term_autowrap),a
.not7:
        djnz .each
        ret

; DSR: 5 is "are you there" (ESC [ 0 n), 6 asks where the cursor is
; (ESC [ row ; col R). BBSes use 6 to find out the screen size.
ansi_dsr:
        ld a,(ansi_p)
        cp 5
        jr z,.ok
        cp 6
        ret nz
        ld a,1Bh
        call acia_send
        ld a,'['
        call acia_send
        ld a,(cur_row)
        inc a
        call send_decimal
        ld a,';'
        call acia_send
        ld a,(cur_col)
        inc a
        call send_decimal
        ld a,'R'
        jp acia_send
.ok:
        ld hl,reply_dsr_ok
        jp send_string

; DA: "a VT100 with no options".
ansi_da:
        ld a,(ansi_p)
        or a
        ret nz
        ld hl,reply_da
        jp send_string

reply_dsr_ok:   db 1Bh,"[0n",0
reply_da:       db 1Bh,"[?1;0c",0

; send_string: send the 0-terminated string at HL to the modem.
send_string:
        ld a,(hl)
        or a
        ret z
        call acia_send
        inc hl
        jr send_string

; send_decimal: send A (0-255) in decimal, no leading zeros.
send_decimal:
        ld c,0                      ; 1 once a digit has gone
        ld b,100
        call .digit
        ld b,10
        call .digit
        add a,'0'
        jp acia_send
.digit:
        ld d,'0'-1
.count:
        inc d
        sub b
        jr nc,.count
        add a,b
        ld e,a
        ld a,d
        cp '0'
        jr nz,.send
        ld a,c
        or a
        ld a,e
        ret z                       ; a leading zero
        ld a,'0'
.send:
        call acia_send
        ld c,1
        ld a,e
        ret

; --- state ----------------------------------------------------------------

ansi_p:         ds ANSI_MAXP        ; the parameters (0 = missing)
ansi_n:         db 0                ; index of the parameter being read
ansi_priv:      db 0                ; private marker, 0 = none
ansi_inter:     db 0                ; 1 = intermediates seen
