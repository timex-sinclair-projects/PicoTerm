; sdsave.asm - files on the TS-Pico's SD card: does one exist, and saving
; a block of memory as SAVE "f:path" CODE would
;
; The save goes the ROM's way, without the ROM (docs/reference: flows/
; save.md, rom/exrom-driver.md "SAVE (1879h)", firmware/tspico-disk.md
; "NATIVE_OPEN"):
;
;   1. tpi:fopen <path>, CODE numbers: op 0 (SAVE) with the CODE token in
;      the high byte, then the session id. The Pico checks the name and,
;      if the file exists, asks "Replace?" (88h): pico_auto_key answers.
;   2. SYNC and a SAVE pre-header: 00h, 0, FFh (bank), the session, the
;      header's address, 17, XOR. Read the pre-load (01h, or a refusal).
;   3. The header block: 00h, the session, the 17-byte tape header (type 3,
;      a 10-character stand-in name, length, start, 32768), the XOR of the
;      flag and the header. Read the mid status.
;   4. About a second later, the data block, with no pre-header: FFh, the
;      session, the bytes, the XOR. The final status comes after the card
;      has been written.
;
; The Pico writes the file as path itself, with a 128-byte +3DOS header
; ahead of the data (firmware/native.md). Interrupts are off while a block
; goes out, as in the ROM: the Pico's capture expects no long gaps.
;
; Until the firmware has a binary-safe channel write (DESIGN.md R2), this is
; how PicoTerm writes binary files.

TOK_CODE        equ 0AFh
SD_CHECK_STREAM equ 201
SAVE_START      equ 32768           ; the start address in the header

; sd_exists: Z if the file at HL can be opened for reading. Quiet.
sd_exists:
        push hl
        ld de,CMD_BUF
        ld hl,txt_chopen_r
        call str_copy
        pop hl
        call str_copy
        xor a
        ld (de),a
        ld a,1
        ld (pico_quiet),a
        ld hl,SD_CHECK_STREAM
        ld (pico_pmr1),hl
        ld hl,0
        ld (pico_pmr2),hl
        ld hl,CMD_BUF
        call pico_cmd_n
        push af
        ld hl,SD_CHECK_STREAM
        ld (pico_pmr1),hl
        ld hl,cmd_chclose
        call pico_cmd_n
        xor a
        ld (pico_quiet),a
        pop af
        cp PS_OK
        ret

; sd_save_code: save BC bytes from DE as the file at HL (an existing one is
; replaced: ask first). A = the status: PS_OK, or the Pico's (or 0: no
; answer).
sd_save_code:
        ld (sd_len),bc
        ld (sd_data),de
        push hl
        ; the session id: anything but 0, as the ROM's comes from FRAMES
        ld hl,(ticks)
        set 0,l
        ld (sd_session),hl
        ; the stand-in tape header: CODE, the path's first 10 characters
        ld hl,sd_header
        ld (hl),3
        inc hl
        ld b,10
        pop de                      ; the path
        push de
.name:
        ld a,(de)
        or a
        jr z,.pad
        ld (hl),a
        inc hl
        inc de
        djnz .name
        jr .named
.pad:
        ld (hl),' '
        inc hl
        djnz .pad
.named:
        ld de,(sd_len)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld (hl),low SAVE_START
        inc hl
        ld (hl),high SAVE_START
        inc hl
        ld (hl),low 32768
        inc hl
        ld (hl),high 32768
        ; 1. tpi:fopen path, op SAVE / CODE, the session
        ld de,CMD_BUF
        ld hl,txt_fopen
        call str_copy
        pop hl
        call str_copy
        xor a
        ld (de),a
        ld hl,TOK_CODE*256
        ld (pico_pmr1),hl
        ld hl,(sd_session)
        ld (pico_pmr2),hl
        ld a,'Y'
        ld (pico_auto_key),a        ; the user has already said yes
        ld a,1
        ld (pico_quiet),a
        ld hl,CMD_BUF
        call pico_cmd_n
        push af
        ld a,'N'
        ld (pico_auto_key),a
        xor a
        ld (pico_quiet),a
        pop af
        cp PS_OK
        ret nz
        ; 2. the SAVE pre-header
        di
        call pico_wait_idle
        ld a,03h
        out (PICO_STAT),a           ; SYNC
        call pico_wait_idle
        ld d,0
        xor a
        call pico_tx                ; 0: a SAVE block
        xor a
        call pico_tx                ; 1: T_ADDR 0
        ld a,0FFh
        call pico_tx                ; 2: the bank, always FFh
        ld a,(sd_session)
        call pico_tx                ; 3-4: the session
        ld a,(sd_session+1)
        call pico_tx
        ld a,low sd_header
        call pico_tx                ; 5-6: IX, the header
        ld a,high sd_header
        call pico_tx
        ld a,17
        call pico_tx                ; 7-8: DE, its length
        xor a
        call pico_tx
        ld a,d
        call pico_tx                ; 9: the XOR
        in a,(PICO_DATA)            ; the pre-load: 01h, or a refusal
        cp 1
        jr nz,.refused
        call pico_wait_ready
        jr c,.lost
        ; 3. the header block, then the mid status
        ld hl,sd_header
        ld bc,17
        xor a
        call sd_block
        call pico_wait_ready
        jr c,.lost
        in a,(PICO_DATA)
        cp PS_OK
        jr nz,.refused
        ei
        ld de,50                    ; the ROM's pause, about a second
        call wait_ticks
        ; 4. the data block and the final status
        di
        ld hl,(sd_data)
        ld bc,(sd_len)
        ld a,0FFh
        call sd_block
        ei
        call pico_wait_long
        jr c,.lost
        in a,(PICO_DATA)
        ret
.refused:
        ei
        or a
        ret nz
.lost:
        ei
        xor a
        ret

; sd_block: a SAVE block: flag A, the session, BC bytes from HL, the XOR of
; the flag and the bytes.
sd_block:
        ld e,a                      ; E: the block's XOR
        push de
        ld d,0
        call pico_tx                ; the flag
        ld a,(sd_session)
        call pico_tx
        ld a,(sd_session+1)
        call pico_tx
        pop de
.byte:
        ld a,(hl)
        inc hl
        push af
        xor e
        ld e,a
        pop af
        call pico_tx                ; keeps BC, E, HL
        dec bc
        ld a,b
        or c
        jr nz,.byte
        ld a,e
        jp pico_tx

txt_chopen_r:   db "tpi:chopen r ",0
txt_fopen:      db "tpi:fopen ",0

sd_session:     dw 0
sd_data:        dw 0
sd_len:         dw 0
sd_header:      ds 17
