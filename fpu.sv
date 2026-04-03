module fpu(
    input [63:0] a,
    input [63:0] b,
    input [4:0] fpu_op,
    output reg [63:0] result
);

//will comeback
always @(*) begin
    case (fpu_op)
        5'h00: result = 64'd0;
        5'h01: result = 64'd0;
        5'h02: result = 64'd0;
        5'h03: result = 64'd0;
        default: result = 64'd0;
    endcase
end

endmodule