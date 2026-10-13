; settings.asm - the Settings screen
;
; Each key changes one setting at once. Columns, PicoVideo and the 64-column
; colour take effect when the screen closes (the mode is set again); the
; emulation is told to Zimodem (the telnet terminal type) if offline. S
; saves everything, phonebook too, to picoterm.cfg on the TS-Pico.

SET_ROW         equ 2               ; the window's top row

settings_run:
        ld a,(set_emul)
        ld (st_old_emul),a
.draw:
        call st_draw
.key:
        call ui_getkey
        call ui_is_back
        jp z,.back
        cp 'E'
        jr z,.emul
        cp 'C'
        jr z,.cols
        cp 'P'
        jr z,.pv
        cp 'I'
        jr z,.ink
        ld hl,set_echo
        cp 'L'
        jr z,.toggle
        ld hl,set_enter
        cp 'N'
        jr z,.toggle
        ld hl,set_blink
        cp 'F'
        jr z,.toggle
        ld hl,set_bell
        cp 'G'
        jr z,.toggle
        cp 'B'
        jr z,.bs
        cp 'M'
        jr z,.init
        cp 'S'
        jr z,.save
        jr .key
.toggle:
        ld a,(hl)
        xor 1
        ld (hl),a
        jr .draw
.emul:
        ld hl,set_emul
        ld b,3
        jr .cycle
.cols:
        ld hl,set_cols
        call cols_count
        jr .cycle
.ink:
        ld hl,set_ink64
        ld b,8
.cycle:
        ld a,(hl)
        inc a
        cp b
        jr c,.set
        xor a
.set:
        ld (hl),a
        jr .draw
.pv:
        ld a,(set_picovideo)
        xor 1
        ld (set_picovideo),a
        jr nz,.draw
        ld a,(set_cols)             ; no PicoVideo: no 80 columns
        cp VM_80
        jr nz,.draw
        ld a,VM_64
        ld (set_cols),a
        jp .draw
.bs:
        ld a,(set_backspace)
        xor 08h ^ 7Fh
        ld (set_backspace),a
        jp .draw
.init:
        ld hl,set_init
        ld bc,(SET_ROW+14)*256+2
        ld de,INIT_MAX*256+28
        call ui_input
        jp .draw
.save:
        call config_save
        ld hl,txt_saved
        jr nc,.said
        ld hl,txt_not_saved
.said:
        call ui_message
        jp .draw
.back:
        ; the column mode and its colours may have changed: set the mode
        ; again (that redraws, so the menu draws itself afresh after)
        ld a,(set_cols)
        call vid_set_mode
        ld a,(set_emul)
        ld hl,st_old_emul
        cp (hl)
        ret z
        ld a,(hayes_online)
        or a
        ret nz
        ld a,RX_CAPTURE             ; tell Zimodem, out of sight
        ld (rx_mode),a
        call send_termtype
        ld a,RX_HOLD
        ld (rx_mode),a
        ret

st_draw:
        ld b,SET_ROW
        ld d,20
        ld hl,txt_settings
        call ui_box
        ld hl,st_script
        call ui_script
        ld e,ATTR_WIN
        ld bc,(SET_ROW+2)*256+18
        ld a,(set_emul)
        ld hl,emul_names
        call ui_pick
        call st_value
        ld bc,(SET_ROW+3)*256+18
        ld a,(set_cols)
        ld hl,cols_names
        call ui_pick
        call st_value
        ld bc,(SET_ROW+4)*256+18
        ld a,(set_picovideo)
        call yes_no_text
        call st_value
        ld bc,(SET_ROW+5)*256+18
        ld a,(set_ink64)
        ld hl,ink_names
        ld e,a
        add a,a
        add a,a
        add a,a
        sub e                       ; x 7
        call vid_add_a
        call st_value
        ld bc,(SET_ROW+6)*256+18
        ld a,(set_backspace)
        call bs_text
        call st_value
        ld bc,(SET_ROW+7)*256+18
        ld a,(set_echo)
        call yes_no_text
        call st_value
        ld bc,(SET_ROW+8)*256+18
        ld hl,txt_cr
        ld a,(set_enter)
        or a
        jr z,.enter
        ld hl,txt_crlf
.enter:
        call st_value
        ld bc,(SET_ROW+9)*256+18
        ld a,(set_blink)
        call yes_no_text
        call st_value
        ld bc,(SET_ROW+10)*256+18
        ld a,(set_bell)
        call yes_no_text
        call st_value
        ld bc,(SET_ROW+14)*256+2
        ld hl,set_init
        ld e,ATTR_FIELD
        ld d,28
        jp pb_field

st_value:
        ld e,ATTR_WIN
        jp ui_text

st_script:
        db SET_ROW+2, 2, ATTR_TITLE, "E",0
        db SET_ROW+2, 4, ATTR_WIN, "Emulation",0
        db SET_ROW+3, 2, ATTR_TITLE, "C",0
        db SET_ROW+3, 4, ATTR_WIN, "Columns",0
        db SET_ROW+4, 2, ATTR_TITLE, "P",0
        db SET_ROW+4, 4, ATTR_WIN, "PicoVideo",0
        db SET_ROW+5, 2, ATTR_TITLE, "I",0
        db SET_ROW+5, 4, ATTR_WIN, "64-col ink",0
        db SET_ROW+6, 2, ATTR_TITLE, "B",0
        db SET_ROW+6, 4, ATTR_WIN, "Backspace",0
        db SET_ROW+7, 2, ATTR_TITLE, "L",0
        db SET_ROW+7, 4, ATTR_WIN, "Local echo",0
        db SET_ROW+8, 2, ATTR_TITLE, "N",0
        db SET_ROW+8, 4, ATTR_WIN, "ENTER sends",0
        db SET_ROW+9, 2, ATTR_TITLE, "F",0
        db SET_ROW+9, 4, ATTR_WIN, "Blink flashes",0
        db SET_ROW+10, 2, ATTR_TITLE, "G",0
        db SET_ROW+10, 4, ATTR_WIN, "Bell",0
        db SET_ROW+12, 2, ATTR_TITLE, "M",0
        db SET_ROW+12, 4, ATTR_WIN, "Modem init string:",0
        db SET_ROW+16, 2, ATTR_TITLE, "S",0
        db SET_ROW+16, 4, ATTR_WIN, "Save",0
        db SET_ROW+16, 14, ATTR_TITLE, "BREAK",0
        db SET_ROW+16, 20, ATTR_WIN, "back",0
        db 0FFh

st_old_emul:    db 0

txt_settings:   db "Settings",0
txt_saved:      db "Saved to picoterm.cfg.",0
txt_not_saved:  db "Couldn't save the settings.",0
txt_cr:         db "CR   ",0
txt_crlf:       db "CR LF",0
ink_names:      db "Black ",0, "Blue  ",0, "Red   ",0, "Magnta",0
                db "Green ",0, "Cyan  ",0, "Yellow",0, "White ",0
