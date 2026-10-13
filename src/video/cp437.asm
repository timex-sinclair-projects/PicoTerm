; cp437.asm - the CP437 8x8 font for 32 and 64 columns (2048 bytes)
;
; The same glyphs PicoVideo uses for its 80-column mode, so the three
; modes look alike. Copied from PicoVideo v4.2 (globals.c, vgaFont), whose
; comment names the source: Bm437_ACM_VGA_8x8 from The Ultimate Oldschool
; PC Font Pack by VileR, https://int10h.org/oldschool-pc-fonts/
; (CC BY-SA 4.0). Eight bytes a character, top line first, bit 7 left.

        db 000h,000h,000h,000h,000h,000h,000h,000h   ; 00h
        db 07Eh,081h,0A5h,081h,0BDh,099h,081h,07Eh   ; 01h
        db 07Eh,0DBh,0FFh,0FFh,0C3h,0E7h,07Eh,000h   ; 02h
        db 036h,07Fh,07Fh,07Fh,03Eh,01Ch,008h,000h   ; 03h
        db 008h,01Ch,03Eh,07Fh,03Eh,01Ch,008h,000h   ; 04h
        db 018h,03Ch,018h,066h,0FFh,066h,018h,03Ch   ; 05h
        db 008h,01Ch,03Eh,07Fh,07Fh,03Eh,008h,01Ch   ; 06h
        db 000h,000h,018h,03Ch,03Ch,018h,000h,000h   ; 07h
        db 0FFh,0FFh,0E7h,0C3h,0C3h,0E7h,0FFh,0FFh   ; 08h
        db 000h,03Ch,066h,042h,042h,066h,03Ch,000h   ; 09h
        db 0FFh,0C3h,099h,0BDh,0BDh,099h,0C3h,0FFh   ; 0Ah
        db 03Fh,00Dh,01Ch,03Eh,063h,063h,03Eh,000h   ; 0Bh
        db 03Eh,063h,063h,03Eh,01Ch,07Fh,01Ch,000h   ; 0Ch
        db 00Eh,00Fh,00Dh,00Dh,01Ch,07Fh,01Ch,000h   ; 0Dh
        db 00Fh,03Bh,037h,03Bh,033h,037h,077h,070h   ; 0Eh
        db 018h,0DBh,03Ch,0E7h,03Ch,0DBh,018h,000h   ; 0Fh
        db 060h,078h,07Eh,07Fh,07Eh,078h,060h,000h   ; 10h
        db 003h,00Fh,03Fh,07Fh,03Fh,00Fh,003h,000h   ; 11h
        db 018h,03Ch,07Eh,018h,018h,07Eh,03Ch,018h   ; 12h
        db 066h,066h,066h,066h,066h,000h,066h,000h   ; 13h
        db 03Fh,06Dh,06Dh,03Dh,00Dh,00Dh,00Dh,000h   ; 14h
        db 03Fh,070h,03Eh,063h,063h,03Eh,007h,07Eh   ; 15h
        db 000h,000h,000h,000h,0FFh,0FFh,0FFh,000h   ; 16h
        db 03Ch,07Eh,018h,018h,07Eh,03Ch,018h,07Eh   ; 17h
        db 018h,03Ch,07Eh,018h,018h,018h,018h,000h   ; 18h
        db 018h,018h,018h,018h,07Eh,03Ch,018h,000h   ; 19h
        db 018h,00Ch,006h,07Fh,006h,00Ch,018h,000h   ; 1Ah
        db 00Ch,018h,030h,07Fh,030h,018h,00Ch,000h   ; 1Bh
        db 000h,000h,000h,060h,060h,07Fh,000h,000h   ; 1Ch
        db 000h,024h,066h,0FFh,066h,024h,000h,000h   ; 1Dh
        db 008h,01Ch,01Ch,03Eh,03Eh,07Fh,07Fh,000h   ; 1Eh
        db 07Fh,07Fh,03Eh,03Eh,01Ch,01Ch,008h,000h   ; 1Fh
        db 000h,000h,000h,000h,000h,000h,000h,000h   ; 20h
        db 018h,018h,018h,018h,018h,000h,018h,000h   ; 21h !
        db 033h,066h,0CCh,000h,000h,000h,000h,000h   ; 22h
        db 036h,036h,07Fh,036h,036h,07Fh,036h,036h   ; 23h #
        db 018h,07Eh,058h,038h,01Ch,01Ah,07Eh,018h   ; 24h $
        db 0E3h,0A6h,0ECh,018h,037h,065h,0C7h,000h   ; 25h %
        db 03Ch,066h,03Ch,038h,06Dh,066h,03Dh,000h   ; 26h &
        db 006h,00Ch,018h,000h,000h,000h,000h,000h   ; 27h
        db 01Ch,030h,060h,060h,060h,030h,01Ch,000h   ; 28h (
        db 038h,00Ch,006h,006h,006h,00Ch,038h,000h   ; 29h )
        db 063h,036h,01Ch,07Fh,01Ch,036h,063h,000h   ; 2Ah *
        db 018h,018h,018h,07Eh,018h,018h,018h,000h   ; 2Bh +
        db 000h,000h,000h,000h,000h,018h,018h,030h   ; 2Ch ,
        db 000h,000h,000h,07Eh,000h,000h,000h,000h   ; 2Dh -
        db 000h,000h,000h,000h,000h,018h,018h,000h   ; 2Eh .
        db 002h,006h,00Ch,018h,030h,060h,040h,000h   ; 2Fh /
        db 03Eh,063h,063h,06Bh,063h,063h,03Eh,000h   ; 30h 0
        db 01Ch,03Ch,00Ch,00Ch,00Ch,00Ch,00Ch,000h   ; 31h 1
        db 03Eh,063h,003h,00Eh,038h,060h,07Fh,000h   ; 32h 2
        db 07Ch,006h,006h,03Ch,006h,006h,07Ch,000h   ; 33h 3
        db 00Eh,01Eh,036h,066h,07Fh,006h,006h,000h   ; 34h 4
        db 07Eh,060h,07Ch,006h,006h,006h,07Ch,000h   ; 35h 5
        db 01Eh,030h,060h,07Eh,063h,063h,03Eh,000h   ; 36h 6
        db 07Eh,066h,00Ch,018h,030h,030h,030h,000h   ; 37h 7
        db 03Eh,063h,036h,01Ch,036h,063h,03Eh,000h   ; 38h 8
        db 03Eh,063h,063h,03Fh,003h,006h,07Ch,000h   ; 39h 9
        db 000h,000h,018h,018h,000h,018h,018h,000h   ; 3Ah :
        db 000h,000h,018h,018h,000h,018h,018h,030h   ; 3Bh
        db 00Ch,018h,030h,060h,030h,018h,00Ch,000h   ; 3Ch <
        db 000h,000h,07Eh,000h,07Eh,000h,000h,000h   ; 3Dh =
        db 030h,018h,00Ch,006h,00Ch,018h,030h,000h   ; 3Eh >
        db 03Eh,063h,006h,00Ch,00Ch,000h,00Ch,000h   ; 3Fh ?
        db 03Eh,063h,06Fh,069h,06Fh,060h,03Fh,000h   ; 40h @
        db 03Ch,066h,066h,07Eh,066h,066h,066h,000h   ; 41h A
        db 07Eh,063h,063h,07Eh,063h,063h,07Eh,000h   ; 42h B
        db 01Eh,033h,060h,060h,060h,033h,01Eh,000h   ; 43h C
        db 07Ch,066h,063h,063h,063h,066h,07Ch,000h   ; 44h D
        db 07Eh,060h,060h,07Ch,060h,060h,07Eh,000h   ; 45h E
        db 07Eh,060h,060h,07Ch,060h,060h,060h,000h   ; 46h F
        db 01Eh,033h,063h,060h,067h,033h,01Eh,000h   ; 47h G
        db 063h,063h,063h,07Fh,063h,063h,063h,000h   ; 48h H
        db 03Ch,018h,018h,018h,018h,018h,03Ch,000h   ; 49h I
        db 006h,006h,006h,006h,066h,066h,03Ch,000h   ; 4Ah J
        db 063h,066h,06Ch,078h,06Ch,066h,063h,000h   ; 4Bh K
        db 030h,030h,030h,030h,030h,030h,03Fh,000h   ; 4Ch L
        db 063h,077h,07Fh,06Bh,063h,063h,063h,000h   ; 4Dh M
        db 063h,073h,07Bh,06Fh,067h,063h,063h,000h   ; 4Eh N
        db 03Eh,063h,063h,063h,063h,063h,03Eh,000h   ; 4Fh O
        db 07Eh,063h,063h,07Eh,060h,060h,060h,000h   ; 50h P
        db 03Eh,063h,063h,063h,07Bh,06Eh,03Ch,007h   ; 51h Q
        db 07Eh,063h,063h,07Eh,06Ch,066h,063h,000h   ; 52h R
        db 03Eh,063h,030h,01Ch,006h,063h,03Eh,000h   ; 53h S
        db 07Eh,018h,018h,018h,018h,018h,018h,000h   ; 54h T
        db 063h,063h,063h,063h,063h,063h,03Eh,000h   ; 55h U
        db 063h,063h,063h,063h,036h,01Ch,008h,000h   ; 56h V
        db 063h,063h,063h,06Bh,06Bh,07Fh,036h,000h   ; 57h W
        db 063h,063h,036h,01Ch,036h,063h,063h,000h   ; 58h X
        db 063h,063h,063h,03Eh,00Ch,00Ch,00Ch,000h   ; 59h Y
        db 07Fh,006h,00Ch,018h,030h,060h,07Fh,000h   ; 5Ah Z
        db 03Eh,030h,030h,030h,030h,030h,03Eh,000h   ; 5Bh [
        db 040h,060h,030h,018h,00Ch,006h,002h,000h   ; 5Ch
        db 03Eh,006h,006h,006h,006h,006h,03Eh,000h   ; 5Dh ]
        db 01Ch,036h,063h,000h,000h,000h,000h,000h   ; 5Eh ^
        db 000h,000h,000h,000h,000h,000h,000h,0FFh   ; 5Fh _
        db 030h,018h,00Ch,000h,000h,000h,000h,000h   ; 60h `
        db 000h,000h,03Ch,006h,03Eh,066h,03Fh,000h   ; 61h a
        db 060h,060h,07Ch,066h,066h,066h,07Ch,000h   ; 62h b
        db 000h,000h,03Eh,063h,060h,060h,03Fh,000h   ; 63h c
        db 006h,006h,03Eh,066h,066h,066h,03Eh,000h   ; 64h d
        db 000h,000h,03Ch,066h,07Ch,060h,03Eh,000h   ; 65h e
        db 01Eh,030h,030h,07Ch,030h,030h,030h,000h   ; 66h f
        db 000h,000h,03Fh,063h,063h,03Fh,003h,07Eh   ; 67h g
        db 060h,060h,06Ch,076h,066h,066h,066h,000h   ; 68h h
        db 018h,000h,038h,018h,018h,018h,018h,000h   ; 69h i
        db 006h,000h,006h,006h,006h,006h,066h,03Ch   ; 6Ah j
        db 060h,060h,066h,06Ch,078h,06Ch,066h,000h   ; 6Bh k
        db 018h,018h,018h,018h,018h,018h,00Ch,000h   ; 6Ch l
        db 000h,000h,076h,07Fh,06Bh,06Bh,063h,000h   ; 6Dh m
        db 000h,000h,06Ch,076h,066h,066h,066h,000h   ; 6Eh n
        db 000h,000h,03Eh,063h,063h,063h,03Eh,000h   ; 6Fh o
        db 000h,000h,07Ch,066h,066h,07Ch,060h,060h   ; 70h p
        db 000h,000h,03Eh,066h,066h,03Eh,006h,006h   ; 71h q
        db 000h,000h,036h,03Bh,030h,030h,030h,000h   ; 72h r
        db 000h,000h,03Eh,070h,03Ch,00Eh,07Ch,000h   ; 73h s
        db 018h,018h,07Eh,018h,018h,018h,00Eh,000h   ; 74h t
        db 000h,000h,066h,066h,066h,066h,03Bh,000h   ; 75h u
        db 000h,000h,066h,066h,066h,03Ch,018h,000h   ; 76h v
        db 000h,000h,063h,063h,06Bh,07Fh,036h,000h   ; 77h w
        db 000h,000h,063h,036h,01Ch,036h,063h,000h   ; 78h x
        db 000h,000h,066h,066h,066h,03Eh,006h,07Ch   ; 79h y
        db 000h,000h,07Eh,00Ch,018h,030h,07Eh,000h   ; 7Ah z
        db 00Eh,018h,018h,078h,018h,018h,00Eh,000h   ; 7Bh {
        db 018h,018h,018h,000h,018h,018h,018h,000h   ; 7Ch |
        db 070h,018h,018h,00Eh,018h,018h,070h,000h   ; 7Dh }
        db 03Bh,06Eh,000h,000h,000h,000h,000h,000h   ; 7Eh ~
        db 018h,03Ch,066h,0C3h,0C3h,0FFh,000h,000h   ; 7Fh
        db 03Eh,063h,060h,060h,063h,03Eh,018h,030h   ; 80h
        db 066h,000h,066h,066h,066h,066h,03Bh,000h   ; 81h
        db 00Ch,010h,03Ch,066h,07Ch,060h,03Eh,000h   ; 82h
        db 03Eh,041h,01Ch,006h,03Eh,066h,03Fh,000h   ; 83h
        db 036h,000h,03Ch,006h,03Eh,066h,03Fh,000h   ; 84h
        db 018h,008h,03Ch,006h,03Eh,066h,03Fh,000h   ; 85h
        db 03Ch,066h,03Ch,006h,03Eh,066h,03Fh,000h   ; 86h
        db 000h,000h,03Eh,060h,060h,03Eh,018h,030h   ; 87h
        db 07Eh,0C3h,03Ch,066h,07Ch,060h,03Eh,000h   ; 88h
        db 036h,000h,03Ch,066h,07Ch,060h,03Eh,000h   ; 89h
        db 018h,008h,03Ch,066h,07Ch,060h,03Eh,000h   ; 8Ah
        db 06Ch,000h,038h,018h,018h,018h,018h,000h   ; 8Bh
        db 03Eh,041h,01Ch,00Ch,00Ch,00Ch,00Ch,000h   ; 8Ch
        db 00Ch,004h,038h,018h,018h,018h,018h,000h   ; 8Dh
        db 066h,018h,03Ch,066h,07Eh,066h,066h,000h   ; 8Eh
        db 018h,024h,03Ch,066h,07Eh,066h,066h,000h   ; 8Fh
        db 00Ch,07Eh,060h,07Ch,060h,060h,07Eh,000h   ; 90h
        db 000h,000h,07Eh,019h,03Fh,04Ch,077h,000h   ; 91h
        db 01Fh,036h,066h,07Fh,066h,066h,067h,000h   ; 92h
        db 07Eh,081h,03Ch,066h,066h,066h,03Ch,000h   ; 93h
        db 066h,000h,03Ch,066h,066h,066h,03Ch,000h   ; 94h
        db 018h,008h,03Ch,066h,066h,066h,03Ch,000h   ; 95h
        db 07Eh,081h,066h,066h,066h,066h,03Bh,000h   ; 96h
        db 018h,008h,066h,066h,066h,066h,03Bh,000h   ; 97h
        db 036h,000h,063h,063h,063h,03Fh,003h,07Eh   ; 98h
        db 063h,000h,03Eh,063h,063h,063h,063h,03Eh   ; 99h
        db 063h,000h,063h,063h,063h,063h,063h,03Eh   ; 9Ah
        db 008h,008h,03Eh,060h,060h,03Eh,008h,008h   ; 9Bh
        db 00Fh,019h,018h,07Eh,018h,018h,07Fh,000h   ; 9Ch
        db 066h,066h,03Ch,07Eh,018h,07Eh,018h,018h   ; 9Dh
        db 07Ch,066h,066h,07Ch,064h,06Fh,064h,067h   ; 9Eh
        db 007h,00Dh,00Ch,03Fh,00Ch,00Ch,04Ch,038h   ; 9Fh
        db 00Ch,010h,03Ch,006h,03Eh,066h,03Fh,000h   ; A0h
        db 018h,020h,01Ch,00Ch,00Ch,00Ch,00Ch,000h   ; A1h
        db 00Ch,010h,03Eh,063h,063h,063h,03Eh,000h   ; A2h
        db 00Ch,010h,066h,066h,066h,066h,03Bh,000h   ; A3h
        db 071h,08Eh,06Ch,076h,066h,066h,066h,000h   ; A4h
        db 073h,08Ch,063h,073h,06Bh,067h,063h,000h   ; A5h
        db 03Eh,066h,03Fh,000h,07Fh,000h,000h,000h   ; A6h
        db 03Ch,066h,03Ch,000h,07Eh,000h,000h,000h   ; A7h
        db 018h,000h,018h,018h,030h,063h,063h,03Eh   ; A8h
        db 000h,000h,07Fh,060h,060h,060h,060h,000h   ; A9h
        db 000h,000h,07Fh,003h,003h,003h,003h,000h   ; AAh
        db 063h,066h,06Ch,01Fh,031h,067h,04Ch,04Fh   ; ABh
        db 063h,066h,06Ch,01Bh,035h,069h,04Fh,041h   ; ACh
        db 018h,000h,018h,018h,018h,018h,018h,018h   ; ADh
        db 000h,033h,066h,0CCh,066h,033h,000h,000h   ; AEh
        db 000h,0CCh,066h,033h,066h,0CCh,000h,000h   ; AFh
        db 011h,044h,011h,044h,011h,044h,011h,044h   ; B0h
        db 055h,0AAh,055h,0AAh,055h,0AAh,055h,0AAh   ; B1h
        db 0DDh,077h,0DDh,077h,0DDh,077h,0DDh,077h   ; B2h
        db 018h,018h,018h,018h,018h,018h,018h,018h   ; B3h
        db 018h,018h,018h,018h,0F8h,018h,018h,018h   ; B4h
        db 018h,018h,0F8h,018h,0F8h,018h,018h,018h   ; B5h
        db 036h,036h,036h,036h,0F6h,036h,036h,036h   ; B6h
        db 000h,000h,000h,000h,0FEh,036h,036h,036h   ; B7h
        db 000h,000h,0F8h,018h,0F8h,018h,018h,018h   ; B8h
        db 036h,036h,0F6h,006h,0F6h,036h,036h,036h   ; B9h
        db 036h,036h,036h,036h,036h,036h,036h,036h   ; BAh
        db 000h,000h,0FEh,006h,0F6h,036h,036h,036h   ; BBh
        db 036h,036h,0F6h,006h,0FEh,000h,000h,000h   ; BCh
        db 036h,036h,036h,036h,0FEh,000h,000h,000h   ; BDh
        db 018h,018h,0F8h,018h,0F8h,000h,000h,000h   ; BEh
        db 000h,000h,000h,000h,0F8h,018h,018h,018h   ; BFh
        db 018h,018h,018h,018h,01Fh,000h,000h,000h   ; C0h
        db 018h,018h,018h,018h,0FFh,000h,000h,000h   ; C1h
        db 000h,000h,000h,000h,0FFh,018h,018h,018h   ; C2h
        db 018h,018h,018h,018h,01Fh,018h,018h,018h   ; C3h
        db 000h,000h,000h,000h,0FFh,000h,000h,000h   ; C4h
        db 018h,018h,018h,018h,0FFh,018h,018h,018h   ; C5h
        db 018h,018h,01Fh,018h,01Fh,018h,018h,018h   ; C6h
        db 036h,036h,036h,036h,037h,036h,036h,036h   ; C7h
        db 036h,036h,037h,030h,03Fh,000h,000h,000h   ; C8h
        db 000h,000h,03Fh,030h,037h,036h,036h,036h   ; C9h
        db 036h,036h,0F7h,000h,0FFh,000h,000h,000h   ; CAh
        db 000h,000h,0FFh,000h,0F7h,036h,036h,036h   ; CBh
        db 036h,036h,037h,030h,037h,036h,036h,036h   ; CCh
        db 000h,000h,0FFh,000h,0FFh,000h,000h,000h   ; CDh
        db 036h,036h,0F7h,000h,0F7h,036h,036h,036h   ; CEh
        db 018h,018h,0FFh,000h,0FFh,000h,000h,000h   ; CFh
        db 036h,036h,036h,036h,0FFh,000h,000h,000h   ; D0h
        db 000h,000h,0FFh,000h,0FFh,018h,018h,018h   ; D1h
        db 000h,000h,000h,000h,0FFh,036h,036h,036h   ; D2h
        db 036h,036h,036h,036h,03Fh,000h,000h,000h   ; D3h
        db 018h,018h,01Fh,018h,01Fh,000h,000h,000h   ; D4h
        db 000h,000h,01Fh,018h,01Fh,018h,018h,018h   ; D5h
        db 000h,000h,000h,000h,03Fh,036h,036h,036h   ; D6h
        db 036h,036h,036h,036h,0FFh,036h,036h,036h   ; D7h
        db 018h,018h,0FFh,018h,0FFh,018h,018h,018h   ; D8h
        db 018h,018h,018h,018h,0F8h,000h,000h,000h   ; D9h
        db 000h,000h,000h,000h,01Fh,018h,018h,018h   ; DAh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh   ; DBh
        db 000h,000h,000h,0FFh,0FFh,0FFh,0FFh,0FFh   ; DCh
        db 0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h,0F0h   ; DDh
        db 00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh,00Fh   ; DEh
        db 0FFh,0FFh,0FFh,0FFh,0FFh,000h,000h,000h   ; DFh
        db 000h,000h,07Bh,0CEh,0CCh,0CEh,07Bh,000h   ; E0h
        db 03Ch,066h,066h,06Eh,063h,063h,06Eh,000h   ; E1h
        db 03Fh,033h,030h,030h,030h,030h,030h,000h   ; E2h
        db 000h,000h,07Fh,0B6h,036h,036h,036h,000h   ; E3h
        db 07Fh,071h,038h,01Ch,038h,071h,07Fh,000h   ; E4h
        db 000h,000h,03Fh,066h,066h,066h,03Ch,000h   ; E5h
        db 000h,000h,066h,066h,066h,07Bh,060h,060h   ; E6h
        db 000h,000h,03Fh,04Ch,00Ch,00Ch,00Ch,000h   ; E7h
        db 018h,07Eh,0DBh,0DBh,0DBh,07Eh,018h,000h   ; E8h
        db 03Ch,066h,0C3h,0BDh,0C3h,066h,03Ch,000h   ; E9h
        db 03Ch,066h,0C3h,0C3h,0C3h,066h,0E7h,000h   ; EAh
        db 03Eh,070h,03Ch,066h,066h,066h,03Ch,000h   ; EBh
        db 000h,000h,07Eh,0DBh,0DBh,07Eh,000h,000h   ; ECh
        db 018h,018h,07Eh,0DBh,0DBh,07Eh,018h,018h   ; EDh
        db 000h,000h,03Eh,060h,03Ch,060h,03Eh,000h   ; EEh
        db 03Eh,063h,063h,063h,063h,063h,063h,000h   ; EFh
        db 07Fh,000h,000h,07Fh,000h,000h,07Fh,000h   ; F0h
        db 018h,018h,07Eh,018h,018h,000h,07Eh,000h   ; F1h
        db 038h,01Ch,00Eh,01Ch,038h,000h,07Eh,000h   ; F2h
        db 01Ch,038h,070h,038h,01Ch,000h,07Eh,000h   ; F3h
        db 00Eh,01Bh,01Bh,018h,018h,018h,018h,018h   ; F4h
        db 018h,018h,018h,018h,018h,0D8h,0D8h,070h   ; F5h
        db 000h,018h,000h,07Eh,000h,018h,000h,000h   ; F6h
        db 000h,000h,03Bh,06Eh,000h,03Bh,06Eh,000h   ; F7h
        db 000h,03Ch,066h,03Ch,000h,000h,000h,000h   ; F8h
        db 000h,000h,018h,03Ch,018h,000h,000h,000h   ; F9h
        db 000h,000h,000h,018h,000h,000h,000h,000h   ; FAh
        db 00Fh,00Ch,00Ch,08Ch,0CCh,06Ch,03Ch,018h   ; FBh
        db 06Ch,036h,036h,036h,000h,000h,000h,000h   ; FCh
        db 07Ch,00Eh,03Ch,060h,07Eh,000h,000h,000h   ; FDh
        db 000h,000h,07Ch,07Ch,07Ch,07Ch,07Ch,07Ch   ; FEh
        db 000h,000h,000h,000h,000h,000h,000h,000h   ; FFh
