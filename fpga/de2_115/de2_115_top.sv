// Terasic DE2-115 (Cyclone IV E, EP4CE115F29C7) top level for the
// pipelined RV32I core.
//
// What it does: on power-up (or when KEY0 is released) the core runs the
// program baked into the on-chip RAM (CoreMark by default). When the
// program finishes it writes tohost, and the board shows the result.
//
//   KEY0         hold to reset, release to run again
//   LEDG0        blinks while the program is running
//   LEDG7        program finished
//   LEDG8        PASS (program exited with code 0)
//   LEDR17       FAIL (nonzero exit code)
//   LEDR7..0     last character printed on the UART
//   HEX7..HEX0   selected by SW1..SW0:
//                  00  value the program wrote to the display register
//                      (CoreMark writes its score x100, in decimal)
//                  01  clock cycles from reset to finish        (hex)
//                  10  instructions retired                       (hex)
//                  11  branch mispredict flushes                  (hex)
//   UART_TXD     115200 baud 8N1 on the RS-232 port: the program's printf output
//
// Memory map (same as the simulation testbench):
//   0x8000_0000  32 KB RAM. Instruction and data memories are two copies
//                of the same program image, as in simulation.
//   0x1000_0000  UART data (write a byte to send it)
//   0x1000_0004  UART status (bit 0 = busy)
//   0x1000_000C  cycle counter
//   0x1000_0010  7-segment display register (8 hex/BCD digits)
// Address of the program's tohost variable. `make fpga` passes the real one.
`ifndef TOHOST_ADDR
`define TOHOST_ADDR 32'h8000_0000
`endif

module de2_115_top #(
  parameter              INIT_DIR      = "mem/",   // where the .hex files are, relative to the Quartus project
  parameter int unsigned CLKS_PER_BIT  = 434,      // 50 MHz / 115200 baud
  parameter logic [31:0] TOHOST        = `TOHOST_ADDR
) (
  input  logic        CLOCK_50,
  input  logic [3:0]  KEY,
  input  logic [17:0] SW,
  output logic [8:0]  LEDG,
  output logic [17:0] LEDR,
  output logic [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7,
  output logic        UART_TXD
);

  logic clk;
  assign clk = CLOCK_50;

  // ---------------- reset ----------------
  // KEY0 reads 0 while pressed. Synchronise it to the clock, and keep reset
  // asserted for 16 cycles after release so everything starts cleanly.
  logic [1:0] key_sync;
  logic [3:0] rst_cnt;
  logic       rst;
  always_ff @(posedge clk) begin
    key_sync <= {key_sync[0], KEY[0]};
    if (!key_sync[1])         rst_cnt <= '0;
    else if (rst_cnt != 4'hF) rst_cnt <= rst_cnt + 4'd1;
  end
  assign rst = (rst_cnt != 4'hF);

  // ---------------- core ----------------
  logic [31:0] imem_addr, imem_rdata;
  logic [31:0] dmem_addr, dmem_wdata, dmem_rdata, ram_rdata;
  logic        dmem_we;
  logic [3:0]  dmem_be;

  logic        ret_valid, ret_rd_we, ret_load, ret_store;
  logic        ret_halt, ret_illegal, ret_misaligned;
  logic [31:0] ret_pc, ret_inst, ret_rd_data, ret_mem_addr, ret_store_data;
  logic [4:0]  ret_rd;
  logic        perf_stall, perf_flush;

  core_pipe #(.BTB_ENTRIES(64)) u_core (.*);

  // ---------------- memories (M9K block RAM) ----------------
  logic is_ram;
  assign is_ram = (dmem_addr[31:28] == 4'h8);

  fpga_rom #(.WORDS(8192), .INIT_FILE({INIT_DIR, "imem.hex"})) u_imem (
    .clk(clk), .addr(imem_addr[14:2]), .rdata(imem_rdata));

  // Data memory: four byte lanes, so sb/sh/sw can write single bytes.
  logic [3:0] lane_we;
  assign lane_we = {4{dmem_we && is_ram}} & dmem_be;

  fpga_ram8 #(.WORDS(8192), .INIT_FILE({INIT_DIR, "dmem_b0.hex"})) u_lane0 (
    .clk(clk), .addr(dmem_addr[14:2]), .we(lane_we[0]), .wdata(dmem_wdata[7:0]),   .rdata(ram_rdata[7:0]));
  fpga_ram8 #(.WORDS(8192), .INIT_FILE({INIT_DIR, "dmem_b1.hex"})) u_lane1 (
    .clk(clk), .addr(dmem_addr[14:2]), .we(lane_we[1]), .wdata(dmem_wdata[15:8]),  .rdata(ram_rdata[15:8]));
  fpga_ram8 #(.WORDS(8192), .INIT_FILE({INIT_DIR, "dmem_b2.hex"})) u_lane2 (
    .clk(clk), .addr(dmem_addr[14:2]), .we(lane_we[2]), .wdata(dmem_wdata[23:16]), .rdata(ram_rdata[23:16]));
  fpga_ram8 #(.WORDS(8192), .INIT_FILE({INIT_DIR, "dmem_b3.hex"})) u_lane3 (
    .clk(clk), .addr(dmem_addr[14:2]), .we(lane_we[3]), .wdata(dmem_wdata[31:24]), .rdata(ram_rdata[31:24]));

  // ---------------- memory-mapped devices ----------------
  localparam logic [31:0] UART_DATA   = 32'h1000_0000;
  localparam logic [31:0] UART_STATUS = 32'h1000_0004;
  localparam logic [31:0] CYCLE_COUNT = 32'h1000_000C;
  localparam logic [31:0] DISPLAY     = 32'h1000_0010;

  logic [31:0] cycles, instret, flushes, run_cycles, display;
  logic        running, done, pass;
  logic [7:0]  last_char;
  logic        uart_busy, uart_start;

  logic [31:0] waddr;
  assign waddr      = {dmem_addr[31:2], 2'b00};
  assign uart_start = dmem_we && waddr == UART_DATA && !uart_busy;

  uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart (
    .clk(clk), .rst(rst), .start(uart_start), .data(dmem_wdata[7:0]),
    .busy(uart_busy), .tx(UART_TXD));

  always_ff @(posedge clk) begin
    if (rst) begin
      cycles <= '0; instret <= '0; flushes <= '0; run_cycles <= '0;
      running <= 1'b1; done <= 1'b0; pass <= 1'b0;
      display <= '0; last_char <= '0;
    end else begin
      cycles <= cycles + 32'd1;
      if (running) begin
        run_cycles <= run_cycles + 32'd1;
        if (ret_valid)  instret <= instret + 32'd1;
        if (perf_flush) flushes <= flushes + 32'd1;
      end
      if (dmem_we && waddr == DISPLAY)  display   <= dmem_wdata;
      if (uart_start)                   last_char <= dmem_wdata[7:0];
      if (dmem_we && waddr == TOHOST && running) begin
        running <= 1'b0;
        done    <= 1'b1;
        pass    <= (dmem_wdata == 32'd1);
      end
    end
  end

  // Device reads have the same one-cycle latency as the block RAM.
  logic [31:0] mmio_rdata, mmio_rdata_q;
  logic        is_mmio_q;
  always_comb begin
    case (waddr)
      CYCLE_COUNT: mmio_rdata = cycles;
      UART_STATUS: mmio_rdata = {31'b0, uart_busy};
      default:     mmio_rdata = 32'b0;
    endcase
  end
  always_ff @(posedge clk) begin
    is_mmio_q    <= !is_ram;
    mmio_rdata_q <= mmio_rdata;
  end
  assign dmem_rdata = is_mmio_q ? mmio_rdata_q : ram_rdata;

  // ---------------- LEDs and 7-segment displays ----------------
  logic [31:0] shown;
  always_comb begin
    case (SW[1:0])
      2'b00:   shown = display;
      2'b01:   shown = run_cycles;
      2'b10:   shown = instret;
      default: shown = flushes;
    endcase
  end

  assign LEDG = {pass, done, 6'b0, running & cycles[23]};
  assign LEDR = {done & !pass, 9'b0, last_char};

  hex7seg u_h0 (.digit(shown[3:0]),   .seg(HEX0));
  hex7seg u_h1 (.digit(shown[7:4]),   .seg(HEX1));
  hex7seg u_h2 (.digit(shown[11:8]),  .seg(HEX2));
  hex7seg u_h3 (.digit(shown[15:12]), .seg(HEX3));
  hex7seg u_h4 (.digit(shown[19:16]), .seg(HEX4));
  hex7seg u_h5 (.digit(shown[23:20]), .seg(HEX5));
  hex7seg u_h6 (.digit(shown[27:24]), .seg(HEX6));
  hex7seg u_h7 (.digit(shown[31:28]), .seg(HEX7));

  // Unused core outputs (the testbench uses these to check every instruction).
  logic unused;
  assign unused = ^{ret_pc, ret_inst, ret_rd_we, ret_rd, ret_rd_data, ret_load, ret_store,
                    ret_mem_addr, ret_store_data, ret_halt, ret_illegal, ret_misaligned,
                    perf_stall, KEY[3:1], SW[17:2], dmem_addr[1:0], imem_addr[31:15],
                    imem_addr[1:0]};

endmodule
