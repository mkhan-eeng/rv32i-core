// Immediate generator.
// Pulls the immediate out of an instruction and sign-extends it to 32 bits.
// Which bits it uses depends on the format, chosen by sel (from the decoder).
module immgen
  import rv_pkg::*;
(
  input  logic [31:0] inst,
  input  imm_type_t   sel,
  output logic [31:0] imm
);

  // The opcode bits [6:0] never contain immediate bits.
  // Naming a signal "unused..." tells the linter that's on purpose.
  logic [6:0] unused_opcode;
  assign unused_opcode = inst[6:0];

  always_comb begin
    unique case (sel)
      // I: 12-bit signed. 20 sign copies + 12 bits.
      IMM_I:   imm = {{20{inst[31]}}, inst[31:20]};

      // S: 12-bit signed, split in two pieces. 20 + 7 + 5.
      IMM_S:   imm = {{20{inst[31]}}, inst[31:25], inst[11:7]};

      // B: 13-bit signed, always even. 19 + 1 + 1 + 6 + 4 + 1.
      IMM_B:   imm = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};

      // U: upper 20 bits, low 12 are zero. 20 + 12.
      IMM_U:   imm = {inst[31:12], 12'b0};

      // J: 21-bit signed, always even. 11 + 1 + 8 + 1 + 10 + 1.
      IMM_J:   imm = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};

      default: imm = 32'b0;
    endcase
  end

endmodule
