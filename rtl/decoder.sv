// Instruction decoder.
// Looks at the opcode, funct3 and funct7 fields and decides every control
// signal for the instruction. Anything that isn't a legal RV32I instruction
// gets illegal=1 and nothing else, so it can never write a register or memory.
module decoder
  import rv_pkg::*;
(
  input  logic [31:0] inst,
  output ctrl_t       ctrl
);

  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;

  assign opcode = inst[6:0];
  assign funct3 = inst[14:12];
  assign funct7 = inst[31:25];

  // The ALU operation for OP and OP-IMM instructions comes from funct3.
  // alt picks the second version of 000 (sub) and 101 (sra/srai).
  function automatic alu_op_t alu_from_funct3(logic [2:0] f3, logic alt);
    case (f3)
      3'b000:  return alt ? ALU_SUB : ALU_ADD;
      3'b001:  return ALU_SLL;
      3'b010:  return ALU_SLT;
      3'b011:  return ALU_SLTU;
      3'b100:  return ALU_XOR;
      3'b101:  return alt ? ALU_SRA : ALU_SRL;
      3'b110:  return ALU_OR;
      default: return ALU_AND;
    endcase
  endfunction

  logic illegal;

  always_comb begin
    ctrl    = '0;        // start from "do nothing"
    illegal = 1'b0;

    unique case (opcode)

      OP_LUI: begin                       // rd = 0 + imm
        ctrl.reg_we   = 1'b1;
        ctrl.a_sel    = A_ZERO;
        ctrl.b_sel    = B_IMM;
        ctrl.alu_op   = ALU_ADD;
        ctrl.imm_type = IMM_U;
        ctrl.wb_sel   = WB_ALU;
      end

      OP_AUIPC: begin                     // rd = pc + imm
        ctrl.reg_we   = 1'b1;
        ctrl.a_sel    = A_PC;
        ctrl.b_sel    = B_IMM;
        ctrl.alu_op   = ALU_ADD;
        ctrl.imm_type = IMM_U;
        ctrl.wb_sel   = WB_ALU;
      end

      OP_JAL: begin                       // rd = pc + 4, pc = pc + imm
        ctrl.reg_we   = 1'b1;
        ctrl.imm_type = IMM_J;
        ctrl.wb_sel   = WB_PC4;
        ctrl.jal      = 1'b1;
      end

      OP_JALR: begin                      // rd = pc + 4, pc = (rs1 + imm) & ~1
        if (funct3 == 3'b000) begin
          ctrl.reg_we   = 1'b1;
          ctrl.a_sel    = A_RS1;
          ctrl.b_sel    = B_IMM;
          ctrl.alu_op   = ALU_ADD;
          ctrl.imm_type = IMM_I;
          ctrl.wb_sel   = WB_PC4;
          ctrl.jalr     = 1'b1;
        end else illegal = 1'b1;
      end

      OP_BRANCH: begin                    // if (condition) pc = pc + imm
        if (funct3 != 3'b010 && funct3 != 3'b011) begin
          ctrl.imm_type = IMM_B;
          ctrl.branch   = 1'b1;
        end else illegal = 1'b1;
      end

      OP_LOAD: begin                      // rd = mem[rs1 + imm]
        if (funct3 inside {3'b000, 3'b001, 3'b010, 3'b100, 3'b101}) begin
          ctrl.reg_we   = 1'b1;
          ctrl.a_sel    = A_RS1;
          ctrl.b_sel    = B_IMM;
          ctrl.alu_op   = ALU_ADD;
          ctrl.imm_type = IMM_I;
          ctrl.mem_read = 1'b1;
          ctrl.wb_sel   = WB_MEM;
        end else illegal = 1'b1;
      end

      OP_STORE: begin                     // mem[rs1 + imm] = rs2
        if (funct3 inside {3'b000, 3'b001, 3'b010}) begin
          ctrl.a_sel     = A_RS1;
          ctrl.b_sel     = B_IMM;
          ctrl.alu_op    = ALU_ADD;
          ctrl.imm_type  = IMM_S;
          ctrl.mem_write = 1'b1;
        end else illegal = 1'b1;
      end

      OP_IMM: begin                       // rd = rs1 (op) imm
        ctrl.reg_we   = 1'b1;
        ctrl.a_sel    = A_RS1;
        ctrl.b_sel    = B_IMM;
        ctrl.imm_type = IMM_I;
        ctrl.wb_sel   = WB_ALU;
        // Only srai uses bit 30 as an opcode bit. In addi etc. it's part
        // of the immediate.
        ctrl.alu_op   = alu_from_funct3(funct3, funct3 == 3'b101 && inst[30]);
        // Shifts: the upper 7 bits must be 0000000 (slli, srli)
        // or 0100000 (srai). Anything else isn't RV32I.
        if (funct3 == 3'b001 && funct7 != 7'b0000000)
          illegal = 1'b1;
        if (funct3 == 3'b101 && funct7 != 7'b0000000 && funct7 != 7'b0100000)
          illegal = 1'b1;
      end

      OP_OP: begin                        // rd = rs1 (op) rs2
        ctrl.reg_we = 1'b1;
        ctrl.a_sel  = A_RS1;
        ctrl.b_sel  = B_RS2;
        ctrl.wb_sel = WB_ALU;
        ctrl.alu_op = alu_from_funct3(funct3, inst[30]);
        // funct7 is 0000000 for everything, except 0100000 for sub and sra.
        if (!(funct7 == 7'b0000000 ||
              (funct7 == 7'b0100000 && (funct3 == 3'b000 || funct3 == 3'b101))))
          illegal = 1'b1;
      end

      OP_FENCE: begin                     // memory ordering: nothing to do here
        if (funct3 != 3'b000) illegal = 1'b1;
      end

      OP_SYSTEM: begin                    // ecall / ebreak end the simulation
        if (inst == 32'h0000_0073 || inst == 32'h0010_0073) ctrl.halt = 1'b1;
        else illegal = 1'b1;
      end

      default: illegal = 1'b1;

    endcase

    // An illegal instruction must not do anything except raise the flag.
    if (illegal) begin
      ctrl         = '0;
      ctrl.illegal = 1'b1;
    end
  end

endmodule
