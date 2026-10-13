; phonebook.asm - 20 hosts, each with its own terminal settings
;
; An entry is PB_SIZE bytes at PHONEBOOK (uninitialised data, cleared at
; start-up and filled from picoterm.cfg). Dialling one applies its
; settings, then sends ATDT"host:port" (ATD for raw TCP) and goes back to
; the terminal, where Zimodem's CONNECT or NO ANSWER appears.

PB_COUNT        equ 20
PB_SIZE         equ 64
PB_NAME         equ 0               ; 16 characters + 0
PB_NAME_MAX     equ 16
PB_HOST         equ 17              ; 40 + 0
PB_HOST_MAX     equ 40
PB_TELNET       equ 58              ; 1 = ATDT, 0 = ATD
PB_EMUL         equ 59              ; EMU_
PB_COLS         equ 60              ; VM_
PB_BS           equ 61              ; 08h or 7Fh
PB_ECHO         equ 62
PB_USED         equ 63              ; 0 = an empty slot

; pb_clear: empty the phonebook.
pb_clear:
        ld hl,PHONEBOOK
        ld de,PHONEBOOK+1
        ld bc,PB_COUNT*PB_SIZE-1
        ld (hl),0
        ldir
        ret

; pb_entry: HL = entry A. Uses A, DE.
pb_entry:
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl                   ; x 64
        ld de,PHONEBOOK
        add hl,de
        ret

; pb_free: A = the first empty slot, C if there's none.
pb_free:
        ld b,0
.look:
        ld a,b
        call pb_entry
        ld de,PB_USED
        add hl,de
        ld a,(hl)
        or a
        ld a,b
        ret z
        inc b
        ld a,b
        cp PB_COUNT
        jr c,.look
        scf
        ret

; pb_run: the phonebook screen. C = a call was started (back to the
; terminal), NC = back to the menu.
pb_run:
.draw:
        call pb_draw
.key:
        call ui_getkey
        call ui_is_back
        jr z,.back
        cp K_UP
        jr z,.up
        cp K_DOWN
        jr z,.down
        cp K_ENTER
        jr z,.dial
        cp 'N'
        jr z,.new
        cp 'E'
        jr z,.edit
        cp 'X'
        jr z,.delete
        jr .key
.back:
        or a
        ret
.up:
        ld a,(pb_sel)
        or a
        jr z,.key
        dec a
        jr .move
.down:
        ld a,(pb_sel)
        cp PB_COUNT-1
        jr nc,.key
        inc a
.move:                              ; redraw just the two rows
        ld hl,pb_sel
        ld b,(hl)
        ld (hl),a
        push af
        ld a,b
        call pb_draw_row
        pop af
        call pb_draw_row
        jr .key
.dial:
        call pb_selected
        jr z,.key                   ; an empty slot
        call pb_dial
        ret c
        jr .draw
.new:
        call pb_free
        jr nc,.room
        ld hl,txt_pb_full
        call ui_message
        jr .draw
.room:
        ld (pb_sel),a
        call pb_entry
        push hl
        ld de,PB_SIZE               ; defaults: this session's settings
        ld b,e
        ld d,h
        ld e,l
.zero:
        xor a
        ld (de),a
        inc de
        djnz .zero
        pop hl
        push hl
        call pb_defaults
        pop hl
        ld a,1
        call pb_edit                ; A = 1: ask for the name and host
        jr .draw
.edit:
        call pb_selected
        jp z,.key
        xor a
        call pb_edit
        jp .draw
.delete:
        call pb_selected
        jp z,.key
        push hl
        ld hl,txt_pb_delete
        call ui_yes_no
        pop hl
        jp nz,.draw
        ld de,PB_USED
        add hl,de
        ld (hl),0
        jp .draw

; pb_selected: HL = the selected entry; Z if it's empty.
pb_selected:
        ld a,(pb_sel)
        call pb_entry
        push hl
        ld de,PB_USED
        add hl,de
        ld a,(hl)
        or a
        pop hl
        ret

; pb_defaults: give the entry at HL this session's settings (and telnet).
pb_defaults:
        ld de,PB_TELNET
        add hl,de
        ld (hl),1
        inc hl
        ld a,(set_emul)
        ld (hl),a
        inc hl
        ld a,(vid_mode)
        ld (hl),a
        inc hl
        ld a,(set_backspace)
        ld (hl),a
        inc hl
        ld a,(set_echo)
        ld (hl),a
        ret

pb_draw:
        ld b,0
        ld d,VID_ROWS
        ld hl,txt_phonebook
        call ui_box
        ld hl,pb_script
        call ui_script
        xor a
.entry:
        push af
        call pb_draw_row
        pop af
        inc a
        cp PB_COUNT
        jr c,.entry
        ret

; pb_draw_row: entry A's row in the list.
pb_draw_row:
        ld (pb_i),a
        inc a
        ld b,a                      ; screen row = entry + 1
        ld c,2
        ld e,ATTR_WIN
        ld a,(pb_i)
        ld hl,pb_sel
        cp (hl)
        ld a,' '
        jr nz,.mark
        ld e,ATTR_SEL
        ld a,'>'
