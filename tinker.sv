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
wire [63:0] next_pc;
wire [31:0] instruction;

wire [4:0] opcode, rd, rs, rt;
wire [11:0] L;

wire use_alu, use_fpu, use_imm, reg_write;
wire [4:0] alu_op, fpu_op;

wire [63:0] rs_data, rt_data;
wire [63:0] alu_b;
wire [63:0] alu_result, fpu_result;
wire [63:0] write_data;

//temporary, will update for branch
assign next_pc = pc + 64'd4;
assign alu_b = use_imm ? {52'b0, L} : rt_data;
assign write_data = use_fpu ? fpu_result : alu_result;

instruction_fetch fetch(.clk(clk), .reset(reset), .next_pc(next_pc), .pc(pc));
memory memory(.clk(clk), .reset(reset), .pc(pc), .instruction(instruction));

instruction_decoder decoder(.instruction(instruction), .opcode(opcode), .rd(rd), .rs(rs), .rt(rt), .L(L), .use_alu(use_alu), .use_fpu(use_fpu), .use_imm(use_imm), .alu_op(alu_op), .fpu_op(fpu_op), .reg_write(reg_write));

register_file reg_file(.clk(clk), .reset(reset), .rd(rd), .rs(rs), .rt(rt), .write_data(write_data), .reg_write(reg_write), .rs_data(rs_data), .rt_data(rt_data));

alu alu(.alu_op(alu_op), .a(rs_data), .b(alu_b), .result(alu_result));
fpu fpu(.fpu_op(fpu_op), .a(rs_data), .b(rt_data), .result(fpu_result));

endmodule