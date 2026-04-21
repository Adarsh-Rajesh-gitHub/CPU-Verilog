module fpu(
    input [63:0] a,
    input [63:0] b,
    input [4:0] fpu_op,
    output reg [63:0] result
);

reg sign_a;
reg sign_b;
reg sign_res;
reg [10:0] exp_a;
reg [10:0] exp_b;
reg [51:0] frac_a;
reg [51:0] frac_b;
reg [52:0] sig_a;
reg [52:0] sig_b;
reg [55:0] ext_a;
reg [55:0] ext_b;
reg [55:0] ext_res;
reg [56:0] ext_sum;
reg [105:0] product;
reg [108:0] div_num;
reg [56:0] div_quot;
reg [108:0] div_rem;
reg div_sticky;
reg a_is_nan;
reg b_is_nan;
reg a_is_inf;
reg b_is_inf;
reg a_is_zero;
reg b_is_zero;
integer exp_a_unbiased;
integer exp_b_unbiased;
integer exp_res_unbiased;
integer diff;
integer shift_amt;
integer i;

function [63:0] fp_qnan;
    begin
        fp_qnan = 64'h7FF8000000000000;
    end
endfunction

function [63:0] fp_inf;
    input sign_in;
    begin
        fp_inf = {sign_in, 11'h7FF, 52'd0};
    end
endfunction

function [63:0] fp_zero;
    input sign_in;
    begin
        fp_zero = {sign_in, 11'd0, 52'd0};
    end
endfunction

function [55:0] shr_sticky56;
    input [55:0] value_in;
    input integer sh;
    integer k;
    reg [55:0] temp;
    reg sticky;
    begin
        if (sh <= 0) begin
            shr_sticky56 = value_in;
        end
        else if (sh >= 56) begin
            shr_sticky56 = 56'd0;
            shr_sticky56[0] = |value_in;
        end
        else begin
            temp = value_in;
            sticky = 1'b0;
            for (k = 0; k < 56; k = k + 1) begin
                if (k < sh) begin
                    sticky = sticky | temp[0];
                    temp = temp >> 1;
                end
            end
            temp[0] = temp[0] | sticky;
            shr_sticky56 = temp;
        end
    end
endfunction

