// Simulation of the whole DE2-115 design: the exact Verilog that Quartus
// compiles (made by sv2v), with the board's 50 MHz clock and KEY0.
// It decodes the UART pin back into text, prints it, and checks the LEDs.
// Two runs: power-up, then press-and-release KEY0, to check that a reset
// re-runs the program correctly from the RAM state the first run left behind.
//   +initdir=<dir>/   where the .hex memory files are
module tb_de2_115;
  localparam int CPB = 8;            // fast UART for simulation

  logic        CLOCK_50 = 0;
  logic [3:0]  KEY = 4'b1111;
  logic [17:0] SW = '0;
  logic [8:0]  LEDG;
  logic [17:0] LEDR;
  logic [6:0]  HEX0, HEX1, HEX2, HEX3, HEX4, HEX5, HEX6, HEX7;
  logic        UART_TXD;

  de2_115_top #(.INIT_DIR(`INITDIR), .CLKS_PER_BIT(CPB)) dut (.*);

  initial forever #10 CLOCK_50 = ~CLOCK_50;     // 50 MHz

  // UART receiver: wait for a start bit, sample each bit in its middle.
  // Remember whether CoreMark's success line went by: keep the last
  // 27 characters received and compare them with it.
  localparam logic [8*27-1:0] OK_LINE = "Correct operation validated";
  logic [8*27-1:0] last27 = '0;
  int ok_count = 0;      // how many times the success line has been seen
  initial forever begin
    logic [7:0] c;
    @(negedge UART_TXD);
    repeat (CPB / 2) @(posedge CLOCK_50);
    for (int i = 0; i < 8; i++) begin
      repeat (CPB) @(posedge CLOCK_50);
      c[i] = UART_TXD;
    end
    repeat (CPB) @(posedge CLOCK_50);
    $write("%c", c);
    last27 = {last27[8*26-1:0], c};
    if (last27 == OK_LINE) ok_count++;
  end

  longint t;
  int ok_before;
  task run_once(int n);
    t = 0;
    ok_before = ok_count;
    while (!LEDG[7] && t < 64'd200_000_000) begin @(posedge CLOCK_50); t++; end
    repeat (40 * CPB) @(posedge CLOCK_50);       // let the last character finish
    $display("\n--- run %0d: LEDG8 (pass) = %b, LEDR17 (fail) = %b, display = %h, cycles = %0d, instret = %0d",
             n, LEDG[8], LEDR[17], dut.display, dut.run_cycles, dut.instret);
    if (!LEDG[7]) begin $display("FAIL: run %0d did not finish", n); $finish; end
    if (!LEDG[8] || LEDR[17]) begin $display("FAIL: run %0d exit code not 0", n); $finish; end
    if (ok_count == ok_before) begin
      $display("FAIL: run %0d CoreMark did not validate", n); $finish;
    end
  endtask

  initial begin
    run_once(1);
    KEY[0] = 0;                                   // press reset
    repeat (100) @(posedge CLOCK_50);
    if (LEDG[7]) begin $display("FAIL: reset did not clear done"); $finish; end
    KEY[0] = 1;                                   // release: run again
    run_once(2);
    $display("PASS: CoreMark ran twice on the DE2-115 design, validated both times");
    $finish;
  end
endmodule
