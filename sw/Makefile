# Build a C program for the RV32I core.
#   make            builds hello (elf, hex, disassembly)
#   make PROG=foo   builds foo.c instead
#   make spike      runs it on Spike
#   make trace      runs it on Spike and saves the commit log
#   make coremark   builds CoreMark (needs tests/coremark, see below)
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

# ---- CoreMark ----
# Get the sources once with:
#   git clone https://github.com/eembc/coremark ../tests/coremark
# Our port is coremark/core_portme.c; the rest comes from CoreMark's
# barebones port, with the UART hook filled in.
CM_SRC  := ../tests/coremark
CM_ITER ?= 10
CM_DIR  := $(BUILD)/coremark

$(CM_DIR)/ee_printf.c: $(CM_SRC)/barebones/ee_printf.c | $(BUILD)
	mkdir -p $(CM_DIR)
	sed 's|^#error "You must implement the method uart_send_char.*|    *(volatile unsigned char *)0x10000000 = (unsigned char)c;|' $< > $@

coremark: $(CM_DIR)/ee_printf.c
	sed '1i #include <stddef.h>' $(CM_SRC)/barebones/core_portme.h > $(CM_DIR)/core_portme.h
	$(CC) $(ARCH) -O2 -ffreestanding -nostdlib -w -I$(CM_DIR) -I$(CM_SRC) \
	  -DPERFORMANCE_RUN=1 -DITERATIONS=$(CM_ITER) -DHAS_FLOAT=0 -DFLAGS_STR='"-O2 -march=rv32i"' \
	  $(LDFLAGS) crt0.S lib.c coremark/core_portme.c $(CM_DIR)/ee_printf.c \
	  $(CM_SRC)/core_list_join.c $(CM_SRC)/core_main.c $(CM_SRC)/core_matrix.c \
	  $(CM_SRC)/core_state.c $(CM_SRC)/core_util.c $(LIBS) -o $(BUILD)/coremark.elf
	$(OBJDUMP) -d $(BUILD)/coremark.elf > $(BUILD)/coremark.dump
	@$(CROSS)size $(BUILD)/coremark.elf

clean:
	rm -rf $(BUILD)

.PHONY: all spike trace coremark clean
