// Self-checking immediate generator testbench.
//
// Part 1: real instructions from your own build (sw/build/hello.dump),
//         with the immediates objdump says they have.
// Part 2: random round trips. Pick a random legal immediate, ENCODE it into
//         instruction bits following the RISC-V spec, then check that your
//         immgen DECODES it back to the same value. Encoding scatters bits
//         and decoding gathers them, so the two are written very differently.
module tb_immgen;
  import rv_pkg::*;

  logic [31:0] inst, imm;
  imm_type_t   sel;

  immgen dut (.inst(inst), .sel(sel), .imm(imm));

  int checks = 0;
  int errors = 0;

  task automatic check(imm_type_t s, logic [31:0] i, logic [31:0] expected, string what);
    inst = i; sel = s;
    #1;
    checks++;
    if (imm !== expected) begin
      errors++;
      if (errors <= 10)
        $display("MISMATCH %s %s inst=%h got=%h expected=%h", s.name(), what, i, imm, expected);
    end
  endtask

  // ---- Encoders: put an immediate into the instruction bits, per the spec ----
  // The non-immediate bits are filled with random junk to make sure
  // your immgen ignores them. Each encoder only uses some bits of v,
  // so tell the linter that's on purpose.
  /* verilator lint_off UNUSEDSIGNAL */

  function automatic logic [31:0] enc_i(logic [31:0] v, logic [31:0] junk);
    logic [31:0] x = junk;
    x[31:20] = v[11:0];
    return x;
  endfunction

  function automatic logic [31:0] enc_s(logic [31:0] v, logic [31:0] junk);
    logic [31:0] x = junk;
    x[31:25] = v[11:5];
    x[11:7]  = v[4:0];
    return x;
  endfunction

  function automatic logic [31:0] enc_b(logic [31:0] v, logic [31:0] junk);
    logic [31:0] x = junk;
    x[31]    = v[12];
    x[7]     = v[11];
    x[30:25] = v[10:5];
    x[11:8]  = v[4:1];
    return x;
  endfunction

  function automatic logic [31:0] enc_u(logic [31:0] v, logic [31:0] junk);
    logic [31:0] x = junk;
    x[31:12] = v[31:12];
    return x;
  endfunction

  function automatic logic [31:0] enc_j(logic [31:0] v, logic [31:0] junk);
    logic [31:0] x = junk;
    x[31]    = v[20];
    x[19:12] = v[19:12];
    x[20]    = v[11];
    x[30:21] = v[10:1];
    return x;
  endfunction

  /* verilator lint_on UNUSEDSIGNAL */

  // Random legal immediate: an N-bit signed value, sign-extended to 32 bits.
  function automatic logic [31:0] rand_signed(int nbits);
    logic [31:0] r = $urandom;
    logic [31:0] mask = (32'd1 << nbits) - 1;
    r = r & mask;
    if (r[nbits-1]) r = r | ~mask;        // sign-extend
    return r;
  endfunction

  initial begin
    // ---- Part 1: real instructions from hello.dump ----
    check(IMM_U, 32'h00008117, 32'h0000_8000, "auipc sp,0x8");
    check(IMM_I, 32'h70028293, 32'd1792,      "addi t0,t0,1792");
    check(IMM_I, 32'h73830313, 32'd1848,      "addi t1,t1,1848");
    check(IMM_B, 32'h0062f863, 32'd16,        "bgeu t0,t1,+16");
    check(IMM_S, 32'h0002a023, 32'd0,         "sw zero,0(t0)");
    check(IMM_I, 32'h00428293, 32'd4,         "addi t0,t0,4");
    check(IMM_J, 32'hff5ff06f, -32'sd12,      "j -12 (backward)");
    check(IMM_J, 32'h4dc000ef, 32'h0000_04dc, "jal main");
    check(IMM_I, 32'h00151513, 32'd1,         "slli a0,a0,1");
    check(IMM_S, 32'h00a2a023, 32'd0,         "sw a0,0(t0)");
    check(IMM_J, 32'h0000006f, 32'd0,         "j to itself");
    check(IMM_B, 32'hfe0596e3, -32'sd20,      "bnez backward (__mulsi3)");

    // ---- Edge cases: biggest and smallest immediates of each format ----
    check(IMM_I, enc_i(32'h0000_07FF, 0), 32'h0000_07FF, "I max +2047");
    check(IMM_I, enc_i(32'hFFFF_F800, 0), 32'hFFFF_F800, "I min -2048");
    check(IMM_I, enc_i(32'hFFFF_FFFF, 0), 32'hFFFF_FFFF, "I -1");
    check(IMM_S, enc_s(32'h0000_07FF, 0), 32'h0000_07FF, "S max +2047");
    check(IMM_S, enc_s(32'hFFFF_F800, 0), 32'hFFFF_F800, "S min -2048");
    check(IMM_B, enc_b(32'h0000_0FFE, 0), 32'h0000_0FFE, "B max +4094");
    check(IMM_B, enc_b(32'hFFFF_F000, 0), 32'hFFFF_F000, "B min -4096");
    check(IMM_U, enc_u(32'hFFFF_F000, 0), 32'hFFFF_F000, "U all ones");
    check(IMM_J, enc_j(32'h000F_FFFE, 0), 32'h000F_FFFE, "J max");
    check(IMM_J, enc_j(32'hFFF0_0000, 0), 32'hFFF0_0000, "J min");

    // ---- Part 2: random round trips, with random junk in the other bits ----
    repeat (20000) begin
      logic [31:0] v, junk;
      junk = $urandom;

      v = rand_signed(12);                      // I: 12-bit signed
      check(IMM_I, enc_i(v, junk), v, "random I");

      v = rand_signed(12);                      // S: 12-bit signed
      check(IMM_S, enc_s(v, junk), v, "random S");

      v = rand_signed(13) & ~32'd1;             // B: 13-bit signed, even
      check(IMM_B, enc_b(v, junk), v, "random B");

      v = $urandom & 32'hFFFF_F000;             // U: upper 20 bits
      check(IMM_U, enc_u(v, junk), v, "random U");

      v = rand_signed(21) & ~32'd1;             // J: 21-bit signed, even
      check(IMM_J, enc_j(v, junk), v, "random J");
    end

    if (errors == 0) $display("PASS: immgen, %0d checks", checks);
    else             $display("FAIL: immgen, %0d of %0d checks wrong", errors, checks);
    $finish;
  end

endmodule
