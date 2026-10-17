; vid64.asm - 64-column driver: the SCLD's 64-column mode (or PicoVideo's
; mode 7, the same with a color per cell)
;
; Even columns are display file 1 and odd columns display file 2, each 32
; bytes wide (Technical Manual 5.2.3): column C is byte C/2 of file C&1. So
; every routine here is the 32-column one with vid_plane set, and rows are
; cleared and scrolled once in each file, as Zebra's OS-64 does.
;
; Attributes are written as in 32 columns (5800h for even columns, 7800h for
; odd). The SCLD ignores them in mode 6; PicoVideo shows them in mode 7.

; vid64_half: C = C/2, vid_plane = 20h for an odd column. Uses A.
vid64_half:
        srl c
        ld a,0
        jr nc,.even
        ld a,20h
.even:
        ld (vid_plane),a
        ret

; vid64_whole: undo vid64_half. Keeps flags... and A.
vid64_whole:
        push af
        ld a,(vid_plane)
        or a
        jr z,.even
        scf
.even:
        rl c
        xor a
        ld (vid_plane),a
        pop af
        ret

vid64_draw:
        push af
        call vid64_half
        pop af
        call vid32_draw
        jr vid64_whole

vid64_cursor:
        call vid64_half
        call vid32_cursor
        jr vid64_whole

vid64_clear_rows:
        push af
        push de
        call vid32_clear_rows
        ld a,20h
        ld (vid_plane),a
        pop de
        pop af
        call vid32_clear_rows
        jr vid64_plane0

vid64_scroll_up:
        push de
        call vid32_scroll_up
        ld a,20h
        ld (vid_plane),a
        pop de
        call vid32_scroll_up
        jr vid64_plane0

vid64_scroll_down:
        push de
        call vid32_scroll_down
        ld a,20h
        ld (vid_plane),a
        pop de
        call vid32_scroll_down
vid64_plane0:
        xor a
        ld (vid_plane),a
        ret
