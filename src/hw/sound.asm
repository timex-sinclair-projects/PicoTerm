; sound.asm - the bell, on the 2068's AY-3-8912 (ports F5h/F6h)
;
; BEL starts a 1 kHz tone on channel A and the ISR stops it BELL_TICKS
; later, so the terminal never waits for it. The AY's clock is 1.76 MHz
; (half the CPU's): period 110 gives 1764000 / (16 x 110) = 1002 Hz.
; Register 7's bits 6-7 stay 0: the AY's I/O ports are inputs (joysticks).

AY_SELECT       equ 0F5h
AY_DATA         equ 0F6h

BELL_PERIOD     equ 110
BELL_TICKS      equ 6               ; about a tenth of a second

; bell_start: start the tone. Keeps BC, DE, HL.
bell_start:
        ld a,(set_bell)
        or a
        ret z
        push hl
        di                          ; the ISR writes the AY too
        ld hl,bell_regs
.reg:
        ld a,(hl)
        cp 0FFh
        jr z,.done
        out (AY_SELECT),a
        inc hl
        ld a,(hl)
        out (AY_DATA),a
        inc hl
        jr .reg
.done:
        ld a,BELL_TICKS
        ld (bell_left),a
        ei
        pop hl
        ret

bell_regs:
        db 0, BELL_PERIOD           ; channel A period, fine
        db 1, 0                     ; coarse
        db 7, 3Eh                   ; mixer: tone A only
        db 8, 0Fh                   ; channel A volume: full
        db 0FFh

; bell_tick: from the ISR. Uses AF.
bell_tick:
        ld a,(bell_left)
        or a
        ret z
        dec a
        ld (bell_left),a
        ret nz
        ld a,8
        out (AY_SELECT),a
        xor a
        out (AY_DATA),a             ; volume 0
        ret

bell_left:      db 0
