; hayes.asm - talking to Zimodem: result codes, commands, hang-up
;
; hayes_watch sees every received byte (before the screen does) and keeps
; the last line. At each line end it looks for a result code: that sets
; hayes_result, and CONNECT / NO CARRIER / NO ANSWER set hayes_online.
; A remote host could send one of these words as text; every Hayes terminal
; has lived with that. (docs/DESIGN.md section 7.)

HR_NONE         equ 0
HR_OK           equ 1
HR_ERROR        equ 2
HR_CONNECT      equ 3
HR_NOCARRIER    equ 4
HR_NOANSWER     equ 5
HR_RING         equ 6

HAYES_LINE_MAX  equ 24

; Guard time for +++: Zimodem wants more than 900 ms of silence either side.
; 66 ticks is 1.1 s at 60 Hz and 1.3 s at 50 Hz.
HAYES_GUARD     equ 66

; hayes_watch: look at received byte A. Keeps A, BC.
hayes_watch:
        push af
        cp 0Dh
        jr z,.eol
        cp 0Ah
        jr z,.eol
        ld e,a
        ld a,(hayes_len)
        cp HAYES_LINE_MAX
        jr nc,.done                 ; long lines aren't result codes
        ld hl,hayes_line
        add a,l
        ld l,a
        adc a,h
        sub l
        ld h,a
        ld (hl),e
        ld hl,hayes_len
        inc (hl)
.done:
        pop af
        ret
.eol:
        ld a,(hayes_len)
        or a
        jr z,.done
        push bc
        call hayes_match
        pop bc
        xor a
        ld (hayes_len),a
        jr .done

; hayes_match: compare the line with the result-code table.
hayes_match:
        ld hl,hayes_codes
.entry:
        ld a,(hl)                   ; the code, 0 = end of the table
        or a
        ret z
        ld c,a
        inc hl
        ld b,(hl)                   ; 1 = the line may go on (CONNECT <id>)
        inc hl
        ld de,hayes_line
        push bc
        ld a,(hayes_len)
        ld b,a                      ; characters left in the line
.cmp:
        ld a,(hl)
        or a
        jr z,.end                   ; the word matched
        ld a,b
        or a
        jr z,.skip                  ; the line is shorter
        ld a,(de)
        cp (hl)
        jr nz,.skip
        inc hl
        inc de
        dec b
        jr .cmp
.end:
        ld a,b
        pop bc
        or a
        jr z,.found                 ; exact length
        ld a,b
        or a
        jr z,.next                  ; longer, and it must be exact
        ld a,(de)
        cp ' '
        jr z,.found                 ; "CONNECT 1"
        jr .next
.skip:
        pop bc
.find0:
        ld a,(hl)
        inc hl
        or a
        jr nz,.find0
        jr .entry
.next:
        inc hl                      ; past the 0
        jr .entry
.found:
        ld a,c
        ld (hayes_result),a
        cp HR_CONNECT
        jr z,.on
        cp HR_NOCARRIER
        jr z,.off
        cp HR_NOANSWER
        ret nz
.off:
        xor a
        ld (hayes_online),a
        ret
.on:
        ld a,1
        ld (hayes_online),a
        ret

hayes_codes:
        db HR_OK, 0, "OK", 0
        db HR_ERROR, 0, "ERROR", 0
        db HR_CONNECT, 1, "CONNECT", 0
        db HR_NOCARRIER, 0, "NO CARRIER", 0
        db HR_NOANSWER, 0, "NO ANSWER", 0
        db HR_RING, 0, "RING", 0
        db 0

; hayes_send: send the 0-terminated command at HL, then CR, after clearing
; hayes_result. Uses all but IX, IY.
hayes_send:
        xor a
        ld (hayes_result),a
.char:
        ld a,(hl)
        or a
        jr z,.cr
        call acia_send
        inc hl
        jr .char
.cr:
        ld a,0Dh
        jp acia_send

; hayes_wait: run the receive side for up to DE ticks, until a result code
; arrives. A = the result, HR_NONE on a timeout.
hayes_wait:
        ld hl,(ticks)
        ld (hayes_t0),hl
        ld a,1
        ld (pump_to_result),a
.loop:
        push de
        call pump_rx
        pop de
        ld a,(hayes_result)
        or a
        jr nz,.done
        ld hl,(ticks)
        push de
        ld de,(hayes_t0)
        or a
        sbc hl,de
        pop de
        or a
        sbc hl,de
        jr c,.loop
        xor a
.done:
        push af
        xor a
        ld (pump_to_result),a
        pop af
        ret

; hayes_command: hayes_send, then hayes_wait. A = the result.
hayes_command:
        push de
        call hayes_send
        pop de
        jr hayes_wait

; wait_ticks: run the receive side for DE ticks, whatever arrives.
wait_ticks:
        ld hl,(ticks)
        ld (hayes_t0),hl
.loop:
        push de
        call pump_rx
        pop de
        ld hl,(ticks)
        push de
        ld de,(hayes_t0)
        or a
        sbc hl,de
        pop de
        or a
        sbc hl,de
        jr c,.loop
        ret

; hayes_hangup: the escape and ATH. Zimodem needs silence, "+++", silence.
hayes_hangup:
        ld de,HAYES_GUARD
        call wait_ticks
        xor a
        ld (hayes_result),a
        ld b,3
.plus:
        ld a,'+'
        call acia_send
        djnz .plus
        ld de,HAYES_GUARD
        call wait_ticks
        ld de,3*50
        call hayes_wait             ; Zimodem's OK
        ld hl,cmd_ath
        ld de,3*50
        call hayes_command
        xor a
        ld (hayes_online),a
        ret

cmd_ath:        db "ATH",0

; --- state ----------------------------------------------------------------

hayes_result:   db HR_NONE
pump_to_result: db 0                ; 1 while hayes_wait waits: pump_rx stops at a result
hayes_online:   db 0
hayes_len:      db 0
hayes_t0:       dw 0
hayes_line:     ds HAYES_LINE_MAX
