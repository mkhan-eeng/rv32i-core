// Self-checking register file testbench.
// Keeps its own copy of what the 32 registers should hold, does thousands
// of random writes and reads, and checks every read against that copy.
module tb_regfile;

  logic        clk = 0;
  logic        we;
  logic [4:0]  waddr, raddr1, raddr2;
  logic [31:0] wdata, rdata1, rdata2;

  regfile dut (.clk(clk), .we(we), .waddr(waddr), .wdata(wdata),
               .raddr1(raddr1), .raddr2(raddr2),
               .rdata1(rdata1), .rdata2(rdata2));

  initial forever #5 clk = ~clk;          // 10 time-unit clock period

  logic [31:0] model [32];                // what the registers should hold
  int checks = 0;
  int errors = 0;

  task automatic check_read(logic [4:0] r1, logic [4:0] r2);
    raddr1 = r1; raddr2 = r2;
    #1;
    checks += 2;
    if (rdata1 !== model[r1]) begin
      errors++;
      if (errors <= 10) $display("MISMATCH port1 x%0d got=%h expected=%h", r1, rdata1, model[r1]);
    end
    if (rdata2 !== model[r2]) begin
      errors++;
      if (errors <= 10) $display("MISMATCH port2 x%0d got=%h expected=%h", r2, rdata2, model[r2]);
    end
  endtask

  // Write on the next rising clock edge, and update the model the same way
  // the real register file should behave.
  task automatic write(logic [4:0] r, logic [31:0] v);
    @(negedge clk);
    we = 1; waddr = r; wdata = v;
    @(posedge clk);
    #1;
    we = 0;
    if (r != 5'd0) model[r] = v;          // writes to x0 must be ignored
  endtask

  initial begin
    we = 0; waddr = 0; wdata = 0; raddr1 = 0; raddr2 = 0;

    // Start from a known state: write every register once.
    model[0] = 32'b0;
    for (int r = 0; r < 32; r++) write(5'(r), $urandom);
    for (int r = 0; r < 32; r++) check_read(5'(r), 5'(31 - r));

    // x0 must stay zero no matter what is written to it.
    write(5'd0, 32'hDEAD_BEEF);
    check_read(5'd0, 5'd0);

    // A write with we=0 must not change anything.
    @(negedge clk);
    we = 0; waddr = 5'd7; wdata = 32'h1234_5678;
    @(posedge clk); #1;
    check_read(5'd7, 5'd7);

    // Random writes and reads.
    repeat (5000) begin
      write(5'($urandom), $urandom);
      check_read(5'($urandom), 5'($urandom));
    end

    if (errors == 0) $display("PASS: regfile, %0d checks", checks);
    else             $display("FAIL: regfile, %0d of %0d checks wrong", errors, checks);
    $finish;
  end

endmodule
