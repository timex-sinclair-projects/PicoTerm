; kbd.asm - keyboard: matrix scan (in the ISR), repeat, key queue, key map
;
; kbd_scan runs every frame from the ISR. It finds one key, applies repeat,
; and queues a raw code: the key's matrix number (0-39) in bits 0-5, CAPS
; SHIFT in bit 6, SYMBOL SHIFT in bit 7. Code 40 is both shifts alone,
; PicoTerm's one-shot Ctrl prefix.
;
; kbd_get, in the main loop, translates raw codes through the tables below
; (docs/DESIGN.md section 8) into ASCII or one of the K_ codes.
;
; Matrix numbering: half-row n (port xxFEh with bit n of the high byte low)
; holds keys n*5 .. n*5+4, bit 0 first.
;   0: CAPS Z X C V     1: A S D F G     2: Q W E R T      3: 1 2 3 4 5
;   4: 0 9 8 7 6        5: P O I U Y     6: ENTER L K J H  7: SPACE SYM M N B

KEY_NONE        equ 0FFh
KEY_CTRL        equ 40

; translated codes above 7Fh
K_ENTER         equ 80h
K_BACKSPACE     equ 81h
K_UP            equ 82h
K_DOWN          equ 83h
K_LEFT          equ 84h
K_RIGHT         equ 85h
K_MENU          equ 86h             ; BREAK (CAPS + SPACE)
K_CAPSLOCK      equ 87h             ; handled inside kbd_get
K_COLS          equ 88h             ; GRAPHICS (CAPS + 9): next column mode

; frames; the tick is 50 or 60 Hz, close enough for typing
REPEAT_DELAY    equ 30
REPEAT_RATE     equ 3

KBQ_SIZE        equ 16              ; power of two

; kbd_scan: called from the ISR. Uses AF, BC, DE, HL.
kbd_scan:
        ; modifiers
        ld bc,0FEFEh
        in a,(c)
        cpl
        and 01h                     ; CAPS
        rrca
        rrca                        ; -> bit 6
        ld d,a
        ld b,7Fh
        in a,(c)
        cpl
        and 02h                     ; SYMBOL SHIFT
        rrca
        rrca                        ; -> bit 7
        or d
        ld d,a                      ; D = modifier bits
        ; first other key
        ld b,0FEh
        ld e,0                      ; E = first key number of this half-row
.row:
        in a,(c)
        cpl
        and 1Fh
        ld h,a
        ld a,e
        or a
        jr nz,.not0
        res 0,h                     ; CAPS isn't a key here
.not0:
        cp 35
        jr nz,.not7
        res 1,h                     ; nor SYMBOL SHIFT
.not7:
        ld a,h
        or a
        jr nz,.found
        ld a,e
        add a,5
        ld e,a
        rlc b
        jr c,.row                   ; until the 0 bit has gone all the way round
        ; no key: both shifts alone is Ctrl
        ld a,d
        cp 0C0h
        ld a,KEY_CTRL
        jr z,.code
        ld a,KEY_NONE
        jr .code
.found:
        rrca                        ; lowest set bit -> key number
        jr c,.bit
        inc e
        jr .found
.bit:
        ld a,e
        or d
.code:
        ; A = raw code. Repeat logic.
        ld hl,kbd_last
        cp (hl)
        jr z,.held
        ld e,a
        ld a,(hl)
        ld (hl),e                   ; new last code
        xor e
        and 3Fh                     ; same key, only the shifts changed?
        ret z
        ld a,e
        cp KEY_NONE
        ret z
        ld a,REPEAT_DELAY
        ld (kbd_count),a
        ld a,e
        jr kbd_put
.held:
        cp KEY_NONE
        ret z
        cp KEY_CTRL
        ret z
        ld hl,kbd_count
        dec (hl)
        ret nz
        ld (hl),REPEAT_RATE
        ; fall through

; kbd_put: queue raw code A (dropped if the queue is full).
kbd_put:
        ld e,a
        ld a,(kbq_head)
        ld b,a
        inc a
        and KBQ_SIZE-1
        ld hl,kbq_tail
        cp (hl)
        ret z                       ; full
        ld (kbq_head),a
        ld a,b
        ld hl,kbq
        add a,l
        ld l,a
        adc a,h
        sub l
        ld h,a
        ld (hl),e
        ret

