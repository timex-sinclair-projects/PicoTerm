; main.asm - PicoTerm entry point
;
; M4: a terminal on the 8251, with ANSI-BBS (default), VT52 or TTY
; emulation, in 32 or 64 columns, or 80 with PicoVideo (CAPS + 9 cycles). At start-up PicoTerm puts the card's
; modem in Hayes mode (if the ROM is the TS-Pico's), resets the 8251 and
; checks Zimodem answers AT. Then keys go to the modem and received bytes
; go to the TTY emulation. BREAK hangs up if connected and returns to BASIC.

        INCLUDE "mem.inc"

        ORG ORG_ADDR

start:
        call dfile_open             ; moves BASIC and its stack out of DF2
        di
        ld (saved_sp),sp
        exx
        ld (saved_hl2),hl           ; BASIC needs HL' back
        exx
        ld sp,STACK_TOP
        call isr_install
        ei

        xor a
        out (PORT_ULA),a            ; black border
        ld a,07h
        ld (cur_attr),a
        ld a,(set_cols)
        call vid_init
        call term_reset
        ld hl,msg_banner
        call term_puts
        call modem_start

main_loop:
        call kbd_get
        jr z,.rx
        cp K_MENU
        jp z,exit
        cp K_COLS
        jr nz,.key
        call next_cols
        jr .rx
.key:
        call send_key
        call activity
.rx:
        call pump_rx
        jr c,main_loop              ; something arrived: look again at once
        call cursor_blink
        jr main_loop

; next_cols: 32 -> 64 -> 80 -> 32; 80 only with PicoVideo.
next_cols:
        ld a,(vid_mode)
        inc a
        cp VM_80
        jr c,.set
        jr nz,.wrap
        ld b,a
        ld a,(set_picovideo)
        or a
        ld a,b
        jr nz,.set
.wrap:
        xor a
.set:
        jp vid_set_mode

; send_key: key A to the modem, and to the screen too with local echo.
send_key:
        push af
        ld a,(set_echo)
        or a
        call nz,.echo
        pop af
        cp K_ENTER
        jr nz,.notenter
        ld a,0Dh
        jp acia_send
.notenter:
        cp K_BACKSPACE
        jr nz,.notbs
        ld a,(set_backspace)
        jp acia_send
.echo:
        pop hl                      ; the return address
        pop af
        push af
        push hl
        cp K_ENTER
        ld hl,crlf
        jp z,term_puts
        cp K_BACKSPACE
        ld hl,bs_echo
        jp z,term_puts
        cp 80h
        ret nc                      ; arrows: not echoed
        jp term_putc
.notbs:
        cp K_UP
        jr c,.plain
        cp K_RIGHT+1
        ret nc                      ; K_MENU is handled above; nothing else
        sub K_UP
        ld hl,arrow_codes
        add a,l
        ld l,a
        adc a,h
        sub l
        ld h,a
        ld a,1Bh
        call acia_send
        ld a,(set_emul)
        cp EMU_VT52
        ld a,'['
        call nz,acia_send           ; ANSI and TTY: ESC [ A; VT52: ESC A
        ld a,(hl)
.plain:
        jp acia_send

arrow_codes:    db "ABDC"           ; K_UP K_DOWN K_LEFT K_RIGHT

; pump_rx: show up to 32 received bytes. C = at least one arrived.
pump_rx:
        ld b,32
        or a
        push af
.next:
        push bc
        call rx_get
        jr nc,.empty
        call hayes_watch
        call term_putc
        pop bc
        pop af
        scf
        push af
        djnz .next
        jr .out
.empty:
        pop bc
.out:
        pop af
        ret nc
        jr activity_c

; activity: restart the cursor blink, so it shows while things happen.
activity:
        or a
activity_c:
        push af
        ld hl,(ticks)
        ld (blink_base),hl
        pop af
        ret

; cursor_blink: the cursor shows for 32 frames and hides for 32, unless
; the host has hidden it.
cursor_blink:
        ld a,(term_cursor)
        or a
        jp z,vid_cursor_off
        ld hl,(ticks)
        ld de,(blink_base)
        or a
        sbc hl,de
        bit 5,l
        jp z,vid_cursor_on
        jp vid_cursor_off

; modem_start: Hayes mode on the card, reset the 8251, check for Zimodem.
modem_start:
        call pico_present
        jr z,.reset
        ld hl,cmd_modem_hayes
        call pico_cmd
        push af
        call term_fresh_line
        pop af
        cp PS_OK
        jr z,.on
        ld hl,msg_no_tpi_modem
        call term_puts
        jr .reset
.on:
        ld hl,cmd_modem_on
        call pico_cmd
        call term_fresh_line
.reset:
        call acia_init
        ld de,5*50                  ; Zimodem takes about a second to start
        call acia_wait_ready
        jr nc,.ready
        ld hl,msg_no_8251
        jp term_puts
.ready:
        ld hl,cmd_at
        ld de,3*50
        call hayes_command
        cp HR_OK
        jr z,.init
        ld hl,msg_no_answer
        jp term_puts
.init:
        ld hl,set_init
        ld de,3*50
        call hayes_command
        ld a,(set_emul)             ; the terminal type for telnet
        add a,a
        ld hl,termtype_cmds
        call vid_add_a
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld de,3*50
        call hayes_command
        ld hl,msg_ready
        jp term_puts

; pico_print: text from the TS-Pico. Its CRs start new lines.
pico_print:
        cp 0Dh
        jp nz,term_putc
        jp term_fresh_line

; exit: hang up if connected, then restore everything BASIC relies on and
; return to it, USR = 0.
exit:
        ld a,(hayes_online)
        or a
        jr z,.released
        ld hl,msg_hangup
        call term_puts
        call hayes_hangup
.released:
        xor a                       ; wait for BREAK to be let go, or the
        in a,(PORT_ULA)             ; ROM sees it and stops with report D
        cpl
        and 1Fh
        jr nz,.released
        call acia_off
        call vid_cursor_off
        ld a,VM_32                  ; the standard screen for BASIC (no redraw:
        call vid_select             ; it's cleared just below)
        call vid_rows_table
        ld a,(SV_ATTR_P)
        ld (cur_attr),a
        ld de,0+VID_ROWS-1
        call vid_clear_rows
        call isr_remove
        ld a,(SV_BORDCR)
        rrca
        rrca
        rrca
        and 07h
        out (PORT_ULA),a
        exx
        ld hl,(saved_hl2)
        exx
        ld iy,SV_IY
        ld sp,(saved_sp)
        ld bc,0
        ei
        ret

        INCLUDE "hw/isr.asm"
        INCLUDE "hw/scld.asm"
        INCLUDE "hw/kbd.asm"
        INCLUDE "hw/acia.asm"
        INCLUDE "hw/pico.asm"
        INCLUDE "modem/hayes.asm"
        INCLUDE "video/vid.asm"
        INCLUDE "video/vid32.asm"
        INCLUDE "video/vid64.asm"
        INCLUDE "video/vid80.asm"
        INCLUDE "hw/sound.asm"
        INCLUDE "term/term.asm"
        INCLUDE "term/ansi.asm"
        INCLUDE "term/vt52.asm"

; --- settings (the Settings screen and picoterm.cfg come in M5) ----------

set_backspace:  db 08h              ; or 7Fh
set_echo:       db 0                ; 1 = local echo (half duplex)
set_emul:       db EMU_ANSI         ; EMU_TTY, EMU_VT52 or EMU_ANSI
set_blink:      db 1                ; 0 = ANSI blink doesn't FLASH
set_bell:       db 1                ; 0 = BEL is silent
set_cols:       db VM_32            ; VM_32, VM_64 or VM_80 at start-up
set_picovideo:  db 0                ; 1 = PicoVideo is fitted: 80 columns, and
                                    ; colour in 64
set_ink64:      db 7                ; SCLD 64-column ink 0-7 (paper is its
                                    ; complement): 7 = white on black
set_init:       db "ATE1V1X1Q0",0

termtype_cmds:  dw tt_tty, tt_vt52, tt_ansi
tt_tty:         db 'AT&S"41=DUMB"',0
tt_vt52:        db 'AT&S"41=VT52"',0
tt_ansi:        db 'AT&S"41=ANSI"',0

; --- text -----------------------------------------------------------------

msg_banner:     db "PicoTerm M4",13,10
                db "BREAK: hang up, back to BASIC",13,10,10,0
msg_ready:      db "Modem ready.",13,10,0
msg_no_tpi_modem: db "This TS-Pico has no tpi:modem.",13,10,0
msg_no_8251:    db "No modem: the 8251 isn't ready.",13,10,0
msg_no_answer:  db "No answer from the modem.",13,10,0
msg_hangup:     db 13,10,"Hanging up...",13,10,0
bs_echo:        db 08h," ",08h,0
cmd_modem_hayes: db "tpi:modem hayes",0
cmd_modem_on:   db "tpi:modem on",0
cmd_at:         db "AT",0

saved_sp:       dw 0
saved_hl2:      dw 0
blink_base:     dw 0

        ALIGN 256
FONT:                               ; 2 KB, page-aligned
        INCLUDE "video/cp437.asm"

end_of_code:

; --- uninitialised data, not in the binary --------------------------------

RX_RING         equ (end_of_code + 255) & 0FF00h    ; 2 KB, page-aligned
SHADOW_CHR      equ RX_RING + RX_SIZE
SHADOW_ATR      equ SHADOW_CHR + MAX_CELLS
BSS_END         equ SHADOW_ATR + MAX_CELLS

        ASSERT BSS_END <= CODE_LIMIT, "Data runs into the stack"
