;VRI image reference file
;Beginning with HEADER

;Constants
version equ 0x01

;Actual header
;First is the unique signature
db 'VRI', 0

;Next two bytes are bytes for version
dw version

;Next 256 bytes specify additional information for use in future implementations of the format
times 256 db 0x00

;Next 4 bytes are the size of the memory descriptor table
dd memdesctable_end-memdesctable_beg

;Next 4 bytes are the absolute offset to the beginning of the memory descriptor table
dd memdesctable_beg

;The memory descriptor table
;Every entry in the table consists of 4x4 bytes:
;1. 32-bit file offset to the beginning of the memory part
;2. 32-bit size of the memory part
;3. 32-bit address in the memory space of the VM
;4. 32-bit bitfield, specifying various aspects about this memory region

memdesctable_beg:

;Entry 1
dd main_image_begin
dd main_image_end-main_image_begin
dd 0x000FE000 ;Place in the memory space - F000:E000
dd 0x00000000 ;Bits which specify various properties of the memory space.

;Entry 3
dd third_image_begin
dd third_image_end-third_image_begin
dd 0x000F6000 ;Place in the memory space - F600:0000
dd 0x00000000 ;Bits which specify various properties of the memory space.

;Entry 4
dd forth_image_begin
dd forth_image_end-third_image_begin
dd 0x000C0000 ;Place in the memory space - F600:0000
dd 0x00000000 ;Bits which specify various properties of the memory space.

memdesctable_end:

;FFFF:0000
ORG 0000
main_image_begin:
incbin "pcxtbios.bin"
main_image_end:

;F600:0000
ORG 0000
third_image_begin:
;incbin "program.bin"
incbin "rombasic.bin"
third_image_end:

;F600:0000
ORG 0000
forth_image_begin:
;incbin "program.bin"
incbin "disk_io.bin"
forth_image_end:

