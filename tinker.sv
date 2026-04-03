`include "instruction_fetch.sv"
`include "instruction_decoder.sv"
`include "register_file.sv"
`include "alu.sv"
`include "fpu.sv"
`include "memory.sv"

module tinker_core(
    input clk,
    input reset
);

wire [63:0] pc;


initial begin
    pc = 64'h2000;
end

wire [63:0] pc = 64'h2000;
reg [63:0] next_pc;
wire [31:0] instruction;

wire [4:0] opcode, rd, rs, rt;
wire [11:0] L;

wire use_alu, use_fpu, is_literal, reg_write;
wire br_abs, br_rel_reg, br_rel_lit, br_nz, br_gt, call_inst, return_inst;
wire [4:0] alu_op, fpu_op;

wire [63:0] rd_data, rs_data, rt_data, r31_data;
wire [63:0] alu_a, alu_b;
wire [63:0] alu_result, fpu_result, write_data;

wire [63:0] literal_ext;
wire [63:0] branch_offset;
wire [63:0] mem_addr;
wire [63:0] mem_write_data;
wire [63:0] mem_data;
wire mem_write;

assign literal_ext = {52'b0, L};
assign branch_offset = {{52{L[11]}}, L};

assign alu_a = is_literal ? rd_data : rs_data;
assign alu_b = is_literal ? literal_ext : rt_data;
assign write_data = use_fpu ? fpu_result : alu_result;

assign mem_addr = r31_data - 64'd8;
assign mem_write_data = pc + 64'd4;
assign mem_write = call_inst;

always @(*) begin
    if (return_inst)
        next_pc = mem_data;
    else if (call_inst)
        next_pc = rd_data;
    else if (br_abs)
        next_pc = rd_data;
    else if (br_rel_reg)
        next_pc = pc + rd_data;
    else if (br_rel_lit)
        next_pc = pc + branch_offset;
    else if (br_nz) begin
        if (rs_data != 64'd0)
            next_pc = rd_data;
        else
            next_pc = pc + 64'd4;
    end
    else if (br_gt) begin
        if ($signed(rs_data) > $signed(rt_data))
            next_pc = rd_data;
        else
            next_pc = pc + 64'd4;
    end
    else
        next_pc = pc + 64'd4;
end

instruction_fetch fetch(.clk(clk), .reset(reset), .next_pc(next_pc), .pc(pc));
memory memory(.clk(clk), .reset(reset), .pc(pc), .instruction(instruction), .data_addr(mem_addr), .write_data(mem_write_data), .mem_write(mem_write), .data_read(mem_data));
instruction_decoder decoder(.instruction(instruction), .opcode(opcode), .rd(rd), .rs(rs), .rt(rt), .L(L), .use_alu(use_alu), .use_fpu(use_fpu), .is_literal(is_literal), .br_abs(br_abs), .br_rel_reg(br_rel_reg), .br_rel_lit(br_rel_lit), .br_nz(br_nz), .br_gt(br_gt), .call_inst(call_inst), .return_inst(return_inst), .alu_op(alu_op), .fpu_op(fpu_op), .reg_write(reg_write));
register_file reg_file(.clk(clk), .reset(reset), .rd(rd), .rs(rs), .rt(rt), .write_data(write_data), .reg_write(reg_write), .rd_data(rd_data), .rs_data(rs_data), .rt_data(rt_data), .r31_data(r31_data));
alu alu(.alu_op(alu_op), .a(alu_a), .b(alu_b), .result(alu_result));
fpu fpu(.fpu_op(fpu_op), .a(rs_data), .b(rt_data), .result(fpu_result));

endmodule