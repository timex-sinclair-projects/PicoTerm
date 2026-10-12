; scld.asm - the SCLD's DECR (port FFh) and the second display file
;
; DF2 (6000h-7AFFh) is where the 2068 keeps its machine stack, its RAM
; dispatcher and the start of BASIC. The ROM's Video Mode Change Service
; (Technical Manual 3.2.2.3, EXROM 0E8Eh) moves all of that out of the way:
; CHANS and PROG go up 12C0h to 7B00h/7B16h, the stack and dispatcher go to
; F7C0h-FFFFh, the UDGs down to F718h. Zebra's OS-64 opens DF2 the same way.
;
; PicoTerm opens DF2 once, as mode 80h (both files available, DF1 shown),
; and leaves it open: CLOSE-DFILE has a bad reputation, and BASIC works
; normally with DF2 open. After that, 64 columns is just a DECR write.

; dfile_open: open DF2 through CHNG_VID, unless VIDMOD says it's open.
; Call it while BASIC's stack and IM1 are still in place: CHNG_VID moves
; the stack (SP comes back 97C0h higher). With too little memory the ROM
; stops with "4 Out of memory", which is a clean return to BASIC.
dfile_open:
        ld a,(SV_VIDMOD)
        or a
        ret nz
        di
        ld a,1
        out (PORT_HSR),a            ; EXROM into chunk 0
        in a,(PORT_DECR)
        set 7,a
        out (PORT_DECR),a
        ei                          ; CHNG_VID does its own DI/EI
        ld a,VIDMOD_DUAL
        call EX_CHNG_VID
        di
        in a,(PORT_DECR)
        res 7,a
        out (PORT_DECR),a
        xor a
        out (PORT_HSR),a            ; all HOME again
        ld a,VIDMOD_DUAL
        ld (SV_VIDMOD),a            ; CHNG_VID stores 0 for 80h (Technical
        ei                          ; Manual figure 3.2.2-2)
        ret

; decr_mode: set DECR's mode and 64-column colour bits from A (bits 0-5).
; Keeps bit 7 (EXROM select) as the ROMs do, by reading the port back, and
; keeps bit 6 clear so the frame interrupt stays on.
decr_mode:
        and 3Fh
        ld b,a
        in a,(PORT_DECR)
        and 80h
        or b
        out (PORT_DECR),a
        ret