function [63:0] round_pack;
    input sign_in;
    input integer exp_in;
    input [55:0] ext_in;
    integer exp_work;
    integer sub_shift;
    reg [55:0] work;
    reg [53:0] sig_round;
    reg guard_bit;
    reg round_bit;
    reg sticky_bit;
    reg [10:0] packed_exp;
    begin
        work = ext_in;
        exp_work = exp_in;

        if (work == 56'd0) begin
            round_pack = fp_zero(1'b0);
        end
        else begin
            if (exp_work < -1022) begin
                sub_shift = -1022 - exp_work;
                work = shr_sticky56(work, sub_shift);
                exp_work = -1022;
            end

            sig_round = {1'b0, work[55:3]};
            guard_bit = work[2];
            round_bit = work[1];
            sticky_bit = work[0];

            if (guard_bit && (round_bit || sticky_bit || sig_round[0]))
                sig_round = sig_round + 1'b1;

            if (sig_round[53]) begin
                sig_round = sig_round >> 1;
                exp_work = exp_work + 1;
            end

            if (sig_round == 54'd0) begin
                round_pack = fp_zero(1'b0);
            end
            else if (exp_work > 1023) begin
                round_pack = fp_inf(sign_in);
            end
            else if (sig_round[52]) begin
                packed_exp = exp_work + 1023;
                round_pack = {sign_in, packed_exp, sig_round[51:0]};
            end
            else begin
                round_pack = {sign_in, 11'd0, sig_round[51:0]};
            end
        end
    end
endfunction

always @(*) begin
    result = 64'd0;

    sign_a = a[63];
    sign_b = b[63];
    exp_a = a[62:52];
    exp_b = b[62:52];
    frac_a = a[51:0];
    frac_b = b[51:0];

    a_is_nan = (exp_a == 11'h7FF) && (frac_a != 0);
    b_is_nan = (exp_b == 11'h7FF) && (frac_b != 0);
    a_is_inf = (exp_a == 11'h7FF) && (frac_a == 0);
    b_is_inf = (exp_b == 11'h7FF) && (frac_b == 0);
    a_is_zero = (exp_a == 11'd0) && (frac_a == 0);
    b_is_zero = (exp_b == 11'd0) && (frac_b == 0);

    case (fpu_op)
        5'h00, 5'h01: begin
            // Stage 0: unpack/decode and special-case classify.
            if (a_is_nan || b_is_nan) begin
                result = fp_qnan();
            end
            else begin
                sign_b = b[63] ^ (fpu_op == 5'h01);

                if (a_is_inf && b_is_inf && (sign_a != sign_b)) begin
                    result = fp_qnan();
                end
                else if (a_is_inf) begin
                    result = fp_inf(sign_a);
                end
                else if (b_is_inf) begin
                    result = fp_inf(sign_b);
                end
                else if (a_is_zero && b_is_zero) begin
                    result = fp_zero(1'b0);
                end
                else if (a_is_zero) begin
                    result = {sign_b, exp_b, frac_b};
                end
                else if (b_is_zero) begin
                    result = a;
                end
                else begin
                    // Stage 1: normalize inputs and align exponents.
                    sig_a = (exp_a == 0) ? {1'b0, frac_a} : {1'b1, frac_a};
                    sig_b = (exp_b == 0) ? {1'b0, frac_b} : {1'b1, frac_b};
                    exp_a_unbiased = (exp_a == 0) ? -1022 : (exp_a - 1023);
                    exp_b_unbiased = (exp_b == 0) ? -1022 : (exp_b - 1023);

                    if (exp_a == 0) begin
                        for (i = 0; i < 52; i = i + 1) begin
                            if ((sig_a != 0) && !sig_a[52]) begin
                                sig_a = sig_a << 1;
                                exp_a_unbiased = exp_a_unbiased - 1;
                            end
                        end
                    end

                    if (exp_b == 0) begin
                        for (i = 0; i < 52; i = i + 1) begin
                            if ((sig_b != 0) && !sig_b[52]) begin
                                sig_b = sig_b << 1;
                                exp_b_unbiased = exp_b_unbiased - 1;
                            end
                        end
                    end

                    ext_a = {sig_a, 3'b000};
                    ext_b = {sig_b, 3'b000};

                    if (exp_a_unbiased > exp_b_unbiased) begin
                        diff = exp_a_unbiased - exp_b_unbiased;
                        ext_b = shr_sticky56(ext_b, diff);
                        exp_res_unbiased = exp_a_unbiased;
                    end
                    else if (exp_b_unbiased > exp_a_unbiased) begin
                        diff = exp_b_unbiased - exp_a_unbiased;
                        ext_a = shr_sticky56(ext_a, diff);
                        exp_res_unbiased = exp_b_unbiased;
                    end
                    else begin
                        exp_res_unbiased = exp_a_unbiased;
                    end

                    // Stage 2: mantissa add/sub.
                    if (sign_a == sign_b) begin
                        sign_res = sign_a;
                        ext_sum = {1'b0, ext_a} + {1'b0, ext_b};
                        if (ext_sum[56]) begin
                            ext_res = ext_sum[56:1];
                            ext_res[0] = ext_res[0] | ext_sum[0];
                            exp_res_unbiased = exp_res_unbiased + 1;
                        end
                        else begin
                            ext_res = ext_sum[55:0];
                        end
                    end
                    else begin
                        if (ext_a > ext_b) begin
                            sign_res = sign_a;
                            ext_res = ext_a - ext_b;
                        end
                        else if (ext_b > ext_a) begin
                            sign_res = sign_b;
                            ext_res = ext_b - ext_a;
                        end
                        else begin
                            ext_res = 56'd0;
                            sign_res = 1'b0;
                        end
                    end

                    // Stage 3: normalization.
                    if (ext_res == 56'd0) begin
                        result = fp_zero(1'b0);
                    end
                    else begin
                        for (i = 0; i < 55; i = i + 1) begin
                            if ((ext_res != 0) && !ext_res[55] && (exp_res_unbiased > -1022)) begin
                                ext_res = ext_res << 1;
                                exp_res_unbiased = exp_res_unbiased - 1;
                            end
                        end

                        // Stage 4: guard/round/sticky pack.
                        result = round_pack(sign_res, exp_res_unbiased, ext_res);
                    end
                end
            end
        end

        5'h02: begin
            if (a_is_nan || b_is_nan) begin
                result = fp_qnan();
            end
            else if ((a_is_inf && b_is_zero) || (b_is_inf && a_is_zero)) begin
                result = fp_qnan();
            end
            else if (a_is_inf || b_is_inf) begin
                result = fp_inf(a[63] ^ b[63]);
            end
            else if (a_is_zero || b_is_zero) begin
                result = fp_zero(a[63] ^ b[63]);
            end
            else begin
                // Stage 0/1: unpack and normalize subnormal inputs.
                sig_a = (exp_a == 0) ? {1'b0, frac_a} : {1'b1, frac_a};
                sig_b = (exp_b == 0) ? {1'b0, frac_b} : {1'b1, frac_b};
                exp_a_unbiased = (exp_a == 0) ? -1022 : (exp_a - 1023);
                exp_b_unbiased = (exp_b == 0) ? -1022 : (exp_b - 1023);

                if (exp_a == 0) begin
                    for (i = 0; i < 52; i = i + 1) begin
                        if ((sig_a != 0) && !sig_a[52]) begin
                            sig_a = sig_a << 1;
                            exp_a_unbiased = exp_a_unbiased - 1;
                        end
                    end
                end

                if (exp_b == 0) begin
                    for (i = 0; i < 52; i = i + 1) begin
                        if ((sig_b != 0) && !sig_b[52]) begin
                            sig_b = sig_b << 1;
                            exp_b_unbiased = exp_b_unbiased - 1;
                        end
                    end
                end

                // Stage 2: mantissa multiply.
                product = sig_a * sig_b;
                sign_res = a[63] ^ b[63];
                exp_res_unbiased = exp_a_unbiased + exp_b_unbiased;

                // Stage 3: normalize the product into {main, guard, round, sticky}.
                if (product[105]) begin
                    ext_res = {product[105:53], product[52], product[51], |product[50:0]};
                    exp_res_unbiased = exp_res_unbiased + 1;
                end
                else begin
                    ext_res = {product[104:52], product[51], product[50], |product[49:0]};
                end

                // Stage 4: round and pack.
                result = round_pack(sign_res, exp_res_unbiased, ext_res);
            end
        end

        5'h03: begin
            if (a_is_nan || b_is_nan) begin
                result = fp_qnan();
            end
            else if ((a_is_inf && b_is_inf) || (a_is_zero && b_is_zero)) begin
                result = fp_qnan();
            end
            else if (a_is_inf) begin
                result = fp_inf(a[63] ^ b[63]);
            end
            else if (b_is_inf) begin
                result = fp_zero(a[63] ^ b[63]);
            end
            else if (b_is_zero) begin
                result = fp_inf(a[63] ^ b[63]);
            end
            else if (a_is_zero) begin
                result = fp_zero(a[63] ^ b[63]);
            end
            else begin
                // Stage 0/1: unpack and normalize subnormal inputs.
                sig_a = (exp_a == 0) ? {1'b0, frac_a} : {1'b1, frac_a};
                sig_b = (exp_b == 0) ? {1'b0, frac_b} : {1'b1, frac_b};
                exp_a_unbiased = (exp_a == 0) ? -1022 : (exp_a - 1023);
                exp_b_unbiased = (exp_b == 0) ? -1022 : (exp_b - 1023);

                if (exp_a == 0) begin
                    for (i = 0; i < 52; i = i + 1) begin
                        if ((sig_a != 0) && !sig_a[52]) begin
                            sig_a = sig_a << 1;
                            exp_a_unbiased = exp_a_unbiased - 1;
                        end
                    end
                end

                if (exp_b == 0) begin
                    for (i = 0; i < 52; i = i + 1) begin
                        if ((sig_b != 0) && !sig_b[52]) begin
                            sig_b = sig_b << 1;
                            exp_b_unbiased = exp_b_unbiased - 1;
                        end
                    end
                end

                // Stage 2: mantissa divide with extra bits for guard/sticky.
                div_num = {56'd0, sig_a} << 56;
                div_quot = div_num / sig_b;
                div_rem = div_num % sig_b;
                div_sticky = (div_rem != 0);
                sign_res = a[63] ^ b[63];
                exp_res_unbiased = exp_a_unbiased - exp_b_unbiased;

                // Stage 3: normalize quotient into {main, guard, round, sticky}.
                if (div_quot[56]) begin
                    ext_res = {div_quot[56:4], div_quot[3], div_quot[2], div_quot[1] | div_quot[0] | div_sticky};
                end
                else begin
                    ext_res = {div_quot[55:3], div_quot[2], div_quot[1], div_quot[0] | div_sticky};
                    exp_res_unbiased = exp_res_unbiased - 1;
                end

                // Stage 4: round and pack.
                result = round_pack(sign_res, exp_res_unbiased, ext_res);
            end
        end

        default: begin
            result = 64'd0;
        end
    endcase
end

endmodule
