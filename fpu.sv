module fpu(
    input clk,
    input reset,
    input in_valid,
    input [63:0] a,
    input [63:0] b,
    input [4:0] fpu_op,
    output reg out_valid,
    output reg [63:0] result
);

localparam [4:0] OP_ADDF = 5'h00;
localparam [4:0] OP_SUBF = 5'h01;
localparam [4:0] OP_MULF = 5'h02;
localparam [4:0] OP_DIVF = 5'h03;

reg s0_valid;
reg [4:0] s0_op;
reg s0_special_valid;
reg [63:0] s0_special_result;
reg s0_sign_a;
reg s0_sign_b;
reg [10:0] s0_exp_a;
reg [10:0] s0_exp_b;
reg [51:0] s0_frac_a;
reg [51:0] s0_frac_b;
reg [52:0] s0_sig_a;
reg [52:0] s0_sig_b;

reg s1_valid;
reg [4:0] s1_op;
reg s1_special_valid;
reg [63:0] s1_special_result;
reg s1_sign_a;
reg s1_sign_b;
integer s1_exp_base;
reg [55:0] s1_ext_a;
reg [55:0] s1_ext_b;
reg [52:0] s1_sig_a;
reg [52:0] s1_sig_b;

reg s2_valid;
reg [4:0] s2_op;
reg s2_special_valid;
reg [63:0] s2_special_result;
reg s2_sign;
integer s2_exp_base;
reg [55:0] s2_ext;
reg [105:0] s2_product;
reg [56:0] s2_div_quot;
reg s2_div_sticky;

reg s3_valid;
reg s3_special_valid;
reg [63:0] s3_special_result;
reg s3_sign;
integer s3_exp_base;
reg [55:0] s3_ext;

reg s4_valid;
reg [63:0] s4_result;

reg n_s1_valid;
reg [4:0] n_s1_op;
reg n_s1_special_valid;
reg [63:0] n_s1_special_result;
reg n_s1_sign_a;
reg n_s1_sign_b;
integer n_s1_exp_base;
reg [55:0] n_s1_ext_a;
reg [55:0] n_s1_ext_b;
reg [52:0] n_s1_sig_a;
reg [52:0] n_s1_sig_b;

reg n_s2_valid;
reg [4:0] n_s2_op;
reg n_s2_special_valid;
reg [63:0] n_s2_special_result;
reg n_s2_sign;
integer n_s2_exp_base;
reg [55:0] n_s2_ext;
reg [105:0] n_s2_product;
reg [56:0] n_s2_div_quot;
reg n_s2_div_sticky;

reg n_s3_valid;
reg n_s3_special_valid;
reg [63:0] n_s3_special_result;
reg n_s3_sign;
integer n_s3_exp_base;
reg [55:0] n_s3_ext;

reg n_s4_valid;
reg [63:0] n_s4_result;

reg s0_a_is_nan;
reg s0_b_is_nan;
reg s0_a_is_inf;
reg s0_b_is_inf;
reg s0_a_is_zero;
reg s0_b_is_zero;

reg [52:0] stg1_sig_a;
reg [52:0] stg1_sig_b;
reg [55:0] stg1_ext_a;
reg [55:0] stg1_ext_b;
integer stg1_exp_a;
integer stg1_exp_b;
integer stg1_shift;

reg [56:0] stg2_sum;
reg [108:0] stg2_div_num;

