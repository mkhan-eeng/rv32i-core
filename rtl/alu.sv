// Arithmetic logic unit. Purely combinational: no clock, no state.
// Every RV32I add/sub/compare/shift/logic instruction ends up here.
module alu
  import rv_pkg::*;
(
  input  alu_op_t     op,
  input  logic [31:0] a,
  input  logic [31:0] b,
  output logic [31:0] y
);

  // RISC-V shifts only use the low 5 bits of the shift amount (0 to 31).
  logic [4:0] shamt;
  assign shamt = b[4:0];

  always_comb begin
    unique case (op)
      ALU_ADD:  y = a + b;
      ALU_SUB:  y = a - b;
      ALU_SLL:  y = a << shamt;
      ALU_SLT:  y = {31'b0, $signed(a) < $signed(b)};  // signed compare
      ALU_SLTU: y = {31'b0, a < b};                    // unsigned compare
      ALU_XOR:  y = a ^ b;
      ALU_SRL:  y = a >> shamt;                        // fills with 0s
      ALU_SRA:  y = $unsigned($signed(a) >>> shamt);   // fills with the sign bit
      ALU_OR:   y = a | b;
      ALU_AND:  y = a & b;
      default:  y = 32'b0;
    endcase
  end

endmodule
