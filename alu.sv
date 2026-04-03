module alu(
    input [4:0] alu_op,
    input [63:0] a,
    input [63:0] b,
    output reg [63:0] result
);

always @(*) begin
    case (alu_op)
        5'h00: result = a & b;
        5'h01: result = a | b;
        5'h02: result = a ^ b;
        5'h03: result = ~a;
        5'h04: result = a >> b[5:0];
        5'h05: result = a << b[5:0];
        5'h06: result = $signed(a) + $signed(b);
        5'h07: result = $signed(a) - $signed(b);
        5'h08: result = a;
        5'h09: result = {b[11:0], a[51:0]};
        5'h0A: result = $signed(a) * $signed(b);
        5'h0B: result = (b != 0) ? ($signed(a) / $signed(b)) : 64'd0;
        default: result = 64'd0;
    endcase
end

endmodule