.mark:
        call ui_put
        inc c
        ld a,' '
        call ui_put
        inc c
        push de
        ld a,(pb_i)
        call pb_entry
        pop de
        push hl
        push de
        ld de,PB_USED
        add hl,de
        ld a,(hl)
        pop de
        pop hl
        or a
        jr nz,.name
        ld hl,txt_pb_empty
.name:
        call ui_text
        ld a,UI_W-1
        sub c
        ld d,a
        ld a,' '
        jp ui_fill

pb_script:
        db 21, 2, ATTR_TITLE, "ENTER",0
        db 21, 8, ATTR_WIN, "dial",0
        db 21, 14, ATTR_TITLE, "N",0
        db 21, 16, ATTR_WIN, "new",0
        db 21, 21, ATTR_TITLE, "E",0
        db 21, 23, ATTR_WIN, "edit",0
        db 22, 2, ATTR_TITLE, "X",0
        db 22, 4, ATTR_WIN, "delete",0
        db 22, 14, ATTR_TITLE, "BREAK",0
        db 22, 20, ATTR_WIN, "back",0
        db 0FFh

; pb_edit: the form for the entry at HL. A = 1 for a new entry: the name
; and host are asked for first. ENTER keeps the changes, BREAK drops them.
pb_edit:
        ld (pb_edit_entry),hl
        push af
        ld de,pb_work
        ld bc,PB_SIZE
        ldir
        pop af
        or a
        jr z,.draw
        call pb_draw_form
        call .name
        jr c,.cancel
        call .host
        jr c,.cancel
.draw:
        call pb_draw_form
.key:
        call ui_getkey
        call ui_is_back
        jr z,.cancel
        cp K_ENTER
        jr z,.save
        ld hl,pb_work+PB_TELNET
        cp 'T'
        jr z,.toggle
        ld hl,pb_work+PB_ECHO
        cp 'L'
        jr z,.toggle
        cp 'N'
        jr z,.ename
        cp 'H'
        jr z,.ehost
        cp 'E'
        jr z,.emul
        cp 'C'
        jr z,.cols
        cp 'B'
        jr z,.bs
        jr .key
.toggle:
        ld a,(hl)
        xor 1
        ld (hl),a
        jr .draw
.ename:
        call .name
        jr .draw
.ehost:
        call .host
        jr .draw
.emul:
        ld hl,pb_work+PB_EMUL
        ld b,3
        jr .cycle
.cols:
        ld hl,pb_work+PB_COLS
        call cols_count
.cycle:
        ld a,(hl)
        inc a
        cp b
        jr c,.set
        xor a
.set:
        ld (hl),a
        jr .draw
.bs:
        ld hl,pb_work+PB_BS
        ld a,(hl)
        xor 08h ^ 7Fh
        ld (hl),a
        jr .draw
.save:
        ld a,(pb_work+PB_HOST)
        or a
        jr z,.key                   ; no host, no entry
        ld a,1
        ld (pb_work+PB_USED),a
        ld hl,pb_work
        ld de,(pb_edit_entry)
        ld bc,PB_SIZE
        ldir
        ret
.cancel:
        ret
.name:
        ld hl,pb_work+PB_NAME
        ld bc,4*256+9               ; row 4, column 9
        ld de,PB_NAME_MAX*256+21
        jp ui_input
.host:
        ld hl,pb_work+PB_HOST
        ld bc,7*256+2
        ld de,PB_HOST_MAX*256+28
        jp ui_input

; cols_count: B = how many column modes there are: 3 with PicoVideo, else 2.
cols_count:
        ld b,2
        ld a,(set_picovideo)
        or a
        ret z
        inc b
        ret

pb_draw_form:
        ld b,2
        ld d,17
        ld hl,txt_pb_entry
        call ui_box
        ld hl,pb_form_script
        call ui_script
        ld bc,4*256+9               ; the name, padded
        ld hl,pb_work+PB_NAME
        ld e,ATTR_FIELD
        ld d,21
        call pb_field
        ld bc,7*256+2               ; the host
        ld hl,pb_work+PB_HOST
        ld d,28
        call pb_field
        ld bc,9*256+15
        ld a,(pb_work+PB_TELNET)
        call yes_no_text
        ld e,ATTR_WIN
        call ui_text
        ld bc,10*256+15
        ld a,(pb_work+PB_EMUL)
        ld hl,emul_names
        call ui_pick
        ld e,ATTR_WIN
        call ui_text
        ld bc,11*256+15
        ld a,(pb_work+PB_COLS)
        ld hl,cols_names
        call ui_pick
        ld e,ATTR_WIN
        call ui_text
        ld bc,12*256+15
        ld a,(pb_work+PB_BS)
        call bs_text
        ld e,ATTR_WIN
        call ui_text
        ld bc,13*256+15
        ld a,(pb_work+PB_ECHO)
        call yes_no_text
        ld e,ATTR_WIN
        jp ui_text

