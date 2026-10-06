# Build a C program for the RV32I core.
#   make            builds hello (elf, hex, disassembly)
#   make PROG=foo   builds foo.c instead
#   make spike      runs it on Spike
#   make trace      runs it on Spike and saves the commit log
#   make clean

CROSS   ?= riscv-none-elf-
CC      := $(CROSS)gcc
OBJCOPY := $(CROSS)objcopy
OBJDUMP := $(CROSS)objdump

ARCH    := -march=rv32i -mabi=ilp32
CFLAGS  := $(ARCH) -O2 -ffreestanding -nostdlib -fno-builtin -Wall -Wextra
LDFLAGS := -T linker.ld -Wl,--no-warn-rwx-segments
LIBS    := -lgcc

PROG    ?= hello
BUILD   := build
ELF     := $(BUILD)/$(PROG).elf

all: $(BUILD)/$(PROG).hex $(BUILD)/$(PROG).dump

$(BUILD):
	mkdir -p $@

$(ELF): crt0.S lib.c $(PROG).c linker.ld | $(BUILD)
	$(CC) $(CFLAGS) $(LDFLAGS) crt0.S lib.c $(PROG).c $(LIBS) -o $@

$(BUILD)/$(PROG).bin: $(ELF)
	$(OBJCOPY) -O binary $< $@

$(BUILD)/$(PROG).hex: $(BUILD)/$(PROG).bin
	python3 ../scripts/bin2hex.py $< $@

$(BUILD)/$(PROG).dump: $(ELF)
	$(OBJDUMP) -d $< > $@

spike: $(ELF)
	spike --isa=rv32i_zicsr $< && echo "PASS" || echo "FAIL (exit code $$?)"

trace: $(ELF)
	spike --isa=rv32i_zicsr --log-commits $< 2> $(BUILD)/$(PROG).spike.log; \
	echo "Trace saved to $(BUILD)/$(PROG).spike.log"

clean:
	rm -rf $(BUILD)

.PHONY: all spike trace clean
