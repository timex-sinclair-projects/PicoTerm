; ui.asm - windows over the terminal, and keys for them
;
; Windows are 32 cells wide (they fit every mode) and centred in wider
; modes. They're drawn with drv_draw, not vid_put, so the shadow keeps the
; terminal's screen and ui_close puts it back with a redraw. While a window
; is open, received bytes wait in the ring (rx_mode = RX_HOLD), or go to the
; capture buffer when a screen asks Zimodem something (RX_CAPTURE).
;
; In the SCLD's 64-column mode there's no colour, so selections are marked
; with a ">" as well as a highlight.

UI_W            equ 32

ATTR_WIN        equ 4Fh             ; bright white on blue
ATTR_TITLE      equ 4Eh             ; bright yellow on blue
ATTR_SEL        equ 70h             ; bright black on yellow
ATTR_FIELD      equ 78h             ; bright black on white

RX_SHOW         equ 0               ; received bytes: to the terminal
RX_HOLD         equ 1               ;   left in the ring
RX_CAPTURE      equ 2               ;   to CAPTURE (and hayes_watch)

CAPTURE_SIZE    equ 1024

; ui_open: hide the cursor, hold received bytes, work out the left edge.
ui_open:
        call vid_cursor_off
        ld a,RX_HOLD
        ld (rx_mode),a
        ld a,(vid_cols)
        sub UI_W
        srl a
        ld (ui_left),a
        ret

; ui_close: back to the terminal: its screen from the shadow, and the
; bytes that waited.
ui_close:
        call vid_redraw
        xor a
        ld (rx_mode),a
        ret

; ui_put: character A at window row B, column C, attribute E. Keeps all.
ui_put:
        push hl
        push bc
        push de
        push af
        ld a,(ui_left)
        add a,c
        ld c,a
        pop af
        push af
        call drv_draw
        pop af
        pop de
        pop bc
        pop hl
        ret

; ui_text: the 0-terminated string at HL from B,C in attribute E. C ends
; after it. Keeps B, DE.
ui_text:
        ld a,(hl)
        or a
        ret z
        call ui_put
        inc hl
        inc c
        jr ui_text

; ui_fill: D copies of A from B,C in attribute E. C ends after them.
ui_fill:
        push af
        ld a,d
        or a
        jr z,.done
        pop af
.cell:
        call ui_put
        inc c
        dec d
        jr nz,.cell
        ret
.done:
        pop af
        ret

; ui_box: a window from row B for D rows, full width, double-line border,
; blank inside, with the title at HL (0 = none) in the top border.
ui_box:
        ld (.title),hl
        ld e,ATTR_WIN
        ld c,0
        ld a,0C9h                   ; top: ╔═══╗
        call ui_put
        inc c
        push de
        ld d,UI_W-2
        ld a,0CDh
        call ui_fill
        pop de
        ld a,0BBh
        call ui_put
        push bc
        ld hl,(.title)
        ld a,h
        or l
        jr z,.notitle
        ld c,2
        ld e,ATTR_TITLE
        ld a,' '
        call ui_put
        inc c
        call ui_text
        ld a,' '
        call ui_put
        ld e,ATTR_WIN
.notitle:
        pop bc
        dec d
        dec d
.mid:                               ; ║   ║
        inc b
        ld c,0
        ld a,0BAh
        call ui_put
        inc c
        push de
        ld d,UI_W-2
        ld a,' '
        call ui_fill
        pop de
        ld a,0BAh
        call ui_put
        dec d
        jr nz,.mid
        inc b                       ; ╚═══╝
        ld c,0
        ld a,0C8h
        call ui_put
        inc c
        ld d,UI_W-2
        ld a,0CDh
        call ui_fill
        ld a,0BCh
        jp ui_put
.title: dw 0

; ui_script: draw a list of texts at HL: each is row, column, attribute,
; then the 0-terminated text; 0FFh ends the list.
ui_script:
        ld a,(hl)
        cp 0FFh
        ret z
        ld b,a
        inc hl
        ld c,(hl)
        inc hl
        ld e,(hl)
        inc hl
        call ui_text
        inc hl
        jr ui_script

; ui_pick: HL = entry A of a table of 5-byte strings (names).
ui_pick:
        ld e,a
        add a,a
        add a,a
        add a,e
        jp vid_add_a

; ui_line: clear the inside of window row B (columns 1-30).
ui_line:
        ld c,1
        ld d,UI_W-2
        ld e,ATTR_WIN
        ld a,' '
        jp ui_fill

; ui_getkey: wait for a key. Letters come back in upper case. Received
; bytes are captured meanwhile if rx_mode says so.
ui_getkey:
        call pump_rx
        call kbd_get
        jr z,ui_getkey
        cp 'a'
        ret c
        cp 'z'+1
        ret nc
        sub 20h
        ret

; ui_is_back: Z if key A means "back": BREAK or EDIT (Esc).
ui_is_back:
        cp K_MENU
        ret z
        cp 1Bh
        ret

; ui_message: a small window at row 9 with the text at HL (up to 28
; characters), then wait for a key.
ui_message:
        push hl
        ld b,9
        ld d,3
        ld hl,0
        call ui_box
        pop hl
        ld b,10
        ld c,2
        ld e,ATTR_WIN
        call ui_text
        jp ui_getkey

; ui_yes_no: like ui_message; Z if the answer is Y.
ui_yes_no:
        call ui_message
        cp 'Y'
        ret

; capture_reset: empty the capture buffer.
capture_reset:
        ld hl,0
        ld (capture_len),hl
        ret

; capture_byte: add A to the capture buffer (dropped when it's full).
capture_byte:
        push af
        ld hl,(capture_len)
        ld de,CAPTURE_SIZE
        or a
        sbc hl,de
        jr nc,.full
        ld hl,(capture_len)
        push hl
        inc hl
        ld (capture_len),hl
        pop hl
        ld de,CAPTURE
        add hl,de
        pop af
        ld (hl),a
        ret
.full:
        pop af
        ret

; --- state ----------------------------------------------------------------

ui_left:        db 0
rx_mode:        db RX_SHOW
capture_len:    dw 0
