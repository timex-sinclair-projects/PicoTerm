; isr.asm - IM2 interrupt setup and the 50/60 Hz tick
;
; The ROM's IM1 routine is not used while PicoTerm runs. The vector table is
; 257 bytes of the same value, so whatever the data bus holds during the
; interrupt acknowledge, the CPU jumps to IM2_HANDLER.

; isr_install: build the table and switch to IM2. Call with interrupts off.
isr_install:
        ld a,i
        ld (isr_saved_i),a
        ld hl,IM2_TABLE
        ld de,IM2_TABLE+1
        ld bc,256
        ld (hl),IM2_VEC
        ldir
        ld a,0C3h                   ; JP isr
        ld (IM2_HANDLER),a
        ld hl,isr
        ld (IM2_HANDLER+1),hl
        ld a,high IM2_TABLE
        ld i,a
        im 2
        ret

; isr_remove: back to the ROM's IM1. Leaves interrupts off.
isr_remove:
        di
        ld a,(isr_saved_i)
        ld i,a
        im 1
        ret

isr:
        push af
        push bc
        push de
        push hl
        ld hl,(ticks)
        inc hl
        ld (ticks),hl
        call kbd_scan
        call acia_drain
        call bell_tick
        pop hl
        pop de
        pop bc
        pop af
        ei
        reti

ticks:          dw 0                ; frames since start-up
isr_saved_i:    db 0
