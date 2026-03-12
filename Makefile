BUILD_DIR := build
ISO_DIR := $(BUILD_DIR)/iso
DIST_DIR := dist

all: $(DIST_DIR)/crispy-funicular.iso

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(ISO_DIR): | $(BUILD_DIR)
	mkdir -p $(ISO_DIR)

$(DIST_DIR):
	mkdir -p $(DIST_DIR)

$(BUILD_DIR)/bootloader.bin: bootloader.asm | $(BUILD_DIR)
	nasm -f bin bootloader.asm -o $@

$(BUILD_DIR)/kernel_entry.o: kernel_entry.asm | $(BUILD_DIR)
	nasm -f elf32 kernel_entry.asm -o $@

$(BUILD_DIR)/kernel.o: kernel.c | $(BUILD_DIR)
	gcc -m32 -ffreestanding -fno-pic -fno-stack-protector -nostdlib -nodefaultlibs -c kernel.c -o $@

$(BUILD_DIR)/kernel.elf: $(BUILD_DIR)/kernel_entry.o $(BUILD_DIR)/kernel.o linker.ld | $(BUILD_DIR)
	ld -m elf_i386 -T linker.ld -nostdlib -o $@ $(BUILD_DIR)/kernel_entry.o $(BUILD_DIR)/kernel.o

$(BUILD_DIR)/kernel.bin: $(BUILD_DIR)/kernel.elf
	objcopy -O binary $< $@

$(BUILD_DIR)/os.flp: $(BUILD_DIR)/bootloader.bin $(BUILD_DIR)/kernel.bin | $(BUILD_DIR)
	dd if=/dev/zero of=$@ bs=512 count=2880 status=none
	dd if=$(BUILD_DIR)/bootloader.bin of=$@ conv=notrunc status=none
	dd if=$(BUILD_DIR)/kernel.bin of=$@ bs=512 seek=1 conv=notrunc status=none

$(DIST_DIR)/crispy-funicular.iso: $(BUILD_DIR)/os.flp | $(ISO_DIR) $(DIST_DIR)
	python3 tools_create_iso.py $(BUILD_DIR)/os.flp $@

run: $(DIST_DIR)/crispy-funicular.iso
	qemu-system-i386 -cdrom $(DIST_DIR)/crispy-funicular.iso

clean:
	rm -rf $(BUILD_DIR) $(DIST_DIR)

.PHONY: all run clean