; kbd_get: NZ and A = the next key (ASCII 01h-7Fh or a K_ code), or Z if
; there is none. Applies caps lock and the Ctrl prefix.
kbd_get:
        ld a,(kbq_tail)
        ld hl,kbq_head
        cp (hl)
        ret z                       ; empty
        ld e,a
        inc a
        and KBQ_SIZE-1
        ld (kbq_tail),a
        ld d,0
        ld hl,kbq
        add hl,de
        ld a,(hl)                   ; raw code
        cp KEY_CTRL
        jr nz,.notctrl
        ld hl,kbd_ctrl
        ld a,(hl)
        cpl
        ld (hl),a                   ; toggle: pressing it twice cancels
        jr kbd_get
.notctrl:
        ld c,a
        and 3Fh
        ld e,a                      ; DE = key number
        ld hl,keymap_plain
        bit 7,c
        jr z,.notsym
        ld hl,keymap_sym
        jr .look
.notsym:
        bit 6,c
        jr z,.look
        ld hl,keymap_caps
.look:
        add hl,de
        ld a,(hl)
        or a
        jr z,kbd_get                ; nothing on this combination
        cp K_CAPSLOCK
        jr nz,.notlock
        ld hl,kbd_capslock
        ld a,(hl)
        cpl
        ld (hl),a
        jr kbd_get
.notlock:
        ld b,a
        ; caps lock: lower-case letters up
        ld a,(kbd_capslock)
        or a
        jr z,.nolock
        ld a,b
        cp 'a'
        jr c,.nolock
        cp 'z'+1
        jr nc,.nolock
        sub 20h
        ld b,a
.nolock:
        ; Ctrl prefix: 40h-7Fh become 00h-1Fh
        ld a,(kbd_ctrl)
        or a
        jr z,.done
        xor a
        ld (kbd_ctrl),a
        ld a,b
        cp 40h
        jr c,.done
        cp 80h
        jr nc,.done
        and 1Fh
        ld b,a
.done:
        ld a,b
        or a                        ; NZ (a key is never 0: Ctrl-@ is skipped)
        ret nz
        jr kbd_get

; kbd_ctrl_pending: A = 0, or FFh while the Ctrl prefix is waiting.
kbd_ctrl_pending:
        ld a,(kbd_ctrl)
        ret

; --- key maps: 40 entries each, in matrix order; 0 = nothing --------------

keymap_plain:
        db 0,   'z', 'x', 'c', 'v'
        db 'a', 's', 'd', 'f', 'g'
        db 'q', 'w', 'e', 'r', 't'
        db '1', '2', '3', '4', '5'
        db '0', '9', '8', '7', '6'
        db 'p', 'o', 'i', 'u', 'y'
        db K_ENTER, 'l', 'k', 'j', 'h'
        db ' ', 0,   'm', 'n', 'b'

keymap_caps:
        db 0,   'Z', 'X', 'C', 'V'
        db 'A', 'S', 'D', 'F', 'G'
        db 'Q', 'W', 'E', 'R', 'T'
        db 1Bh, K_CAPSLOCK, 09h, 0, K_LEFT      ; EDIT, CAPS LOCK, TRUE VID, INV VID, left
        db K_BACKSPACE, K_COLS, K_RIGHT, K_UP, K_DOWN ; DELETE, GRAPHICS, right, up, down
        db 'P', 'O', 'I', 'U', 'Y'
        db K_ENTER, 'L', 'K', 'J', 'H'
        db K_MENU, 0, 'M', 'N', 'B'

; The 2068's symbol legends, with the BASIC keywords replaced by the ASCII
; characters the keyboard otherwise can't type.
keymap_sym:
        db 0,   ':', '`', '?', '/'              ; X is the pound sign
        db '~', '|', 5Ch, '{', '}'              ; STOP NOT STEP TO THEN (5Ch = \)
        db 0,   0,   0,   '<', '>'              ; <= <> >=
        db '!', '@', '#', '$', '%'
        db '_', ')', '(', "'", '&'
        db '"', ';', 0,   ']', '['              ; I is AT; U OR, Y AND
        db K_ENTER, '=', '+', '-', '^'
        db ' ', 0,   '.', ',', '*'

        ASSERT $ - keymap_plain == 3*40, "Key maps must be 40 entries each"

; --- state ----------------------------------------------------------------

kbd_last:       db KEY_NONE
kbd_count:      db 0
kbd_ctrl:       db 0
kbd_capslock:   db 0
kbq_head:       db 0                ; written only by the ISR
kbq_tail:       db 0                ; written only by kbd_get
kbq:            ds KBQ_SIZE
