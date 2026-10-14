// Testbench for the whole core (single-cycle, or pipelined with +define+PIPELINE).
//
// Runs a program and reports PASS or FAIL the same way Spike does: by
// watching for a store to the tohost address. Also models a few
// memory-mapped devices at 0x1000_0000 so programs can print and time
// themselves:
//   0x1000_0000  UART data      store a byte to print it
//   0x1000_0004  UART status    always reads 0 (ready)
//   0x1000_000C  cycle counter  cycles since reset
//
//   +hex=<file>       program image ($readmemh format), loaded into both memories
//   +tohost=<hex>     address of the tohost symbol (from nm)
//   +trace=<file>     optional: write a Spike-style commit log
//   +max_cycles=<n>   optional: give up after n cycles (default 1,000,000)
module tb_core #(
  // Branch target buffer entries. Only the pipelined core uses it.
  /* verilator lint_off UNUSEDPARAM */
  parameter int BTB = 64
  /* verilator lint_on UNUSEDPARAM */
);

  logic clk = 0;
  logic rst = 1;

  logic [31:0] imem_addr, imem_rdata;
  logic [31:0] dmem_addr, dmem_wdata, dmem_rdata, ram_rdata, mmio_rdata;
  logic        dmem_we;
  logic [3:0]  dmem_be;

  logic        ret_valid, ret_rd_we, ret_load, ret_store;
  logic        ret_halt, ret_illegal, ret_misaligned;
  logic [31:0] ret_pc, ret_inst, ret_rd_data, ret_mem_addr, ret_store_data;
  logic [4:0]  ret_rd;
  logic        perf_stall, perf_flush;

`ifdef PIPELINE
  core_pipe #(.BTB_ENTRIES(BTB)) dut (.*);
`else
  core dut (.*);
`endif

  // Instruction and data memories, both loaded with the same program image.
  // The pipelined core uses synchronous memories (data one cycle after the address).
`ifdef PIPELINE
  localparam bit SYNC = 1'b1;
