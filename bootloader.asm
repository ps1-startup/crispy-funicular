; Simple BIOS bootloader for Crispy Funicular OS
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

    ; Load kernel sectors from floppy image (starting at LBA 1)
    mov ax, KERNEL_SEG
    mov es, ax
    xor bx, bx

    mov si, 1                  ; LBA start (sector after boot sector)
    mov di, KERNEL_SECTORS     ; Number of sectors to load

.load_loop:
    cmp di, 0
    je .loaded

    call lba_to_chs

    mov ah, 0x02               ; BIOS read sectors
    mov al, 1                  ; read one sector per iteration
    mov dl, [boot_drive]
    int 0x13
    jc disk_error

    add bx, 512
    inc si
    dec di
    jmp .load_loop

.loaded:
    cli

    lgdt [gdt_descriptor]

    mov eax, cr0
    or eax, 1
    mov cr0, eax

    jmp CODE_SEL:protected_mode_entry

; Input: SI = LBA sector
; Output: CH = cylinder, DH = head, CL = sector (1-based)
lba_to_chs:
    push ax
    push bx
    push dx

    mov ax, si
    xor dx, dx
    mov bx, SECTORS_PER_TRACK
    div bx                      ; ax = temp, dx = sector index
    mov cl, dl
    inc cl

    xor dx, dx
    mov bx, HEADS
    div bx                      ; ax = cylinder, dx = head
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

disk_error_msg db 'Disk read error', 0
boot_drive db 0

SECTORS_PER_TRACK equ 18
HEADS equ 2
KERNEL_SEG equ 0x1000
KERNEL_LINEAR_ADDR equ 0x10000
KERNEL_SECTORS equ 64

; GDT
align 8
gdt_start:
    dq 0x0000000000000000      ; null
    dq 0x00CF9A000000FFFF      ; code 0x08
    dq 0x00CF92000000FFFF      ; data 0x10
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

CODE_SEL equ 0x08
DATA_SEL equ 0x10

times 510 - ($ - $$) db 0
dw 0xAA55
