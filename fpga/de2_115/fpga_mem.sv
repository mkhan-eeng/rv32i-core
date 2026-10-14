// Block RAM for the FPGA build, written in the plain style Quartus turns
// into M9K memory blocks. Both read synchronously (data appears after the
// clock edge), matching the mem.sv model the pipelined core is tested with.

// Instruction memory: 32-bit words, read-only, loaded from INIT_FILE.
module fpga_rom #(
  parameter int unsigned WORDS     = 8192,
  parameter              INIT_FILE = "imem.hex"
) (
  input  logic                     clk,
  input  logic [$clog2(WORDS)-1:0] addr,
  output logic [31:0]              rdata
);
  logic [31:0] rom [0:WORDS-1];
  initial $readmemh(INIT_FILE, rom);
  always_ff @(posedge clk) rdata <= rom[addr];
endmodule

// Data memory byte lane: 8-bit words. Four of these side by side make a
// 32-bit memory where each byte can be written on its own (sb, sh, sw).
module fpga_ram8 #(
  parameter int unsigned WORDS     = 8192,
  parameter              INIT_FILE = "dmem_b0.hex"
) (
  input  logic                     clk,
  input  logic [$clog2(WORDS)-1:0] addr,
  input  logic                     we,
  input  logic [7:0]               wdata,
  output logic [7:0]               rdata
);
  logic [7:0] ram [0:WORDS-1];
  initial $readmemh(INIT_FILE, ram);
  always_ff @(posedge clk) begin
    if (we) ram[addr] <= wdata;
    rdata <= ram[addr];               // old data on a write cycle (read-before-write)
  end
endmodule
