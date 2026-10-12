; main.asm - PicoTerm entry point
;
; M1: take over the machine (DF2 opened, own stack, IM2), then run a local
; "typewriter": keys go through the key map and straight into the TTY
; emulation. BREAK (CAPS SHIFT + SPACE) gives the machine back to BASIC.

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
        call font_init              ; copies the ROM font through CHARS
        call isr_install
        ei

        xor a
        out (PORT_ULA),a            ; black border
        ld a,07h
        ld (cur_attr),a
        call vid_init
        call term_reset
        ld hl,msg_banner
        call term_puts

main_loop:
        call kbd_get
        jr z,.idle
        cp K_MENU
        jr z,exit
        call local_key
        ld hl,(ticks)
        ld (blink_base),hl
        jr main_loop
.idle:
        call cursor_blink
        jr main_loop

; local_key: the typewriter: show key A as the far end would echo it.
local_key:
        cp K_ENTER
        jr nz,.notenter
        ld a,0Dh
        call term_putc
        ld a,0Ah
        jp term_putc
.notenter:
        cp K_BACKSPACE
        jr nz,.notbs
        ld hl,bs_echo
        jp term_puts
.notbs:
        cp 80h
        ret nc                      ; arrows: sent to the modem from M2 on
        jp term_putc

; cursor_blink: the cursor shows for 32 frames and hides for 32, starting
; shown whenever something was typed.
cursor_blink:
        ld hl,(ticks)
        ld de,(blink_base)
        or a
        sbc hl,de
        bit 5,l
        jp z,vid_cursor_on
        jp vid_cursor_off

; exit: restore everything BASIC relies on and return to it, USR = 0.
exit:
        xor a                       ; wait for BREAK to be let go, or the
        in a,(PORT_ULA)             ; ROM sees it and stops with report D
        cpl
        and 1Fh
        jr nz,exit
        call vid_cursor_off
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
        INCLUDE "video/font.asm"
        INCLUDE "video/vid.asm"
        INCLUDE "video/vid32.asm"
        INCLUDE "term/tty.asm"

msg_banner:     db "PicoTerm M1 - local typewriter",13,10
                db "BREAK returns to BASIC",13,10,10,0
bs_echo:        db 08h," ",08h,0

saved_sp:       dw 0
saved_hl2:      dw 0
blink_base:     dw 0

end_of_code:

; --- uninitialised data, not in the binary --------------------------------

FONT            equ (end_of_code + 255) & 0FF00h    ; 2 KB, page-aligned
SHADOW_CHR      equ FONT + 2048
SHADOW_ATR      equ SHADOW_CHR + MAX_CELLS
BSS_END         equ SHADOW_ATR + MAX_CELLS

        ASSERT BSS_END <= CODE_LIMIT, "Data runs into the stack"
