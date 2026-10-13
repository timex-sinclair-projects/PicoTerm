; config.asm - picoterm.cfg on the TS-Pico's SD card
;
; A text file in the card's current folder: one "key=value" line per
; setting, then one "phone=" line per phonebook entry:
;
;   phone=name|host:port|telnet|emulation|columns|backspace|echo
;
; Written in text mode through the channel commands (tpi:chopen w, tpi:chwr
; in hex, tpi:chclose; Programmer's Manual chapter 6) and read back with
; tpi:chrd. Unknown keys and bad values are skipped, so an old or
; hand-edited file can't stop PicoTerm starting.

CFG_STREAM      equ 200             ; a channel number BASIC won't be using
CFG_LINE_MAX    equ 127
CFG_CHUNK       equ 100             ; bytes per tpi:chwr: 200 hex digits

; config_save: NC = saved, C = not (no TS-Pico, or the card said no).
config_save:
        call pico_present
        scf
        ret z
        ld a,1
        ld (pico_quiet),a
        ld hl,cmd_cfg_open_w
        call cfg_cmd
        cp PS_OK
        jp nz,.fail
        ld hl,cfg_keys
.setting:
        ld a,(hl)
        or a
        jr z,.phones
        ld de,cfg_line
        call str_copy               ; the key
        inc hl
        ld a,'='
        ld (de),a
        inc de
        ld a,(hl)                   ; the type
        inc hl
        ld c,(hl)
        inc hl
        ld b,(hl)                   ; BC = the setting
        inc hl
        inc hl                      ; past its limit
        push hl
        ld h,b
        ld l,c
        or a
        jr nz,.string
        ld a,(hl)
        call dec_to_buf
        jr .line
.string:
        call str_copy
.line:
        call cfg_end_line
        pop hl
        jr c,.fail
        jr .setting
.phones:
        xor a
        ld (cfg_i),a
.phone:
        ld a,(cfg_i)
        call pb_entry
        push hl
        ld de,PB_USED
        add hl,de
        ld a,(hl)
        pop hl
        or a
        jr z,.nextphone
        ld de,cfg_line
        push hl
        ld hl,txt_phone_eq
        call str_copy
        pop hl
        push hl
        call str_copy               ; the name
        ld a,'|'
        ld (de),a
        inc de
        pop hl
        push hl
        ld bc,PB_HOST
        add hl,bc
        call str_copy
        pop hl
        ld bc,PB_TELNET
        add hl,bc
        ld b,5                      ; telnet, emulation, columns, bs, echo
.field:
        ld a,'|'
        ld (de),a
        inc de
        ld a,(hl)
        inc hl
        push hl
        push bc
        call dec_to_buf
        pop bc
        pop hl
        djnz .field
        call cfg_end_line
        jr c,.fail
.nextphone:
        ld a,(cfg_i)
        inc a
        ld (cfg_i),a
        cp PB_COUNT
        jr c,.phone
        ld hl,cmd_chclose
        call cfg_cmd
        xor a
        ld (pico_quiet),a
        ret                         ; NC
.fail:
        ld hl,cmd_chclose
        call cfg_cmd
        xor a
        ld (pico_quiet),a
        scf
        ret

; cfg_end_line: CR after the line at cfg_line (ending at DE), then write it
; with tpi:chwr. C = the TS-Pico said no.
cfg_end_line:
        ld a,0Dh
        ld (de),a
        inc de
        ex de,hl
        ld de,cfg_line
        or a
        sbc hl,de
        ld b,l                      ; the length (a line is under 256)
        ex de,hl                    ; HL = cfg_line
.chunk:
        ld a,b
        or a
        ret z
        cp CFG_CHUNK
        jr c,.last
        ld a,CFG_CHUNK
.last:
        ld c,a
        push bc
        ld de,CMD_BUF
        push hl
        ld hl,txt_chwr
        call str_copy
        pop hl
        ld b,c
.hex:
        ld a,(hl)
        inc hl
        call hex_to_buf
        djnz .hex
        xor a
        ld (de),a
        push hl
        ld hl,CMD_BUF
        call cfg_cmd
        pop hl
        pop bc
        cp PS_OK
        scf
        ret nz
        ld a,b
        sub c
        ld b,a
        jr .chunk

; cfg_cmd: the command at HL on CFG_STREAM. A = the status.
cfg_cmd:
        push hl
        ld hl,CFG_STREAM
        ld (pico_pmr1),hl
        ld hl,0
        ld (pico_pmr2),hl
        pop hl
        jp pico_cmd_n

; config_load: read picoterm.cfg if there is one. Quietly: nothing is
; drawn, so it can run before the screen is set up.
config_load:
        call pico_present
        ret z
        ld a,1
        ld (pico_quiet),a
        xor a
        ld (cfg_len),a
        ld hl,cmd_cfg_open_r
        call cfg_cmd
        cp PS_OK
        jr nz,.done                 ; no file: the defaults stand
.read:
        ld hl,CFG_STREAM
        ld (pico_pmr1),hl
        ld hl,255
        ld (pico_pmr2),hl
        ld hl,cmd_chrd
        ld de,CFG_READ
        call pico_data
        cp PS_DATA
        jr nz,.close
        ld a,b
        or a
        jr z,.read
        ld hl,CFG_READ
.byte:
        ld a,(hl)
        inc hl
        push hl
        push bc
        call cfg_char
        pop bc
        pop hl
        djnz .byte
        jr .read
.close:
        call cfg_parse              ; a last line with no CR
        ld hl,cmd_chclose
        call cfg_cmd
.done:
        xor a
        ld (pico_quiet),a
        ret

; cfg_char: one byte of the file.
cfg_char:
        cp 0Dh
        jr z,cfg_parse
        cp 0Ah
        jr z,cfg_parse
        ld c,a
        ld a,(cfg_len)
        cp CFG_LINE_MAX
        ret nc
        ld hl,cfg_line
        call vid_add_a
        ld (hl),c
        ld hl,cfg_len
        inc (hl)
        ret

; cfg_parse: act on the line in cfg_line.
cfg_parse:
        ld a,(cfg_len)
        or a
        ret z
        ld hl,cfg_line
        call vid_add_a
        ld (hl),0
        xor a
        ld (cfg_len),a
        ld hl,cfg_line              ; split at "="
.eq:
        ld a,(hl)
        or a
        ret z
        inc hl
        cp '='
        jr nz,.eq
        dec hl
        ld (hl),0
        inc hl
        ld (cfg_value),hl
        ld de,txt_phone
        ld hl,cfg_line
        call str_same
        jr z,cfg_phone
        ld hl,cfg_keys
.key:
        ld a,(hl)
        or a
        ret z                       ; an unknown key
        ld de,cfg_line
        push hl
        call str_same
        pop hl
        push af
.skip:
        ld a,(hl)                   ; past the key
        inc hl
        or a
        jr nz,.skip
        pop af
        jr z,.found
        inc hl                      ; type, address, limit
        inc hl
        inc hl
        inc hl
        jr .key
.found:
        ld a,(hl)                   ; the type
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld b,(hl)                   ; the limit
        ld hl,(cfg_value)
        or a
        jr nz,.string
        push de
        call dec_from
        pop de
        ret c                       ; not a number
        cp b
        ret nc                      ; out of range
        ld (de),a
        ret
.string:
        ld a,(hl)                   ; at most B characters
        ld (de),a
        or a
        ret z
        inc hl
        inc de
        djnz .string
        xor a
        ld (de),a
        ret

; cfg_phone: "name|host|t|e|c|bs|echo" into the first empty entry.
cfg_phone:
        call pb_free
        ret c
        call pb_entry
        ld (cfg_entry),hl
        ex de,hl
        ld hl,(cfg_value)
        ld b,PB_NAME_MAX
        call cfg_field
        ret c
        ld de,(cfg_entry)
        ex de,hl
        ld bc,PB_HOST
        add hl,bc
        ex de,hl
        ld b,PB_HOST_MAX
        call cfg_field
        ret c
        ld de,(cfg_entry)
        ex de,hl
        ld bc,PB_TELNET
        add hl,bc
        ex de,hl
        ld b,5
.num:
        push bc
        push de
        call dec_from
        pop de
        pop bc
        ret c
        ld (de),a
        inc de
        ld a,(hl)
        inc hl
        cp '|'
        jr z,.more
        or a
        jr nz,.bad
        dec b
        jr nz,.bad                  ; ended early
        jr .check
.more:
        djnz .num
.bad:
        ret                         ; too many or too few fields: not used
.check:
        ld hl,(cfg_entry)           ; a host, and sane numbers
        ld bc,PB_HOST
        add hl,bc
        ld a,(hl)
        or a
        ret z
        ld hl,(cfg_entry)
        ld bc,PB_EMUL
        add hl,bc
        ld a,(hl)
        cp 3
        ret nc
        inc hl
        ld a,(hl)
        cp 3
        ret nc
        inc hl
        ld a,(hl)
        cp 08h
        jr z,.ok
        cp 7Fh
        ret nz
.ok:
        ld hl,(cfg_entry)
        ld bc,PB_USED
        add hl,bc
        ld (hl),1
        ret

; cfg_field: copy from HL to DE up to "|", at most B characters; HL ends
; after the "|". C = no "|".
cfg_field:
        ld a,(hl)
        inc hl
        or a
        scf
        ret z
        cp '|'
        jr z,.end
        ld c,a
        ld a,b
        or a
        jr z,cfg_field              ; too long: the rest is dropped
        ld a,c
        ld (de),a
        inc de
        dec b
        jr cfg_field
.end:
        xor a
        ld (de),a
        ret

; str_same: Z if the 0-terminated strings at HL and DE are the same.
str_same:
        ld a,(de)
        cp (hl)
        ret nz
        or a
        ret z
        inc hl
        inc de
        jr str_same

; dec_from: A = the decimal number at HL (HL ends after it). C = no digits
; or over 255.
dec_from:
        ld a,(hl)
        sub '0'
        cp 10
        ccf
        ret c                       ; no digits
        ld c,0
.digit:
        ld a,(hl)
        sub '0'
        cp 10
        jr nc,.done
        ld e,a
        ld a,c
        cp 26
        ccf
        ret c
        add a,a
        ld d,a
        add a,a
        add a,a
        add a,d                     ; x 10
        add a,e
        ret c
        ld c,a
        inc hl
        jr .digit
.done:
        ld a,c
        or a                        ; NC
        ret

; dec_to_buf: A in decimal at DE (DE ends after it).
dec_to_buf:
        ld c,0                      ; 1 once a digit has been written
        ld b,100
        call .digit
        ld b,10
        call .digit
        add a,'0'
        ld (de),a
        inc de
        ret
.digit:
        ld h,'0'-1
.count:
        inc h
        sub b
        jr nc,.count
        add a,b
        ld l,a
        ld a,h
        cp '0'
        jr nz,.put
        ld a,c
        or a
        ld a,l
        ret z
        ld a,'0'
.put:
        ld (de),a
        inc de
        ld c,1
        ld a,l
        ret

; hex_to_buf: A as two hex digits at DE.
hex_to_buf:
        push af
        rrca
        rrca
        rrca
        rrca
        call .nib
        pop af
.nib:
        and 0Fh
        add a,'0'
        cp '9'+1
        jr c,.put
        add a,'a'-'9'-1
.put:
        ld (de),a
        inc de
        ret

; The settings in the file: key, 0, type (0 a number, 1 a string), the
; setting's address, then the limit (numbers: below this; strings: at most
; this many characters).
cfg_keys:
        db "emul",0, 0 : dw set_emul : db 3
        db "cols",0, 0 : dw set_cols : db 3
        db "picovideo",0, 0 : dw set_picovideo : db 2
        db "ink64",0, 0 : dw set_ink64 : db 8
        db "bs",0, 0 : dw set_backspace : db 128
        db "echo",0, 0 : dw set_echo : db 2
        db "enter",0, 0 : dw set_enter : db 2
        db "blink",0, 0 : dw set_blink : db 2
        db "bell",0, 0 : dw set_bell : db 2
        db "init",0, 1 : dw set_init : db INIT_MAX
        db 0

cmd_cfg_open_w: db "tpi:chopen w picoterm.cfg",0
cmd_cfg_open_r: db "tpi:chopen r picoterm.cfg",0
cmd_chrd:       db "tpi:chrd",0
cmd_chclose:    db "tpi:chclose",0
txt_chwr:       db "tpi:chwr ",0
txt_phone:      db "phone",0
txt_phone_eq:   db "phone=",0

cfg_i:          db 0
cfg_len:        db 0
cfg_value:      dw 0
cfg_entry:      dw 0
