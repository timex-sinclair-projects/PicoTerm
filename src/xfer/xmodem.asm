; xmodem.asm - receiving a file with XMODEM (CRC, 1K and checksum)
;
; The receiver asks for CRC mode with "C" (three tries, 3 s apart), then
; falls back to NAK and the 8-bit checksum. Blocks are SOH (128 bytes) or
; STX (1024). A good block is ACKed and kept; a repeat of the last one is
; ACKed and dropped; a bad one is NAKed once the line has gone quiet (NAK,
; not C, even before the first good block: a sender that has begun ignores
; C). Ten
; errors in a row, CAN CAN from the sender, BREAK, or a block out of
; sequence end the transfer (BREAK and out-of-sequence send CAN x 5). EOT
; is ACKed. (docs/DESIGN.md section 9.)
;
; Bytes come straight from the receive ring (rx_get) with rx_mode at
; RX_HOLD, so nothing else takes them. The file goes to XFER_BUF, at most
; XFER_MAX bytes; a longer one is cancelled.

SOH             equ 01h
STX             equ 02h
EOT             equ 04h
ACK             equ 06h
NAK             equ 15h
CAN             equ 18h

XM_OK           equ 0               ; xm_receive's results
XM_CANCELLED    equ 1               ; by the sender
XM_BREAK        equ 2               ; by the user
XM_TOO_BIG      equ 3
XM_ERRORS       equ 4               ; too many errors, or out of sequence
XM_NO_START     equ 5               ; the sender never began

XM_TRIES        equ 10
XM_BYTE_TICKS   equ 50              ; 1 s for a byte inside a block
XM_BLOCK_TICKS  equ 500             ; 10 s for a block to begin
XM_START_TICKS  equ 150             ; 3 s between C (or NAK) at the start

; xm_receive: A = a result; xm_length = the bytes received (padding
; included). xm_progress is called after every block.
xm_receive:
        ld hl,0
        ld (xm_length),hl
        ld (xm_blocks),hl
        ld (xm_total_errors),hl
        ld a,1
        ld (xm_expect),a
        xor a
        ld (xm_errors),a
        ; the start: C three times, then NAK
        ld a,'C'
        ld (xm_start),a
        ld a,1
        ld (xm_crc),a
        ld b,XM_TRIES
.start:
        push bc
        ld a,b
        cp XM_TRIES-3+1
        jr nc,.ask
        ld a,NAK                    ; three Cs got nothing: checksums
        ld (xm_start),a
        xor a
        ld (xm_crc),a
.ask:
        ld a,(xm_start)
        call acia_send
        ld de,XM_START_TICKS
        call xm_get
        pop bc
        jr c,.first
        ld a,(xm_break)
        or a
        jp nz,xm_cancel_break
        djnz .start
        ld a,XM_NO_START
        ret
.first:
        jr .header
; each block
.next:
        ld de,XM_BLOCK_TICKS
        call xm_get
        jr c,.header
        ld a,(xm_break)
        or a
        jp nz,xm_cancel_break
        jp .error                   ; nothing came: NAK
.header:
        cp SOH
        ld hl,128
        jr z,.block
        cp STX
        ld hl,1024
        jr z,.block
        cp EOT
        jr z,.eot
        cp CAN
        jr z,.can
        jr .next                    ; noise between blocks
.can:
        ld de,XM_BYTE_TICKS         ; a second CAN means it
        call xm_get
        jr nc,.next
        cp CAN
        jr nz,.next
        ld a,XM_CANCELLED
        ret
.eot:
        ld a,ACK
        call acia_send
        ld a,XM_OK
        ret
.block:
        ld (xm_size),hl
        call xm_get_byte            ; the block number
        jp nc,.error
        ld (xm_num),a
        call xm_get_byte            ; and its complement
        jp nc,.error
        ld hl,xm_num
        add a,(hl)
        inc a
        jp nz,.error                ; they don't match
        ; the data, into BLOCK_BUF
        ld hl,BLOCK_BUF
        ld bc,(xm_size)
.data:
        push bc
        push hl
        call xm_get_byte
        pop hl
        pop bc
        jp nc,.error
        ld (hl),a
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,.data
        ; the check: a CRC (high byte first) or a checksum
        ld a,(xm_crc)
        or a
        jr z,.sum
        call xm_get_byte
        jr nc,.error
        ld (xm_check+1),a
        call xm_get_byte
        jr nc,.error
        ld (xm_check),a
        call xm_block_crc           ; HL = the CRC of BLOCK_BUF
        ld de,(xm_check)
        or a
        sbc hl,de
        jr nz,.error
        jr .checked
.sum:
        call xm_get_byte
        jr nc,.error
        ld c,a
        call xm_block_sum
        cp c
        jr nz,.error
