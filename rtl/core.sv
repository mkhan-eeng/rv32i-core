// Single-cycle RV32I core.
// Every instruction is fetched, decoded, executed and written back in one
// clock cycle. Slow, but simple, and the reference for the pipelined version.
//
// Memories live outside the core (in the testbench, later on the FPGA), and
// are read combinationally: the address goes out and the data comes back in
// the same cycle.
module core
  import rv_pkg::*;
(
  input  logic        clk,
  input  logic        rst,

  // instruction memory
  output logic [31:0] imem_addr,
  input  logic [31:0] imem_rdata,

  // data memory
  output logic [31:0] dmem_addr,
  output logic        dmem_we,
  output logic [3:0]  dmem_be,
  output logic [31:0] dmem_wdata,
  input  logic [31:0] dmem_rdata,

  // Retire port: what the instruction finishing this cycle did.
  // The testbench prints these as a trace and compares it with Spike.
  output logic        ret_valid,
  output logic [31:0] ret_pc,
  output logic [31:0] ret_inst,
  output logic        ret_rd_we,
  output logic [4:0]  ret_rd,
  output logic [31:0] ret_rd_data,
  output logic        ret_load,
  output logic        ret_store,
  output logic [31:0] ret_mem_addr,
  output logic [31:0] ret_store_data,
  output logic        ret_halt,
  output logic        ret_illegal,
  output logic        ret_misaligned,

  // Performance counters. A single-cycle core never stalls or flushes.
  output logic        perf_stall,
  output logic        perf_flush
);

  // ---------------- fetch ----------------
  logic [31:0] pc, pc_next, pc_plus4;
  logic [31:0] inst;

  always_ff @(posedge clk) begin
    if (rst) pc <= RESET_PC;
    else     pc <= pc_next;
  end

  assign imem_addr = pc;
  assign inst      = imem_rdata;
  assign pc_plus4  = pc + 32'd4;

  // ---------------- decode ----------------
  ctrl_t       ctrl;
  logic [4:0]  rs1, rs2, rd;
  logic [2:0]  funct3;
  logic [31:0] rs1_val, rs2_val, imm;

  assign rs1    = inst[19:15];
  assign rs2    = inst[24:20];
  assign rd     = inst[11:7];
  assign funct3 = inst[14:12];

  decoder u_decoder (.inst(inst), .ctrl(ctrl));

  immgen u_immgen (.inst(inst), .sel(ctrl.imm_type), .imm(imm));

  logic        rf_we;
  logic [31:0] wb_data;

  regfile u_regfile (
    .clk(clk), .we(rf_we), .waddr(rd), .wdata(wb_data),
    .raddr1(rs1), .raddr2(rs2), .rdata1(rs1_val), .rdata2(rs2_val));

  // ---------------- execute ----------------
  logic [31:0] alu_a, alu_b, alu_y;

  always_comb begin
    unique case (ctrl.a_sel)
      A_RS1:   alu_a = rs1_val;
      A_PC:    alu_a = pc;
      A_ZERO:  alu_a = 32'b0;
      default: alu_a = 32'b0;
    endcase
  end

  assign alu_b = (ctrl.b_sel == B_IMM) ? imm : rs2_val;

  alu u_alu (.op(ctrl.alu_op), .a(alu_a), .b(alu_b), .y(alu_y));

  // Branch condition, from funct3.
  logic take;
  always_comb begin
    unique case (funct3)
      3'b000:  take = (rs1_val == rs2_val);                     // beq
      3'b001:  take = (rs1_val != rs2_val);                     // bne
      3'b100:  take = ($signed(rs1_val) <  $signed(rs2_val));   // blt
      3'b101:  take = ($signed(rs1_val) >= $signed(rs2_val));   // bge
      3'b110:  take = (rs1_val <  rs2_val);                     // bltu
      3'b111:  take = (rs1_val >= rs2_val);                     // bgeu
      default: take = 1'b0;
    endcase
  end

  // Next PC: jalr goes to rs1 + imm with bit 0 cleared; jal and taken
  // branches go to pc + imm; everything else goes to pc + 4.
  logic [31:0] target;
  assign target = pc + imm;

  always_comb begin
    if (ctrl.jalr)                            pc_next = {alu_y[31:1], 1'b0};
    else if (ctrl.jal || (ctrl.branch && take)) pc_next = target;
    else                                      pc_next = pc_plus4;
  end

  // ---------------- memory ----------------
  logic [31:0] load_data;
  logic        misaligned;

  lsu u_lsu (
    .funct3(funct3), .addr_lo(alu_y[1:0]),
    .is_load(ctrl.mem_read), .is_store(ctrl.mem_write),
    .store_data(rs2_val), .mem_wdata(dmem_wdata), .mem_be(dmem_be),
    .mem_rdata(dmem_rdata), .load_data(load_data), .misaligned(misaligned));

  assign dmem_addr = alu_y;
  assign dmem_we   = ctrl.mem_write && !misaligned && !rst;

  // ---------------- write back ----------------
  always_comb begin
    unique case (ctrl.wb_sel)
      WB_ALU:  wb_data = alu_y;
      WB_MEM:  wb_data = load_data;
      WB_PC4:  wb_data = pc_plus4;
      default: wb_data = alu_y;
    endcase
  end

  assign rf_we = ctrl.reg_we && !misaligned && !rst;

  // ---------------- retire port ----------------
  assign ret_valid      = !rst;
  assign ret_pc         = pc;
  assign ret_inst       = inst;
  assign ret_rd_we      = rf_we && (rd != 5'd0);
  assign ret_rd         = rd;
  assign ret_rd_data    = wb_data;
  assign ret_load       = ctrl.mem_read;
  assign ret_store      = ctrl.mem_write;
  assign ret_mem_addr   = alu_y;
  assign ret_store_data = rs2_val;
  assign ret_halt       = ctrl.halt;
  assign ret_illegal    = ctrl.illegal;
  assign ret_misaligned = misaligned;

  assign perf_stall = 1'b0;
  assign perf_flush = 1'b0;

endmodule
