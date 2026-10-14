module alu (
	op,
	a,
	b,
	y
);
	reg _sv2v_0;
	input wire [3:0] op;
	input wire [31:0] a;
	input wire [31:0] b;
	output reg [31:0] y;
	wire [4:0] shamt;
	assign shamt = b[4:0];
	always @(*) begin
		if (_sv2v_0)
			;
		(* full_case, parallel_case *)
		case (op)
			4'd0: y = a + b;
			4'd1: y = a - b;
			4'd2: y = a << shamt;
			4'd3: y = {31'b0000000000000000000000000000000, $signed(a) < $signed(b)};
			4'd4: y = {31'b0000000000000000000000000000000, a < b};
			4'd5: y = a ^ b;
			4'd6: y = a >> shamt;
			4'd7: y = $unsigned($signed(a) >>> shamt);
			4'd8: y = a | b;
			4'd9: y = a & b;
			default: y = 32'b00000000000000000000000000000000;
		endcase
	end
	initial _sv2v_0 = 0;
endmodule
module regfile (
	clk,
	we,
	waddr,
	wdata,
	raddr1,
	raddr2,
	rdata1,
	rdata2
);
	input wire clk;
	input wire we;
	input wire [4:0] waddr;
	input wire [31:0] wdata;
	input wire [4:0] raddr1;
	input wire [4:0] raddr2;
	output wire [31:0] rdata1;
	output wire [31:0] rdata2;
	reg [31:0] regs [0:31];
	always @(posedge clk)
		if (we && (waddr != 5'd0))
			regs[waddr] <= wdata;
	assign rdata1 = (raddr1 == 5'd0 ? 32'b00000000000000000000000000000000 : regs[raddr1]);
	assign rdata2 = (raddr2 == 5'd0 ? 32'b00000000000000000000000000000000 : regs[raddr2]);
endmodule
module immgen (
	inst,
	sel,
	imm
);
	reg _sv2v_0;
	input wire [31:0] inst;
	input wire [2:0] sel;
	output reg [31:0] imm;
	wire [6:0] unused_opcode;
	assign unused_opcode = inst[6:0];
	always @(*) begin
		if (_sv2v_0)
			;
		(* full_case, parallel_case *)
		case (sel)
			3'd0: imm = {{20 {inst[31]}}, inst[31:20]};
			3'd1: imm = {{20 {inst[31]}}, inst[31:25], inst[11:7]};
			3'd2: imm = {{19 {inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
			3'd3: imm = {inst[31:12], 12'b000000000000};
			3'd4: imm = {{11 {inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};
			default: imm = 32'b00000000000000000000000000000000;
		endcase
	end
	initial _sv2v_0 = 0;
endmodule
module decoder (
	inst,
	ctrl
);
	reg _sv2v_0;
	input wire [31:0] inst;
	output reg [19:0] ctrl;
	wire [6:0] opcode;
	wire [2:0] funct3;
	wire [6:0] funct7;
	assign opcode = inst[6:0];
	assign funct3 = inst[14:12];
	assign funct7 = inst[31:25];
	function automatic [3:0] alu_from_funct3;
		input reg [2:0] f3;
		input reg alt;
		case (f3)
			3'b000: alu_from_funct3 = (alt ? 4'd1 : 4'd0);
			3'b001: alu_from_funct3 = 4'd2;
			3'b010: alu_from_funct3 = 4'd3;
			3'b011: alu_from_funct3 = 4'd4;
			3'b100: alu_from_funct3 = 4'd5;
			3'b101: alu_from_funct3 = (alt ? 4'd7 : 4'd6);
			3'b110: alu_from_funct3 = 4'd8;
			default: alu_from_funct3 = 4'd9;
		endcase
	endfunction
	reg illegal;
	localparam [6:0] rv_pkg_OP_AUIPC = 7'b0010111;
	localparam [6:0] rv_pkg_OP_BRANCH = 7'b1100011;
	localparam [6:0] rv_pkg_OP_FENCE = 7'b0001111;
	localparam [6:0] rv_pkg_OP_IMM = 7'b0010011;
	localparam [6:0] rv_pkg_OP_JAL = 7'b1101111;
	localparam [6:0] rv_pkg_OP_JALR = 7'b1100111;
	localparam [6:0] rv_pkg_OP_LOAD = 7'b0000011;
	localparam [6:0] rv_pkg_OP_LUI = 7'b0110111;
	localparam [6:0] rv_pkg_OP_OP = 7'b0110011;
	localparam [6:0] rv_pkg_OP_STORE = 7'b0100011;
	localparam [6:0] rv_pkg_OP_SYSTEM = 7'b1110011;
	always @(*) begin
		if (_sv2v_0)
			;
		ctrl = 1'sb0;
		illegal = 1'b0;
		(* full_case, parallel_case *)
		case (opcode)
			rv_pkg_OP_LUI: begin
				ctrl[19] = 1'b1;
				ctrl[18-:2] = 2'd2;
				ctrl[16] = 1'd1;
				ctrl[15-:4] = 4'd0;
				ctrl[11-:3] = 3'd3;
				ctrl[6-:2] = 2'd0;
			end
			rv_pkg_OP_AUIPC: begin
				ctrl[19] = 1'b1;
				ctrl[18-:2] = 2'd1;
				ctrl[16] = 1'd1;
				ctrl[15-:4] = 4'd0;
				ctrl[11-:3] = 3'd3;
				ctrl[6-:2] = 2'd0;
			end
			rv_pkg_OP_JAL: begin
				ctrl[19] = 1'b1;
				ctrl[11-:3] = 3'd4;
				ctrl[6-:2] = 2'd2;
				ctrl[3] = 1'b1;
			end
			rv_pkg_OP_JALR:
				if (funct3 == 3'b000) begin
					ctrl[19] = 1'b1;
					ctrl[18-:2] = 2'd0;
					ctrl[16] = 1'd1;
					ctrl[15-:4] = 4'd0;
					ctrl[11-:3] = 3'd0;
					ctrl[6-:2] = 2'd2;
					ctrl[2] = 1'b1;
				end
				else
					illegal = 1'b1;
			rv_pkg_OP_BRANCH:
				if ((funct3 != 3'b010) && (funct3 != 3'b011)) begin
					ctrl[11-:3] = 3'd2;
					ctrl[4] = 1'b1;
				end
				else
					illegal = 1'b1;
			rv_pkg_OP_LOAD:
				if (|{funct3 == 3'b000, funct3 == 3'b001, funct3 == 3'b010, funct3 == 3'b100, funct3 == 3'b101}) begin
					ctrl[19] = 1'b1;
					ctrl[18-:2] = 2'd0;
					ctrl[16] = 1'd1;
					ctrl[15-:4] = 4'd0;
					ctrl[11-:3] = 3'd0;
					ctrl[8] = 1'b1;
					ctrl[6-:2] = 2'd1;
				end
				else
					illegal = 1'b1;
			rv_pkg_OP_STORE:
				if (|{funct3 == 3'b000, funct3 == 3'b001, funct3 == 3'b010}) begin
					ctrl[18-:2] = 2'd0;
					ctrl[16] = 1'd1;
					ctrl[15-:4] = 4'd0;
					ctrl[11-:3] = 3'd1;
					ctrl[7] = 1'b1;
				end
				else
					illegal = 1'b1;
			rv_pkg_OP_IMM: begin
				ctrl[19] = 1'b1;
				ctrl[18-:2] = 2'd0;
				ctrl[16] = 1'd1;
				ctrl[11-:3] = 3'd0;
				ctrl[6-:2] = 2'd0;
				ctrl[15-:4] = alu_from_funct3(funct3, (funct3 == 3'b101) && inst[30]);
				if ((funct3 == 3'b001) && (funct7 != 7'b0000000))
					illegal = 1'b1;
				if (((funct3 == 3'b101) && (funct7 != 7'b0000000)) && (funct7 != 7'b0100000))
					illegal = 1'b1;
			end
			rv_pkg_OP_OP: begin
				ctrl[19] = 1'b1;
				ctrl[18-:2] = 2'd0;
				ctrl[16] = 1'd0;
				ctrl[6-:2] = 2'd0;
				ctrl[15-:4] = alu_from_funct3(funct3, inst[30]);
				if (!((funct7 == 7'b0000000) || ((funct7 == 7'b0100000) && ((funct3 == 3'b000) || (funct3 == 3'b101)))))
					illegal = 1'b1;
			end
			rv_pkg_OP_FENCE:
				if (funct3 != 3'b000)
					illegal = 1'b1;
			rv_pkg_OP_SYSTEM:
				if ((inst == 32'h00000073) || (inst == 32'h00100073))
					ctrl[1] = 1'b1;
				else
					illegal = 1'b1;
			default: illegal = 1'b1;
		endcase
		if (illegal) begin
			ctrl = 1'sb0;
			ctrl[0] = 1'b1;
		end
	end
	initial _sv2v_0 = 0;
endmodule
module lsu (
	funct3,
	addr_lo,
	is_load,
	is_store,
	store_data,
	mem_wdata,
	mem_be,
	mem_rdata,
	load_data,
	misaligned
);
	reg _sv2v_0;
	input wire [2:0] funct3;
	input wire [1:0] addr_lo;
	input wire is_load;
	input wire is_store;
	input wire [31:0] store_data;
	output reg [31:0] mem_wdata;
	output reg [3:0] mem_be;
	input wire [31:0] mem_rdata;
	output reg [31:0] load_data;
	output reg misaligned;
	wire [15:0] shifted;
	function automatic [15:0] sv2v_cast_16;
		input reg [15:0] inp;
		sv2v_cast_16 = inp;
	endfunction
	assign shifted = sv2v_cast_16(mem_rdata >> {addr_lo, 3'b000});
	always @(*) begin
		if (_sv2v_0)
			;
		mem_wdata = 32'b00000000000000000000000000000000;
		mem_be = 4'b0000;
		if (is_store)
			(* full_case, parallel_case *)
			case (funct3[1:0])
				2'b00: begin
					mem_wdata = {4 {store_data[7:0]}};
					mem_be = 4'b0001 << addr_lo;
				end
				2'b01: begin
					mem_wdata = {2 {store_data[15:0]}};
					mem_be = 4'b0011 << addr_lo;
				end
				2'b10: begin
					mem_wdata = store_data;
					mem_be = 4'b1111;
				end
				default:
					;
			endcase
		(* full_case, parallel_case *)
		case (funct3)
			3'b000: load_data = {{24 {shifted[7]}}, shifted[7:0]};
			3'b001: load_data = {{16 {shifted[15]}}, shifted[15:0]};
			3'b010: load_data = mem_rdata;
			3'b100: load_data = {24'b000000000000000000000000, shifted[7:0]};
			3'b101: load_data = {16'b0000000000000000, shifted[15:0]};
			default: load_data = 32'b00000000000000000000000000000000;
		endcase
		misaligned = (is_load || is_store) && (((funct3[1:0] == 2'b01) && addr_lo[0]) || ((funct3[1:0] == 2'b10) && (addr_lo != 2'b00)));
	end
	initial _sv2v_0 = 0;
endmodule
module core_pipe (
	clk,
	rst,
	imem_addr,
	imem_rdata,
	dmem_addr,
	dmem_we,
	dmem_be,
	dmem_wdata,
	dmem_rdata,
	ret_valid,
	ret_pc,
	ret_inst,
	ret_rd_we,
	ret_rd,
	ret_rd_data,
	ret_load,
	ret_store,
	ret_mem_addr,
	ret_store_data,
	ret_halt,
	ret_illegal,
	ret_misaligned,
	perf_stall,
	perf_flush
);
	reg _sv2v_0;
	parameter signed [31:0] BTB_ENTRIES = 64;
	input wire clk;
	input wire rst;
	output wire [31:0] imem_addr;
	input wire [31:0] imem_rdata;
	output wire [31:0] dmem_addr;
	output wire dmem_we;
	output wire [3:0] dmem_be;
	output wire [31:0] dmem_wdata;
	input wire [31:0] dmem_rdata;
	output wire ret_valid;
	output wire [31:0] ret_pc;
	output wire [31:0] ret_inst;
	output wire ret_rd_we;
	output wire [4:0] ret_rd;
	output wire [31:0] ret_rd_data;
	output wire ret_load;
	output wire ret_store;
	output wire [31:0] ret_mem_addr;
	output wire [31:0] ret_store_data;
	output wire ret_halt;
	output wire ret_illegal;
	output wire ret_misaligned;
	output wire perf_stall;
	output wire perf_flush;
	reg [96:0] ifid;
	reg [227:0] idex;
	reg [186:0] exmem;
	reg [171:0] memwb;
	wire stall;
	wire redirect;
	wire [31:0] redirect_pc;
	reg [31:0] pc_f;
	reg [31:0] pc_f_next;
	wire [31:0] pred_next_f;
	localparam signed [31:0] NB = (BTB_ENTRIES > 0 ? BTB_ENTRIES : 1);
	localparam signed [31:0] IB = (NB > 1 ? $clog2(NB) : 1);
	reg btb_valid [0:NB - 1];
	reg [31:0] btb_pc [0:NB - 1];
	reg [31:0] btb_target [0:NB - 1];
	reg [1:0] btb_ctr [0:NB - 1];
	wire [IB - 1:0] idx_f;
	wire pred_taken_f;
	function automatic [IB - 1:0] sv2v_cast_5381C;
		input reg [IB - 1:0] inp;
		sv2v_cast_5381C = inp;
	endfunction
	assign idx_f = sv2v_cast_5381C(pc_f >> 2);
	assign pred_taken_f = (((BTB_ENTRIES > 0) && btb_valid[idx_f]) && (btb_pc[idx_f] == pc_f)) && btb_ctr[idx_f][1];
	assign pred_next_f = (pred_taken_f ? btb_target[idx_f] : pc_f + 32'd4);
	localparam [31:0] rv_pkg_RESET_PC = 32'h80000000;
	always @(*) begin
		if (_sv2v_0)
			;
		if (rst)
			pc_f_next = rv_pkg_RESET_PC;
		else if (redirect)
			pc_f_next = redirect_pc;
		else if (stall)
			pc_f_next = pc_f;
		else
			pc_f_next = pred_next_f;
	end
	assign imem_addr = pc_f_next;
	always @(posedge clk) pc_f <= pc_f_next;
	always @(posedge clk)
		if (rst || redirect)
			ifid <= 1'sb0;
		else if (!stall)
			ifid <= {1'b1, pc_f, imem_rdata, pred_next_f};
	wire [19:0] ctrl_d;
	wire [31:0] imm_d;
	wire [31:0] rf_rdata1;
	wire [31:0] rf_rdata2;
	wire [31:0] rs1_val_d;
	wire [31:0] rs2_val_d;
	wire [4:0] rs1_d;
	wire [4:0] rs2_d;
	wire [4:0] rd_d;
	wire [6:0] opcode_d;
	wire uses_rs1_d;
	wire uses_rs2_d;
	assign rs1_d = ifid[51:47];
	assign rs2_d = ifid[56:52];
	assign rd_d = ifid[43:39];
	assign opcode_d = ifid[38:32];
	decoder u_decoder(
		.inst(ifid[63-:32]),
		.ctrl(ctrl_d)
	);
	immgen u_immgen(
		.inst(ifid[63-:32]),
		.sel(ctrl_d[11-:3]),
		.imm(imm_d)
	);
	wire wb_we;
	wire [4:0] wb_rd;
	wire [31:0] wb_data;
	regfile u_regfile(
		.clk(clk),
		.we(wb_we),
		.waddr(wb_rd),
		.wdata(wb_data),
		.raddr1(rs1_d),
		.raddr2(rs2_d),
		.rdata1(rf_rdata1),
		.rdata2(rf_rdata2)
	);
	assign rs1_val_d = ((wb_we && (rs1_d != 5'd0)) && (wb_rd == rs1_d) ? wb_data : rf_rdata1);
	assign rs2_val_d = ((wb_we && (rs2_d != 5'd0)) && (wb_rd == rs2_d) ? wb_data : rf_rdata2);
	localparam [6:0] rv_pkg_OP_AUIPC = 7'b0010111;
	localparam [6:0] rv_pkg_OP_JAL = 7'b1101111;
	localparam [6:0] rv_pkg_OP_LUI = 7'b0110111;
	assign uses_rs1_d = !(((opcode_d == rv_pkg_OP_LUI) || (opcode_d == rv_pkg_OP_AUIPC)) || (opcode_d == rv_pkg_OP_JAL));
	localparam [6:0] rv_pkg_OP_BRANCH = 7'b1100011;
	localparam [6:0] rv_pkg_OP_OP = 7'b0110011;
	localparam [6:0] rv_pkg_OP_STORE = 7'b0100011;
	assign uses_rs2_d = ((opcode_d == rv_pkg_OP_BRANCH) || (opcode_d == rv_pkg_OP_STORE)) || (opcode_d == rv_pkg_OP_OP);
	assign stall = (((ifid[96] && idex[227]) && idex[119]) && (idex[100-:5] != 5'd0)) && ((uses_rs1_d && (idex[100-:5] == rs1_d)) || (uses_rs2_d && (idex[100-:5] == rs2_d)));
	function automatic [31:0] sv2v_cast_32;
		input reg [31:0] inp;
		sv2v_cast_32 = inp;
	endfunction
	always @(posedge clk)
		if ((rst || redirect) || stall)
			idex <= 1'sb0;
		else
			idex <= {ifid[96], sv2v_cast_32(ifid[95-:32]), sv2v_cast_32(ifid[63-:32]), sv2v_cast_32(ifid[31-:32]), ctrl_d, rs1_d, rs2_d, rd_d, rs1_val_d, rs2_val_d, imm_d};
	wire [31:0] fwd1;
	wire [31:0] fwd2;
	reg [31:0] alu_a;
	wire [31:0] alu_b;
	wire [31:0] alu_y;
	reg take;
	reg [31:0] next_e;
	wire [31:0] pc_plus4_e;
	wire [31:0] target_e;
	function automatic [31:0] forward;
		input reg [4:0] r;
		input reg [31:0] from_id;
		reg [0:1] _sv2v_jump;
		begin
			_sv2v_jump = 2'b00;
			if ((((exmem[186] && exmem[121]) && !exmem[110]) && (r != 5'd0)) && (exmem[101-:5] == r)) begin
				forward = exmem[64-:32];
				_sv2v_jump = 2'b11;
			end
			if (_sv2v_jump == 2'b00) begin
				if (((memwb[171] && memwb[106]) && (r != 5'd0)) && (memwb[105-:5] == r)) begin
					forward = memwb[100-:32];
					_sv2v_jump = 2'b11;
				end
				if (_sv2v_jump == 2'b00) begin
					forward = from_id;
					_sv2v_jump = 2'b11;
				end
			end
		end
	endfunction
	assign fwd1 = forward(idex[110-:5], idex[95-:32]);
	assign fwd2 = forward(idex[105-:5], idex[63-:32]);
	always @(*) begin
		if (_sv2v_0)
			;
		(* full_case, parallel_case *)
		case (idex[129-:2])
			2'd0: alu_a = fwd1;
			2'd1: alu_a = idex[226-:32];
			2'd2: alu_a = 32'b00000000000000000000000000000000;
			default: alu_a = 32'b00000000000000000000000000000000;
		endcase
	end
	assign alu_b = (idex[127] == 1'd1 ? idex[31-:32] : fwd2);
	alu u_alu(
		.op(idex[126-:4]),
		.a(alu_a),
		.b(alu_b),
		.y(alu_y)
	);
	always @(*) begin
		if (_sv2v_0)
			;
		(* full_case, parallel_case *)
		case (idex[177:175])
			3'b000: take = fwd1 == fwd2;
			3'b001: take = fwd1 != fwd2;
			3'b100: take = $signed(fwd1) < $signed(fwd2);
			3'b101: take = $signed(fwd1) >= $signed(fwd2);
			3'b110: take = fwd1 < fwd2;
			3'b111: take = fwd1 >= fwd2;
			default: take = 1'b0;
		endcase
	end
	assign pc_plus4_e = idex[226-:32] + 32'd4;
	assign target_e = idex[226-:32] + idex[31-:32];
	always @(*) begin
		if (_sv2v_0)
			;
		if (idex[113])
			next_e = {alu_y[31:1], 1'b0};
		else if (idex[114] || (idex[115] && take))
			next_e = target_e;
		else
			next_e = pc_plus4_e;
	end
	assign redirect = idex[227] && (next_e != idex[162-:32]);
	assign redirect_pc = next_e;
	wire [IB - 1:0] idx_e;
	wire taken_e;
	assign idx_e = sv2v_cast_5381C(idex[226-:32] >> 2);
	assign taken_e = idex[114] || take;
	always @(posedge clk)
		if (rst) begin : sv2v_autoblock_1
			reg signed [31:0] i;
			for (i = 0; i < NB; i = i + 1)
				btb_valid[i] <= 1'b0;
		end
		else if (((BTB_ENTRIES > 0) && idex[227]) && (idex[115] || idex[114])) begin
			if (btb_valid[idx_e] && (btb_pc[idx_e] == idex[226-:32])) begin
				if (taken_e && (btb_ctr[idx_e] != 2'b11))
					btb_ctr[idx_e] <= btb_ctr[idx_e] + 2'b01;
				if (!taken_e && (btb_ctr[idx_e] != 2'b00))
					btb_ctr[idx_e] <= btb_ctr[idx_e] - 2'b01;
			end
			else if (taken_e) begin
				btb_valid[idx_e] <= 1'b1;
				btb_pc[idx_e] <= idex[226-:32];
				btb_target[idx_e] <= target_e;
				btb_ctr[idx_e] <= 2'b10;
			end
		end
	wire misaligned_e;
	wire [31:0] unused_load_e;
	lsu u_lsu_store(
		.funct3(idex[177:175]),
		.addr_lo(alu_y[1:0]),
		.is_load(idex[227] && idex[119]),
		.is_store(idex[227] && idex[118]),
		.store_data(fwd2),
		.mem_wdata(dmem_wdata),
		.mem_be(dmem_be),
		.mem_rdata(32'b00000000000000000000000000000000),
		.load_data(unused_load_e),
		.misaligned(misaligned_e)
	);
	assign dmem_addr = alu_y;
	assign dmem_we = (idex[227] && idex[118]) && !misaligned_e;
	function automatic [19:0] sv2v_cast_20;
		input reg [19:0] inp;
		sv2v_cast_20 = inp;
	endfunction
	function automatic [4:0] sv2v_cast_5;
		input reg [4:0] inp;
		sv2v_cast_5 = inp;
	endfunction
	always @(posedge clk)
		if (rst)
			exmem <= 1'sb0;
		else
			exmem <= {idex[227], sv2v_cast_32(idex[226-:32]), sv2v_cast_32(idex[194-:32]), sv2v_cast_20(idex[130-:20]), sv2v_cast_5(idex[100-:5]), alu_y, (idex[117-:2] == 2'd2 ? pc_plus4_e : alu_y), fwd2, misaligned_e};
	wire [31:0] load_data;
	wire misaligned_m;
	wire [31:0] unused_wdata_m;
	wire [3:0] unused_be_m;
	wire unused_misaligned_m;
	assign misaligned_m = exmem[0];
	lsu u_lsu_load(
		.funct3(exmem[136:134]),
		.addr_lo(exmem[66:65]),
		.is_load(1'b0),
		.is_store(1'b0),
		.store_data(32'b00000000000000000000000000000000),
		.mem_wdata(unused_wdata_m),
		.mem_be(unused_be_m),
		.mem_rdata(dmem_rdata),
		.load_data(load_data),
		.misaligned(unused_misaligned_m)
	);
	always @(posedge clk)
		if (rst)
			memwb <= 1'sb0;
		else
			memwb <= {exmem[186], exmem[185-:32], exmem[153-:32], exmem[121] && !misaligned_m, exmem[101-:5], (exmem[108-:2] == 2'd1 ? load_data : exmem[64-:32]), exmem[110], exmem[109], exmem[96-:32], exmem[32-:32], exmem[103], exmem[102], misaligned_m};
	assign wb_we = memwb[171] && memwb[106];
	assign wb_rd = memwb[105-:5];
	assign wb_data = memwb[100-:32];
	assign ret_valid = memwb[171];
	assign ret_pc = memwb[170-:32];
	assign ret_inst = memwb[138-:32];
	assign ret_rd_we = wb_we && (memwb[105-:5] != 5'd0);
	assign ret_rd = memwb[105-:5];
	assign ret_rd_data = memwb[100-:32];
	assign ret_load = memwb[68];
	assign ret_store = memwb[67];
	assign ret_mem_addr = memwb[66-:32];
	assign ret_store_data = memwb[34-:32];
	assign ret_halt = memwb[2];
	assign ret_illegal = memwb[1];
	assign ret_misaligned = memwb[0];
	assign perf_stall = stall && !redirect;
	assign perf_flush = redirect;
	initial _sv2v_0 = 0;
endmodule
module fpga_rom (
	clk,
	addr,
	rdata
);
	parameter [31:0] WORDS = 8192;
	parameter INIT_FILE = "imem.hex";
	input wire clk;
	input wire [$clog2(WORDS) - 1:0] addr;
	output reg [31:0] rdata;
	reg [31:0] rom [0:WORDS - 1];
	initial $readmemh(INIT_FILE, rom);
	always @(posedge clk) rdata <= rom[addr];
endmodule
module fpga_ram8 (
	clk,
	addr,
	we,
	wdata,
	rdata
);
	parameter [31:0] WORDS = 8192;
	parameter INIT_FILE = "dmem_b0.hex";
	input wire clk;
	input wire [$clog2(WORDS) - 1:0] addr;
	input wire we;
	input wire [7:0] wdata;
	output reg [7:0] rdata;
	reg [7:0] ram [0:WORDS - 1];
	initial $readmemh(INIT_FILE, ram);
	always @(posedge clk) begin
		if (we)
			ram[addr] <= wdata;
		rdata <= ram[addr];
	end
endmodule
module uart_tx (
	clk,
	rst,
	start,
	data,
	busy,
	tx
);
	parameter [31:0] CLKS_PER_BIT = 434;
	input wire clk;
	input wire rst;
	input wire start;
	input wire [7:0] data;
	output wire busy;
	output reg tx;
	reg [9:0] shift;
	reg [3:0] bits_left;
	reg [15:0] timer;
	assign busy = bits_left != 0;
	function automatic [15:0] sv2v_cast_16;
		input reg [15:0] inp;
		sv2v_cast_16 = inp;
	endfunction
	always @(posedge clk) begin
		if (rst) begin
			tx <= 1'b1;
			bits_left <= 1'sb0;
			timer <= 1'sb0;
			shift <= 1'sb1;
		end
		else if (start && !busy) begin
			shift <= {1'b1, data, 1'b0};
			bits_left <= 4'd10;
			timer <= 1'sb0;
		end
		else if (busy) begin
			if (timer == sv2v_cast_16(CLKS_PER_BIT - 1)) begin
				timer <= 1'sb0;
				shift <= {1'b1, shift[9:1]};
				bits_left <= bits_left - 4'd1;
			end
			else
				timer <= timer + 16'd1;
		end
		tx <= (busy ? shift[0] : 1'b1);
	end
endmodule
module hex7seg (
	digit,
	seg
);
	reg _sv2v_0;
	input wire [3:0] digit;
	output reg [6:0] seg;
	always @(*) begin
		if (_sv2v_0)
			;
		case (digit)
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
			4'ha: seg = ~7'b1110111;
			4'hb: seg = ~7'b1111100;
			4'hc: seg = ~7'b0111001;
			4'hd: seg = ~7'b1011110;
			4'he: seg = ~7'b1111001;
			default: seg = ~7'b1110001;
		endcase
	end
	initial _sv2v_0 = 0;
endmodule
module de2_115_top (
	CLOCK_50,
	KEY,
	SW,
	LEDG,
	LEDR,
	HEX0,
	HEX1,
	HEX2,
	HEX3,
	HEX4,
	HEX5,
	HEX6,
	HEX7,
	UART_TXD
);
	reg _sv2v_0;
	parameter INIT_DIR = "mem/";
	parameter [31:0] CLKS_PER_BIT = 434;
	parameter [31:0] TOHOST = 32'h800045c0;
	input wire CLOCK_50;
	input wire [3:0] KEY;
	input wire [17:0] SW;
	output wire [8:0] LEDG;
	output wire [17:0] LEDR;
	output wire [6:0] HEX0;
	output wire [6:0] HEX1;
	output wire [6:0] HEX2;
	output wire [6:0] HEX3;
	output wire [6:0] HEX4;
	output wire [6:0] HEX5;
	output wire [6:0] HEX6;
	output wire [6:0] HEX7;
	output wire UART_TXD;
	wire clk;
	assign clk = CLOCK_50;
	reg [1:0] key_sync;
	reg [3:0] rst_cnt;
	wire rst;
	always @(posedge clk) begin
		key_sync <= {key_sync[0], KEY[0]};
		if (!key_sync[1])
			rst_cnt <= 1'sb0;
		else if (rst_cnt != 4'hf)
			rst_cnt <= rst_cnt + 4'd1;
	end
	assign rst = rst_cnt != 4'hf;
	wire [31:0] imem_addr;
	wire [31:0] imem_rdata;
	wire [31:0] dmem_addr;
	wire [31:0] dmem_wdata;
	wire [31:0] dmem_rdata;
	wire [31:0] ram_rdata;
	wire dmem_we;
	wire [3:0] dmem_be;
	wire ret_valid;
	wire ret_rd_we;
	wire ret_load;
	wire ret_store;
	wire ret_halt;
	wire ret_illegal;
	wire ret_misaligned;
	wire [31:0] ret_pc;
	wire [31:0] ret_inst;
	wire [31:0] ret_rd_data;
	wire [31:0] ret_mem_addr;
	wire [31:0] ret_store_data;
	wire [4:0] ret_rd;
	wire perf_stall;
	wire perf_flush;
	core_pipe #(.BTB_ENTRIES(64)) u_core(
		.clk(clk),
		.rst(rst),
		.imem_addr(imem_addr),
		.imem_rdata(imem_rdata),
		.dmem_addr(dmem_addr),
		.dmem_we(dmem_we),
		.dmem_be(dmem_be),
		.dmem_wdata(dmem_wdata),
		.dmem_rdata(dmem_rdata),
		.ret_valid(ret_valid),
		.ret_pc(ret_pc),
		.ret_inst(ret_inst),
		.ret_rd_we(ret_rd_we),
		.ret_rd(ret_rd),
		.ret_rd_data(ret_rd_data),
		.ret_load(ret_load),
		.ret_store(ret_store),
		.ret_mem_addr(ret_mem_addr),
		.ret_store_data(ret_store_data),
		.ret_halt(ret_halt),
		.ret_illegal(ret_illegal),
		.ret_misaligned(ret_misaligned),
		.perf_stall(perf_stall),
		.perf_flush(perf_flush)
	);
	wire is_ram;
	assign is_ram = dmem_addr[31:28] == 4'h8;
	fpga_rom #(
		.WORDS(8192),
		.INIT_FILE({INIT_DIR, "imem.hex"})
	) u_imem(
		.clk(clk),
		.addr(imem_addr[14:2]),
		.rdata(imem_rdata)
	);
	wire [3:0] lane_we;
	assign lane_we = {4 {dmem_we && is_ram}} & dmem_be;
	fpga_ram8 #(
		.WORDS(8192),
		.INIT_FILE({INIT_DIR, "dmem_b0.hex"})
	) u_lane0(
		.clk(clk),
		.addr(dmem_addr[14:2]),
		.we(lane_we[0]),
		.wdata(dmem_wdata[7:0]),
		.rdata(ram_rdata[7:0])
	);
	fpga_ram8 #(
		.WORDS(8192),
		.INIT_FILE({INIT_DIR, "dmem_b1.hex"})
	) u_lane1(
		.clk(clk),
		.addr(dmem_addr[14:2]),
		.we(lane_we[1]),
		.wdata(dmem_wdata[15:8]),
		.rdata(ram_rdata[15:8])
	);
	fpga_ram8 #(
		.WORDS(8192),
		.INIT_FILE({INIT_DIR, "dmem_b2.hex"})
	) u_lane2(
		.clk(clk),
		.addr(dmem_addr[14:2]),
		.we(lane_we[2]),
		.wdata(dmem_wdata[23:16]),
		.rdata(ram_rdata[23:16])
	);
	fpga_ram8 #(
		.WORDS(8192),
		.INIT_FILE({INIT_DIR, "dmem_b3.hex"})
	) u_lane3(
		.clk(clk),
		.addr(dmem_addr[14:2]),
		.we(lane_we[3]),
		.wdata(dmem_wdata[31:24]),
		.rdata(ram_rdata[31:24])
	);
	localparam [31:0] UART_DATA = 32'h10000000;
	localparam [31:0] UART_STATUS = 32'h10000004;
	localparam [31:0] CYCLE_COUNT = 32'h1000000c;
	localparam [31:0] DISPLAY = 32'h10000010;
	reg [31:0] cycles;
	reg [31:0] instret;
	reg [31:0] flushes;
	reg [31:0] run_cycles;
	reg [31:0] display;
	reg running;
	reg done;
	reg pass;
	reg [7:0] last_char;
	wire uart_busy;
	wire uart_start;
	wire [31:0] waddr;
	assign waddr = {dmem_addr[31:2], 2'b00};
	assign uart_start = (dmem_we && (waddr == UART_DATA)) && !uart_busy;
	uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_uart(
		.clk(clk),
		.rst(rst),
		.start(uart_start),
		.data(dmem_wdata[7:0]),
		.busy(uart_busy),
		.tx(UART_TXD)
	);
	always @(posedge clk)
		if (rst) begin
			cycles <= 1'sb0;
			instret <= 1'sb0;
			flushes <= 1'sb0;
			run_cycles <= 1'sb0;
			running <= 1'b1;
			done <= 1'b0;
			pass <= 1'b0;
			display <= 1'sb0;
			last_char <= 1'sb0;
		end
		else begin
			cycles <= cycles + 32'd1;
			if (running) begin
				run_cycles <= run_cycles + 32'd1;
				if (ret_valid)
					instret <= instret + 32'd1;
				if (perf_flush)
					flushes <= flushes + 32'd1;
			end
			if (dmem_we && (waddr == DISPLAY))
				display <= dmem_wdata;
			if (uart_start)
				last_char <= dmem_wdata[7:0];
			if ((dmem_we && (waddr == TOHOST)) && running) begin
				running <= 1'b0;
				done <= 1'b1;
				pass <= dmem_wdata == 32'd1;
			end
		end
	reg [31:0] mmio_rdata;
	reg [31:0] mmio_rdata_q;
	reg is_mmio_q;
	always @(*) begin
		if (_sv2v_0)
			;
		case (waddr)
			CYCLE_COUNT: mmio_rdata = cycles;
			UART_STATUS: mmio_rdata = {31'b0000000000000000000000000000000, uart_busy};
			default: mmio_rdata = 32'b00000000000000000000000000000000;
		endcase
	end
	always @(posedge clk) begin
		is_mmio_q <= !is_ram;
		mmio_rdata_q <= mmio_rdata;
	end
	assign dmem_rdata = (is_mmio_q ? mmio_rdata_q : ram_rdata);
	reg [31:0] shown;
	always @(*) begin
		if (_sv2v_0)
			;
		case (SW[1:0])
			2'b00: shown = display;
			2'b01: shown = run_cycles;
			2'b10: shown = instret;
			default: shown = flushes;
		endcase
	end
	assign LEDG = {pass, done, 6'b000000, running & cycles[23]};
	assign LEDR = {done & !pass, 9'b000000000, last_char};
	hex7seg u_h0(
		.digit(shown[3:0]),
		.seg(HEX0)
	);
	hex7seg u_h1(
		.digit(shown[7:4]),
		.seg(HEX1)
	);
	hex7seg u_h2(
		.digit(shown[11:8]),
		.seg(HEX2)
	);
	hex7seg u_h3(
		.digit(shown[15:12]),
		.seg(HEX3)
	);
	hex7seg u_h4(
		.digit(shown[19:16]),
		.seg(HEX4)
	);
	hex7seg u_h5(
		.digit(shown[23:20]),
		.seg(HEX5)
	);
	hex7seg u_h6(
		.digit(shown[27:24]),
		.seg(HEX6)
	);
	hex7seg u_h7(
		.digit(shown[31:28]),
		.seg(HEX7)
	);
	wire unused;
	assign unused = ^{ret_pc, ret_inst, ret_rd_we, ret_rd, ret_rd_data, ret_load, ret_store, ret_mem_addr, ret_store_data, ret_halt, ret_illegal, ret_misaligned, perf_stall, KEY[3:1], SW[17:2], dmem_addr[1:0], imem_addr[31:15], imem_addr[1:0]};
	initial _sv2v_0 = 0;
endmodule
