// Load/store unit. Purely combinational.
//
// Memory is organised as 32-bit words with one write-enable per byte.
// Stores: copy the byte or halfword into every lane it could land in, and
//         turn on only the byte enables for the bytes actually written.
// Loads:  memory returns the whole word; pick out the byte or halfword
//         and sign- or zero-extend it to 32 bits.
//
// funct3 comes straight from the instruction:
//   loads  000 lb, 001 lh, 010 lw, 100 lbu, 101 lhu
//   stores 000 sb, 001 sh, 010 sw
module lsu (
  input  logic [2:0]  funct3,
  input  logic [1:0]  addr_lo,      // low 2 bits of the address: which byte
  input  logic        is_load,
  input  logic        is_store,
  // store path
  input  logic [31:0] store_data,   // rs2
  output logic [31:0] mem_wdata,
  output logic [3:0]  mem_be,       // byte enables
  // load path
  input  logic [31:0] mem_rdata,    // the whole word from memory
  output logic [31:0] load_data,
  // a halfword at an odd address or a word not on a 4-byte boundary
  output logic        misaligned
);

  // The addressed byte or halfword, moved down to the bottom bits.
  logic [15:0] shifted;
  assign shifted = 16'(mem_rdata >> {addr_lo, 3'b000});

  always_comb begin
    // ---- stores ----
    mem_wdata = 32'b0;
    mem_be    = 4'b0000;
    if (is_store) begin
      unique case (funct3[1:0])
        2'b00: begin                                // sb
          mem_wdata = {4{store_data[7:0]}};
          mem_be    = 4'b0001 << addr_lo;
        end
        2'b01: begin                                // sh
          mem_wdata = {2{store_data[15:0]}};
          mem_be    = 4'b0011 << addr_lo;
        end
        2'b10: begin                                // sw
          mem_wdata = store_data;
          mem_be    = 4'b1111;
        end
        default: ;
      endcase
    end

    // ---- loads ----
    unique case (funct3)
      3'b000:  load_data = {{24{shifted[7]}},  shifted[7:0]};    // lb
      3'b001:  load_data = {{16{shifted[15]}}, shifted[15:0]};   // lh
      3'b010:  load_data = mem_rdata;                            // lw
      3'b100:  load_data = {24'b0, shifted[7:0]};                // lbu
      3'b101:  load_data = {16'b0, shifted[15:0]};               // lhu
      default: load_data = 32'b0;
    endcase

    // ---- alignment check ----
    misaligned = (is_load || is_store) &&
                 ((funct3[1:0] == 2'b01 && addr_lo[0]) ||
                  (funct3[1:0] == 2'b10 && addr_lo != 2'b00));
  end

endmodule