; pb_field: the string at HL in a D-wide field (cut if longer).
pb_field:
.cell:
        ld a,(hl)
        or a
        jr z,.pad
        call ui_put
        inc hl
        inc c
        dec d
        jr nz,.cell
        ret
.pad:
        ld a,' '
        jp ui_fill

; yes_no_text: HL = "Yes" if A is non-zero, else "No".
yes_no_text:
        ld hl,txt_yes
        or a
        ret nz
        ld hl,txt_no
        ret

; bs_text: HL = "BS (08h)" or "DEL (7Fh)" for A.
bs_text:
        ld hl,txt_bs
        cp 08h
        ret z
        ld hl,txt_del
        ret

pb_form_script:
        db 4, 2, ATTR_TITLE, "N",0
        db 4, 4, ATTR_WIN, "Name",0
        db 6, 2, ATTR_TITLE, "H",0
        db 6, 4, ATTR_WIN, "Host:port",0
        db 9, 2, ATTR_TITLE, "T",0
        db 9, 4, ATTR_WIN, "Telnet",0
        db 10, 2, ATTR_TITLE, "E",0
        db 10, 4, ATTR_WIN, "Emulation",0
        db 11, 2, ATTR_TITLE, "C",0
        db 11, 4, ATTR_WIN, "Columns",0
        db 12, 2, ATTR_TITLE, "B",0
        db 12, 4, ATTR_WIN, "Backspace",0
        db 13, 2, ATTR_TITLE, "L",0
        db 13, 4, ATTR_WIN, "Local echo",0
        db 16, 2, ATTR_TITLE, "ENTER",0
        db 16, 8, ATTR_WIN, "save",0
        db 16, 14, ATTR_TITLE, "BREAK",0
        db 16, 20, ATTR_WIN, "cancel",0
        db 0FFh

; pb_dial: the entry at HL. C = dialling (back to the terminal), NC = not
; possible (a message has been shown).
pb_dial:
        ld a,(hayes_online)
        or a
        jr z,.offline
        ld hl,txt_hang_up_first
        call ui_message
        or a
        ret
.offline:
        ld (pb_dial_entry),hl
        ld de,PB_EMUL               ; the entry's settings
        add hl,de
        ld a,(hl)
        ld (set_emul),a
        inc hl
        ld a,(hl)
        ld (pb_dial_cols),a
        inc hl
        ld a,(hl)
        ld (set_backspace),a
        inc hl
        ld a,(hl)
        ld (set_echo),a
        ld de,dial_buf              ; ATDT"host" or ATD"host"
        ld hl,txt_atd
        call str_copy
        ld hl,(pb_dial_entry)
        ld bc,PB_TELNET
        add hl,bc
        ld a,(hl)
        or a
        jr z,.raw
        ld a,'T'
        ld (de),a
        inc de
.raw:
        ld a,'"'
        ld (de),a
        inc de
        ld hl,(pb_dial_entry)
        ld bc,PB_HOST
        add hl,bc
        call str_copy
        ld a,'"'
        ld (de),a
        inc de
        xor a
        ld (de),a
        ; back to the terminal, in the entry's column mode
        ld a,(pb_dial_cols)
        ld b,a
        ld a,(set_picovideo)
        or a
        jr nz,.cols
        ld a,b
        cp VM_80
        jr nz,.cols
        ld b,VM_64                  ; no PicoVideo: 64 is the widest
.cols:
        ld a,b
        ld hl,vid_mode
        cp (hl)
        jr z,.same
        call vid_set_mode           ; redraws, which closes the window
        xor a
        ld (rx_mode),a
        jr .shown
.same:
        call ui_close
.shown:
        call term_fresh_line
        ld hl,txt_dialling
        call term_puts
        ld hl,(pb_dial_entry)
        call term_puts              ; the name
        ld hl,crlf
        call term_puts
        call send_termtype
        ld hl,dial_buf
        call hayes_send
        scf
        ret

; str_copy: the 0-terminated string at HL to DE, without the 0. DE ends
; after it.
str_copy:
        ld a,(hl)
        or a
        ret z
        ld (de),a
        inc hl
        inc de
        jr str_copy

; --- state ----------------------------------------------------------------

pb_sel:         db 0
pb_i:           db 0
pb_edit_entry:  dw 0
pb_dial_entry:  dw 0
pb_dial_cols:   db 0
pb_work:        ds PB_SIZE
dial_buf:       ds 4+1+PB_HOST_MAX+2

txt_phonebook:  db "Phonebook",0
txt_pb_entry:   db "Entry",0
txt_pb_empty:   db "-",0
txt_pb_full:    db "The phonebook is full.",0
txt_pb_delete:  db "Delete this entry? (Y/N)",0
txt_hang_up_first: db "Hang up first.",0
txt_yes:        db "Yes",0
txt_no:         db "No ",0
txt_bs:         db "BS (08h) ",0
txt_del:        db "DEL (7Fh)",0
txt_atd:        db "ATD",0
txt_dialling:   db "Dialling ",0
