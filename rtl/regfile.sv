// 32 x 32-bit register file.
// Two combinational read ports, one synchronous write port. x0 is always 0.
module regfile (
  input  logic        clk,
  input  logic        we,
  input  logic [4:0]  waddr,
  input  logic [31:0] wdata,
  input  logic [4:0]  raddr1,
  input  logic [4:0]  raddr2,
  output logic [31:0] rdata1,
  output logic [31:0] rdata2
);

  // 32 entries, each 32 bits wide.
  logic [31:0] regs [32];

  // Write port: happens only on the rising clock edge.
  always_ff @(posedge clk) begin
    if (we && waddr != 5'd0)
      regs[waddr] <= wdata;
  end

  // Read ports: combinational, so the output changes as soon as the address does.
  assign rdata1 = (raddr1 == 5'd0) ? 32'b0 : regs[raddr1];
  assign rdata2 = (raddr2 == 5'd0) ? 32'b0 : regs[raddr2];

endmodule
