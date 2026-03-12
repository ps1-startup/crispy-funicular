; BIOS bootloader for Crispy Funicular OS
; Loads kernel.bin from subsequent sectors into 0x10000 and enters protected mode.

BITS 16
ORG 0x7C00

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti

    mov [boot_drive], dl

    ; Set VGA mode 13h (320x200x256)
    mov ax, 0x0013
    int 0x10

    ; Try INT 13h extensions first (works for El Torito emulated/non-emulated devices)
    mov ah, 0x41
    mov bx, 0x55AA
    mov dl, [boot_drive]
    int 0x13
    jc .legacy_chs
    cmp bx, 0xAA55
    jne .legacy_chs
    test cx, 1
    jz .legacy_chs

    call load_kernel_lba
    jmp short .loaded

.legacy_chs:
    call load_kernel_chs

.loaded:
    cli
    lgdt [gdt_descriptor]

    mov eax, cr0
    or eax, 1
    mov cr0, eax

    jmp CODE_SEL:protected_mode_entry

; LBA loader via INT 13h AH=42h
load_kernel_lba:
    mov bx, 0x0000              ; destination offset in KERNEL_SEG
    mov di, KERNEL_SECTORS

    mov word [dap + 8], 1       ; starting LBA (sector after boot sector)
    mov word [dap + 10], 0
    mov dword [dap + 12], 0

.lba_loop:
    cmp di, 0
    je .done

    mov word [dap + 4], bx      ; buffer offset
    mov word [dap + 6], KERNEL_SEG
    mov si, dap
    mov ah, 0x42
    mov dl, [boot_drive]
    int 0x13
    jc disk_error

    add bx, 512
    inc word [dap + 8]
    dec di
    jmp .lba_loop

.done:
    ret

; Legacy CHS fallback for old BIOSes
load_kernel_chs:
    mov ax, KERNEL_SEG
    mov es, ax
    xor bx, bx
    mov si, 1
    mov di, KERNEL_SECTORS

.chs_loop:
    cmp di, 0
    je .done

    call lba_to_chs

    mov ah, 0x02
    mov al, 1
    mov dl, [boot_drive]
    int 0x13
    jc disk_error

    add bx, 512
    inc si
    dec di
    jmp .chs_loop

.done:
    ret

; Input: SI = LBA sector
; Output: CH = cylinder, DH = head, CL = sector (1-based)
lba_to_chs:
    push ax
    push bx
    push dx

    mov ax, si
    xor dx, dx
    mov bx, SECTORS_PER_TRACK
    div bx
    mov cl, dl
    inc cl

    xor dx, dx
    mov bx, HEADS
    div bx
    mov ch, al
    mov dh, dl

    pop dx
    pop bx
    pop ax
    ret

disk_error:
    mov si, disk_error_msg
.print:
    lodsb
    test al, al
    jz .halt
    mov ah, 0x0E
    int 0x10
    jmp .print
.halt:
    cli
    hlt

[BITS 32]
protected_mode_entry:
    mov ax, DATA_SEL
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x9FC00

    jmp KERNEL_LINEAR_ADDR

[BITS 16]

boot_drive db 0

disk_error_msg db 'Disk read error', 0

; INT 13h Extensions Disk Address Packet
; 00 size=16, 01 reserved, 02 sector count, 04 buffer offset, 06 buffer segment,
; 08 LBA (qword)
dap:
    db 16
    db 0
    dw 1
    dw 0
    dw KERNEL_SEG
    dd 1
    dd 0

SECTORS_PER_TRACK equ 18
HEADS equ 2
KERNEL_SEG equ 0x1000
KERNEL_LINEAR_ADDR equ 0x10000
%include "build/kernel_sectors.inc"

align 8
gdt_start:
    dq 0x0000000000000000
    dq 0x00CF9A000000FFFF
    dq 0x00CF92000000FFFF
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

CODE_SEL equ 0x08
DATA_SEL equ 0x10

times 510 - ($ - $$) db 0
dw 0xAA55
