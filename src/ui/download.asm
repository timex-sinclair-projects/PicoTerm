; download.asm - the Download screen: XMODEM into memory, then to the SD
; card
;
; The file is received into XFER_BUF (display file 2's area, 6000h-7AFFh:
; 6912 bytes), so in the SCLD's 64-column mode, which shows that area,
; PicoTerm drops to 32 columns for the transfer. It's saved with
; sd_save_code: a file with a 128-byte +3DOS header, the way SAVE "f:name"
; CODE writes one. A firmware change (DESIGN.md R2) would let it write
; plain files of any size, as they arrive.

DL_ROW          equ 4
DL_NAME_MAX     equ 40

dl_run:
        ld a,(hayes_online)
        or a
        jr nz,.online
        ld hl,txt_dl_offline
        jp ui_message
.online:
        call pico_present
        jr nz,.pico
        ld hl,txt_dl_no_pico
        jp ui_message
.pico:
        call dl_box
        ld hl,txt_dl_name
        ld bc,(DL_ROW+2)*256+2
        ld e,ATTR_WIN
        call ui_text
        ld hl,dl_name
        ld bc,(DL_ROW+3)*256+2
        ld de,DL_NAME_MAX*256+28
        call ui_input
        ret c
        ld a,(dl_name)
        or a
        ret z
        ld hl,dl_name
        call sd_exists
        jr nz,.new
        ld hl,txt_dl_replace
        call ui_yes_no
        ret nz
.new:
        ; the buffer is display file 2: not while it's on show
        ld a,(vid_mode)
        ld (dl_old_mode),a
        cp VM_64
        jr nz,.mode
        ld a,VM_32
        call vid_set_mode
.mode:
        call dl_box
        ld hl,dl_script
        call ui_script
        call xm_progress
        call xm_receive
        ld (dl_result),a
        or a
        jr nz,.failed
        ; done: strip the padding?
        ld hl,txt_dl_strip
        call ui_yes_no
        call z,dl_strip
        call dl_box
        ld hl,txt_dl_saving
        ld bc,(DL_ROW+2)*256+2
        ld e,ATTR_WIN
        call ui_text
        ld hl,dl_name
        ld de,XFER_BUF
        ld bc,(xm_length)
        call sd_save_code
        cp PS_OK
        jr nz,.notsaved
        ld de,dl_msg                ; "Saved: 1234 bytes."
        ld hl,txt_dl_saved
        call str_copy
        ld hl,(xm_length)
        call dec16_to_buf
        ld hl,txt_dl_bytes
        call str_copy
        xor a
        ld (de),a
        ld hl,dl_msg
        jr .say
.notsaved:
        ld hl,txt_dl_not_saved
        jr .say
.failed:
        ld hl,dl_results-2
        add a,a
        call vid_add_a
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
.say:
        call ui_message
        ld a,(dl_old_mode)          ; back to the columns we had
        ld hl,vid_mode
        cp (hl)
        ret z
        jp vid_set_mode

; dl_strip: drop the 1Ah (^Z) bytes XMODEM pads the last block with.
dl_strip:
        ld hl,(xm_length)
.back:
        ld a,h
        or l
        jr z,.done
        dec hl
        ld de,XFER_BUF
        push hl
        add hl,de
        ld a,(hl)
        pop hl
        cp 1Ah
        jr z,.back
        inc hl
.done:
        ld (xm_length),hl
        ret

dl_box:
        ld b,DL_ROW
        ld d,10
        ld hl,txt_download
        jp ui_box

; xm_progress: the counts, on the window's row DL_ROW+5.
xm_progress:
        ld de,dl_msg
        ld hl,txt_dl_blocks
        call str_copy
        ld hl,(xm_blocks)
        call dec16_to_buf
        ld hl,txt_dl_bytes_n
        call str_copy
        ld hl,(xm_length)
        call dec16_to_buf
        ld hl,txt_dl_errors
        call str_copy
        ld hl,(xm_total_errors)
        call dec16_to_buf
        ld a,' '
        ld (de),a
        inc de
        xor a
        ld (de),a
        ld hl,dl_msg
        ld bc,(DL_ROW+5)*256+2
        ld e,ATTR_WIN
        jp ui_text

; dec16_to_buf: HL in decimal at DE, no leading zeros; DE ends after it.
dec16_to_buf:
        ld (dec_out),de
        xor a
        ld (dec_any),a
        ld de,10000
        call .digit
        ld de,1000
        call .digit
        ld de,100
        call .digit
        ld de,10
        call .digit
        ld a,l
        add a,'0'
        call .put
        ld de,(dec_out)
        ret
.digit:
        ld a,'0'-1
.count:
        inc a
        or a
        sbc hl,de
        jr nc,.count
        add hl,de
        cp '0'
        jr nz,.put
        ld c,a
        ld a,(dec_any)
        or a
        ret z                       ; a leading zero
        ld a,c
.put:
        push hl
        ld hl,(dec_out)
        ld (hl),a
        inc hl
        ld (dec_out),hl
        pop hl
        ld a,1
        ld (dec_any),a
        ret

dec_out:        dw 0
dec_any:        db 0

dl_script:
        db DL_ROW+2, 2, ATTR_WIN, "Start the download on the BBS,",0
        db DL_ROW+3, 2, ATTR_WIN, "then wait. XMODEM, to memory.",0
        db DL_ROW+7, 2, ATTR_TITLE, "BREAK",0
        db DL_ROW+7, 8, ATTR_WIN, "cancels",0
        db 0FFh

dl_results:     dw txt_xm_canceled, txt_xm_break, txt_xm_too_big
                dw txt_xm_errors, txt_xm_no_start

dl_old_mode:    db 0
dl_result:      db 0
dl_name:        db "download.bin",0
                ds DL_NAME_MAX-12
dl_msg:         ds 40

txt_download:   db "Download",0
txt_dl_name:    db "Save it as:",0
txt_dl_offline: db "Connect to a BBS first.",0
txt_dl_no_pico: db "No TS-Pico to save it to.",0
txt_dl_replace: db "Replace that file? (Y/N)",0
txt_dl_strip:   db "Strip ^Z padding? (Y/N)",0
txt_dl_saving:  db "Saving...",0
txt_dl_saved:   db "Saved: ",0
txt_dl_bytes:   db " bytes.",0
txt_dl_not_saved: db "Couldn't save the file.",0
txt_dl_blocks:  db "Blk ",0
txt_dl_bytes_n: db "  Bytes ",0
txt_dl_errors:  db "  Err ",0
txt_xm_canceled: db "The sender canceled.",0
txt_xm_break:   db "Canceled.",0
txt_xm_too_big: db "Too big for memory (6912).",0
txt_xm_errors:  db "Too many errors. Canceled.",0
txt_xm_no_start: db "The sender didn't start.",0
