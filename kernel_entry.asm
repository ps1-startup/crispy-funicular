BITS 32
global _start
extern kmain

section .text
_start:
    mov esp, 0x9F000
    call kmain
.hang:
    cli
    hlt
    jmp .hang
