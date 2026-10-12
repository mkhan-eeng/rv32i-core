// Self-checking memory testbench.
// Run with +hex=tb/mem_init.hex (the Makefile does this).
// Checks the file loaded, then does random byte-enabled writes and reads
// against a model, and checks addresses outside the RAM are ignored.
module tb_mem;

  localparam int unsigned SIZE = 32768;
  localparam logic [31:0] BASE = 32'h8000_0000;

  logic        clk = 0;
  logic [31:0] addr, rdata, wdata;
  logic        we;
  logic [3:0]  be;

  mem #(.SIZE_BYTES(SIZE), .BASE(BASE)) dut (
    .clk(clk), .addr(addr), .rdata(rdata), .we(we), .be(be), .wdata(wdata));

  initial forever #5 clk = ~clk;

  logic [31:0] model [SIZE / 4];
  int checks = 0;
  int errors = 0;

  task automatic expect_word(logic [31:0] a, logic [31:0] v, string what);
    addr = a; we = 0;
    #1;
    checks++;
    if (rdata !== v) begin
      errors++;
      if (errors <= 10) $display("MISMATCH %s addr=%h got=%h expected=%h", what, a, rdata, v);
    end
  endtask

  task automatic write(logic [31:0] a, logic [3:0] b, logic [31:0] v);
    @(negedge clk);
    addr = a; we = 1; be = b; wdata = v;
    @(posedge clk); #1;
    we = 0;
  endtask

  initial begin
    we = 0; be = 0; wdata = 0; addr = BASE;

    // The program file: line N is the word at BASE + 4N. Everything after it is 0.
    expect_word(BASE + 0,  32'h0000_8117, "hex line 0");
    expect_word(BASE + 4,  32'h0001_0113, "hex line 1");
    expect_word(BASE + 8,  32'hDEAD_BEEF, "hex line 2");
    expect_word(BASE + 12, 32'hCAFE_F00D, "hex line 3");
    expect_word(BASE + 16, 32'h0000_0000, "after the file");

    // The low 2 address bits don't matter: memory returns the whole word.
    expect_word(BASE + 9,  32'hDEAD_BEEF, "unaligned address, same word");

    for (int i = 0; i < int'(SIZE / 4); i++) model[i] = 32'b0;
    model[0] = 32'h0000_8117; model[1] = 32'h0001_0113;
    model[2] = 32'hDEAD_BEEF; model[3] = 32'hCAFE_F00D;

    // Random byte-enabled writes, each followed by a random read.
    // (Declare first, then assign: a variable declared with a value inside
    //  a loop only gets that value once.)
    repeat (5000) begin
      int unsigned w;
      logic [3:0]  b;
      logic [31:0] v;
      w = $urandom_range(SIZE / 4 - 1);
      b = 4'($urandom);
      v = $urandom;
      write(BASE + 4 * w, b, v);
      for (int k = 0; k < 4; k++) if (b[k]) model[w][8*k +: 8] = v[8*k +: 8];
      w = $urandom_range(SIZE / 4 - 1);
      expect_word(BASE + 4 * w, model[w], "random read");
    end

    // Outside the RAM: reads are 0, writes change nothing.
    expect_word(BASE - 4,    32'b0, "below RAM");
    expect_word(BASE + SIZE, 32'b0, "above RAM");
    expect_word(32'h1000_0000, 32'b0, "MMIO region");
    write(BASE + SIZE, 4'b1111, 32'h1234_5678);     // would land on word 0 if not checked
    write(BASE - 4,    4'b1111, 32'h1234_5678);     // would land on the last word
    expect_word(BASE,              model[0],             "word 0 after out-of-range write");
    expect_word(BASE + SIZE - 4,   model[SIZE / 4 - 1],  "last word after out-of-range write");

    if (errors == 0) $display("PASS: mem, %0d checks", checks);
    else             $display("FAIL: mem, %0d of %0d checks wrong", errors, checks);
    $finish;
  end

endmodule
