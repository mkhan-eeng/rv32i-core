// Simulation memory: SIZE_BYTES of RAM starting at BASE.
// Reads are combinational (needed by the single-cycle core).
// Writes happen on the rising clock edge, one enable per byte.
//
// At startup it loads the program given on the command line:
//   +hex=sw/build/hello.hex
// Line N of that file is the word at BASE + 4*N.
// Addresses outside the RAM read as 0 and writes to them are ignored.
module mem #(
  parameter int unsigned SIZE_BYTES = 32768,
  parameter logic [31:0] BASE       = 32'h8000_0000
) (
  input  logic        clk,
  input  logic [31:0] addr,
  output logic [31:0] rdata,
  input  logic        we,
  input  logic [3:0]  be,
  input  logic [31:0] wdata
);

  localparam int unsigned WORDS = SIZE_BYTES / 4;
  localparam int unsigned AW    = $clog2(WORDS);

  logic [31:0] ram [WORDS];

  // Offset from the start of RAM, and whether the address is inside it.
  logic [31:0]   offset;
  logic          in_range;
  logic [AW-1:0] index;

  assign offset   = addr - BASE;
  assign in_range = offset < SIZE_BYTES;
  assign index    = offset[AW+1:2];

  initial begin
    string hexfile;
    for (int i = 0; i < int'(WORDS); i++) ram[i] = 32'b0;
    if ($value$plusargs("hex=%s", hexfile)) $readmemh(hexfile, ram);
  end

  assign rdata = in_range ? ram[index] : 32'b0;

  always_ff @(posedge clk) begin
    if (we && in_range) begin
      for (int b = 0; b < 4; b++)
        if (be[b]) ram[index][8*b +: 8] <= wdata[8*b +: 8];
    end
  end

endmodule
