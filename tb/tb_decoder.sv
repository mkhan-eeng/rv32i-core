// Self-checking decoder testbench.
//
// The reference is a table straight from the RISC-V spec: every RV32I
// instruction is a MASK/MATCH pair (an instruction is that instruction if
// (inst & MASK) == MATCH), plus the control signals it should produce.
// Anything that matches no row must be flagged illegal and do nothing.
//
// 1. One real encoding of every RV32I instruction (assembled with GCC).
// 2. Hand-picked illegal encodings that look almost legal.
// 3. 100,000 random legal instructions (random registers and immediates).
// 4. 100,000 legal instructions with one random bit flipped.
// 5. 100,000 completely random 32-bit words.
module tb_decoder;
  import rv_pkg::*;

  logic [31:0] inst;
  ctrl_t       ctrl;

  decoder dut (.inst(inst), .ctrl(ctrl));

  typedef struct {
    string       name;
    logic [31:0] mask;
    logic [31:0] match;
    ctrl_t       exp;
  } row_t;

  row_t spec [$];
  int checks = 0;
  int errors = 0;
  int n_illegal = 0;

  // Build the expected control word. Fields an instruction doesn't use are
  // expected to stay at 0 (A_RS1, B_RS2, ALU_ADD, IMM_I, WB_ALU).
  function automatic ctrl_t mk(logic we, a_sel_t a, b_sel_t b, alu_op_t op,
                               imm_type_t it, logic mr, logic mw, wb_sel_t wb,
                               logic br, logic j, logic jr, logic h);
    ctrl_t c = '0;
    c.reg_we = we;  c.a_sel = a;      c.b_sel = b;      c.alu_op = op;
    c.imm_type = it; c.mem_read = mr; c.mem_write = mw; c.wb_sel = wb;
    c.branch = br;  c.jal = j;        c.jalr = jr;      c.halt = h;
    return c;
  endfunction

  function automatic void add(string n, logic [31:0] mask, logic [31:0] match, ctrl_t e);
    row_t r;
    r.name = n; r.mask = mask; r.match = match; r.exp = e;
    spec.push_back(r);
  endfunction

  function automatic ctrl_t illegal_ctrl();
    ctrl_t c = '0;
    c.illegal = 1'b1;
    return c;
  endfunction

  // Reference decode: find the row that matches.
  function automatic ctrl_t ref_decode(logic [31:0] i, output string nm);
    foreach (spec[k])
      if ((i & spec[k].mask) == spec[k].match) begin
        nm = spec[k].name;
        return spec[k].exp;
      end
    nm = "illegal";
    return illegal_ctrl();
  endfunction

  // Print a control word field by field, so a mismatch is readable.
  function automatic string show(ctrl_t c);
    return $sformatf("we=%0d a=%s b=%s alu=%s imm=%s rd=%0d wr=%0d wb=%s br=%0d jal=%0d jalr=%0d halt=%0d ill=%0d",
                     c.reg_we, c.a_sel.name(), c.b_sel.name(), c.alu_op.name(), c.imm_type.name(),
                     c.mem_read, c.mem_write, c.wb_sel.name(), c.branch, c.jal, c.jalr, c.halt, c.illegal);
  endfunction

  task automatic check(logic [31:0] i, string label);
    ctrl_t expected;
    string nm;
    inst = i;
    #1;
    expected = ref_decode(i, nm);
    if (expected.illegal) n_illegal++;
    checks++;
    if (ctrl !== expected) begin
      errors++;
      if (errors <= 10) begin
        $display("MISMATCH %s inst=%h (spec says %s)", label, i, nm);
        $display("   got      %s", show(ctrl));
        $display("   expected %s", show(expected));
      end
    end
  endtask

  // Checks the spec table itself: a real encoding must match the named row.
  task automatic check_named(logic [31:0] i, string want);
    string nm;
    void'(ref_decode(i, nm));
    if (nm != want) begin
      errors++;
      $display("TABLE ERROR %h is %s in the table, expected %s", i, nm, want);
    end
    check(i, want);
  endtask

  // One real encoding of every RV32I instruction, from GCC.
  logic [31:0] real_enc [40] = '{
    32'h12345537, 32'hfffff597, 32'h004000ef, 32'h004502e7,
    32'h00b50c63, 32'h00b51a63, 32'h00b54863, 32'h00b55663, 32'h00b56463, 32'h00b57263,
    32'hffc10503, 32'hffc11503, 32'hffc12503, 32'hffc14503, 32'hffc15503,
    32'h00b10423, 32'h00b11423, 32'h00b12423,
    32'hff958513, 32'hff95a513, 32'hff95b513, 32'hff95c513, 32'hff95e513, 32'hff95f513,
    32'h00559513, 32'h0055d513, 32'h4055d513,
    32'h00c58533, 32'h40c58533, 32'h00c59533, 32'h00c5a533, 32'h00c5b533,
    32'h00c5c533, 32'h00c5d533, 32'h40c5d533, 32'h00c5e533, 32'h00c5f533,
    32'h0ff0000f, 32'h00000073, 32'h00100073};
  string real_name [40] = '{
    "lui", "auipc", "jal", "jalr",
    "beq", "bne", "blt", "bge", "bltu", "bgeu",
    "lb", "lh", "lw", "lbu", "lhu",
    "sb", "sh", "sw",
    "addi", "slti", "sltiu", "xori", "ori", "andi",
    "slli", "srli", "srai",
    "add", "sub", "sll", "slt", "sltu",
    "xor", "srl", "sra", "or", "and",
    "fence", "ecall", "ebreak"};

  // Encodings that are close to legal but are not RV32I.
  logic [31:0] bad_enc [14] = '{
    32'h0000_0000,   // all zeros
    32'hffff_ffff,   // all ones
    32'h0000_0001,   // compressed instruction (low bits not 11)
    32'h02c58533,   // mul (M extension)
    32'h0000100f,   // fence.i (Zifencei)
    32'hc0002573,   // csrr a0, cycle (Zicsr)
    32'h00151567,   // jalr with funct3 = 001
    32'h00b52463,   // branch with funct3 = 010
    32'hffc13503,   // ld (RV64 load, funct3 = 011)
    32'h00b13423,   // sd (RV64 store, funct3 = 011)
    32'h02059513,   // slli with a bad upper field
    32'h40c5c533,   // "xor" with funct7 = 0100000
    32'h4255d513,   // srai with funct7 = 0100001
    32'h30200073};  // mret (privileged)

  initial begin
    // ---------------- the spec table ----------------
    add("lui",   32'h0000007f, 32'h00000037, mk(1, A_ZERO, B_IMM, ALU_ADD, IMM_U, 0, 0, WB_ALU, 0, 0, 0, 0));
    add("auipc", 32'h0000007f, 32'h00000017, mk(1, A_PC,   B_IMM, ALU_ADD, IMM_U, 0, 0, WB_ALU, 0, 0, 0, 0));
    add("jal",   32'h0000007f, 32'h0000006f, mk(1, A_RS1,  B_RS2, ALU_ADD, IMM_J, 0, 0, WB_PC4, 0, 1, 0, 0));
    add("jalr",  32'h0000707f, 32'h00000067, mk(1, A_RS1,  B_IMM, ALU_ADD, IMM_I, 0, 0, WB_PC4, 0, 0, 1, 0));
    add("beq",   32'h0000707f, 32'h00000063, mk(0, A_RS1,  B_RS2, ALU_ADD, IMM_B, 0, 0, WB_ALU, 1, 0, 0, 0));
    add("bne",   32'h0000707f, 32'h00001063, mk(0, A_RS1,  B_RS2, ALU_ADD, IMM_B, 0, 0, WB_ALU, 1, 0, 0, 0));
    add("blt",   32'h0000707f, 32'h00004063, mk(0, A_RS1,  B_RS2, ALU_ADD, IMM_B, 0, 0, WB_ALU, 1, 0, 0, 0));
    add("bge",   32'h0000707f, 32'h00005063, mk(0, A_RS1,  B_RS2, ALU_ADD, IMM_B, 0, 0, WB_ALU, 1, 0, 0, 0));
    add("bltu",  32'h0000707f, 32'h00006063, mk(0, A_RS1,  B_RS2, ALU_ADD, IMM_B, 0, 0, WB_ALU, 1, 0, 0, 0));
    add("bgeu",  32'h0000707f, 32'h00007063, mk(0, A_RS1,  B_RS2, ALU_ADD, IMM_B, 0, 0, WB_ALU, 1, 0, 0, 0));
    add("lb",    32'h0000707f, 32'h00000003, mk(1, A_RS1,  B_IMM, ALU_ADD, IMM_I, 1, 0, WB_MEM, 0, 0, 0, 0));
    add("lh",    32'h0000707f, 32'h00001003, mk(1, A_RS1,  B_IMM, ALU_ADD, IMM_I, 1, 0, WB_MEM, 0, 0, 0, 0));
    add("lw",    32'h0000707f, 32'h00002003, mk(1, A_RS1,  B_IMM, ALU_ADD, IMM_I, 1, 0, WB_MEM, 0, 0, 0, 0));
    add("lbu",   32'h0000707f, 32'h00004003, mk(1, A_RS1,  B_IMM, ALU_ADD, IMM_I, 1, 0, WB_MEM, 0, 0, 0, 0));
    add("lhu",   32'h0000707f, 32'h00005003, mk(1, A_RS1,  B_IMM, ALU_ADD, IMM_I, 1, 0, WB_MEM, 0, 0, 0, 0));
    add("sb",    32'h0000707f, 32'h00000023, mk(0, A_RS1,  B_IMM, ALU_ADD, IMM_S, 0, 1, WB_ALU, 0, 0, 0, 0));
    add("sh",    32'h0000707f, 32'h00001023, mk(0, A_RS1,  B_IMM, ALU_ADD, IMM_S, 0, 1, WB_ALU, 0, 0, 0, 0));
    add("sw",    32'h0000707f, 32'h00002023, mk(0, A_RS1,  B_IMM, ALU_ADD, IMM_S, 0, 1, WB_ALU, 0, 0, 0, 0));
    add("addi",  32'h0000707f, 32'h00000013, mk(1, A_RS1,  B_IMM, ALU_ADD,  IMM_I, 0, 0, WB_ALU, 0, 0, 0, 0));
    add("slti",  32'h0000707f, 32'h00002013, mk(1, A_RS1,  B_IMM, ALU_SLT,  IMM_I, 0, 0, WB_ALU, 0, 0, 0, 0));
    add("sltiu", 32'h0000707f, 32'h00003013, mk(1, A_RS1,  B_IMM, ALU_SLTU, IMM_I, 0, 0, WB_ALU, 0, 0, 0, 0));
    add("xori",  32'h0000707f, 32'h00004013, mk(1, A_RS1,  B_IMM, ALU_XOR,  IMM_I, 0, 0, WB_ALU, 0, 0, 0, 0));
    add("ori",   32'h0000707f, 32'h00006013, mk(1, A_RS1,  B_IMM, ALU_OR,   IMM_I, 0, 0, WB_ALU, 0, 0, 0, 0));
    add("andi",  32'h0000707f, 32'h00007013, mk(1, A_RS1,  B_IMM, ALU_AND,  IMM_I, 0, 0, WB_ALU, 0, 0, 0, 0));
    add("slli",  32'hfe00707f, 32'h00001013, mk(1, A_RS1,  B_IMM, ALU_SLL,  IMM_I, 0, 0, WB_ALU, 0, 0, 0, 0));
    add("srli",  32'hfe00707f, 32'h00005013, mk(1, A_RS1,  B_IMM, ALU_SRL,  IMM_I, 0, 0, WB_ALU, 0, 0, 0, 0));
    add("srai",  32'hfe00707f, 32'h40005013, mk(1, A_RS1,  B_IMM, ALU_SRA,  IMM_I, 0, 0, WB_ALU, 0, 0, 0, 0));
    add("add",   32'hfe00707f, 32'h00000033, mk(1, A_RS1,  B_RS2, ALU_ADD,  IMM_I, 0, 0, WB_ALU, 0, 0, 0, 0));
    add("sub",   32'hfe00707f, 32'h40000033, mk(1, A_RS1,  B_RS2, ALU_SUB,  IMM_I, 0, 0, WB_ALU, 0, 0, 0, 0));
    add("sll",   32'hfe00707f, 32'h00001033, mk(1, A_RS1,  B_RS2, ALU_SLL,  IMM_I, 0, 0, WB_ALU, 0, 0, 0, 0));
    add("slt",   32'hfe00707f, 32'h00002033, mk(1, A_RS1,  B_RS2, ALU_SLT,  IMM_I, 0, 0, WB_ALU, 0, 0, 0, 0));
    add("sltu",  32'hfe00707f, 32'h00003033, mk(1, A_RS1,  B_RS2, ALU_SLTU, IMM_I, 0, 0, WB_ALU, 0, 0, 0, 0));
    add("xor",   32'hfe00707f, 32'h00004033, mk(1, A_RS1,  B_RS2, ALU_XOR,  IMM_I, 0, 0, WB_ALU, 0, 0, 0, 0));
    add("srl",   32'hfe00707f, 32'h00005033, mk(1, A_RS1,  B_RS2, ALU_SRL,  IMM_I, 0, 0, WB_ALU, 0, 0, 0, 0));
    add("sra",   32'hfe00707f, 32'h40005033, mk(1, A_RS1,  B_RS2, ALU_SRA,  IMM_I, 0, 0, WB_ALU, 0, 0, 0, 0));
    add("or",    32'hfe00707f, 32'h00006033, mk(1, A_RS1,  B_RS2, ALU_OR,   IMM_I, 0, 0, WB_ALU, 0, 0, 0, 0));
    add("and",   32'hfe00707f, 32'h00007033, mk(1, A_RS1,  B_RS2, ALU_AND,  IMM_I, 0, 0, WB_ALU, 0, 0, 0, 0));
    add("fence", 32'h0000707f, 32'h0000000f, mk(0, A_RS1,  B_RS2, ALU_ADD,  IMM_I, 0, 0, WB_ALU, 0, 0, 0, 0));
    add("ecall", 32'hffffffff, 32'h00000073, mk(0, A_RS1,  B_RS2, ALU_ADD,  IMM_I, 0, 0, WB_ALU, 0, 0, 0, 1));
    add("ebreak",32'hffffffff, 32'h00100073, mk(0, A_RS1,  B_RS2, ALU_ADD,  IMM_I, 0, 0, WB_ALU, 0, 0, 0, 1));

    // ---------------- 1. every real instruction ----------------
    foreach (real_enc[i]) check_named(real_enc[i], real_name[i]);

    // ---------------- 2. almost-legal encodings ----------------
    foreach (bad_enc[i]) check_named(bad_enc[i], "illegal");

    // ---------------- 3. random legal instructions ----------------
    // (Declare first, then assign: a variable declared with a value inside
    //  a loop only gets that value once.)
    repeat (100000) begin
      int k;
      k = $urandom_range(spec.size() - 1);
      check(spec[k].match | ($urandom & ~spec[k].mask), "random legal");
    end

    // ---------------- 4. legal with one bit flipped ----------------
    repeat (100000) begin
      int k;
      logic [31:0] i;
      k = $urandom_range(spec.size() - 1);
      i = spec[k].match | ($urandom & ~spec[k].mask);
      check(i ^ (32'd1 << $urandom_range(31)), "one bit flipped");
    end

    // ---------------- 5. completely random words ----------------
    repeat (100000) check($urandom, "random word");

    if (errors == 0) $display("PASS: decoder, %0d checks (%0d of them illegal encodings)", checks, n_illegal);
    else             $display("FAIL: decoder, %0d of %0d checks wrong", errors, checks);
    $finish;
  end

endmodule
