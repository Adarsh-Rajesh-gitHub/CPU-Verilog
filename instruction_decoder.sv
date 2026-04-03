module instruction_decoder(
    input [31:0] instruction,
    output [4:0] opcode,
    output [4:0] rd,
    output [4:0] rs,
    output [4:0] rt,
    output [11:0] L,
    output reg use_alu,
    output reg use_fpu,
    output reg is_literal,
    output reg br_abs,
    output reg br_rel_reg,
    output reg br_rel_lit,
    output reg br_nz,
    output reg br_gt,
    output reg call_inst,
    output reg return_inst,
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
    is_literal = 1'b0;
    br_abs = 1'b0;
    br_rel_reg = 1'b0;
    br_rel_lit = 1'b0;
    br_nz = 1'b0;
    br_gt = 1'b0;
    call_inst = 1'b0;
    return_inst = 1'b0;
    alu_op = 5'h00;
    fpu_op = 5'h00;
    reg_write = 1'b0;

    case (opcode)
        5'h00: begin use_alu = 1'b1; reg_write = 1'b1; alu_op = 5'h00; end
        5'h01: begin use_alu = 1'b1; reg_write = 1'b1; alu_op = 5'h01; end
        5'h02: begin use_alu = 1'b1; reg_write = 1'b1; alu_op = 5'h02; end
        5'h03: begin use_alu = 1'b1; reg_write = 1'b1; alu_op = 5'h03; end
        5'h04: begin use_alu = 1'b1; reg_write = 1'b1; alu_op = 5'h04; end
        5'h05: begin use_alu = 1'b1; is_literal = 1'b1; reg_write = 1'b1; alu_op = 5'h04; end
        5'h06: begin use_alu = 1'b1; reg_write = 1'b1; alu_op = 5'h05; end
        5'h07: begin use_alu = 1'b1; is_literal = 1'b1; reg_write = 1'b1; alu_op = 5'h05; end

        5'h08: begin br_abs = 1'b1; end
        5'h09: begin br_rel_reg = 1'b1; end
        5'h0A: begin br_rel_lit = 1'b1; end
        5'h0B: begin br_nz = 1'b1; end
        5'h0C: begin call_inst = 1'b1; end
        5'h0D: begin return_inst = 1'b1; end
        5'h0E: begin br_gt = 1'b1; end

        5'h11: begin use_alu = 1'b1; reg_write = 1'b1; alu_op = 5'h08; end
        5'h12: begin use_alu = 1'b1; is_literal = 1'b1; reg_write = 1'b1; alu_op = 5'h09; end

        5'h14: begin use_fpu = 1'b1; reg_write = 1'b1; fpu_op = 5'h00; end
        5'h15: begin use_fpu = 1'b1; reg_write = 1'b1; fpu_op = 5'h01; end
        5'h16: begin use_fpu = 1'b1; reg_write = 1'b1; fpu_op = 5'h02; end
        5'h17: begin use_fpu = 1'b1; reg_write = 1'b1; fpu_op = 5'h03; end

        5'h18: begin use_alu = 1'b1; reg_write = 1'b1; alu_op = 5'h06; end
        5'h19: begin use_alu = 1'b1; is_literal = 1'b1; reg_write = 1'b1; alu_op = 5'h06; end
        5'h1A: begin use_alu = 1'b1; reg_write = 1'b1; alu_op = 5'h07; end
        5'h1B: begin use_alu = 1'b1; is_literal = 1'b1; reg_write = 1'b1; alu_op = 5'h07; end
        5'h1C: begin use_alu = 1'b1; reg_write = 1'b1; alu_op = 5'h0A; end
        5'h1D: begin use_alu = 1'b1; reg_write = 1'b1; alu_op = 5'h0B; end

        default: begin end
    endcase
end

endmodule