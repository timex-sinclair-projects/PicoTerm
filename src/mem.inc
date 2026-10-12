; mem.inc - fixed addresses (docs/DESIGN.md section 3)
;
; ORG_ADDR comes from the Makefile (-DORG_ADDR=...), so the loader and the
; code agree on it.

; --- 2068 hardware ---------------------------------------------------------
DF1             equ 4000h           ; display file 1 bitmap
ATTR1           equ 5800h           ; display file 1 attributes
DF2             equ 6000h           ; display file 2 bitmap (64-col mode only)

PORT_ULA        equ 0FEh            ; keyboard (IN), border (OUT bits 0-2)

; --- ROM and system variables (same addresses as the Spectrum's) ----------
ROM_VERSION     equ 0065h           ; HOME ROM byte: 23h = TS-Pico ROM 2.3
SV_CHARS        equ 5C36h           ; font address - 256
SV_BORDCR       equ 5C48h           ; border colour in bits 3-5
SV_STKEND       equ 5C65h           ; end of BASIC's calculator stack
SV_IY           equ 5C3Ah           ; IY must hold this when BASIC runs

; --- PicoTerm's own memory -----------------------------------------------
STACK_TOP       equ 0FD00h          ; stack FC00h-FCFFh, grows down
IM2_TABLE       equ 0FD00h          ; 257 bytes of IM2_VEC
IM2_VEC         equ 0FEh            ; every vector reads FEFEh
IM2_HANDLER     equ 0FEFEh          ; JP isr
