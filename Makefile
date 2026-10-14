# RV32I core: unit tests, full-core simulation, tests against Spike, benchmarks.
#
#   make deps        download riscv-tests and CoreMark into tests/ (once)
#   make test        unit test every module
#   make lint        Verilator lint on all RTL
#   make sim         build the three core simulators
#   make hello       run sw/hello.c and compare every instruction with Spike
#   make isa         official rv32ui tests, each compared with Spike
#   make random      random programs compared with Spike (N=200; try N=1000)
#   make coremark    CoreMark on all three cores, with CPI
#   make check       everything: lint, test, hello, isa, random
#   make images      pipeline diagram, waveform and results card into docs/img
#   make fpga        DE2-115 build files: CoreMark image + Verilog for Quartus
#   make fpga_sim    simulate the whole DE2-115 design running CoreMark
#   make clean
#
# CORE picks the core for hello / isa / random:
#   single      single-cycle core (rtl/core.sv)
#   pipe        5-stage pipeline with branch predictor (default)
#   pipe_nobtb  5-stage pipeline, no branch predictor

VERILATOR := verilator
VFLAGS    := --binary --timing -Wall -Wno-DECLFILENAME -j 0

CROSS ?= riscv-none-elf-
SPIKE ?= spike
CORE  ?= pipe
N     ?= 200
export CROSS SPIKE CORE

PKG      := rtl/rv_pkg.sv
CORE_RTL := $(PKG) rtl/alu.sv rtl/regfile.sv rtl/immgen.sv rtl/decoder.sv rtl/lsu.sv rtl/mem.sv
RV       := python3 scripts/rv.py

# ---------------- unit tests ----------------
UNITS       := alu regfile immgen decoder lsu mem
SRC_alu     := $(PKG) rtl/alu.sv
SRC_regfile := rtl/regfile.sv
SRC_immgen  := $(PKG) rtl/immgen.sv
SRC_decoder := $(PKG) rtl/decoder.sv
SRC_lsu     := rtl/lsu.sv
SRC_mem     := rtl/mem.sv
ARGS_mem    := +hex=tb/mem_init.hex

test: $(addprefix test_,$(UNITS))

# Build and run one unit testbench; fail unless it prints PASS.
test_%:
	mkdir -p build/$*
	$(VERILATOR) $(VFLAGS) --top-module tb_$* -Mdir build/$* $(SRC_$*) tb/tb_$*.sv > build/$*/build.log
	./build/$*/Vtb_$* $(ARGS_$*) | tee build/$*/run.log | grep -E '^(PASS|FAIL|MISMATCH)'
	@grep -q '^PASS' build/$*/run.log

lint:
	$(VERILATOR) --lint-only -Wall $(PKG) rtl/alu.sv --top-module alu
	$(VERILATOR) --lint-only -Wall rtl/regfile.sv --top-module regfile
	$(VERILATOR) --lint-only -Wall $(PKG) rtl/immgen.sv --top-module immgen
	$(VERILATOR) --lint-only -Wall $(PKG) rtl/decoder.sv --top-module decoder
	$(VERILATOR) --lint-only -Wall rtl/lsu.sv --top-module lsu
	$(VERILATOR) --lint-only -Wall rtl/mem.sv --top-module mem
	$(VERILATOR) --lint-only -Wall $(CORE_RTL) rtl/core.sv --top-module core
	$(VERILATOR) --lint-only -Wall $(CORE_RTL) rtl/core_pipe.sv --top-module core_pipe

# ---------------- core simulators ----------------
SIMS := build/single/Vtb_core build/pipe/Vtb_core build/pipe_nobtb/Vtb_core

sim: $(SIMS)

build/single/Vtb_core: $(CORE_RTL) rtl/core.sv tb/tb_core.sv
	mkdir -p build/single
	$(VERILATOR) $(VFLAGS) --top-module tb_core -Mdir build/single \
	  $(CORE_RTL) rtl/core.sv tb/tb_core.sv > build/single/build.log

build/pipe/Vtb_core: $(CORE_RTL) rtl/core_pipe.sv tb/tb_core.sv
	mkdir -p build/pipe
	$(VERILATOR) $(VFLAGS) --top-module tb_core -Mdir build/pipe +define+PIPELINE \
	  $(CORE_RTL) rtl/core_pipe.sv tb/tb_core.sv > build/pipe/build.log

build/pipe_nobtb/Vtb_core: $(CORE_RTL) rtl/core_pipe.sv tb/tb_core.sv
	mkdir -p build/pipe_nobtb
	$(VERILATOR) $(VFLAGS) --top-module tb_core -Mdir build/pipe_nobtb +define+PIPELINE -GBTB=0 \
	  $(CORE_RTL) rtl/core_pipe.sv tb/tb_core.sv > build/pipe_nobtb/build.log

# ---------------- programs ----------------
hello: sim
	$(MAKE) -C sw
	$(RV) compare sw/build/hello.elf

isa: sim
	$(RV) isa

random: sim
	$(RV) random -n $(N)

