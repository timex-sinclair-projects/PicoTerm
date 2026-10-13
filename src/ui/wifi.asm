; wifi.asm - choosing and joining a WiFi network through Zimodem
;
; ATW lists the networks Zimodem can see, one a line: the SSID, " (RSSI)",
; then "*" if it's encrypted (Zimodem's doWiFiCommand). PicoTerm keeps the
; text before the last " (" as the SSID. Joining is ATW"ssid,password";
; AT&W makes it Zimodem's default. Zimodem has no way to quote a comma or
; a double quote inside either, so those can't be used.

WIFI_MAX        equ 16              ; networks listed
WIFI_SSID_MAX   equ 32
WIFI_ENTRY      equ WIFI_SSID_MAX+1
WIFI_ROW        equ 1

wifi_run:
        ld a,(hayes_online)
        or a
        jr z,.scan
        ld hl,txt_hang_up_first
        jp ui_message
.scan:
        xor a
        ld (wifi_sel),a
        ld b,WIFI_ROW
        ld d,22
        ld hl,txt_wifi
        call ui_box
        ld hl,txt_scanning
        ld bc,(WIFI_ROW+2)*256+2
        ld e,ATTR_WIN
        call ui_text
        ld hl,cmd_atw
        ld de,15*50
        call wifi_ask
        call wifi_parse
.draw:
        call wifi_draw
.key:
        call ui_getkey
        call ui_is_back
        ret z
        cp K_UP
        jr z,.up
        cp K_DOWN
        jr z,.down
        cp 'R'
        jr z,.scan
        cp 'M'
        jr z,.manual
        cp K_ENTER
        jr nz,.key
        ld a,(wifi_count)
        or a
        jr z,.key
        ld a,(wifi_sel)
        call wifi_entry
        ld de,wifi_ssid
        ld bc,WIFI_ENTRY
        ldir
        jr .join
.up:
        ld a,(wifi_sel)
        or a
        jr z,.key
        dec a
        jr .move
.down:
        ld a,(wifi_count)
        dec a
        ld hl,wifi_sel
        cp (hl)
        jr c,.key
        jr z,.key
        ld a,(hl)
        inc a
.move:                              ; redraw just the two rows
        ld hl,wifi_sel
        ld b,(hl)
        ld (hl),a
        push af
        ld a,b
        call wifi_draw_row
        pop af
        call wifi_draw_row
        jr .key
.manual:
        xor a
        ld (wifi_ssid),a
        ld hl,txt_ssid
        call wifi_prompt
        ld hl,wifi_ssid
        ld de,WIFI_SSID_MAX*256+28
        call ui_input
        jr c,.draw
        ld a,(wifi_ssid)
        or a
        jr z,.draw
.join:
        xor a
        ld (wifi_pass),a
        ld hl,txt_password
        call wifi_prompt
        ld a,1
        ld (ui_mask),a
        ld hl,wifi_pass
        ld de,WIFI_PASS_MAX*256+28
        call ui_input
        ld a,0
        ld (ui_mask),a
        jp c,.draw
        ; ATW"ssid,password"
        ld de,wifi_cmd
        ld hl,txt_atw_q
        call str_copy
        ld hl,wifi_ssid
        call str_copy
        ld a,','
        ld (de),a
        inc de
        ld hl,wifi_pass
        call str_copy
        ld a,'"'
        ld (de),a
        inc de
        xor a
        ld (de),a
        ld hl,txt_joining
        call wifi_prompt
        ld hl,wifi_cmd
        ld de,20*50
        call wifi_ask
        cp HR_OK
        jr z,.joined
        ld hl,txt_join_failed
        call ui_message
        jp .draw
.joined:
        ld hl,txt_save_wifi
        call ui_yes_no
        jp nz,.draw
        ld hl,cmd_at_w
        ld de,5*50
        call wifi_ask
        ld hl,txt_wifi_saved
        cp HR_OK
        jr z,.done
        ld hl,txt_not_saved
.done:
        call ui_message
        jp .draw

; wifi_prompt: the text at HL on row 20 of the window, with the field row
; under it cleared; BC = where the field goes.
wifi_prompt:
        push hl
        ld b,WIFI_ROW+19
        call ui_line
        ld b,WIFI_ROW+20
        call ui_line
        pop hl
        ld bc,(WIFI_ROW+19)*256+2
        ld e,ATTR_TITLE
        call ui_text
        ld bc,(WIFI_ROW+20)*256+2
        ret

; wifi_ask: send the command at HL with the replies captured (out of
; sight), and wait up to DE ticks. A = the result code.
wifi_ask:
        push de
        push hl
        call capture_reset
        ld a,RX_CAPTURE
        ld (rx_mode),a
        pop hl
        pop de
        call hayes_command
        push af
        ld a,RX_HOLD
        ld (rx_mode),a
        pop af
        ret

