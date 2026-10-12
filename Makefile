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

.PHONY: test lint sim hello isa random coremark check deps clean
