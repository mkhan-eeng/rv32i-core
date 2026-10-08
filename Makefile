# Simulation targets for the RV32I core.
#   make test_alu       build and run the ALU testbench
#   make test_regfile   build and run the register file testbench
#   make test_immgen    build and run the immediate generator testbench
#   make test           run every unit test
#   make lint           check all RTL for warnings
#   make clean

VERILATOR := verilator
VFLAGS    := --binary --timing -Wall -Wno-DECLFILENAME -j 0

PKG := rtl/rv_pkg.sv

test_alu:
	mkdir -p build/alu
	$(VERILATOR) $(VFLAGS) --top-module tb_alu -Mdir build/alu \
	  $(PKG) rtl/alu.sv tb/tb_alu.sv
	./build/alu/Vtb_alu

test_regfile:
	mkdir -p build/regfile
	$(VERILATOR) $(VFLAGS) --top-module tb_regfile -Mdir build/regfile \
	  rtl/regfile.sv tb/tb_regfile.sv
	./build/regfile/Vtb_regfile

test_immgen:
	mkdir -p build/immgen
	$(VERILATOR) $(VFLAGS) --top-module tb_immgen -Mdir build/immgen \
	  $(PKG) rtl/immgen.sv tb/tb_immgen.sv
	./build/immgen/Vtb_immgen

test: test_alu test_regfile test_immgen

lint:
	$(VERILATOR) --lint-only -Wall $(PKG) rtl/alu.sv --top-module alu
	$(VERILATOR) --lint-only -Wall rtl/regfile.sv --top-module regfile
	$(VERILATOR) --lint-only -Wall $(PKG) rtl/immgen.sv --top-module immgen

clean:
	rm -rf build

.PHONY: test_alu test_regfile test_immgen test lint clean