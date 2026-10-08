// Self-checking ALU testbench.
// Compares the ALU against a reference model written a different way,
// on edge cases and on 100,000 random inputs.
module tb_alu;
  import rv_pkg::*;

  alu_op_t     op;
  logic [31:0] a, b, y;

  alu dut (.op(op), .a(a), .b(b), .y(y));

  int checks = 0;
  int errors = 0;

  // Reference model: 64-bit integer math and bit loops,
  // deliberately different from how alu.sv is written.
  function automatic logic [31:0] ref_alu(alu_op_t o, logic [31:0] x, logic [31:0] z);
    longint sx = longint'(signed'(x));    // sign-extended to 64 bits
    longint sz = longint'(signed'(z));
    longint ux = longint'(x);             // zero-extended to 64 bits
    longint uz = longint'(z);
    int     sh = int'(z[4:0]);
    logic [31:0] r;
    case (o)
      ALU_ADD:  return 32'(ux + uz);
      ALU_SUB:  return 32'(ux - uz);
      ALU_SLL:  return 32'(ux * (64'd1 << sh));
      ALU_SLT:  return (sx < sz) ? 32'd1 : 32'd0;
      ALU_SLTU: return (ux < uz) ? 32'd1 : 32'd0;
      ALU_XOR:  return x ^ z;
      ALU_SRL:  return 32'(ux / (64'd1 << sh));
      ALU_SRA: begin
        r = x;
        for (int i = 0; i < sh; i++) r = {r[31], r[31:1]};
        return r;
      end
      ALU_OR:   return x | z;
      ALU_AND:  return x & z;
      default:  return 32'b0;
    endcase
  endfunction

  task automatic check(alu_op_t o, logic [31:0] x, logic [31:0] z);
    logic [31:0] expected;
    op = o; a = x; b = z;
    #1;                                   // let the combinational logic settle
    expected = ref_alu(o, x, z);
    checks++;
    if (y !== expected) begin
      errors++;
      if (errors <= 10)
        $display("MISMATCH %s a=%h b=%h got=%h expected=%h",
                 o.name(), x, z, y, expected);
    end
  endtask

  alu_op_t ops[10] = '{ALU_ADD, ALU_SUB, ALU_SLL, ALU_SLT, ALU_SLTU,
                       ALU_XOR, ALU_SRL, ALU_SRA, ALU_OR, ALU_AND};

  // Values where ALU bugs usually hide.
  logic [31:0] edges[12] = '{32'h0000_0000, 32'h0000_0001, 32'hFFFF_FFFF,
                             32'h8000_0000, 32'h7FFF_FFFF, 32'h8000_0001,
                             32'h0000_001F, 32'h0000_0020, 32'h0000_0021,
                             32'hFFFF_FFE0, 32'h5555_5555, 32'hAAAA_AAAA};

  initial begin
    foreach (ops[i])
      foreach (edges[j])
        foreach (edges[k])
          check(ops[i], edges[j], edges[k]);

    repeat (10000)
      foreach (ops[i])
        check(ops[i], $urandom, $urandom);

    if (errors == 0) $display("PASS: alu, %0d checks", checks);
    else             $display("FAIL: alu, %0d of %0d checks wrong", errors, checks);
    $finish;
  end

endmodule