reg [55:0] stg3_ext;
integer stg3_exp;
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
    n_s1_valid = s0_valid;
    n_s1_op = s0_op;
    n_s1_special_valid = s0_special_valid;
    n_s1_special_result = s0_special_result;
    n_s1_sign_a = s0_sign_a;
    n_s1_sign_b = s0_sign_b;
    n_s1_exp_base = 0;
    n_s1_ext_a = 56'd0;
    n_s1_ext_b = 56'd0;
    n_s1_sig_a = 53'd0;
    n_s1_sig_b = 53'd0;

    stg1_sig_a = s0_sig_a;
    stg1_sig_b = s0_sig_b;
    stg1_exp_a = (s0_exp_a == 0) ? -1022 : (s0_exp_a - 1023);
    stg1_exp_b = (s0_exp_b == 0) ? -1022 : (s0_exp_b - 1023);

    if (s0_exp_a == 0) begin
        for (i = 0; i < 52; i = i + 1) begin
            if ((stg1_sig_a != 0) && !stg1_sig_a[52]) begin
                stg1_sig_a = stg1_sig_a << 1;
                stg1_exp_a = stg1_exp_a - 1;
            end
        end
    end

    if (s0_exp_b == 0) begin
        for (i = 0; i < 52; i = i + 1) begin
            if ((stg1_sig_b != 0) && !stg1_sig_b[52]) begin
                stg1_sig_b = stg1_sig_b << 1;
                stg1_exp_b = stg1_exp_b - 1;
            end
        end
    end

    if (s0_op == OP_ADDF || s0_op == OP_SUBF) begin
        stg1_ext_a = {stg1_sig_a, 3'b000};
        stg1_ext_b = {stg1_sig_b, 3'b000};
        if (stg1_exp_a > stg1_exp_b) begin
            stg1_shift = stg1_exp_a - stg1_exp_b;
            stg1_ext_b = shr_sticky56(stg1_ext_b, stg1_shift);
            n_s1_exp_base = stg1_exp_a;
        end
        else if (stg1_exp_b > stg1_exp_a) begin
            stg1_shift = stg1_exp_b - stg1_exp_a;
            stg1_ext_a = shr_sticky56(stg1_ext_a, stg1_shift);
            n_s1_exp_base = stg1_exp_b;
        end
        else begin
            n_s1_exp_base = stg1_exp_a;
        end
        n_s1_ext_a = stg1_ext_a;
        n_s1_ext_b = stg1_ext_b;
    end
    else if (s0_op == OP_MULF) begin
        n_s1_sig_a = stg1_sig_a;
        n_s1_sig_b = stg1_sig_b;
        n_s1_exp_base = stg1_exp_a + stg1_exp_b;
    end
    else begin
        n_s1_sig_a = stg1_sig_a;
        n_s1_sig_b = stg1_sig_b;
        n_s1_exp_base = stg1_exp_a - stg1_exp_b;
    end
end

always @(*) begin
    n_s2_valid = s1_valid;
    n_s2_op = s1_op;
    n_s2_special_valid = s1_special_valid;
    n_s2_special_result = s1_special_result;
    n_s2_sign = 1'b0;
    n_s2_exp_base = s1_exp_base;
    n_s2_ext = 56'd0;
    n_s2_product = 106'd0;
    n_s2_div_quot = 57'd0;
    n_s2_div_sticky = 1'b0;

    if (s1_op == OP_ADDF || s1_op == OP_SUBF) begin
        if (s1_sign_a == s1_sign_b) begin
            n_s2_sign = s1_sign_a;
            stg2_sum = {1'b0, s1_ext_a} + {1'b0, s1_ext_b};
            if (stg2_sum[56]) begin
                n_s2_ext = stg2_sum[56:1];
                n_s2_ext[0] = n_s2_ext[0] | stg2_sum[0];
                n_s2_exp_base = s1_exp_base + 1;
            end
            else begin
                n_s2_ext = stg2_sum[55:0];
            end
        end
        else begin
            if (s1_ext_a > s1_ext_b) begin
                n_s2_sign = s1_sign_a;
                n_s2_ext = s1_ext_a - s1_ext_b;
            end
            else if (s1_ext_b > s1_ext_a) begin
                n_s2_sign = s1_sign_b;
                n_s2_ext = s1_ext_b - s1_ext_a;
            end
            else begin
                n_s2_sign = 1'b0;
                n_s2_ext = 56'd0;
            end
        end
    end
    else if (s1_op == OP_MULF) begin
        n_s2_sign = s1_sign_a ^ s1_sign_b;
        n_s2_product = s1_sig_a * s1_sig_b;
    end
    else begin
        n_s2_sign = s1_sign_a ^ s1_sign_b;
        stg2_div_num = {s1_sig_a, 56'd0};
        n_s2_div_quot = stg2_div_num / s1_sig_b;
        n_s2_div_sticky = ((stg2_div_num % s1_sig_b) != 0);
    end
end

always @(*) begin
    n_s3_valid = s2_valid;
    n_s3_special_valid = s2_special_valid;
    n_s3_special_result = s2_special_result;
    n_s3_sign = s2_sign;
    n_s3_exp_base = s2_exp_base;
    n_s3_ext = 56'd0;

    if (s2_op == OP_ADDF || s2_op == OP_SUBF) begin
        stg3_ext = s2_ext;
        stg3_exp = s2_exp_base;
        if (stg3_ext != 0) begin
            for (i = 0; i < 55; i = i + 1) begin
                if ((stg3_ext != 0) && !stg3_ext[55]) begin
                    stg3_ext = stg3_ext << 1;
                    stg3_exp = stg3_exp - 1;
                end
            end
        end
        n_s3_ext = stg3_ext;
        n_s3_exp_base = stg3_exp;
    end
    else if (s2_op == OP_MULF) begin
        if (s2_product[105]) begin
            n_s3_ext = {s2_product[105:53], s2_product[52], s2_product[51], |s2_product[50:0]};
            n_s3_exp_base = s2_exp_base + 1;
        end
        else begin
            n_s3_ext = {s2_product[104:52], s2_product[51], s2_product[50], |s2_product[49:0]};
        end
    end
    else begin
        if (s2_div_quot[56]) begin
            n_s3_ext = {s2_div_quot[56:4], s2_div_quot[3], s2_div_quot[2], s2_div_quot[1] | s2_div_quot[0] | s2_div_sticky};
        end
        else begin
            n_s3_ext = {s2_div_quot[55:3], s2_div_quot[2], s2_div_quot[1], s2_div_quot[0] | s2_div_sticky};
            n_s3_exp_base = s2_exp_base - 1;
        end
    end
end

always @(*) begin
    n_s4_valid = s3_valid;
    if (s3_special_valid)
        n_s4_result = s3_special_result;
    else
        n_s4_result = round_pack(s3_sign, s3_exp_base, s3_ext);
end

always @(*) begin
    out_valid = s4_valid;
    result = s4_result;
end

always @(posedge clk or posedge reset) begin
    if (reset) begin
        s0_valid <= 1'b0;
        s0_op <= 5'd0;
        s0_special_valid <= 1'b0;
        s0_special_result <= 64'd0;
        s0_sign_a <= 1'b0;
        s0_sign_b <= 1'b0;
        s0_exp_a <= 11'd0;
        s0_exp_b <= 11'd0;
        s0_frac_a <= 52'd0;
        s0_frac_b <= 52'd0;
        s0_sig_a <= 53'd0;
        s0_sig_b <= 53'd0;

        s1_valid <= 1'b0;
        s1_op <= 5'd0;
        s1_special_valid <= 1'b0;
        s1_special_result <= 64'd0;
        s1_sign_a <= 1'b0;
        s1_sign_b <= 1'b0;
        s1_exp_base <= 0;
        s1_ext_a <= 56'd0;
        s1_ext_b <= 56'd0;
        s1_sig_a <= 53'd0;
        s1_sig_b <= 53'd0;

        s2_valid <= 1'b0;
        s2_op <= 5'd0;
        s2_special_valid <= 1'b0;
        s2_special_result <= 64'd0;
        s2_sign <= 1'b0;
        s2_exp_base <= 0;
        s2_ext <= 56'd0;
        s2_product <= 106'd0;
        s2_div_quot <= 57'd0;
        s2_div_sticky <= 1'b0;

        s3_valid <= 1'b0;
        s3_special_valid <= 1'b0;
        s3_special_result <= 64'd0;
        s3_sign <= 1'b0;
        s3_exp_base <= 0;
        s3_ext <= 56'd0;

        s4_valid <= 1'b0;
        s4_result <= 64'd0;
    end
    else begin
        // Stage 4: round/pack register.
        s4_valid <= n_s4_valid;
        s4_result <= n_s4_result;

        // Stage 3 register.
        s3_valid <= n_s3_valid;
        s3_special_valid <= n_s3_special_valid;
        s3_special_result <= n_s3_special_result;
        s3_sign <= n_s3_sign;
        s3_exp_base <= n_s3_exp_base;
        s3_ext <= n_s3_ext;

        // Stage 2 register.
        s2_valid <= n_s2_valid;
        s2_op <= n_s2_op;
        s2_special_valid <= n_s2_special_valid;
        s2_special_result <= n_s2_special_result;
        s2_sign <= n_s2_sign;
        s2_exp_base <= n_s2_exp_base;
        s2_ext <= n_s2_ext;
        s2_product <= n_s2_product;
        s2_div_quot <= n_s2_div_quot;
        s2_div_sticky <= n_s2_div_sticky;

        // Stage 1 register.
        s1_valid <= n_s1_valid;
        s1_op <= n_s1_op;
        s1_special_valid <= n_s1_special_valid;
        s1_special_result <= n_s1_special_result;
        s1_sign_a <= n_s1_sign_a;
        s1_sign_b <= n_s1_sign_b;
        s1_exp_base <= n_s1_exp_base;
        s1_ext_a <= n_s1_ext_a;
        s1_ext_b <= n_s1_ext_b;
        s1_sig_a <= n_s1_sig_a;
        s1_sig_b <= n_s1_sig_b;

        // Stage 0: unpack/decode and special-case classify.
        s0_valid <= in_valid;
        s0_op <= fpu_op;
        s0_sign_a <= a[63];
        s0_sign_b <= b[63] ^ (fpu_op == OP_SUBF);
        s0_exp_a <= a[62:52];
        s0_exp_b <= b[62:52];
        s0_frac_a <= a[51:0];
        s0_frac_b <= b[51:0];
        s0_sig_a <= (a[62:52] == 0) ? {1'b0, a[51:0]} : {1'b1, a[51:0]};
        s0_sig_b <= (b[62:52] == 0) ? {1'b0, b[51:0]} : {1'b1, b[51:0]};

        s0_a_is_nan = (a[62:52] == 11'h7FF) && (a[51:0] != 0);
        s0_b_is_nan = (b[62:52] == 11'h7FF) && (b[51:0] != 0);
        s0_a_is_inf = (a[62:52] == 11'h7FF) && (a[51:0] == 0);
        s0_b_is_inf = (b[62:52] == 11'h7FF) && (b[51:0] == 0);
        s0_a_is_zero = (a[62:52] == 11'd0) && (a[51:0] == 0);
        s0_b_is_zero = (b[62:52] == 11'd0) && (b[51:0] == 0);

        s0_special_valid <= 1'b0;
        s0_special_result <= 64'd0;

        if ((a[62:52] == 11'h7FF && a[51:0] != 0) || (b[62:52] == 11'h7FF && b[51:0] != 0)) begin
            s0_special_valid <= 1'b1;
            s0_special_result <= fp_qnan();
        end
        else if (fpu_op == OP_ADDF || fpu_op == OP_SUBF) begin
            if ((a[62:52] == 11'h7FF) && (a[51:0] == 0) &&
                (b[62:52] == 11'h7FF) && (b[51:0] == 0) &&
                (a[63] != (b[63] ^ (fpu_op == OP_SUBF)))) begin
                s0_special_valid <= 1'b1;
                s0_special_result <= fp_qnan();
            end
            else if ((a[62:52] == 11'h7FF) && (a[51:0] == 0)) begin
                s0_special_valid <= 1'b1;
                s0_special_result <= fp_inf(a[63]);
            end
            else if ((b[62:52] == 11'h7FF) && (b[51:0] == 0)) begin
                s0_special_valid <= 1'b1;
                s0_special_result <= fp_inf(b[63] ^ (fpu_op == OP_SUBF));
            end
            else if ((a[62:52] == 11'd0) && (a[51:0] == 0) &&
                     (b[62:52] == 11'd0) && (b[51:0] == 0)) begin
                s0_special_valid <= 1'b1;
                s0_special_result <= fp_zero(1'b0);
            end
            else if ((a[62:52] == 11'd0) && (a[51:0] == 0)) begin
                s0_special_valid <= 1'b1;
                s0_special_result <= {b[63] ^ (fpu_op == OP_SUBF), b[62:0]};
            end
            else if ((b[62:52] == 11'd0) && (b[51:0] == 0)) begin
                s0_special_valid <= 1'b1;
                s0_special_result <= a;
            end
        end
        else if (fpu_op == OP_MULF) begin
            if (((a[62:52] == 11'h7FF) && (a[51:0] == 0) && (b[62:0] == 0)) ||
                ((b[62:52] == 11'h7FF) && (b[51:0] == 0) && (a[62:0] == 0))) begin
                s0_special_valid <= 1'b1;
                s0_special_result <= fp_qnan();
            end
            else if ((a[62:52] == 11'h7FF) && (a[51:0] == 0)) begin
                s0_special_valid <= 1'b1;
                s0_special_result <= fp_inf(a[63] ^ b[63]);
            end
            else if ((b[62:52] == 11'h7FF) && (b[51:0] == 0)) begin
                s0_special_valid <= 1'b1;
                s0_special_result <= fp_inf(a[63] ^ b[63]);
            end
            else if ((a[62:0] == 0) || (b[62:0] == 0)) begin
                s0_special_valid <= 1'b1;
                s0_special_result <= fp_zero(a[63] ^ b[63]);
            end
        end
        else begin
            if (((a[62:52] == 11'h7FF) && (a[51:0] == 0) &&
                 (b[62:52] == 11'h7FF) && (b[51:0] == 0)) ||
                ((a[62:0] == 0) && (b[62:0] == 0))) begin
                s0_special_valid <= 1'b1;
                s0_special_result <= fp_qnan();
            end
            else if ((a[62:52] == 11'h7FF) && (a[51:0] == 0)) begin
                s0_special_valid <= 1'b1;
                s0_special_result <= fp_inf(a[63] ^ b[63]);
            end
            else if ((b[62:52] == 11'h7FF) && (b[51:0] == 0)) begin
                s0_special_valid <= 1'b1;
                s0_special_result <= fp_zero(a[63] ^ b[63]);
            end
            else if (b[62:0] == 0) begin
                s0_special_valid <= 1'b1;
                s0_special_result <= fp_inf(a[63] ^ b[63]);
            end
            else if (a[62:0] == 0) begin
                s0_special_valid <= 1'b1;
                s0_special_result <= fp_zero(a[63] ^ b[63]);
            end
        end
    end
end

endmodule