; wifi_parse: networks from the capture buffer into wifi_list.
wifi_parse:
        xor a
        ld (wifi_count),a
        ld hl,CAPTURE
        ld bc,(capture_len)
.line:
        ld a,b
        or c
        ret z
        ld de,wifi_line             ; one line, up to 63 characters
        ld a,0
        ld (wifi_len),a
.char:
        ld a,b
        or c
        jr z,.end
        ld a,(hl)
        inc hl
        dec bc
        cp 0Dh
        jr z,.end
        cp 0Ah
        jr z,.end
        push af
        ld a,(wifi_len)
        cp 63
        jr nc,.long
        inc a
        ld (wifi_len),a
        pop af
        ld (de),a
        inc de
        jr .char
.long:
        pop af
        jr .char
.end:
        xor a
        ld (de),a
        push hl
        push bc
        call wifi_take
        pop bc
        pop hl
        ld a,(wifi_count)
        cp WIFI_MAX
        ret nc
        jr .line

; wifi_take: if wifi_line has " (", keep what's before the last one.
wifi_take:
        ld a,(wifi_len)
        or a
        ret z
        ld hl,wifi_line
        ld de,0                     ; the last " (" found
.find:
        ld a,(hl)
        or a
        jr z,.found
        cp ' '
        jr nz,.next
        inc hl
        ld a,(hl)
        dec hl
        cp '('
        jr nz,.next
        ld d,h
        ld e,l
.next:
        inc hl
        jr .find
.found:
        ld a,d
        or e
        ret z                       ; not a network line
        xor a
        ld (de),a                   ; end the SSID there
        ld hl,wifi_line
        ld a,(hl)
        or a
        ret z                       ; a hidden network: no name to show
        ld a,(wifi_count)
        call wifi_entry
        ex de,hl                    ; DE = the slot
        ld hl,wifi_line
        ld b,WIFI_SSID_MAX
.copy:
        ld a,(hl)
        ld (de),a
        or a
        jr z,.copied
        inc hl
        inc de
        djnz .copy
        xor a
        ld (de),a
.copied:
        ld hl,wifi_count
        inc (hl)
        ret

; wifi_entry: HL = list entry A.
wifi_entry:
        ld l,a
        ld h,0
        ld e,l
        ld d,h
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl                   ; x 32
        add hl,de                   ; x 33
        ld de,wifi_list
        add hl,de
        ret

wifi_draw:
        ld b,WIFI_ROW
        ld d,22
        ld hl,txt_wifi
        call ui_box
        ld hl,wifi_script
        call ui_script
        ld a,(wifi_count)
        or a
        jr nz,.list
        ld hl,txt_no_networks
        ld bc,(WIFI_ROW+2)*256+2
        ld e,ATTR_WIN
        jp ui_text
.list:
        xor a
.entry:
        push af
        call wifi_draw_row
        pop af
        inc a
        ld hl,wifi_count
        cp (hl)
        jr c,.entry
        ret

; wifi_draw_row: network A's row in the list.
wifi_draw_row:
        ld (wifi_i),a
        add a,WIFI_ROW+1
        ld b,a
        ld c,2
        ld e,ATTR_WIN
        ld a,(wifi_i)
        ld hl,wifi_sel
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
        ld a,(wifi_i)
        call wifi_entry
        pop de
        ld d,26
        jp pb_field

wifi_script:
        db WIFI_ROW+18, 2, ATTR_TITLE, "ENTER",0
        db WIFI_ROW+18, 8, ATTR_WIN, "join",0
        db WIFI_ROW+18, 14, ATTR_TITLE, "M",0
        db WIFI_ROW+18, 16, ATTR_WIN, "other",0
        db WIFI_ROW+18, 23, ATTR_TITLE, "R",0
        db WIFI_ROW+18, 25, ATTR_WIN, "rescan",0
        db WIFI_ROW+20, 2, ATTR_TITLE, "BREAK",0
        db WIFI_ROW+20, 8, ATTR_WIN, "back",0
        db 0FFh

WIFI_PASS_MAX   equ 63

wifi_sel:       db 0
wifi_i:         db 0
wifi_count:     db 0
wifi_len:       db 0

cmd_atw:        db "ATW",0
cmd_at_w:       db "AT&W",0
txt_atw_q:      db 'ATW"',0
txt_wifi:       db "WiFi",0
txt_scanning:   db "Scanning...",0
txt_no_networks: db "No networks found.",0
txt_ssid:       db "Network name (SSID):",0
txt_password:   db "Password:",0
txt_joining:    db "Joining...",0
txt_join_failed: db "Couldn't join that network.",0
txt_save_wifi:  db "Joined. Make it default? Y/N",0
txt_wifi_saved: db "Saved in the modem.",0
