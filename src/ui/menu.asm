; menu.asm - the PicoTerm menu (BREAK in the terminal)

; menu_run: NC = back to the terminal, C = quit to BASIC.
menu_run:
        call ui_open
.draw:
        call menu_draw
.key:
        call ui_getkey
        call ui_is_back
        jr z,.back
        cp 'D'
        jr z,.dial
        cp 'H'
        jr z,.hangup
        cp 'W'
        jr z,.wifi
        cp 'S'
        jr z,.settings
        cp 'X'
        jr z,.download
        cp 'C'
        jr z,.clear
        cp 'Q'
        jr z,.quit
        jr .key
.dial:
        call pb_run
        jr nc,.again                ; back from the phonebook
        or a                        ; dialling: the terminal shows the rest
        ret
.wifi:
        call wifi_run
        jr .again
.settings:
        call settings_run
        jr .again
.download:
        call dl_run
.again:
        call vid_redraw             ; the terminal again, under the menu
        jr .draw
.hangup:
        call ui_close
        ld a,(hayes_online)
        or a
        ret z
        ld hl,msg_hangup
        call term_puts
        call hayes_hangup
        or a
        ret
.clear:
        call ui_close
        call term_full_reset
        or a
        ret
.back:
        call ui_close
        or a
        ret
.quit:
        xor a
        ld (rx_mode),a              ; exit's hang-up needs to see the replies
        scf
        ret

menu_draw:
        ld b,3
        ld d,13
        ld hl,txt_picoterm
        call ui_box
        ld hl,menu_script
        call ui_script
        ; the status line: online or not, emulation, columns
        ld b,4
        ld c,2
        ld e,ATTR_WIN
        ld hl,txt_offline
        ld a,(hayes_online)
        or a
        jr z,.state
        ld hl,txt_online
.state:
        call ui_text
        inc c
        ld a,(set_emul)
        ld hl,emul_names
        call ui_pick
        ld e,ATTR_WIN
        call ui_text
        inc c
        ld a,(vid_mode)
        ld hl,cols_names
        call ui_pick
        ld e,ATTR_WIN
        call ui_text
        ld hl,txt_cols
        jp ui_text

menu_script:
        db 6, 2, ATTR_TITLE, "D",0
        db 6, 5, ATTR_WIN, "Dial (phonebook)",0
        db 7, 2, ATTR_TITLE, "H",0
        db 7, 5, ATTR_WIN, "Hang up",0
        db 8, 2, ATTR_TITLE, "W",0
        db 8, 5, ATTR_WIN, "WiFi",0
        db 9, 2, ATTR_TITLE, "S",0
        db 9, 5, ATTR_WIN, "Settings",0
        db 10, 2, ATTR_TITLE, "X",0
        db 10, 5, ATTR_WIN, "Download (XMODEM)",0
        db 11, 2, ATTR_TITLE, "C",0
        db 11, 5, ATTR_WIN, "Clear the screen",0
        db 12, 2, ATTR_TITLE, "Q",0
        db 12, 5, ATTR_WIN, "Quit to BASIC",0
        db 14, 2, ATTR_WIN, "BREAK: back to the terminal",0
        db 0FFh

txt_picoterm:   db "PicoTerm",0
txt_offline:    db "Offline",0
txt_online:     db "Online ",0
txt_cols:       db " columns",0
emul_names:     db "TTY",0,0, "VT52",0, "ANSI",0
cols_names:     db "32",0,0,0, "64",0,0,0, "80",0,0,0
