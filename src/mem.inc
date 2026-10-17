; mem.inc - fixed addresses (docs/DESIGN.md section 3)
;
; ORG_ADDR comes from the Makefile (-DORG_ADDR=...), so the loader and the
; code agree on it.

; --- 2068 hardware ---------------------------------------------------------
DF1             equ 4000h           ; display file 1 bitmap
ATTR1           equ 5800h           ; display file 1 attributes
DF2             equ 6000h           ; display file 2 bitmap (64-col mode only)

PORT_HSR        equ 0F4h            ; horizontal select: chunks to DOCK/EXROM
PORT_ULA        equ 0FEh            ; keyboard (IN), border (OUT bits 0-2)
PORT_DECR       equ 0FFh            ; SCLD: video mode 0-2, 64-col ink 3-5,
                                    ; interrupt inhibit 6, EXROM select 7

DECR_STANDARD   equ 00h             ; video mode field values
DECR_64COL      equ 06h             ; SCLD 64 columns, one color (bits 3-5)
DECR_TEXT80     equ 05h             ; PicoVideo: 80-column text
DECR_64COLOR   equ 07h             ; PicoVideo: 64 columns, attributes as in 32

TEXT80_CHR      equ 4000h           ; PicoVideo mode 5: character codes, 80 a row
TEXT80_ATR      equ 4780h           ;   and their attributes (Spectrum format)

; --- ROM and system variables -------------------------------------------
ROM_VERSION     equ 0065h           ; HOME ROM byte: 23h = TS-Pico ROM 2.3
SV_CHARS        equ 5C36h           ; font address - 256
SV_BORDCR       equ 5C48h           ; border color in bits 3-5
SV_CHANS        equ 5C4Fh
SV_ATTR_P       equ 5C8Dh           ; BASIC's permanent colors
SV_STKEND       equ 5C65h           ; end of BASIC's calculator stack
SV_IY           equ 5C3Ah           ; IY must hold this when BASIC runs
SV_MSTBOT       equ 5CC0h           ; machine stack base / dispatcher entry
SV_VIDMOD       equ 5CC2h           ; 0 = DF2 closed; 80h = both open, DF1 shown

EX_CHNG_VID     equ 0E8Eh           ; EXROM Video Mode Change Service
VIDMOD_DUAL     equ 80h

; --- PicoTerm's own memory -----------------------------------------------
; Once DF2 is open, the ROM keeps its machine stack and dispatcher at
; F7C0h-FFFFh and the UDGs at F718h-F7BFh, so PicoTerm stays below F718h.
CODE_LIMIT      equ 0F400h          ; code and data end below here
STACK_TOP       equ 0F500h          ; stack F400h-F4FFh, grows down
IM2_TABLE       equ 0F500h          ; 257 bytes of IM2_VEC
IM2_VEC         equ 0F6h            ; every vector reads F6F6h
IM2_HANDLER     equ 0F6F6h          ; JP isr
