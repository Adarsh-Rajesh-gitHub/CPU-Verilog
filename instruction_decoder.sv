module instruction_decoder(
    input [31:0] instruction,
    output [4:0] opcode,
    output [4:0] rd,
    output [4:0] rs,
    output [4:0] rt,
    output [11:0] L,
    output reg use_alu,
    output reg use_fpu,
    output reg use_imm,
    output reg [4:0] alu_op,
    output reg [4:0] fpu_op,
    output reg reg_write
);

assign opcode = instruction[31:27];
assign rd = instruction[26:22];
assign rs = instruction[21:17];
assign rt = instruction[16:12];
assign L = instruction[11:0];

always @(*) begin
    use_alu = 1'b0;
    use_fpu = 1'b0;
    use_imm = 1'b0;
    alu_op = 5'h00;
    fpu_op = 5'h00;
    reg_write = 1'b0;

    case (opcode)
        5'h00: begin use_alu = 1'b1; reg_write = 1'b1; alu_op = 5'h00; end // and
        5'h01: begin use_alu = 1'b1; reg_write = 1'b1; alu_op = 5'h01; end // or
        5'h02: begin use_alu = 1'b1; reg_write = 1'b1; alu_op = 5'h02; end // xor
        5'h03: begin use_alu = 1'b1; reg_write = 1'b1; alu_op = 5'h03; end // not
        5'h04: begin use_alu = 1'b1; reg_write = 1'b1; alu_op = 5'h04; end // shftr
        5'h05: begin use_alu = 1'b1; use_imm = 1'b1; reg_write = 1'b1; alu_op = 5'h04; end // shftri
        5'h06: begin use_alu = 1'b1; reg_write = 1'b1; alu_op = 5'h05; end // shftl
        5'h07: begin use_alu = 1'b1; use_imm = 1'b1; reg_write = 1'b1; alu_op = 5'h05; end // shftli

        5'h11: begin use_alu = 1'b1; reg_write = 1'b1; alu_op = 5'h08; end // mov rd, rs
        5'h12: begin use_alu = 1'b1; use_imm = 1'b1; reg_write = 1'b1; alu_op = 5'h09; end // mov rd, L

        5'h14: begin use_fpu = 1'b1; reg_write = 1'b1; fpu_op = 5'h00; end // addf
        5'h15: begin use_fpu = 1'b1; reg_write = 1'b1; fpu_op = 5'h01; end // subf
        5'h16: begin use_fpu = 1'b1; reg_write = 1'b1; fpu_op = 5'h02; end // mulf
        5'h17: begin use_fpu = 1'b1; reg_write = 1'b1; fpu_op = 5'h03; end // divf

        5'h18: begin use_alu = 1'b1; reg_write = 1'b1; alu_op = 5'h06; end // add
        5'h19: begin use_alu = 1'b1; use_imm = 1'b1; reg_write = 1'b1; alu_op = 5'h06; end // addi
        5'h1A: begin use_alu = 1'b1; reg_write = 1'b1; alu_op = 5'h07; end // sub
        5'h1B: begin use_alu = 1'b1; use_imm = 1'b1; reg_write = 1'b1; alu_op = 5'h07; end // subi
        5'h1C: begin use_alu = 1'b1; reg_write = 1'b1; alu_op = 5'h0A; end // mul
        5'h1D: begin use_alu = 1'b1; reg_write = 1'b1; alu_op = 5'h0B; end // div

        default: begin end
    endcase
end

endmodule