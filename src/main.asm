; main.asm - PicoTerm entry point
;
; M0: take over the machine (own stack, IM2), show a banner and some
; start-up facts, count interrupts until a key is pressed, then give the
; machine back to BASIC as it was.

        INCLUDE "mem.inc"

        ORG ORG_ADDR

start:
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
        call vid32_cls

        ld hl,msg_banner
        call vid32_puts

        ld hl,msg_rom
        call vid32_puts
        ld a,(ROM_VERSION)
        call vid32_hex8

        ; BASIC lives inside DF2 on the 2068 (CHANS is about 6840h), so
        ; 64-column mode has to save DF2..STKEND and put it back on exit.
        ld hl,msg_df2
        call vid32_puts
        ld hl,(SV_STKEND)
        ld de,DF2
        or a
        sbc hl,de
        jr nc,.df2
        ld hl,0
.df2:
        call vid32_hex16
        ld hl,msg_bytes
        call vid32_puts

        ld hl,msg_ticks
        call vid32_puts

        call wait_no_key
.loop:
        ld bc,TICKS_POS
        call vid32_at
        ld hl,(ticks)
        call vid32_hex16
        call any_key
        jr z,.loop

        call wait_no_key
        ; fall through

; exit: restore everything BASIC relies on and return to it, USR = 0.
exit:
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

; any_key: NZ if any key is down.
any_key:
        xor a                       ; all half-rows
        in a,(PORT_ULA)
        cpl
        and 1Fh
        ret

wait_no_key:
        call any_key
        jr nz,wait_no_key
        ret

        INCLUDE "hw/isr.asm"
        INCLUDE "video/vid32.asm"

TICKS_POS       equ 070Ch           ; row 7, column 12: after "Interrupts: "

msg_banner:     db "PicoTerm M0",13
                db "TS-2068 terminal for TS-Pico",13,13,0
msg_rom:        db "ROM byte 0065h: ",0
msg_df2:        db 13,"BASIC in DF2: ",0
msg_bytes:      db "h bytes",13,13,0
msg_ticks:      db 13,"Interrupts: ",13,13
                db "Press a key to return to BASIC",0

saved_sp:       dw 0
saved_hl2:      dw 0

end_of_code:
        ASSERT end_of_code <= STACK_TOP - 256, "Code runs into the stack"
