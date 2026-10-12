// Self-checking load/store unit testbench.
// The reference works one byte at a time: it treats the memory word as four
// separate bytes, the way the RISC-V spec describes loads and stores.
module tb_lsu;

  logic [2:0]  funct3;
  logic [1:0]  addr_lo;
  logic        is_load, is_store;
  logic [31:0] store_data, mem_wdata, mem_rdata, load_data;
  logic [3:0]  mem_be;
  logic        misaligned;

  lsu dut (.funct3(funct3), .addr_lo(addr_lo), .is_load(is_load), .is_store(is_store),
           .store_data(store_data), .mem_wdata(mem_wdata), .mem_be(mem_be),
           .mem_rdata(mem_rdata), .load_data(load_data), .misaligned(misaligned));

  int checks = 0;
  int errors = 0;

  function automatic int size_of(logic [1:0] sz);   // bytes accessed (funct3[1:0])
    case (sz)
      2'b00:   return 1;
      2'b01:   return 2;
      default: return 4;
    endcase
  endfunction

  function automatic logic ref_misaligned(logic [1:0] sz, logic [1:0] lo);
    return (int'(lo) % size_of(sz)) != 0;
  endfunction

  task automatic fail(string msg);
    errors++;
    if (errors <= 10) $display("MISMATCH %s", msg);
  endtask

  // ---- loads: lb lh lw lbu lhu ----
  task automatic check_load(logic [2:0] f3, logic [1:0] lo, logic [31:0] word);
    logic [7:0]  bytes [4];
    logic [31:0] expected;
    int          n = size_of(f3[1:0]);
    funct3 = f3; addr_lo = lo; mem_rdata = word;
    is_load = 1; is_store = 0; store_data = $urandom;
    #1;
    checks++;
    if (misaligned !== ref_misaligned(f3[1:0], lo))
      fail($sformatf("load misaligned flag f3=%b lo=%0d got=%b", f3, lo, misaligned));
    if (mem_be !== 4'b0000)
      fail($sformatf("load must not write: be=%b", mem_be));
    if (ref_misaligned(f3[1:0], lo)) return;
    for (int i = 0; i < 4; i++) bytes[i] = word[8*i +: 8];
    expected = 32'b0;
    for (int i = 0; i < n; i++) expected[8*i +: 8] = bytes[int'(lo) + i];
    if (!f3[2] && n < 4 && expected[8*n - 1])           // signed: extend the top bit
      for (int i = n; i < 4; i++) expected[8*i +: 8] = 8'hFF;
    if (load_data !== expected)
      fail($sformatf("load f3=%b lo=%0d word=%h got=%h expected=%h", f3, lo, word, load_data, expected));
  endtask

  // ---- stores: sb sh sw ----
  // Apply the LSU's byte enables to an old memory word and compare with
  // writing the bytes one by one.
  task automatic check_store(logic [2:0] f3, logic [1:0] lo, logic [31:0] data, logic [31:0] old);
    logic [31:0] merged, expected;
    int          n = size_of(f3[1:0]);
    funct3 = f3; addr_lo = lo; store_data = data;
    is_load = 0; is_store = 1; mem_rdata = $urandom;
    #1;
    checks++;
    if (misaligned !== ref_misaligned(f3[1:0], lo))
      fail($sformatf("store misaligned flag f3=%b lo=%0d got=%b", f3, lo, misaligned));
    if (ref_misaligned(f3[1:0], lo)) return;
    for (int i = 0; i < 4; i++) merged[8*i +: 8] = mem_be[i] ? mem_wdata[8*i +: 8] : old[8*i +: 8];
    expected = old;
    for (int i = 0; i < n; i++) expected[8*(int'(lo) + i) +: 8] = data[8*i +: 8];
    if (merged !== expected)
      fail($sformatf("store f3=%b lo=%0d data=%h old=%h got=%h expected=%h", f3, lo, data, old, merged, expected));
  endtask

  logic [2:0] load_f3  [5] = '{3'b000, 3'b001, 3'b010, 3'b100, 3'b101};
  logic [2:0] store_f3 [3] = '{3'b000, 3'b001, 3'b010};

  initial begin
    // Every load and store at every byte offset, with a word whose bytes
    // all have the top bit set (catches missing sign extension).
    foreach (load_f3[i])  for (int lo = 0; lo < 4; lo++) check_load(load_f3[i], 2'(lo), 32'h8180_8382);
    foreach (store_f3[i]) for (int lo = 0; lo < 4; lo++) check_store(store_f3[i], 2'(lo), 32'hA1B2_C3D4, 32'h1122_3344);

    // Neither a load nor a store: no byte enables, no misaligned flag.
    funct3 = 3'b010; addr_lo = 2'd1; is_load = 0; is_store = 0; #1;
    checks++;
    if (mem_be !== 4'b0 || misaligned !== 1'b0) fail("idle LSU must not write or flag");

    repeat (50000) begin
      check_load(load_f3[$urandom_range(4)], 2'($urandom), $urandom);
      check_store(store_f3[$urandom_range(2)], 2'($urandom), $urandom, $urandom);
    end

    if (errors == 0) $display("PASS: lsu, %0d checks", checks);
    else             $display("FAIL: lsu, %0d of %0d checks wrong", errors, checks);
    $finish;
  end

endmodule