.checked:
        ld a,(xm_expect)
        ld b,a
        ld a,(xm_num)
        cp b
        jr z,.good
        inc a
        cp b
        jp nz,xm_cancel_sequence    ; not this one, not the last one
        ld a,ACK                    ; the last one again: our ACK was lost
        call acia_send
        jp .next
.good:
        ; keep it, if it fits
        ld hl,(xm_length)
        ld bc,(xm_size)
        add hl,bc
        ld de,XFER_MAX+1
        or a
        sbc hl,de
        jr nc,xm_cancel_big
        ld de,(xm_length)
        ld hl,XFER_BUF
        add hl,de
        ex de,hl
        ld hl,BLOCK_BUF
        ldir
        ld hl,(xm_length)
        ld bc,(xm_size)
        add hl,bc
        ld (xm_length),hl
        ld hl,(xm_blocks)
        inc hl
        ld (xm_blocks),hl
        ld hl,xm_expect
        inc (hl)
        xor a
        ld (xm_errors),a
        ld a,ACK
        call acia_send
        call xm_progress
        jp .next
.error:
        ld a,(xm_break)
        or a
        jr nz,xm_cancel_break
        ld hl,(xm_total_errors)
        inc hl
        ld (xm_total_errors),hl
        ld hl,xm_errors
        inc (hl)
        ld a,(hl)
        cp XM_TRIES
        jr nc,xm_cancel_errors
        call xm_purge
        ld a,NAK                    ; the sender has started: NAK asks again
        call acia_send
        call xm_progress
        jp .next

xm_cancel_break:
        ld b,XM_BREAK
        jr xm_cancel
xm_cancel_big:
        ld b,XM_TOO_BIG
        jr xm_cancel
xm_cancel_sequence:
xm_cancel_errors:
        ld b,XM_ERRORS
xm_cancel:
        push bc
        ld b,5
.can:
        ld a,CAN
        call acia_send
        djnz .can
        call xm_purge
        pop bc
        ld a,b
        ret

; xm_get_byte: a byte within a block: C and A, or NC after 1 s (or BREAK).
xm_get_byte:
        ld de,XM_BYTE_TICKS
        ; fall through

; xm_get: wait up to DE ticks for a byte: C and A = the byte; NC on a
; timeout, or with xm_break set if BREAK was pressed.
xm_get:
        xor a
        ld (xm_break),a
        ld hl,(ticks)
        ld (xm_t0),hl
.poll:
        push de
        call rx_get
        pop de
        ret c
        push de
        call kbd_get
        pop de
        jr z,.time
        cp K_MENU
        jr nz,.time
        ld a,1
        ld (xm_break),a
        or a                        ; NC
        ret
.time:
        ld hl,(ticks)
        push de
        ld de,(xm_t0)
        or a
        sbc hl,de
        pop de
        or a
        sbc hl,de
        jr c,.poll
        or a                        ; NC: timed out
        ret

; xm_purge: read and drop bytes until the line is quiet for 1 s.
xm_purge:
        ld de,XM_BYTE_TICKS
        call xm_get
        jr c,xm_purge
        ret

; xm_block_crc: HL = the CRC-16/XMODEM (polynomial 1021h, start 0) of the
; xm_size bytes at BLOCK_BUF.
xm_block_crc:
        ld hl,0
        ld de,BLOCK_BUF
        ld bc,(xm_size)
.byte:
        ld a,(de)
        inc de
        xor h
        ld h,a
        push bc
        ld b,8
.bit:
        add hl,hl
        jr nc,.next
        ld a,h
        xor 10h
        ld h,a
        ld a,l
        xor 21h
        ld l,a
.next:
        djnz .bit
        pop bc
        dec bc
        ld a,b
        or c
        jr nz,.byte
        ret

; xm_block_sum: A = the 8-bit sum of the xm_size bytes at BLOCK_BUF.
xm_block_sum:
        ld hl,BLOCK_BUF
        ld de,(xm_size)
        xor a
.byte:
        add a,(hl)
        inc hl
        dec de
        ld b,a
        ld a,d
        or e
        ld a,b
        jr nz,.byte
        ret

; --- state ----------------------------------------------------------------

xm_start:       db 'C'              ; what we send to start: C or NAK
xm_crc:         db 1                ; 1 = CRC mode, 0 = checksums
xm_expect:      db 1                ; the next block number
xm_num:         db 0
xm_errors:      db 0                ; in a row
xm_break:       db 0
xm_size:        dw 0
xm_check:       dw 0
xm_t0:          dw 0
xm_length:      dw 0
xm_blocks:      dw 0
xm_total_errors: dw 0
