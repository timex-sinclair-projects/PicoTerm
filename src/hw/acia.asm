; acia.asm - the 8251 at $73/$77: set-up, sending, and the receive ring
;
; A status of FFh is taken as "no 8251": with no card the bus floats high,
; and a real 8251 never shows SYNDET with every error bit and both ready
; bits at once.
;
; The ISR drains the receiver into a 2 KB ring (RX_RING, page-aligned);
; the main loop takes bytes out with rx_get. Only the ISR reads $73. When
; the ring is full the ISR stops reading, the card's own ring fills, and the
; card XOFFs Zimodem: back-pressure without PicoTerm sending XON/XOFF.
; (docs/DESIGN.md sections 2 and 4.)

ACIA_DATA       equ 73h
ACIA_CTRL       equ 77h             ; OUT: mode, then commands; IN: status

ACIA_MODE       equ 4Fh             ; x64, 8 bits, no parity, 1 stop
ACIA_RUN        equ 37h             ; TxEN DTR RxE ER RTS: also the error reset
ACIA_IDLE       equ 15h             ; TxEN RxE ER, DTR and RTS off (MTERM's)

ST_TXRDY        equ 0
ST_RXRDY        equ 1
ST_ERRORS       equ 38h             ; PE OE FE

RX_SIZE         equ 2048
RX_MASK         equ RX_SIZE-1
RX_PER_TICK     equ 64              ; most bytes one interrupt takes

TX_TIMEOUT      equ 50              ; ticks: 1 s at 50 Hz

; acia_init: reset the 8251 the datasheet's way and set it running.
; Interrupts may be on: only the ISR reads the 8251, and it waits for
; acia_on.
acia_init:
        xor a
        ld (acia_on),a
        ld hl,0
        ld (rx_head),hl
        ld (rx_tail),hl
        ld hl,acia_setup
        ld b,acia_setup_len
.out:
        ld a,(hl)
        out (ACIA_CTRL),a
        inc hl
        ex (sp),hl                  ; recovery time between control writes
        ex (sp),hl
        djnz .out
        ld a,1
        ld (acia_ok),a
        ld (acia_on),a
        ret

acia_setup:     db 00h, 00h, 00h, 40h, ACIA_MODE, ACIA_RUN
acia_setup_len  equ $-acia_setup

; acia_off: stop receiving and leave the 8251 idle, DTR and RTS off.
acia_off:
        xor a
        ld (acia_on),a
        ld a,ACIA_IDLE
        out (ACIA_CTRL),a
        ret

; acia_wait_ready: wait up to DE ticks for TxRDY (DE = 0: look once).
; NC = ready, C = not. Uses AF, HL.
acia_wait_ready:
        ld hl,(ticks)
        ld (acia_t0),hl
.poll:
        in a,(ACIA_CTRL)
        cp 0FFh                     ; a floating bus: no 8251 there
        jr z,.busy
        bit ST_TXRDY,a
        jr z,.busy
        or a
        ret
.busy:
        push de
        ld hl,(ticks)
        ld de,(acia_t0)
        or a
        sbc hl,de                   ; HL = ticks waited
        pop de
        or a
        sbc hl,de                   ; carry while that's under the limit
        jr c,.poll
        scf
        ret

; acia_send: send A. Waits for TxRDY up to TX_TIMEOUT ticks; once a wait
; has failed, later sends only try once, until the 8251 is ready again, so
; a missing modem can't make every key take a second.
; NC = sent, C = dropped. Keeps BC, DE, HL.
acia_send:
        push hl
        push de
        push af
        ld de,TX_TIMEOUT
        ld a,(acia_ok)
        or a
        jr nz,.wait
        ld de,0
.wait:
        call acia_wait_ready
        jr c,.fail
        pop af
        out (ACIA_DATA),a
        ld a,1
        ld (acia_ok),a
        pop de
        pop hl
        or a
        ret
.fail:
        xor a
        ld (acia_ok),a
        pop af
        pop de
        pop hl
        scf
        ret

; acia_drain: from the ISR. Moves waiting bytes into the ring. Uses AF,
; BC, DE, HL.
acia_drain:
        ld a,(acia_on)
        or a
        ret z
        ld b,RX_PER_TICK
.next:
        in a,(ACIA_CTRL)
        cp 0FFh                     ; a floating bus: no 8251 there
        ret z
        bit ST_RXRDY,a
        ret z
        and ST_ERRORS
        jr z,.room
        ld a,ACIA_RUN               ; ER clears PE, OE and FE
        out (ACIA_CTRL),a
        ld hl,acia_errors
        inc (hl)
.room:
        ld hl,(rx_head)
        ld d,h
        ld e,l
        inc hl
        ld a,h
        and high RX_MASK
        ld h,a                      ; HL = the head after this byte
        push hl
        ld hl,(rx_tail)
        or a
        sbc hl,de
        dec hl                      ; tail - head - 1 = free space, mod size
        ld a,h
        and high RX_MASK
        or l
        pop hl
        ret z                       ; full: leave the byte in the 8251
        ld (rx_head),hl
        ld hl,RX_RING
        add hl,de
        in a,(ACIA_DATA)
        ld (hl),a
        djnz .next
        ret

; rx_get: C and A = the next received byte, or NC if there is none.
; Uses AF, DE, HL.
rx_get:
        ld hl,(rx_tail)
        ld de,(rx_head)             ; one instruction: the ISR can't split it
        or a
        sbc hl,de
        ret z                       ; empty (and NC)
        ld hl,(rx_tail)
        ld d,h
        ld e,l
        inc hl
        ld a,h
        and high RX_MASK
        ld h,a
        ld (rx_tail),hl
        ld hl,RX_RING
        add hl,de
        ld a,(hl)
        scf
        ret

; --- state ----------------------------------------------------------------

acia_on:        db 0                ; 1 = the ISR drains the receiver
acia_ok:        db 0                ; 0 = the last send timed out
acia_errors:    db 0                ; PE/OE/FE seen (wraps)
acia_t0:        dw 0
rx_head:        dw 0                ; written only by the ISR
rx_tail:        dw 0                ; written only by rx_get
