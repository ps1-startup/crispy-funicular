# Crispy Funicular OS

A minimal from-scratch toy OS that boots from a BIOS `.iso`, loads `kernel.bin` via a custom bootloader, switches to 32-bit protected mode, draws a basic Windows 7-inspired desktop style in VGA mode 13h, and supports a PS/2 mouse cursor.

## Features

- Custom 512-byte bootloader (`bootloader.asm`) with BIOS disk reads.
- Kernel delivered as `kernel.bin`.
- Bootable ISO output: `dist/crispy-funicular.iso`.
- VGA 320x200 GUI scene with classic window-like decorations.
- PS/2 mouse polling and software cursor rendering.

## Build requirements

- `nasm`
- `gcc` with 32-bit support (`-m32`)
- `ld`, `objcopy`
- `python3`
- Optional: `qemu-system-i386` for testing

## Build

```bash
make
```

Output:

- ISO: `dist/crispy-funicular.iso`
- Intermediate kernel binary: `build/kernel.bin`

## Run in QEMU

```bash
make run
```
