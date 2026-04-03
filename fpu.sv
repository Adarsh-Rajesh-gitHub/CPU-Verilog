module fpu(
    input [63:0] a,
    input [63:0] b,
    input [4:0] fpu_op,
    output reg [63:0] result
);

//will comeback

reg sign, sign_a, sign_b;
reg [10:0] exp_1, exp_2, diff;
reg [52:0] mant_1, mant_2;
reg [11:0] exp_res;
reg [52:0] mant_res;
reg [53:0] temp;
reg [105:0] temp_big;

always @(*) begin
    case (fpu_op)        
        5'h00, 5'h01:  begin //subf or addf for sub do addf but //just reverse on e sign and change op code
                    //align exponents by incrementing smaller exp and shifting mantissa to right till both equal, add mantissas sign same then add else subtract smaller mag form bigger mag and take sign of biggest mag, in end also check if mantiss over 1 on significant bit and if so just add 1 to exp and if mantissa such that leading bit shift left one and subtract 1 to exp
            if(a[62:0] == 0) 
                if(fpu_op == 5'h00) result = b;
                else result = -b;
            else if(b[62:0] == 0) result = a;
            else begin
                sign_a = a[63];
                sign_b = b[63] ^ (fpu_op == 5'h01);

                exp_1 = a[62:52];
                exp_2 = b[62:52];
                mant_1 = {1'b1, a[51:0]};
                mant_2 = {1'b1, b[51:0]};

                diff = exp_1 > exp_2 ? exp_1-exp_2  : exp_2-exp_1;
                if (exp_1 > exp_2) begin
                    mant_2 = mant_2 >> diff;
                    exp_2 = exp_2 + diff;
                end

                if (exp_2 > exp_1) begin
                    mant_1 = mant_1 >> diff;
                    exp_1 = exp_1 + diff;
                end

                if (sign_a == sign_b) begin
                    sign = sign_a;
                    temp = mant_1 + mant_2;

                    if (temp[53]) begin
                        exp_1 = exp_1 + 1;
                        mant_res = temp[53:1];
                    end
                    else begin
                        mant_res = temp[52:0];
                    end
                end
                else begin
                    if (mant_1 >= mant_2) begin
                        sign = sign_a;
                        mant_res = mant_1 - mant_2;
                    end
                    else begin
                        sign = sign_b;
                        mant_res = mant_2 - mant_1;
                    end

                    if (mant_res == 0) begin
                        sign = 1'b0;
                        exp_1 = 11'd0;
                    end
                    else begin
                        while (!mant_res[52]) begin
                            mant_res = mant_res << 1;
                            exp_1 = exp_1 - 1;
                        end
                    end
                end
                result = {sign, exp_1[10:0], mant_res[51:0]};
            end
            
        end
        5'h02: begin//mulf
        //exponents-bias and add both and then add the bias, multiply mantissa assuming that on eahead and rewriter
            if((a[62:52] == 11'h7FF && a[51:0] != 0) || (b[62:52] == 11'h7FF && b[51:0] != 0))
                result = 64'h7FF8000000000000;
            else if((a[62:52] == 11'h7FF && a[51:0] == 0 && b[62:0] == 0) || (b[62:52] == 11'h7FF && b[51:0] == 0 && a[62:0] == 0))
                result = 64'h7FF8000000000000;
            else if((a[62:52] == 11'h7FF && a[51:0] == 0) || (b[62:52] == 11'h7FF && b[51:0] == 0))
                result = {a[63] ^ b[63], 11'h7FF, 52'd0};
            else if(a[62:0] == 0 || b[62:0] == 0)
                result = {a[63] ^ b[63], 11'd0, 52'd0};
            else begin
                sign = a[63] ^ b[63];
                exp_1 = a[62:52] - 1023;
                exp_2 = b[62:52] - 1023;
                mant_1 = {1'b1, a[51:0]};
                mant_2 = {1'b1, b[51:0]};
                temp_big = mant_1 * mant_2;
                exp_res = exp_1 + exp_2 + 1023;

                if (temp_big[105]) begin
                    mant_res = temp_big[105:53];
                    exp_res = exp_res + 1;
                end
                else begin
                    mant_res = temp_big[104:52];
                end

                result = {sign, exp_res[10:0], mant_res[51:0]};
            end
        end
        5'h03: begin//divf
            //just do opposite of mulf
            if((a[62:52] == 11'h7FF && a[51:0] != 0) || (b[62:52] == 11'h7FF && b[51:0] != 0))
                result = 64'h7FF8000000000000;
            else if((a[62:52] == 11'h7FF && a[51:0] == 0) && (b[62:52] == 11'h7FF && b[51:0] == 0))
                result = 64'h7FF8000000000000;
            else if(a[62:0] == 0 && b[62:0] == 0)
                result = 64'h7FF8000000000000;
            else if(a[62:52] == 11'h7FF && a[51:0] == 0)
                result = {a[63] ^ b[63], 11'h7FF, 52'd0};
            else if(b[62:52] == 11'h7FF && b[51:0] == 0)
                result = {a[63] ^ b[63], 11'd0, 52'd0};
            else begin
                sign = a[63] ^ b[63];
                exp_1 = a[62:52];
                exp_2 = b[62:52];
                mant_1 = {1'b1, a[51:0]};
                mant_2 = {1'b1, b[51:0]};

                if (mant_2 == 0 && exp_2 == 0) begin
                    result = 64'h7FF8000000000000;
                end
                else begin
                    exp_res = exp_1 - exp_2 + 1023;
                    temp_big = ({53'd0, mant_1} << 52) / mant_2;
                    mant_res = temp_big[52:0];

                    if (mant_res < (53'd1 << 52)) begin
                        mant_res = mant_res << 1;
                        exp_res = exp_res - 1;
                    end

                    result = {sign, exp_res[10:0], mant_res[51:0]};
                end
            end
        end
        default: result = 64'd0;
    endcase
end

endmodule