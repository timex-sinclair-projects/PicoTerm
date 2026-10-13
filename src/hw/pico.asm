; pico.asm - TS-Pico commands through ports 14/15, without the ROM
;
; Adapted from picolib.asm (tspico-firmware-build docs/manual/examples, MIT),
; following the TS-Pico Programmer's Manual (docs/reference/programmers-manual.md,
; chapters 2-4). Differences: no RST 10h (text the Pico sends goes to
; pico_print), no Scroll? prompts (aborted, as nothing here asks for one),
; and the pre-header carries the ROM version 23h, as ROM 2.3 sends.

PICO_DATA       equ 0Eh
PICO_STAT       equ 0Fh

PST_READY       equ 6               ; 1 = the Pico has its answer
PST_IDLE        equ 3               ; 1 = no transaction open
PST_RECOV       equ 2               ; 0 = the Pico gave up on a transaction

PICO_ROM_MIN    equ 23h             ; ROM 2.3: the SYNC protocol

; status codes PicoTerm cares about (Programmer's Manual 3.6)
PS_OK           equ 1
PS_NONSENSE     equ 5               ; C: unknown command
PS_NOANSWER     equ 0               ; empty FIFO, a timeout or a lost link

; pico_present: NZ if the HOME ROM is TS-Pico 2.3 or later.
pico_present:
        ld a,(ROM_VERSION)
        cp 0FFh                     ; a stock ROM
        jr z,.no
        cp PICO_ROM_MIN
        jr c,.no
        or a
        ret
.no:
        xor a
        ret

; pico_cmd: run the command at HL (0-terminated, "tpi:..."), CODE numbers 0.
; Text the Pico sends back goes to pico_print. A = the status (PS_OK = 1).
; Uses all but IX, IY.
pico_cmd:
        ld bc,0
        ld (pico_pmr1),bc
        ld (pico_pmr2),bc
; pico_cmd_n: the same with the CODE numbers already in pico_pmr1/2.
pico_cmd_n:
        push hl
        ld bc,0
.len:
        ld a,(hl)
        or a
        jr z,.counted
        inc hl
        inc bc
        jr .len
.counted:
        pop hl
        call pico_send
        jr c,.fail
        call pico_reply
        ret
.fail:
        xor a
        ret

; pico_wait_idle: up to about 1 s for READY and IDLE. Z = idle. Uses AF, BC.
pico_wait_idle:
        ld bc,0
.poll:
        in a,(PICO_STAT)
        and (1 << PST_READY) | (1 << PST_IDLE)
        cp (1 << PST_READY) | (1 << PST_IDLE)
        ret z
        dec bc
        ld a,b
        or c
        jr nz,.poll
        inc a
        ret

; pico_wait_ready: up to about 3 s for READY. NC = ready, C = failed
; (timeout, or the Pico abandoned the transaction). Keeps BC, DE, HL.
pico_wait_ready:
        push bc
        push hl
        ld hl,0
        ld c,2
.poll:
        in a,(PICO_STAT)
        bit PST_READY,a
        jr nz,.ready
        dec hl
        ld a,h
        or l
        jr nz,.poll
        dec c
        jr nz,.poll
        jr .fail
.ready:
        bit PST_RECOV,a             ; active low
        jr z,.fail
        pop hl
        pop bc
        or a
        ret
.fail:
        pop hl
        pop bc
        scf
        ret

; pico_tx: send A, XOR it into D, pause about 50 us. Keeps BC, E, HL.
pico_tx:
        out (PICO_DATA),a
        xor d
        ld d,a
        push bc
        ld b,11
.d:     djnz .d
        pop bc
        ret

; pico_rx: pause about 75 us, then read a byte. Keeps BC, DE, HL.
pico_rx:
        push bc
        ld b,16
.d:     djnz .d
        pop bc
        in a,(PICO_DATA)
        ret

; pico_send: SYNC, pre-header, pre-load, body. HL = text, BC = length.
; NC = sent, C = the link failed.
pico_send:
        push hl
        push bc
        call pico_wait_idle
        ld a,03h
        out (PICO_STAT),a           ; SYNC
        call pico_wait_idle
        pop bc
        pop hl
        ld d,0
        ld a,'B'
        call pico_tx                ; 0: a command block
        xor a
        call pico_tx                ; 1: SAVE "tpi:..."
        ld a,PICO_ROM_MIN
        call pico_tx                ; 2: the ROM version
        ld a,(pico_pmr1)
        call pico_tx                ; 3-6: the two CODE numbers
        ld a,(pico_pmr1+1)
        call pico_tx
        ld a,(pico_pmr2)
        call pico_tx
        ld a,(pico_pmr2+1)
        call pico_tx
        ld a,c
        call pico_tx                ; 7-8: text length
        ld a,b
        call pico_tx
        ld a,d
        call pico_tx                ; 9: XOR of 0-8
        in a,(PICO_DATA)            ; the pre-load
        cp 1
        scf
        ret nz
        call pico_wait_ready
        ret c
        ld d,0
        ld a,'D'
        call pico_tx
        ld a,c
        call pico_tx
        ld a,b
        call pico_tx
.body:
        ld a,(hl)
        inc hl
        call pico_tx
        dec bc
        ld a,b
        or c
        jr nz,.body
        ld a,d
        call pico_tx                ; checked by the Pico
        or a
        ret

; pico_reply: read a status, or an 81h message (status, text, 00h).
; A = the status; PS_NOANSWER if the answer never came.
pico_reply:
        call pico_wait_ready
        jr c,.none
        in a,(PICO_DATA)
        cp 81h
        jr z,.msg
        cp 80h
        ret c                       ; a plain status
        ld a,03h                    ; anything else: abort it
        out (PICO_STAT),a
        call pico_wait_idle
.none:
        xor a
        ret
.msg:
        call pico_rx                ; the status
        push af
.text:
        call pico_rx
        or a
        jr z,.end
        cp 03h
        jr z,.end
        cp 10h                      ; 10h-17h carry value bytes: skip them
        jr c,.put
        cp 18h
        jr nc,.put
        cp 16h                      ; AT and TAB: two values
        jr c,.one
        call pico_rx
.one:
        call pico_rx
        jr .text
.put:
        call pico_print
        jr .text
.end:
        pop af
        ret

; pico_data: send the command at HL (CODE numbers in pico_pmr1/2) and read
; a data answer (tpi:chrd) to DE: status 1, a count n, n bytes, their XOR.
; A = the status: PS_DATA with B = n, PS_EOF, or an error (a bad XOR reads
; as 2, R). Uses all but IX, IY.
PS_DATA         equ 1
PS_EOF          equ 7

pico_data:
        push de
        push hl
        ld bc,0
.len:
        ld a,(hl)
        or a
        jr z,.counted
        inc hl
        inc bc
        jr .len
.counted:
        pop hl
        call pico_send
        pop hl
        jr c,.none
        call pico_wait_ready
        jr c,.none
        in a,(PICO_DATA)
        cp PS_DATA
        ret nz                      ; end of file, or an error status
        call pico_rx
        ld b,a
        ld c,0                      ; the XOR
        or a
        jr z,.check
        push bc
.byte:
        call pico_rx
        ld (hl),a
        inc hl
        xor c
        ld c,a
        djnz .byte
        ld a,c
        pop bc
        ld c,a
.check:
        call pico_rx
        cp c
        ld a,PS_DATA
        ret z
        ld a,2                      ; R: a byte went missing
        ret
.none:
        xor a
        ret

pico_pmr1:      dw 0                ; the CODE numbers for the next command
pico_pmr2:      dw 0
