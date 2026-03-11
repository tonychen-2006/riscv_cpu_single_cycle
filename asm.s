.equ LEDR_OFFSET, 0x00
.equ HEX3_OFFSET, 0x20
.equ HEX5_OFFSET, 0x30
.equ SW_OFFSET,   0x40
.equ BASE_PTR, 0x80

lw t0, BASE_PTR(zero)

loop:

lw t1, SW_OFFSET(t0)

sw t1, LEDR_OFFSET(t0)

sw t1, HEX3_OFFSET(t0)

sw t1, HEX5_OFFSET(t0)

j loop

# End of program
.org BASE_PTR
BASE_ADDR:
.word 0xFF200000