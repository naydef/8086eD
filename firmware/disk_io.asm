USE16
CPU 186

db 0x55 ; Byte 1
db 0xAA ; Byte 2
db 0x10 ; Byte 3
start:
cli
xor ax, ax
mov ds, ax
mov word [ds:4Ch], int_13_handler
mov ax, cs
mov word [ds:4Eh], ax
retf


int_13_handler:
db 0xF3
db 0xF1
iret

; fill with zeroes till signature
times    8191-($-$$) db   0x00
db    0x00   ; checksum
