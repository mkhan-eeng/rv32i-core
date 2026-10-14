// 5-stage pipelined RV32I core: IF, ID, EX, MEM, WB.
//
// Five instructions are in flight at once, one per stage. Same ports and
// same behaviour as the single-cycle core, so the same tests run on both.
//
// Memories are SYNCHRONOUS, like FPGA block RAM and ASIC SRAM: the address
// goes in on one clock edge and the data comes out after it.
//   - Instruction memory gets the address of the NEXT PC, so the instruction
//     for pc_f is ready in the cycle pc_f is in IF.
//   - Data memory gets its address (and store data) from EX, so load data is
//     ready in MEM, and stores are written at the end of EX.
//
// Hazards:
//   - Data:    results are forwarded from MEM and WB back to EX. A load
//              followed by an instruction that uses its result stalls for
//              one cycle (the data only exists after the MEM stage).
//              The register file also forwards a value being written in WB
//              to an instruction reading it in ID.
//   - Control: the next PC is guessed in IF (by the branch target buffer,
//              or pc + 4 without one) and checked in EX. A wrong guess
//              flushes the two younger instructions and refetches.
module core_pipe
  import rv_pkg::*;
#(
  // Branch target buffer entries. 0 = no predictor: always guess pc + 4.
  parameter int BTB_ENTRIES = 64
) (
  input  logic        clk,
  input  logic        rst,

  output logic [31:0] imem_addr,
  input  logic [31:0] imem_rdata,

  output logic [31:0] dmem_addr,
  output logic        dmem_we,
  output logic [3:0]  dmem_be,
  output logic [31:0] dmem_wdata,
  input  logic [31:0] dmem_rdata,

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

  // Performance counters: one pulse per stall cycle / per flush.
  output logic        perf_stall,
  output logic        perf_flush
);

  // ================= pipeline registers =================

  typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic [31:0] inst;
    logic [31:0] pred_next;     // where IF guessed the next instruction is
  } if_id_t;

  typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic [31:0] inst;
    logic [31:0] pred_next;
    ctrl_t       ctrl;
    logic [4:0]  rs1, rs2, rd;
    logic [31:0] rs1_val, rs2_val, imm;
  } id_ex_t;

  typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic [31:0] inst;
    ctrl_t       ctrl;
    logic [4:0]  rd;
    logic [31:0] alu_y;         // result, or the memory address for loads/stores
    logic [31:0] result;        // what gets written back if it isn't a load
    logic [31:0] store_data;
    logic        misaligned;
  } ex_mem_t;

  typedef struct packed {
    logic        valid;
    logic [31:0] pc;
    logic [31:0] inst;
    logic        reg_we;
    logic [4:0]  rd;
    logic [31:0] wb_data;
    logic        is_load, is_store;
    logic [31:0] mem_addr, store_data;
    logic        halt, illegal, misaligned;
  } mem_wb_t;

  if_id_t  ifid;
  id_ex_t  idex;
  ex_mem_t exmem;
  mem_wb_t memwb;

  logic        stall;           // load-use hazard: hold IF and ID for a cycle
  logic        redirect;        // EX found the guessed next PC was wrong
  logic [31:0] redirect_pc;

  // ================= IF: fetch and guess the next PC =================

  logic [31:0] pc_f, pc_f_next, pred_next_f;

  localparam int NB = (BTB_ENTRIES > 0) ? BTB_ENTRIES : 1;
  localparam int IB = (NB > 1) ? $clog2(NB) : 1;

  logic          btb_valid  [NB];
  logic [31:0]   btb_pc     [NB];
  logic [31:0]   btb_target [NB];
  logic [1:0]    btb_ctr    [NB];   // 2-bit counter: 00/01 guess not taken, 10/11 taken

  logic [IB-1:0] idx_f;
  logic          pred_taken_f;

  assign idx_f        = IB'(pc_f >> 2);
  assign pred_taken_f = (BTB_ENTRIES > 0) && btb_valid[idx_f] &&
                        (btb_pc[idx_f] == pc_f) && btb_ctr[idx_f][1];
  assign pred_next_f  = pred_taken_f ? btb_target[idx_f] : pc_f + 32'd4;
  // Where the PC goes next. The same value is sent to the instruction
  // memory, so its output after this clock edge is the instruction at pc_f.
  always_comb begin
    if (rst)           pc_f_next = RESET_PC;
    else if (redirect) pc_f_next = redirect_pc;
    else if (stall)    pc_f_next = pc_f;
    else               pc_f_next = pred_next_f;
  end

  assign imem_addr = pc_f_next;

  always_ff @(posedge clk) pc_f <= pc_f_next;

  always_ff @(posedge clk) begin
    if (rst || redirect) ifid <= '0;                        // flush
    else if (!stall)     ifid <= '{valid: 1'b1, pc: pc_f, inst: imem_rdata, pred_next: pred_next_f};
  end

  // ================= ID: decode and read registers =================

  ctrl_t       ctrl_d;
  logic [31:0] imm_d, rf_rdata1, rf_rdata2, rs1_val_d, rs2_val_d;
  logic [4:0]  rs1_d, rs2_d, rd_d;
  logic [6:0]  opcode_d;
  logic        uses_rs1_d, uses_rs2_d;

  assign rs1_d    = ifid.inst[19:15];
  assign rs2_d    = ifid.inst[24:20];
  assign rd_d     = ifid.inst[11:7];
  assign opcode_d = ifid.inst[6:0];

  decoder u_decoder (.inst(ifid.inst), .ctrl(ctrl_d));
  immgen  u_immgen  (.inst(ifid.inst), .sel(ctrl_d.imm_type), .imm(imm_d));

  logic        wb_we;
  logic [4:0]  wb_rd;
  logic [31:0] wb_data;

  regfile u_regfile (
    .clk(clk), .we(wb_we), .waddr(wb_rd), .wdata(wb_data),
    .raddr1(rs1_d), .raddr2(rs2_d), .rdata1(rf_rdata1), .rdata2(rf_rdata2));

  // Register file bypass: a value being written this cycle is read as the new value.
  assign rs1_val_d = (wb_we && rs1_d != 5'd0 && wb_rd == rs1_d) ? wb_data : rf_rdata1;
  assign rs2_val_d = (wb_we && rs2_d != 5'd0 && wb_rd == rs2_d) ? wb_data : rf_rdata2;

  // Which source registers this instruction actually reads.
  assign uses_rs1_d = !(opcode_d == OP_LUI || opcode_d == OP_AUIPC || opcode_d == OP_JAL);
  assign uses_rs2_d =  (opcode_d == OP_BRANCH || opcode_d == OP_STORE || opcode_d == OP_OP);

  // Load-use hazard: the instruction in EX is a load, and the one in ID needs its result.
  assign stall = ifid.valid && idex.valid && idex.ctrl.mem_read && idex.rd != 5'd0 &&
                 ((uses_rs1_d && idex.rd == rs1_d) || (uses_rs2_d && idex.rd == rs2_d));

  always_ff @(posedge clk) begin
    if (rst || redirect || stall) idex <= '0;               // flush, or insert a bubble
    else idex <= '{valid: ifid.valid, pc: ifid.pc, inst: ifid.inst, pred_next: ifid.pred_next,
                   ctrl: ctrl_d, rs1: rs1_d, rs2: rs2_d, rd: rd_d,
                   rs1_val: rs1_val_d, rs2_val: rs2_val_d, imm: imm_d};
  end

  // ================= EX: forward, compute, resolve branches =================

  logic [31:0] fwd1, fwd2, alu_a, alu_b, alu_y;
  logic        take;
  logic [31:0] next_e, pc_plus4_e, target_e;

  // Forwarding: take the newest value of each source register.
  // EX/MEM is newer than MEM/WB. A load in EX/MEM has no data yet, but
  // the load-use stall guarantees nothing here needs it.
  function automatic logic [31:0] forward(logic [4:0] r, logic [31:0] from_id);
    if (exmem.valid && exmem.ctrl.reg_we && !exmem.ctrl.mem_read && r != 5'd0 && exmem.rd == r)
      return exmem.result;
    if (memwb.valid && memwb.reg_we && r != 5'd0 && memwb.rd == r)
      return memwb.wb_data;
    return from_id;
  endfunction

  assign fwd1 = forward(idex.rs1, idex.rs1_val);
  assign fwd2 = forward(idex.rs2, idex.rs2_val);

  always_comb begin
    unique case (idex.ctrl.a_sel)
      A_RS1:   alu_a = fwd1;
      A_PC:    alu_a = idex.pc;
      A_ZERO:  alu_a = 32'b0;
      default: alu_a = 32'b0;
    endcase
  end
  assign alu_b = (idex.ctrl.b_sel == B_IMM) ? idex.imm : fwd2;

  alu u_alu (.op(idex.ctrl.alu_op), .a(alu_a), .b(alu_b), .y(alu_y));

  always_comb begin
    unique case (idex.inst[14:12])
      3'b000:  take = (fwd1 == fwd2);
      3'b001:  take = (fwd1 != fwd2);
      3'b100:  take = ($signed(fwd1) <  $signed(fwd2));
      3'b101:  take = ($signed(fwd1) >= $signed(fwd2));
      3'b110:  take = (fwd1 <  fwd2);
      3'b111:  take = (fwd1 >= fwd2);
      default: take = 1'b0;
    endcase
  end

  assign pc_plus4_e = idex.pc + 32'd4;
  assign target_e   = idex.pc + idex.imm;

  always_comb begin
    if (idex.ctrl.jalr)                                   next_e = {alu_y[31:1], 1'b0};
    else if (idex.ctrl.jal || (idex.ctrl.branch && take)) next_e = target_e;
    else                                                  next_e = pc_plus4_e;
  end

  // The guess made in IF was wrong: fetch from the right place and throw
  // away the two younger instructions (in IF/ID and ID/EX).
  assign redirect    = idex.valid && (next_e != idex.pred_next);
  assign redirect_pc = next_e;

  // Train the branch target buffer with what actually happened.
  logic [IB-1:0] idx_e;
  logic          taken_e;
  assign idx_e   = IB'(idex.pc >> 2);
  assign taken_e = idex.ctrl.jal || take;

  always_ff @(posedge clk) begin
    if (rst) begin
      for (int i = 0; i < NB; i++) btb_valid[i] <= 1'b0;
    end else if (BTB_ENTRIES > 0 && idex.valid && (idex.ctrl.branch || idex.ctrl.jal)) begin
      if (btb_valid[idx_e] && btb_pc[idx_e] == idex.pc) begin
        if (taken_e && btb_ctr[idx_e] != 2'b11)  btb_ctr[idx_e] <= btb_ctr[idx_e] + 2'b01;
        if (!taken_e && btb_ctr[idx_e] != 2'b00) btb_ctr[idx_e] <= btb_ctr[idx_e] - 2'b01;
      end else if (taken_e) begin                           // new entry, weakly taken
        btb_valid[idx_e]  <= 1'b1;
        btb_pc[idx_e]     <= idex.pc;
        btb_target[idx_e] <= target_e;
        btb_ctr[idx_e]    <= 2'b10;
      end
    end
  end

  // Data memory access starts here: address, store data and byte enables
  // go out now; the store is written at the end of this cycle, and load
  // data comes back in MEM.
  logic misaligned_e;
  logic [31:0] unused_load_e;

  lsu u_lsu_store (
    .funct3(idex.inst[14:12]), .addr_lo(alu_y[1:0]),
    .is_load(idex.valid && idex.ctrl.mem_read), .is_store(idex.valid && idex.ctrl.mem_write),
    .store_data(fwd2), .mem_wdata(dmem_wdata), .mem_be(dmem_be),
    .mem_rdata(32'b0), .load_data(unused_load_e), .misaligned(misaligned_e));

  assign dmem_addr = alu_y;
  assign dmem_we   = idex.valid && idex.ctrl.mem_write && !misaligned_e;

  always_ff @(posedge clk) begin
    if (rst) exmem <= '0;
    else exmem <= '{valid: idex.valid, pc: idex.pc, inst: idex.inst, ctrl: idex.ctrl, rd: idex.rd,
                    alu_y: alu_y,
                    result: (idex.ctrl.wb_sel == WB_PC4) ? pc_plus4_e : alu_y,
                    store_data: fwd2, misaligned: misaligned_e};
  end

  // ================= MEM: load data arrives =================

  logic [31:0] load_data;
  logic        misaligned_m;
  logic [31:0] unused_wdata_m;
  logic [3:0]  unused_be_m;
  logic        unused_misaligned_m;

  assign misaligned_m = exmem.misaligned;

  lsu u_lsu_load (
    .funct3(exmem.inst[14:12]), .addr_lo(exmem.alu_y[1:0]),
    .is_load(1'b0), .is_store(1'b0),
    .store_data(32'b0), .mem_wdata(unused_wdata_m), .mem_be(unused_be_m),
    .mem_rdata(dmem_rdata), .load_data(load_data), .misaligned(unused_misaligned_m));

  always_ff @(posedge clk) begin
    if (rst) memwb <= '0;
    else memwb <= '{valid: exmem.valid, pc: exmem.pc, inst: exmem.inst,
                    reg_we: exmem.ctrl.reg_we && !misaligned_m, rd: exmem.rd,
                    wb_data: (exmem.ctrl.wb_sel == WB_MEM) ? load_data : exmem.result,
                    is_load: exmem.ctrl.mem_read, is_store: exmem.ctrl.mem_write,
                    mem_addr: exmem.alu_y, store_data: exmem.store_data,
                    halt: exmem.ctrl.halt, illegal: exmem.ctrl.illegal, misaligned: misaligned_m};
  end

  // ================= WB: write the register file, retire =================

  assign wb_we   = memwb.valid && memwb.reg_we;
  assign wb_rd   = memwb.rd;
  assign wb_data = memwb.wb_data;

  assign ret_valid      = memwb.valid;
  assign ret_pc         = memwb.pc;
  assign ret_inst       = memwb.inst;
  assign ret_rd_we      = wb_we && memwb.rd != 5'd0;
  assign ret_rd         = memwb.rd;
  assign ret_rd_data    = memwb.wb_data;
  assign ret_load       = memwb.is_load;
  assign ret_store      = memwb.is_store;
  assign ret_mem_addr   = memwb.mem_addr;
  assign ret_store_data = memwb.store_data;
  assign ret_halt       = memwb.halt;
  assign ret_illegal    = memwb.illegal;
  assign ret_misaligned = memwb.misaligned;

  assign perf_stall = stall && !redirect;
  assign perf_flush = redirect;

endmodule
