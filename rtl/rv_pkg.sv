// Shared definitions for the whole core.
// Every module that needs these says "import rv_pkg::*;".
package rv_pkg;

  // Not every module uses every constant, so don't warn about unused ones.
  /* verilator lint_off UNUSEDPARAM */

  // Reset address. Matches Spike and the linker script.
  localparam logic [31:0] RESET_PC = 32'h8000_0000;

  // RV32I major opcodes: instruction bits [6:0].
  localparam logic [6:0] OP_LUI    = 7'b0110111;
  localparam logic [6:0] OP_AUIPC  = 7'b0010111;
  localparam logic [6:0] OP_JAL    = 7'b1101111;
  localparam logic [6:0] OP_JALR   = 7'b1100111;
  localparam logic [6:0] OP_BRANCH = 7'b1100011;
  localparam logic [6:0] OP_LOAD   = 7'b0000011;
  localparam logic [6:0] OP_STORE  = 7'b0100011;
  localparam logic [6:0] OP_IMM    = 7'b0010011;
  localparam logic [6:0] OP_OP     = 7'b0110011;
  localparam logic [6:0] OP_FENCE  = 7'b0001111;
  localparam logic [6:0] OP_SYSTEM = 7'b1110011;

  // ALU operations. The decoder picks one of these per instruction.
  typedef enum logic [3:0] {
    ALU_ADD,
    ALU_SUB,
    ALU_SLL,
    ALU_SLT,
    ALU_SLTU,
    ALU_XOR,
    ALU_SRL,
    ALU_SRA,
    ALU_OR,
    ALU_AND
  } alu_op_t;

  // Immediate formats. The decoder tells the immediate generator which one
  // the current instruction uses.
  typedef enum logic [2:0] {
    IMM_I,   // addi, loads, jalr
    IMM_S,   // stores
    IMM_B,   // branches
    IMM_U,   // lui, auipc
    IMM_J    // jal
  } imm_type_t;

  /* verilator lint_on UNUSEDPARAM */

endpackage
