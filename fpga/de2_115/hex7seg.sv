// One hex digit to a 7-segment display. DE2-115 segments are active low.
// seg[0] = a (top), going clockwise to seg[5] = f, seg[6] = g (middle).
module hex7seg (
  input  logic [3:0] digit,
  output logic [6:0] seg
);
  always_comb begin
    case (digit)          // gfedcba
      4'h0: seg = ~7'b0111111;
      4'h1: seg = ~7'b0000110;
      4'h2: seg = ~7'b1011011;
      4'h3: seg = ~7'b1001111;
      4'h4: seg = ~7'b1100110;
      4'h5: seg = ~7'b1101101;
      4'h6: seg = ~7'b1111101;
      4'h7: seg = ~7'b0000111;
      4'h8: seg = ~7'b1111111;
      4'h9: seg = ~7'b1101111;
      4'hA: seg = ~7'b1110111;
      4'hB: seg = ~7'b1111100;
      4'hC: seg = ~7'b0111001;
      4'hD: seg = ~7'b1011110;
      4'hE: seg = ~7'b1111001;
      default: seg = ~7'b1110001;   // F
    endcase
  end
endmodule
