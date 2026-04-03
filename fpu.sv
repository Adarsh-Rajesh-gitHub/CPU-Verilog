module fpu(
    input [63:0] a,
    input [63:0] b,
    input [4:0] fpu_op,
    output reg [63:0] result
);

//will comeback

reg sign;
reg [10:0] exp_1, exp_2;
reg [52:0] mant_1, mant_2;
reg [11:0] exp_res;
reg [52:0] mant_res;
always @(*) begin
    case (fpu_op)
        5'h00: begin//addf
            //align exponents by incrementing smaller exp and shifting mantissa to right till both equal, add mantissas sign same then add else subtract smaller mag form bigger mag and take sign of biggest mag, in end also check if mantiss over 1 on significant bit and if so just add 1 to exp and if mantissa such that leading bit shift left one and subtract 1 to exp
            result = 64'd0; 
            
        end
        5'h01: begin//subf
            result = 64'd0;
        end
        5'h02: begin//mulf
        //exponents-bias and add both and then add the bias, multiply mantissa assuming that on eahead and rewriter
            sign = a[63] ^ b[63];
            exp_1 = a[62:52] - 1023;
            exp_2 = b[62:52] - 1023;
            mant_1 = {1'b1, a[51:0]};
            mant_2 = {1'b1, b[51:0]};
            exp_res = exp_1 + exp_2 + 1023;
            mant_res = (mant_1 * mant_2) >> 52;
            result = {sign, exp_res[10:0], mant_res[51:0]};
        end
        5'h03: begin//divf
            result = 64'd0;
        end
        default: result = 64'd0;
    endcase
end

endmodule