coremark: sim
	$(MAKE) -C sw coremark
	@for c in single pipe_nobtb pipe; do \
	  echo "== $$c"; \
	  CORE=$$c $(RV) run sw/build/coremark.elf --max-cycles 100000000 | grep -E 'Total ticks|crcfinal|^PASS|^FAIL'; \
	done

check: lint test hello isa random

# ---------------- third-party test suites ----------------
deps:
	test -d tests/riscv-tests || git clone --depth 1 https://github.com/riscv-software-src/riscv-tests tests/riscv-tests
	test -d tests/coremark || git clone --depth 1 https://github.com/eembc/coremark tests/coremark

clean:
	rm -rf build tests/build
	$(MAKE) -C sw clean

.PHONY: fpga fpga_sim images test lint sim hello isa random coremark check deps clean

# ---------------- images for the README ----------------
DEMO := sw/build/pipeline_demo
images: build/pipe/Vtb_core
	mkdir -p sw/build
	$(CROSS)gcc -march=rv32i -mabi=ilp32 -nostdlib -Wl,--no-warn-rwx-segments -T sw/linker.ld -o $(DEMO).elf sw/demo/pipeline_demo.S
	$(CROSS)objcopy -O binary $(DEMO).elf $(DEMO).bin
	python3 scripts/bin2hex.py $(DEMO).bin $(DEMO).hex
	$(CROSS)objdump -d $(DEMO).elf > $(DEMO).dump
	./build/pipe/Vtb_core +hex=$(DEMO).hex +tohost=$$($(CROSS)nm $(DEMO).elf | awk '/ tohost$$/{print $$1}') +pipeview=build/demo.pv
	python3 scripts/pipeview.py build/demo.pv $(DEMO).dump docs/img
	python3 scripts/results_card.py

# ---------------- DE2-115 FPGA (Cyclone IV) ----------------
# Quartus gets one plain-Verilog file made from our SystemVerilog by sv2v,
# so it compiles the same on any Quartus version.
SV2V     ?= sv2v
FPGA_DIR := fpga/de2_115
FPGA_RTL := $(PKG) rtl/alu.sv rtl/regfile.sv rtl/immgen.sv rtl/decoder.sv rtl/lsu.sv rtl/core_pipe.sv \
            $(FPGA_DIR)/fpga_mem.sv $(FPGA_DIR)/uart_tx.sv $(FPGA_DIR)/hex7seg.sv $(FPGA_DIR)/de2_115_top.sv
FPGA_ITER ?= 700

# Real build: 700 CoreMark iterations, about 12 seconds at 50 MHz (CoreMark needs at least 10).
fpga:
	rm -f sw/build/coremark/ee_printf.c
	$(MAKE) -C sw coremark CM_ITER=$(FPGA_ITER) CM_CLOCK=50000000 CM_NAME=coremark_fpga
	$(CROSS)objcopy -O binary sw/build/coremark_fpga.elf sw/build/coremark_fpga.bin
	python3 scripts/fpga_hex.py sw/build/coremark_fpga.bin $(FPGA_DIR)/mem
	$(VERILATOR) --lint-only -Wall -Wno-DECLFILENAME --top-module de2_115_top $(FPGA_RTL)
	T=$$($(CROSS)nm sw/build/coremark_fpga.elf | awk '/ tohost$$/{print $$1}'); \
	  $(SV2V) --define=TOHOST_ADDR="32'h$$T" $(FPGA_RTL) > $(FPGA_DIR)/rv32i_de2_115.v
	@echo "Done. Open $(FPGA_DIR)/rv32i_de2_115.qpf in Quartus and compile."

# Simulation of the board: 2 iterations, with a fake 100 kHz clock so CoreMark's
# "must run 10 seconds" check passes, and a fast UART.
fpga_sim:
	rm -f sw/build/coremark/ee_printf.c
	$(MAKE) -C sw coremark CM_ITER=2 CM_CLOCK=100000 CM_NAME=coremark_fsim
	$(CROSS)objcopy -O binary sw/build/coremark_fsim.elf sw/build/coremark_fsim.bin
	python3 scripts/fpga_hex.py sw/build/coremark_fsim.bin build/fpga_sim/mem
	T=$$($(CROSS)nm sw/build/coremark_fsim.elf | awk '/ tohost$$/{print $$1}'); \
	  $(SV2V) --define=TOHOST_ADDR="32'h$$T" $(FPGA_RTL) > build/fpga_sim/top.v
	$(VERILATOR) --binary --timing -j 0 -Wno-fatal -Wno-lint -Wno-style --top-module tb_de2_115 \
	  -Mdir build/fpga_sim/obj +define+INITDIR='"build/fpga_sim/mem/"' \
	  build/fpga_sim/top.v $(FPGA_DIR)/tb_de2_115.sv > build/fpga_sim/build.log
	./build/fpga_sim/obj/Vtb_de2_115 | tee build/fpga_sim/run.log
	@grep -q '^PASS' build/fpga_sim/run.log
