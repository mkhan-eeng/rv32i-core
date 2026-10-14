// UART transmitter, 8 data bits, no parity, 1 stop bit.
// Pulse start for one cycle with data while busy is low.
module uart_tx #(
  parameter int unsigned CLKS_PER_BIT = 434   // 50 MHz / 115200
) (
  input  logic       clk,
  input  logic       rst,
  input  logic       start,
  input  logic [7:0] data,
  output logic       busy,
  output logic       tx
);
  logic [9:0]  shift;      // stop bit, 8 data bits (LSB first), start bit
  logic [3:0]  bits_left;
  logic [15:0] timer;

  assign busy = (bits_left != 0);

  always_ff @(posedge clk) begin
    if (rst) begin
      tx <= 1'b1; bits_left <= '0; timer <= '0; shift <= '1;
    end else if (start && !busy) begin
      shift     <= {1'b1, data, 1'b0};
      bits_left <= 4'd10;
      timer     <= '0;
    end else if (busy) begin
      if (timer == 16'(CLKS_PER_BIT - 1)) begin
        timer     <= '0;
        shift     <= {1'b1, shift[9:1]};
        bits_left <= bits_left - 4'd1;
      end else begin
        timer <= timer + 16'd1;
      end
    end
    tx <= busy ? shift[0] : 1'b1;
  end
endmodule