`else
  localparam bit SYNC = 1'b0;
`endif

  mem #(.SYNC_READ(SYNC)) imem (.clk(clk), .addr(imem_addr), .rdata(imem_rdata),
                                .we(1'b0), .be(4'b0000), .wdata(32'b0));
  mem #(.SYNC_READ(SYNC)) dmem (.clk(clk), .addr(dmem_addr), .rdata(ram_rdata),
                                .we(dmem_we), .be(dmem_be), .wdata(dmem_wdata));

  // ---------------- memory-mapped devices ----------------
  localparam logic [31:0] UART_DATA   = 32'h1000_0000;
  localparam logic [31:0] UART_STATUS = 32'h1000_0004;
  localparam logic [31:0] CYCLE_COUNT = 32'h1000_000C;

  longint cycles = 0;

  always_comb begin
    case ({dmem_addr[31:2], 2'b00})
      CYCLE_COUNT: mmio_rdata = cycles[31:0];
      UART_STATUS: mmio_rdata = 32'b0;
      default:     mmio_rdata = 32'b0;
    endcase
  end
  // Device reads follow the same timing as the memory.
  logic        is_mmio, is_mmio_q;
  logic [31:0] mmio_rdata_q;
  assign is_mmio = (dmem_addr[31:28] == 4'h1);
  always_ff @(posedge clk) begin
    is_mmio_q    <= is_mmio;
    mmio_rdata_q <= mmio_rdata;
  end
  assign dmem_rdata = SYNC ? (is_mmio_q ? mmio_rdata_q : ram_rdata)
                           : (is_mmio   ? mmio_rdata   : ram_rdata);

  initial forever #5 clk = ~clk;

  logic [31:0] tohost;
  string       tracefile;
  int          fd = 0;
  longint      max_cycles = 1000000;
  longint      retired = 0, stalls = 0, flushes = 0;

  initial begin
    if (!$value$plusargs("tohost=%h", tohost)) begin
      $display("ERROR: run with +tohost=<address of tohost>");
      $finish;
    end
    if ($value$plusargs("trace=%s", tracefile)) fd = $fopen(tracefile, "w");
    void'($value$plusargs("max_cycles=%d", max_cycles));
    // Hold reset for two clock edges (pc loads RESET_PC), then release it
    // just after an edge so the first instruction gets a full cycle.
    repeat (2) @(posedge clk);
    #1 rst = 0;
  end

  // Bytes written by a store, from funct3.
  function automatic int store_bytes(logic [1:0] size);   // funct3[1:0]
    case (size)
      2'b00:   return 1;
      2'b01:   return 2;
      default: return 4;
    endcase
  endfunction

  task automatic finish_run(string result);
    $display("%s  (%0d instructions, %0d cycles, CPI %0.3f, %0d stall cycles, %0d flushes)",
             result, retired, cycles, (retired > 0) ? real'(cycles) / real'(retired) : 0.0,
             stalls, flushes);
    if (fd != 0) $fclose(fd);
    $finish;
  endtask

  // Look at each cycle in the middle, when everything has settled,
  // just before the clock edge commits it.
  initial forever begin
    @(negedge clk);
    if (!rst) begin
      cycles++;
      if (perf_stall) stalls++;
      if (perf_flush) flushes++;
    end
    if (ret_valid) begin
      string line;
      retired++;

      if (fd != 0) begin
        line = $sformatf("core   0: 3 0x%h (0x%h)", ret_pc, ret_inst);
        if (ret_rd_we)
          line = {line, $sformatf(" x%0d%s0x%h", ret_rd, (ret_rd < 10) ? "  " : " ", ret_rd_data)};
        if (ret_load)
          line = {line, $sformatf(" mem 0x%h", ret_mem_addr)};
        if (ret_store) begin
          case (store_bytes(ret_inst[13:12]))
            1:       line = {line, $sformatf(" mem 0x%h 0x%h", ret_mem_addr, ret_store_data[7:0])};
            2:       line = {line, $sformatf(" mem 0x%h 0x%h", ret_mem_addr, ret_store_data[15:0])};
            default: line = {line, $sformatf(" mem 0x%h 0x%h", ret_mem_addr, ret_store_data)};
          endcase
        end
        $fdisplay(fd, "%s", line);
      end

      if (ret_store && ret_mem_addr == UART_DATA)
        $write("%c", ret_store_data[7:0]);

      if (ret_illegal)
        finish_run($sformatf("FAIL: illegal instruction 0x%h at pc 0x%h", ret_inst, ret_pc));
      else if (ret_misaligned)
        finish_run($sformatf("FAIL: misaligned access to 0x%h at pc 0x%h", ret_mem_addr, ret_pc));
      else if (ret_halt)
        finish_run($sformatf("FAIL: ecall/ebreak at pc 0x%h", ret_pc));
      else if (ret_store && ret_mem_addr == tohost) begin
        if (ret_store_data == 32'd1) finish_run("PASS");
        else finish_run($sformatf("FAIL: exit code %0d", ret_store_data >> 1));
      end
    end
    if (cycles >= max_cycles)
      finish_run($sformatf("FAIL: timeout after %0d cycles, pc 0x%h", max_cycles, ret_pc));
  end

`ifdef PIPELINE
  // +pipeview=<file>: one line per cycle with the PC in each stage, for
  // drawing pipeline diagrams (scripts/pipeview.py). "-" means a bubble.
  int pv = 0;
  initial begin
    string pvfile;
    if ($value$plusargs("pipeview=%s", pvfile)) pv = $fopen(pvfile, "w");
  end
  function automatic string stg(logic v, logic [31:0] pc);
    return v ? $sformatf("%h", pc) : "-";
  endfunction
  initial forever begin
    @(negedge clk);
    if (pv != 0 && !rst)
      $fdisplay(pv, "%0d %h %s %s %s %s %0d %0d", cycles, dut.pc_f,
                stg(dut.ifid.valid, dut.ifid.pc), stg(dut.idex.valid, dut.idex.pc),
                stg(dut.exmem.valid, dut.exmem.pc), stg(dut.memwb.valid, dut.memwb.pc),
                perf_stall, perf_flush);
  end
`endif

endmodule
