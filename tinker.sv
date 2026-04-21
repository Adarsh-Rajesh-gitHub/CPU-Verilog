`include "instruction_fetch.sv"
`include "instruction_decoder.sv"
`include "register_file.sv"
`include "alu.sv"
`include "fpu.sv"
`include "memory.sv"

module tinker_core(
    input clk,
    input reset,
    output logic hlt
);

localparam ARCH_REGS = 32;
localparam PHYS_REGS = 64;
localparam PHYS_TAG_W = 6;
localparam ROB_SIZE = 16;
localparam ROB_IDX_W = 4;
localparam INT_RS_SIZE = 8;
localparam FP_RS_SIZE = 8;
localparam LSQ_SIZE = 8;
localparam FPU_LAT = 5; // unpack/decode, align, execute, normalize, round-pack
localparam PRED_SIZE = 8;
localparam PRED_IDX_W = 3;

localparam CLASS_NOP = 4'd0;
localparam CLASS_INT = 4'd1;
localparam CLASS_FP = 4'd2;
localparam CLASS_LOAD = 4'd3;
localparam CLASS_STORE = 4'd4;
localparam CLASS_BRANCH = 4'd5;
localparam CLASS_CALL = 4'd6;
localparam CLASS_RETURN = 4'd7;
localparam CLASS_HALT = 4'd8;

function [63:0] zero_ext12;
    input [11:0] imm;
    begin
        zero_ext12 = {52'd0, imm};
    end
endfunction

function [63:0] sign_ext12;
    input [11:0] imm;
    begin
        sign_ext12 = {{52{imm[11]}}, imm};
    end
endfunction

function [ROB_IDX_W-1:0] rob_inc;
    input [ROB_IDX_W-1:0] idx;
    begin
        if (idx == ROB_SIZE - 1)
            rob_inc = {ROB_IDX_W{1'b0}};
        else
            rob_inc = idx + 1'b1;
    end
endfunction

function [6:0] free_inc;
    input [6:0] idx;
    begin
        if (idx == PHYS_REGS - 1)
            free_inc = 7'd0;
        else
            free_inc = idx + 1'b1;
    end
endfunction

function [4:0] rob_distance;
    input [ROB_IDX_W-1:0] head_idx;
    input [ROB_IDX_W-1:0] idx;
    begin
        if (idx >= head_idx)
            rob_distance = idx - head_idx;
        else
            rob_distance = idx + ROB_SIZE - head_idx;
    end
endfunction

function rob_is_younger;
    input [ROB_IDX_W-1:0] head_idx;
    input [ROB_IDX_W-1:0] cand;
    input [ROB_IDX_W-1:0] ref_idx;
    begin
        rob_is_younger = (rob_distance(head_idx, cand) > rob_distance(head_idx, ref_idx));
    end
endfunction

function [6:0] free_count_from_ptrs;
    input [6:0] head_ptr;
    input [6:0] tail_ptr;
    begin
        if (tail_ptr >= head_ptr)
            free_count_from_ptrs = tail_ptr - head_ptr;
        else
            free_count_from_ptrs = tail_ptr + PHYS_REGS - head_ptr;
    end
endfunction

function [PRED_IDX_W-1:0] pred_index;
    input [63:0] pc_in;
    begin
        pred_index = pc_in[4:2];
    end
endfunction

reg [PHYS_TAG_W-1:0] rat [0:ARCH_REGS-1];
reg [63:0] phys_value [0:PHYS_REGS-1];
reg phys_ready [0:PHYS_REGS-1];
reg [PHYS_TAG_W-1:0] free_list [0:PHYS_REGS-1];
reg [6:0] free_head;
reg [6:0] free_tail;
reg [6:0] free_count;

reg rob_valid [0:ROB_SIZE-1];
reg rob_ready [0:ROB_SIZE-1];
reg rob_has_dest [0:ROB_SIZE-1];
reg [4:0] rob_dest_arch [0:ROB_SIZE-1];
reg [PHYS_TAG_W-1:0] rob_dest_phys [0:ROB_SIZE-1];
reg [PHYS_TAG_W-1:0] rob_old_phys [0:ROB_SIZE-1];
reg [63:0] rob_value [0:ROB_SIZE-1];
reg [63:0] rob_pc [0:ROB_SIZE-1];
reg [4:0] rob_opcode [0:ROB_SIZE-1];
reg rob_is_store [0:ROB_SIZE-1];
reg rob_is_call [0:ROB_SIZE-1];
reg rob_is_return [0:ROB_SIZE-1];
reg rob_is_branch [0:ROB_SIZE-1];
reg rob_is_halt [0:ROB_SIZE-1];
reg rob_pred_taken [0:ROB_SIZE-1];
reg [63:0] rob_pred_target [0:ROB_SIZE-1];
reg [63:0] rob_store_addr [0:ROB_SIZE-1];
reg [63:0] rob_store_data [0:ROB_SIZE-1];
reg [6:0] rob_checkpoint_free_head [0:ROB_SIZE-1];
reg [PHYS_TAG_W-1:0] rob_checkpoint_rat [0:ROB_SIZE-1][0:ARCH_REGS-1];
reg [ROB_IDX_W-1:0] rob_head;
reg [ROB_IDX_W-1:0] rob_tail;

reg int_rs_valid [0:INT_RS_SIZE-1];
reg int_rs_is_branch [0:INT_RS_SIZE-1];
reg int_rs_is_cond [0:INT_RS_SIZE-1];
reg int_rs_br_abs [0:INT_RS_SIZE-1];
reg int_rs_br_rel_reg [0:INT_RS_SIZE-1];
reg int_rs_br_rel_lit [0:INT_RS_SIZE-1];
reg int_rs_br_nz [0:INT_RS_SIZE-1];
reg int_rs_br_gt [0:INT_RS_SIZE-1];
reg [4:0] int_rs_alu_op [0:INT_RS_SIZE-1];
reg [63:0] int_rs_pc [0:INT_RS_SIZE-1];
reg [63:0] int_rs_imm [0:INT_RS_SIZE-1];
reg [ROB_IDX_W-1:0] int_rs_rob [0:INT_RS_SIZE-1];
reg int_rs_has_dest [0:INT_RS_SIZE-1];
reg [PHYS_TAG_W-1:0] int_rs_dest [0:INT_RS_SIZE-1];
reg int_rs_src0_ready [0:INT_RS_SIZE-1];
reg [PHYS_TAG_W-1:0] int_rs_src0_tag [0:INT_RS_SIZE-1];
reg [63:0] int_rs_src0_value [0:INT_RS_SIZE-1];
reg int_rs_src1_ready [0:INT_RS_SIZE-1];
reg [PHYS_TAG_W-1:0] int_rs_src1_tag [0:INT_RS_SIZE-1];
reg [63:0] int_rs_src1_value [0:INT_RS_SIZE-1];
reg int_rs_src2_ready [0:INT_RS_SIZE-1];
reg [PHYS_TAG_W-1:0] int_rs_src2_tag [0:INT_RS_SIZE-1];
reg [63:0] int_rs_src2_value [0:INT_RS_SIZE-1];
reg int_rs_pred_taken [0:INT_RS_SIZE-1];
reg [63:0] int_rs_pred_target [0:INT_RS_SIZE-1];

reg fp_rs_valid [0:FP_RS_SIZE-1];
reg [4:0] fp_rs_op [0:FP_RS_SIZE-1];
reg [ROB_IDX_W-1:0] fp_rs_rob [0:FP_RS_SIZE-1];
reg [PHYS_TAG_W-1:0] fp_rs_dest [0:FP_RS_SIZE-1];
reg fp_rs_src0_ready [0:FP_RS_SIZE-1];
reg [PHYS_TAG_W-1:0] fp_rs_src0_tag [0:FP_RS_SIZE-1];
reg [63:0] fp_rs_src0_value [0:FP_RS_SIZE-1];
reg fp_rs_src1_ready [0:FP_RS_SIZE-1];
reg [PHYS_TAG_W-1:0] fp_rs_src1_tag [0:FP_RS_SIZE-1];
reg [63:0] fp_rs_src1_value [0:FP_RS_SIZE-1];

reg lsq_valid [0:LSQ_SIZE-1];
reg lsq_is_load [0:LSQ_SIZE-1];
reg lsq_is_store [0:LSQ_SIZE-1];
reg lsq_is_call [0:LSQ_SIZE-1];
reg lsq_is_return [0:LSQ_SIZE-1];
reg [ROB_IDX_W-1:0] lsq_rob [0:LSQ_SIZE-1];
reg [PHYS_TAG_W-1:0] lsq_dest [0:LSQ_SIZE-1];
reg [63:0] lsq_pc [0:LSQ_SIZE-1];
reg [63:0] lsq_imm [0:LSQ_SIZE-1];
reg lsq_src0_ready [0:LSQ_SIZE-1];
reg [PHYS_TAG_W-1:0] lsq_src0_tag [0:LSQ_SIZE-1];
reg [63:0] lsq_src0_value [0:LSQ_SIZE-1];
reg lsq_src1_ready [0:LSQ_SIZE-1];
reg [PHYS_TAG_W-1:0] lsq_src1_tag [0:LSQ_SIZE-1];
reg [63:0] lsq_src1_value [0:LSQ_SIZE-1];
reg lsq_addr_ready [0:LSQ_SIZE-1];
reg [63:0] lsq_addr [0:LSQ_SIZE-1];
reg lsq_data_ready [0:LSQ_SIZE-1];
reg [63:0] lsq_data [0:LSQ_SIZE-1];
reg lsq_control_issued [0:LSQ_SIZE-1];
reg lsq_control_done [0:LSQ_SIZE-1];
reg lsq_pred_taken [0:LSQ_SIZE-1];
reg [63:0] lsq_pred_target [0:LSQ_SIZE-1];

reg alu_pipe_valid [0:1];
reg alu_pipe_has_dest [0:1];
reg [ROB_IDX_W-1:0] alu_pipe_rob [0:1];
reg [PHYS_TAG_W-1:0] alu_pipe_dest [0:1];
reg [63:0] alu_pipe_value [0:1];
reg alu_pipe_is_branch [0:1];
reg alu_pipe_is_cond [0:1];
reg alu_pipe_pred_taken [0:1];
reg [63:0] alu_pipe_pred_target [0:1];
reg alu_pipe_actual_taken [0:1];
reg [63:0] alu_pipe_actual_target [0:1];
reg [63:0] alu_pipe_pc [0:1];

reg fpu_pipe_valid [0:1][0:FPU_LAT-1];
reg [ROB_IDX_W-1:0] fpu_pipe_rob [0:1][0:FPU_LAT-1];
reg [PHYS_TAG_W-1:0] fpu_pipe_dest [0:1][0:FPU_LAT-1];

reg lsu_pipe_valid [0:1];
reg lsu_pipe_has_dest [0:1];
reg lsu_pipe_is_call [0:1];
reg lsu_pipe_is_return [0:1];
reg [ROB_IDX_W-1:0] lsu_pipe_rob [0:1];
reg [PHYS_TAG_W-1:0] lsu_pipe_dest [0:1];
reg [63:0] lsu_pipe_value [0:1];
reg lsu_pipe_pred_taken [0:1];
reg [63:0] lsu_pipe_pred_target [0:1];
reg lsu_pipe_actual_taken [0:1];
reg [63:0] lsu_pipe_actual_target [0:1];
reg [63:0] lsu_pipe_pc [0:1];

reg [1:0] bht [0:PRED_SIZE-1];
reg btb_valid [0:PRED_SIZE-1];
reg [63:5] btb_tag [0:PRED_SIZE-1];
reg [63:0] btb_target [0:PRED_SIZE-1];

wire [63:0] pc;
reg [63:0] next_pc;
wire [31:0] instruction0;
wire [31:0] instruction1;
reg [63:0] load_mem_addr0;
reg [63:0] load_mem_addr1;
wire [63:0] load_mem_data0;
wire [63:0] load_mem_data1;

wire [4:0] opcode0;
wire [4:0] rd0;
wire [4:0] rs0;
wire [4:0] rt0;
wire [11:0] L0;
wire use_alu0;
wire use_fpu0;
wire is_literal0;
wire br_abs0;
wire br_rel_reg0;
wire br_rel_lit0;
wire br_nz0;
wire br_gt0;
wire call0;
wire return0;
wire [4:0] alu_op0;
wire [4:0] fpu_op0;
wire reg_write0;

wire [4:0] opcode1;
wire [4:0] rd1;
wire [4:0] rs1;
wire [4:0] rt1;
wire [11:0] L1;
wire use_alu1;
wire use_fpu1;
wire is_literal1;
wire br_abs1;
wire br_rel_reg1;
wire br_rel_lit1;
wire br_nz1;
wire br_gt1;
wire call1;
wire return1;
wire [4:0] alu_op1;
wire [4:0] fpu_op1;
wire reg_write1;

wire [63:0] rd0_arch_data;
wire [63:0] rs0_arch_data;
wire [63:0] rt0_arch_data;
wire [63:0] rd1_arch_data;
wire [63:0] rs1_arch_data;
wire [63:0] rt1_arch_data;
wire [63:0] sp_arch_data;

wire [ROB_IDX_W-1:0] rob_head_plus1;
wire commit0_valid;
wire commit1_valid;
wire commit1_fire;
wire commit0_is_store;
wire commit1_is_store;
wire commit0_has_dest;
wire commit1_has_dest;

reg [4:0] rob_count_now;
reg halt_inflight;

reg int_free0_valid;
reg int_free1_valid;
reg [2:0] int_free0_idx;
reg [2:0] int_free1_idx;
reg fp_free0_valid;
reg fp_free1_valid;
reg [2:0] fp_free0_idx;
reg [2:0] fp_free1_idx;
reg lsq_free0_valid;
reg lsq_free1_valid;
reg [2:0] lsq_free0_idx;
reg [2:0] lsq_free1_idx;

reg recovery_valid;
reg [ROB_IDX_W-1:0] recovery_rob;
reg [63:0] recovery_target;

reg issue_int0_valid;
reg issue_int1_valid;
reg [2:0] issue_int0_idx;
reg [2:0] issue_int1_idx;
reg [63:0] issue_int0_a;
reg [63:0] issue_int0_b;
reg [4:0] issue_int0_op;
reg issue_int0_is_branch;
reg issue_int0_is_cond;
reg issue_int0_pred_taken;
reg [63:0] issue_int0_pred_target;
reg issue_int0_actual_taken;
reg [63:0] issue_int0_actual_target;

reg [63:0] issue_int1_a;
reg [63:0] issue_int1_b;
reg [4:0] issue_int1_op;
reg issue_int1_is_branch;
reg issue_int1_is_cond;
reg issue_int1_pred_taken;
reg [63:0] issue_int1_pred_target;
reg issue_int1_actual_taken;
reg [63:0] issue_int1_actual_target;

reg issue_fp0_valid;
reg issue_fp1_valid;
reg [2:0] issue_fp0_idx;
reg [2:0] issue_fp1_idx;
reg [63:0] issue_fp0_a;
reg [63:0] issue_fp0_b;
reg [4:0] issue_fp0_op;
reg [63:0] issue_fp1_a;
reg [63:0] issue_fp1_b;
reg [4:0] issue_fp1_op;

reg issue_lsu0_valid;
reg issue_lsu1_valid;
reg [2:0] issue_lsu0_idx;
reg [2:0] issue_lsu1_idx;
reg issue_lsu0_has_dest;
reg issue_lsu1_has_dest;
reg issue_lsu0_is_call;
reg issue_lsu1_is_call;
reg issue_lsu0_is_return;
reg issue_lsu1_is_return;
reg [63:0] issue_lsu0_value;
reg [63:0] issue_lsu1_value;
reg issue_lsu0_pred_taken;
reg issue_lsu1_pred_taken;
reg [63:0] issue_lsu0_pred_target;
reg [63:0] issue_lsu1_pred_target;
reg issue_lsu0_actual_taken;
reg issue_lsu1_actual_taken;
reg [63:0] issue_lsu0_actual_target;
reg [63:0] issue_lsu1_actual_target;

reg dispatch0_valid;
reg dispatch1_valid;
reg [3:0] slot0_class;
reg [3:0] slot1_class;
reg slot0_has_dest;
reg slot1_has_dest;
reg [PHYS_TAG_W-1:0] slot0_dest_phys;
reg [PHYS_TAG_W-1:0] slot1_dest_phys;
reg [PHYS_TAG_W-1:0] slot0_old_phys;
reg [PHYS_TAG_W-1:0] slot1_old_phys;
reg slot0_src0_ready;
reg [PHYS_TAG_W-1:0] slot0_src0_tag;
reg [63:0] slot0_src0_value;
reg slot0_src1_ready;
reg [PHYS_TAG_W-1:0] slot0_src1_tag;
reg [63:0] slot0_src1_value;
reg slot0_src2_ready;
reg [PHYS_TAG_W-1:0] slot0_src2_tag;
reg [63:0] slot0_src2_value;
reg slot1_src0_ready;
reg [PHYS_TAG_W-1:0] slot1_src0_tag;
reg [63:0] slot1_src0_value;
reg slot1_src1_ready;
reg [PHYS_TAG_W-1:0] slot1_src1_tag;
reg [63:0] slot1_src1_value;
reg slot1_src2_ready;
reg [PHYS_TAG_W-1:0] slot1_src2_tag;
reg [63:0] slot1_src2_value;
reg slot0_pred_taken;
reg [63:0] slot0_pred_target;
reg slot1_pred_taken;
reg [63:0] slot1_pred_target;
reg slot0_blocks_second;
reg slot1_blocks_fetch;

wire [PHYS_TAG_W-1:0] alloc_tag0;
wire [PHYS_TAG_W-1:0] alloc_tag1;

reg [63:0] alu0_result_hold;
reg [63:0] alu1_result_hold;
wire [63:0] alu0_result;
wire [63:0] alu1_result;
wire [63:0] fpu0_result;
wire [63:0] fpu1_result;
wire fpu0_out_valid;
wire fpu1_out_valid;

reg [4:0] int_best0;
reg [4:0] int_best1;
reg [4:0] int_curd;
reg [4:0] fp_best0;
reg [4:0] fp_best1;
reg [4:0] fp_curd;
reg [4:0] lsu_best_load_dist;
reg [4:0] lsu_best_load_dist1;
reg [4:0] lsu_load_dist;
reg [4:0] lsu_store_dist;
reg [4:0] lsu_best_store_dist;
reg lsu_safe;
reg lsu_forward_hit;
reg [63:0] lsu_forward_data;
reg [PRED_IDX_W-1:0] idx0_reg;
reg [PRED_IDX_W-1:0] idx1_reg;
reg use_second_int_slot;
reg use_second_fp_slot;
reg use_second_lsq_slot;
reg [2:0] int_slot1_idx_reg;
reg [2:0] fp_slot1_idx_reg;
reg [2:0] lsq_slot1_idx_reg;

integer i;
integer j;
integer s;
integer u;

task map_source;
    input [4:0] arch_idx;
    input [63:0] arch_value;
    input override_valid;
    input [4:0] override_arch;
    input [PHYS_TAG_W-1:0] override_tag;
    output mapped_ready;
    output [PHYS_TAG_W-1:0] mapped_tag;
    output [63:0] mapped_value;
    begin
        if (override_valid && (arch_idx == override_arch)) begin
            mapped_ready = 1'b0;
            mapped_tag = override_tag;
            mapped_value = 64'd0;
        end
        else begin
            mapped_tag = rat[arch_idx];
            if (rat[arch_idx] == {1'b0, arch_idx}) begin
                mapped_ready = 1'b1;
                mapped_value = arch_value;
            end
            else begin
                mapped_ready = phys_ready[rat[arch_idx]];
                mapped_value = phys_value[rat[arch_idx]];
            end
        end
    end
endtask

task broadcast_result;
    input [PHYS_TAG_W-1:0] tag_in;
    input [63:0] value_in;
    begin
        for (i = 0; i < INT_RS_SIZE; i = i + 1) begin
            if (int_rs_valid[i] && !int_rs_src0_ready[i] && (int_rs_src0_tag[i] == tag_in)) begin
                int_rs_src0_ready[i] = 1'b1;
                int_rs_src0_value[i] = value_in;
            end
            if (int_rs_valid[i] && !int_rs_src1_ready[i] && (int_rs_src1_tag[i] == tag_in)) begin
                int_rs_src1_ready[i] = 1'b1;
                int_rs_src1_value[i] = value_in;
            end
            if (int_rs_valid[i] && !int_rs_src2_ready[i] && (int_rs_src2_tag[i] == tag_in)) begin
                int_rs_src2_ready[i] = 1'b1;
                int_rs_src2_value[i] = value_in;
            end
        end
        for (i = 0; i < FP_RS_SIZE; i = i + 1) begin
            if (fp_rs_valid[i] && !fp_rs_src0_ready[i] && (fp_rs_src0_tag[i] == tag_in)) begin
                fp_rs_src0_ready[i] = 1'b1;
                fp_rs_src0_value[i] = value_in;
            end
            if (fp_rs_valid[i] && !fp_rs_src1_ready[i] && (fp_rs_src1_tag[i] == tag_in)) begin
                fp_rs_src1_ready[i] = 1'b1;
                fp_rs_src1_value[i] = value_in;
            end
        end
        for (i = 0; i < LSQ_SIZE; i = i + 1) begin
            if (lsq_valid[i] && !lsq_src0_ready[i] && (lsq_src0_tag[i] == tag_in)) begin
                lsq_src0_ready[i] = 1'b1;
                lsq_src0_value[i] = value_in;
            end
            if (lsq_valid[i] && !lsq_src1_ready[i] && (lsq_src1_tag[i] == tag_in)) begin
                lsq_src1_ready[i] = 1'b1;
                lsq_src1_value[i] = value_in;
            end
        end
    end
endtask

assign alloc_tag0 = free_list[free_head];
assign alloc_tag1 = free_list[free_inc(free_head)];

assign rob_head_plus1 = rob_inc(rob_head);
assign commit0_valid = rob_valid[rob_head] && rob_ready[rob_head];
assign commit0_is_store = commit0_valid && (rob_is_store[rob_head] || rob_is_call[rob_head]);
assign commit0_has_dest = commit0_valid && rob_has_dest[rob_head];
assign commit1_is_store = commit0_valid && !rob_is_halt[rob_head] && rob_valid[rob_head_plus1] && rob_ready[rob_head_plus1] && (rob_is_store[rob_head_plus1] || rob_is_call[rob_head_plus1]);
assign commit1_valid = commit0_valid && !rob_is_halt[rob_head] && rob_valid[rob_head_plus1] && rob_ready[rob_head_plus1] && !commit1_is_store;
assign commit1_fire = commit1_valid && (!recovery_valid || !rob_is_younger(rob_head, rob_head_plus1, recovery_rob));
assign commit1_has_dest = commit1_fire && rob_has_dest[rob_head_plus1];

instruction_fetch fetch(
    .clk(clk),
    .reset(reset),
    .next_pc(next_pc),
    .pc(pc)
);

memory memory(
    .clk(clk),
    .reset(reset),
    .pc(pc),
    .instruction(instruction0),
    .pc_b(pc + 64'd4),
    .instruction_b(instruction1),
    .data_addr(commit0_is_store ? rob_store_addr[rob_head] : load_mem_addr1),
    .write_data(commit0_is_store ? rob_store_data[rob_head] : 64'd0),
    .mem_write(commit0_is_store && !hlt),
    .data_read(load_mem_data1),
    .data_addr_b(load_mem_addr0),
    .data_read_b(load_mem_data0)
);

instruction_decoder decoder0(
    .instruction(instruction0),
    .opcode(opcode0),
    .rd(rd0),
    .rs(rs0),
    .rt(rt0),
    .L(L0),
    .use_alu(use_alu0),
    .use_fpu(use_fpu0),
    .is_literal(is_literal0),
    .br_abs(br_abs0),
    .br_rel_reg(br_rel_reg0),
    .br_rel_lit(br_rel_lit0),
    .br_nz(br_nz0),
    .br_gt(br_gt0),
    .call_inst(call0),
    .return_inst(return0),
    .alu_op(alu_op0),
    .fpu_op(fpu_op0),
    .reg_write(reg_write0)
);

instruction_decoder decoder1(
    .instruction(instruction1),
    .opcode(opcode1),
    .rd(rd1),
    .rs(rs1),
    .rt(rt1),
    .L(L1),
    .use_alu(use_alu1),
    .use_fpu(use_fpu1),
    .is_literal(is_literal1),
    .br_abs(br_abs1),
    .br_rel_reg(br_rel_reg1),
    .br_rel_lit(br_rel_lit1),
    .br_nz(br_nz1),
    .br_gt(br_gt1),
    .call_inst(call1),
    .return_inst(return1),
    .alu_op(alu_op1),
    .fpu_op(fpu_op1),
    .reg_write(reg_write1)
);

register_file reg_file(
    .clk(clk),
    .reset(reset),
    .rd(rd0),
    .rs(rs0),
    .rt(rt0),
    .rd2(rd1),
    .rs2(rs1),
    .rt2(rt1),
    .wr_rd_a(commit0_has_dest ? rob_dest_arch[rob_head] : 5'd0),
    .write_data(commit0_has_dest ? rob_value[rob_head] : 64'd0),
    .reg_write(commit0_has_dest && !hlt),
    .rd_b(commit1_has_dest ? rob_dest_arch[rob_head_plus1] : 5'd0),
    .write_data_b(commit1_has_dest ? rob_value[rob_head_plus1] : 64'd0),
    .reg_write_b(commit1_has_dest && !hlt),
    .rd_data(rd0_arch_data),
    .rs_data(rs0_arch_data),
    .rt_data(rt0_arch_data),
    .rd2_data(rd1_arch_data),
    .rs2_data(rs1_arch_data),
    .rt2_data(rt1_arch_data),
    .r31_data(sp_arch_data)
);

alu alu0(
    .alu_op(issue_int0_op),
    .a(issue_int0_a),
    .b(issue_int0_b),
    .result(alu0_result)
);

alu alu1(
    .alu_op(issue_int1_op),
    .a(issue_int1_a),
    .b(issue_int1_b),
    .result(alu1_result)
);

fpu fpu(
    .clk(clk),
    .reset(reset),
    .in_valid(issue_fp0_valid && !hlt && !recovery_valid),
    .a(issue_fp0_a),
    .b(issue_fp0_b),
    .fpu_op(issue_fp0_op),
    .out_valid(fpu0_out_valid),
    .result(fpu0_result)
);

fpu fpu1(
    .clk(clk),
    .reset(reset),
    .in_valid(issue_fp1_valid && !hlt && !recovery_valid),
    .a(issue_fp1_a),
    .b(issue_fp1_b),
    .fpu_op(issue_fp1_op),
    .out_valid(fpu1_out_valid),
    .result(fpu1_result)
);

always @(*) begin
    rob_count_now = 5'd0;
    halt_inflight = 1'b0;
    int_free0_valid = 1'b0;
    int_free1_valid = 1'b0;
    int_free0_idx = 3'd0;
    int_free1_idx = 3'd0;
    fp_free0_valid = 1'b0;
    fp_free1_valid = 1'b0;
    fp_free0_idx = 3'd0;
    fp_free1_idx = 3'd0;
    lsq_free0_valid = 1'b0;
    lsq_free1_valid = 1'b0;
    lsq_free0_idx = 3'd0;
    lsq_free1_idx = 3'd0;

    for (i = 0; i < ROB_SIZE; i = i + 1) begin
        if (rob_valid[i]) begin
            rob_count_now = rob_count_now + 1'b1;
            if (rob_is_halt[i])
                halt_inflight = 1'b1;
        end
    end

    for (i = 0; i < INT_RS_SIZE; i = i + 1) begin
        if (!int_rs_valid[i]) begin
            if (!int_free0_valid) begin
                int_free0_valid = 1'b1;
                int_free0_idx = i[2:0];
            end
            else if (!int_free1_valid) begin
                int_free1_valid = 1'b1;
                int_free1_idx = i[2:0];
            end
        end
    end

    for (i = 0; i < FP_RS_SIZE; i = i + 1) begin
        if (!fp_rs_valid[i]) begin
            if (!fp_free0_valid) begin
                fp_free0_valid = 1'b1;
                fp_free0_idx = i[2:0];
            end
            else if (!fp_free1_valid) begin
                fp_free1_valid = 1'b1;
                fp_free1_idx = i[2:0];
            end
        end
    end

    for (i = 0; i < LSQ_SIZE; i = i + 1) begin
        if (!lsq_valid[i]) begin
            if (!lsq_free0_valid) begin
                lsq_free0_valid = 1'b1;
                lsq_free0_idx = i[2:0];
            end
            else if (!lsq_free1_valid) begin
                lsq_free1_valid = 1'b1;
                lsq_free1_idx = i[2:0];
            end
        end
    end
end

always @(*) begin
    recovery_valid = 1'b0;
    recovery_rob = {ROB_IDX_W{1'b0}};
    recovery_target = pc + 64'd4;

    if (alu_pipe_valid[0] && alu_pipe_is_branch[0]) begin
        if ((alu_pipe_actual_taken[0] != alu_pipe_pred_taken[0]) ||
            (alu_pipe_actual_taken[0] && alu_pipe_pred_taken[0] && (alu_pipe_actual_target[0] != alu_pipe_pred_target[0]))) begin
            recovery_valid = 1'b1;
            recovery_rob = alu_pipe_rob[0];
            recovery_target = alu_pipe_actual_taken[0] ? alu_pipe_actual_target[0] : (alu_pipe_pc[0] + 64'd4);
        end
    end

    if (alu_pipe_valid[1] && alu_pipe_is_branch[1]) begin
        if ((alu_pipe_actual_taken[1] != alu_pipe_pred_taken[1]) ||
            (alu_pipe_actual_taken[1] && alu_pipe_pred_taken[1] && (alu_pipe_actual_target[1] != alu_pipe_pred_target[1]))) begin
            if (!recovery_valid || rob_is_younger(rob_head, recovery_rob, alu_pipe_rob[1])) begin
                recovery_valid = 1'b1;
                recovery_rob = alu_pipe_rob[1];
                recovery_target = alu_pipe_actual_taken[1] ? alu_pipe_actual_target[1] : (alu_pipe_pc[1] + 64'd4);
            end
        end
    end

    for (u = 0; u < 2; u = u + 1) begin
        if (lsu_pipe_valid[u] && (lsu_pipe_is_call[u] || lsu_pipe_is_return[u])) begin
            if ((lsu_pipe_actual_taken[u] != lsu_pipe_pred_taken[u]) ||
                (lsu_pipe_actual_taken[u] && lsu_pipe_pred_taken[u] && (lsu_pipe_actual_target[u] != lsu_pipe_pred_target[u]))) begin
                if (!recovery_valid || rob_is_younger(rob_head, recovery_rob, lsu_pipe_rob[u])) begin
                    recovery_valid = 1'b1;
                    recovery_rob = lsu_pipe_rob[u];
                    recovery_target = lsu_pipe_actual_taken[u] ? lsu_pipe_actual_target[u] : (lsu_pipe_pc[u] + 64'd4);
                end
            end
        end
    end
end

always @(*) begin
    issue_int0_valid = 1'b0;
    issue_int1_valid = 1'b0;
    issue_int0_idx = 3'd0;
    issue_int1_idx = 3'd0;
    issue_int0_a = 64'd0;
    issue_int0_b = 64'd0;
    issue_int1_a = 64'd0;
    issue_int1_b = 64'd0;
    issue_int0_op = 5'd0;
    issue_int1_op = 5'd0;
    issue_int0_is_branch = 1'b0;
    issue_int1_is_branch = 1'b0;
    issue_int0_is_cond = 1'b0;
    issue_int1_is_cond = 1'b0;
    issue_int0_pred_taken = 1'b0;
    issue_int1_pred_taken = 1'b0;
    issue_int0_pred_target = 64'd0;
    issue_int1_pred_target = 64'd0;
    issue_int0_actual_taken = 1'b0;
    issue_int1_actual_taken = 1'b0;
    issue_int0_actual_target = 64'd0;
    issue_int1_actual_target = 64'd0;

    int_best0 = ROB_SIZE;
    int_best1 = ROB_SIZE;
    for (i = 0; i < INT_RS_SIZE; i = i + 1) begin
        if (int_rs_valid[i] && int_rs_src0_ready[i] && int_rs_src1_ready[i] && int_rs_src2_ready[i]) begin
            int_curd = rob_distance(rob_head, int_rs_rob[i]);
            if (!issue_int0_valid || (int_curd < int_best0)) begin
                issue_int1_valid = issue_int0_valid;
                issue_int1_idx = issue_int0_idx;
                int_best1 = int_best0;
                issue_int0_valid = 1'b1;
                issue_int0_idx = i[2:0];
                int_best0 = int_curd;
            end
            else if (!issue_int1_valid || (int_curd < int_best1)) begin
                issue_int1_valid = 1'b1;
                issue_int1_idx = i[2:0];
                int_best1 = int_curd;
            end
        end
    end

    if (issue_int0_valid) begin
        issue_int0_a = int_rs_src0_value[issue_int0_idx];
        issue_int0_b = int_rs_src1_value[issue_int0_idx];
        issue_int0_op = int_rs_alu_op[issue_int0_idx];
        issue_int0_is_branch = int_rs_is_branch[issue_int0_idx];
        issue_int0_is_cond = int_rs_is_cond[issue_int0_idx];
        issue_int0_pred_taken = int_rs_pred_taken[issue_int0_idx];
        issue_int0_pred_target = int_rs_pred_target[issue_int0_idx];
        if (int_rs_is_branch[issue_int0_idx]) begin
            if (int_rs_br_abs[issue_int0_idx]) begin
                issue_int0_actual_taken = 1'b1;
                issue_int0_actual_target = int_rs_src2_value[issue_int0_idx];
            end
            else if (int_rs_br_rel_reg[issue_int0_idx]) begin
                issue_int0_actual_taken = 1'b1;
                issue_int0_actual_target = int_rs_pc[issue_int0_idx] + int_rs_src2_value[issue_int0_idx];
            end
            else if (int_rs_br_rel_lit[issue_int0_idx]) begin
                issue_int0_actual_taken = 1'b1;
                issue_int0_actual_target = int_rs_pc[issue_int0_idx] + int_rs_imm[issue_int0_idx];
            end
            else if (int_rs_br_nz[issue_int0_idx]) begin
                issue_int0_actual_taken = (int_rs_src0_value[issue_int0_idx] != 64'd0);
                issue_int0_actual_target = int_rs_src2_value[issue_int0_idx];
            end
            else begin
                issue_int0_actual_taken = ($signed(int_rs_src0_value[issue_int0_idx]) > $signed(int_rs_src1_value[issue_int0_idx]));
                issue_int0_actual_target = int_rs_src2_value[issue_int0_idx];
            end
        end
    end

    if (issue_int1_valid) begin
        issue_int1_a = int_rs_src0_value[issue_int1_idx];
        issue_int1_b = int_rs_src1_value[issue_int1_idx];
        issue_int1_op = int_rs_alu_op[issue_int1_idx];
        issue_int1_is_branch = int_rs_is_branch[issue_int1_idx];
        issue_int1_is_cond = int_rs_is_cond[issue_int1_idx];
        issue_int1_pred_taken = int_rs_pred_taken[issue_int1_idx];
        issue_int1_pred_target = int_rs_pred_target[issue_int1_idx];
        if (int_rs_is_branch[issue_int1_idx]) begin
            if (int_rs_br_abs[issue_int1_idx]) begin
                issue_int1_actual_taken = 1'b1;
                issue_int1_actual_target = int_rs_src2_value[issue_int1_idx];
            end
            else if (int_rs_br_rel_reg[issue_int1_idx]) begin
                issue_int1_actual_taken = 1'b1;
                issue_int1_actual_target = int_rs_pc[issue_int1_idx] + int_rs_src2_value[issue_int1_idx];
            end
            else if (int_rs_br_rel_lit[issue_int1_idx]) begin
                issue_int1_actual_taken = 1'b1;
                issue_int1_actual_target = int_rs_pc[issue_int1_idx] + int_rs_imm[issue_int1_idx];
            end
            else if (int_rs_br_nz[issue_int1_idx]) begin
                issue_int1_actual_taken = (int_rs_src0_value[issue_int1_idx] != 64'd0);
                issue_int1_actual_target = int_rs_src2_value[issue_int1_idx];
            end
            else begin
                issue_int1_actual_taken = ($signed(int_rs_src0_value[issue_int1_idx]) > $signed(int_rs_src1_value[issue_int1_idx]));
                issue_int1_actual_target = int_rs_src2_value[issue_int1_idx];
            end
        end
    end
end

always @(*) begin
    issue_fp0_valid = 1'b0;
    issue_fp1_valid = 1'b0;
    issue_fp0_idx = 3'd0;
    issue_fp1_idx = 3'd0;
    issue_fp0_a = 64'd0;
    issue_fp0_b = 64'd0;
    issue_fp1_a = 64'd0;
    issue_fp1_b = 64'd0;
    issue_fp0_op = 5'd0;
    issue_fp1_op = 5'd0;
    fp_best0 = ROB_SIZE;
    fp_best1 = ROB_SIZE;

    for (i = 0; i < FP_RS_SIZE; i = i + 1) begin
        if (fp_rs_valid[i] && fp_rs_src0_ready[i] && fp_rs_src1_ready[i]) begin
            fp_curd = rob_distance(rob_head, fp_rs_rob[i]);
            if (!issue_fp0_valid || (fp_curd < fp_best0)) begin
                issue_fp1_valid = issue_fp0_valid;
                issue_fp1_idx = issue_fp0_idx;
                fp_best1 = fp_best0;
                issue_fp0_valid = 1'b1;
                issue_fp0_idx = i[2:0];
                fp_best0 = fp_curd;
            end
            else if (!issue_fp1_valid || (fp_curd < fp_best1)) begin
                issue_fp1_valid = 1'b1;
                issue_fp1_idx = i[2:0];
                fp_best1 = fp_curd;
            end
        end
    end

    if (issue_fp0_valid) begin
        issue_fp0_a = fp_rs_src0_value[issue_fp0_idx];
        issue_fp0_b = fp_rs_src1_value[issue_fp0_idx];
        issue_fp0_op = fp_rs_op[issue_fp0_idx];
    end
    if (issue_fp1_valid) begin
        issue_fp1_a = fp_rs_src0_value[issue_fp1_idx];
        issue_fp1_b = fp_rs_src1_value[issue_fp1_idx];
        issue_fp1_op = fp_rs_op[issue_fp1_idx];
    end
end

always @(*) begin
    issue_lsu0_valid = 1'b0;
    issue_lsu1_valid = 1'b0;
    issue_lsu0_idx = 3'd0;
    issue_lsu1_idx = 3'd0;
    issue_lsu0_has_dest = 1'b0;
    issue_lsu1_has_dest = 1'b0;
    issue_lsu0_is_call = 1'b0;
    issue_lsu1_is_call = 1'b0;
    issue_lsu0_is_return = 1'b0;
    issue_lsu1_is_return = 1'b0;
    issue_lsu0_value = 64'd0;
    issue_lsu1_value = 64'd0;
    issue_lsu0_pred_taken = 1'b0;
    issue_lsu1_pred_taken = 1'b0;
    issue_lsu0_pred_target = 64'd0;
    issue_lsu1_pred_target = 64'd0;
    issue_lsu0_actual_taken = 1'b0;
    issue_lsu1_actual_taken = 1'b0;
    issue_lsu0_actual_target = 64'd0;
    issue_lsu1_actual_target = 64'd0;
    load_mem_addr0 = 64'd0;
    load_mem_addr1 = 64'd0;
    lsu_best_load_dist = ROB_SIZE;
    lsu_best_load_dist1 = ROB_SIZE;

    for (i = 0; i < LSQ_SIZE; i = i + 1) begin
        if (lsq_valid[i]) begin
            lsu_load_dist = rob_distance(rob_head, lsq_rob[i]);
            lsu_safe = 1'b0;
            lsu_forward_hit = 1'b0;
            lsu_forward_data = 64'd0;
            lsu_best_store_dist = 5'd0;

            if (lsq_is_call[i] && !lsq_control_issued[i] && lsq_src1_ready[i] && lsq_addr_ready[i] && lsq_data_ready[i]) begin
                lsu_safe = 1'b1;
            end
            else if ((lsq_is_load[i] || lsq_is_return[i]) && lsq_addr_ready[i]) begin
                lsu_safe = 1'b1;
                for (j = 0; j < LSQ_SIZE; j = j + 1) begin
                    if (lsq_valid[j] && (lsq_is_store[j] || lsq_is_call[j]) && rob_is_younger(rob_head, lsq_rob[i], lsq_rob[j])) begin
                        if (!lsq_addr_ready[j]) begin
                            lsu_safe = 1'b0;
                        end
                        else if (lsq_addr[j] == lsq_addr[i]) begin
                            if (!lsq_data_ready[j]) begin
                                lsu_safe = 1'b0;
                            end
                            else begin
                                lsu_store_dist = rob_distance(rob_head, lsq_rob[j]);
                                if (!lsu_forward_hit || (lsu_store_dist > lsu_best_store_dist)) begin
                                    lsu_forward_hit = 1'b1;
                                    lsu_forward_data = lsq_data[j];
                                    lsu_best_store_dist = lsu_store_dist;
                                end
                            end
                        end
                    end
                end
            end

            if (lsu_safe && (!issue_lsu0_valid || (lsu_load_dist < lsu_best_load_dist))) begin
                issue_lsu0_valid = 1'b1;
                issue_lsu0_idx = i[2:0];
                lsu_best_load_dist = lsu_load_dist;
            end
        end
    end

    for (i = 0; i < LSQ_SIZE; i = i + 1) begin
        if (lsq_valid[i] && (!issue_lsu0_valid || (i[2:0] != issue_lsu0_idx)) &&
            (lsq_is_call[i] || !commit0_is_store)) begin
            lsu_load_dist = rob_distance(rob_head, lsq_rob[i]);
            lsu_safe = 1'b0;
            lsu_forward_hit = 1'b0;
            lsu_forward_data = 64'd0;
            lsu_best_store_dist = 5'd0;

            if (lsq_is_call[i] && !lsq_control_issued[i] && lsq_src1_ready[i] && lsq_addr_ready[i] && lsq_data_ready[i]) begin
                lsu_safe = 1'b1;
            end
            else if ((lsq_is_load[i] || lsq_is_return[i]) && lsq_addr_ready[i]) begin
                lsu_safe = 1'b1;
                for (j = 0; j < LSQ_SIZE; j = j + 1) begin
                    if (lsq_valid[j] && (lsq_is_store[j] || lsq_is_call[j]) && rob_is_younger(rob_head, lsq_rob[i], lsq_rob[j])) begin
                        if (!lsq_addr_ready[j]) begin
                            lsu_safe = 1'b0;
                        end
                        else if (lsq_addr[j] == lsq_addr[i]) begin
                            if (!lsq_data_ready[j]) begin
                                lsu_safe = 1'b0;
                            end
                            else begin
                                lsu_store_dist = rob_distance(rob_head, lsq_rob[j]);
                                if (!lsu_forward_hit || (lsu_store_dist > lsu_best_store_dist)) begin
                                    lsu_forward_hit = 1'b1;
                                    lsu_forward_data = lsq_data[j];
                                    lsu_best_store_dist = lsu_store_dist;
                                end
                            end
                        end
                    end
                end
            end

            if (lsu_safe && (!issue_lsu1_valid || (lsu_load_dist < lsu_best_load_dist1))) begin
                issue_lsu1_valid = 1'b1;
                issue_lsu1_idx = i[2:0];
                lsu_best_load_dist1 = lsu_load_dist;
            end
        end
    end

    if (issue_lsu0_valid) begin
        issue_lsu0_has_dest = lsq_is_load[issue_lsu0_idx];
        issue_lsu0_is_call = lsq_is_call[issue_lsu0_idx];
        issue_lsu0_is_return = lsq_is_return[issue_lsu0_idx];
        issue_lsu0_pred_taken = lsq_pred_taken[issue_lsu0_idx];
        issue_lsu0_pred_target = lsq_pred_target[issue_lsu0_idx];
        if (lsq_is_call[issue_lsu0_idx]) begin
            issue_lsu0_actual_taken = 1'b1;
            issue_lsu0_actual_target = lsq_src1_value[issue_lsu0_idx];
        end
        else begin
            load_mem_addr0 = lsq_addr[issue_lsu0_idx];
            lsu_forward_hit = 1'b0;
            lsu_forward_data = 64'd0;
            lsu_best_store_dist = 5'd0;
            for (j = 0; j < LSQ_SIZE; j = j + 1) begin
                if (lsq_valid[j] && (lsq_is_store[j] || lsq_is_call[j]) &&
                    rob_is_younger(rob_head, lsq_rob[issue_lsu0_idx], lsq_rob[j]) &&
                    lsq_addr_ready[j] && (lsq_addr[j] == lsq_addr[issue_lsu0_idx]) && lsq_data_ready[j]) begin
                    lsu_store_dist = rob_distance(rob_head, lsq_rob[j]);
                    if (!lsu_forward_hit || (lsu_store_dist > lsu_best_store_dist)) begin
                        lsu_forward_hit = 1'b1;
                        lsu_forward_data = lsq_data[j];
                        lsu_best_store_dist = lsu_store_dist;
                    end
                end
            end
            issue_lsu0_value = lsu_forward_hit ? lsu_forward_data : load_mem_data0;
            issue_lsu0_actual_taken = lsq_is_return[issue_lsu0_idx];
            issue_lsu0_actual_target = lsu_forward_hit ? lsu_forward_data : load_mem_data0;
        end
    end

    if (issue_lsu1_valid) begin
        issue_lsu1_has_dest = lsq_is_load[issue_lsu1_idx];
        issue_lsu1_is_call = lsq_is_call[issue_lsu1_idx];
        issue_lsu1_is_return = lsq_is_return[issue_lsu1_idx];
        issue_lsu1_pred_taken = lsq_pred_taken[issue_lsu1_idx];
        issue_lsu1_pred_target = lsq_pred_target[issue_lsu1_idx];
        if (lsq_is_call[issue_lsu1_idx]) begin
            issue_lsu1_actual_taken = 1'b1;
            issue_lsu1_actual_target = lsq_src1_value[issue_lsu1_idx];
        end
        else begin
            load_mem_addr1 = lsq_addr[issue_lsu1_idx];
            lsu_forward_hit = 1'b0;
            lsu_forward_data = 64'd0;
            lsu_best_store_dist = 5'd0;
            for (j = 0; j < LSQ_SIZE; j = j + 1) begin
                if (lsq_valid[j] && (lsq_is_store[j] || lsq_is_call[j]) &&
                    rob_is_younger(rob_head, lsq_rob[issue_lsu1_idx], lsq_rob[j]) &&
                    lsq_addr_ready[j] && (lsq_addr[j] == lsq_addr[issue_lsu1_idx]) && lsq_data_ready[j]) begin
                    lsu_store_dist = rob_distance(rob_head, lsq_rob[j]);
                    if (!lsu_forward_hit || (lsu_store_dist > lsu_best_store_dist)) begin
                        lsu_forward_hit = 1'b1;
                        lsu_forward_data = lsq_data[j];
                        lsu_best_store_dist = lsu_store_dist;
                    end
                end
            end
            issue_lsu1_value = lsu_forward_hit ? lsu_forward_data : load_mem_data1;
            issue_lsu1_actual_taken = lsq_is_return[issue_lsu1_idx];
            issue_lsu1_actual_target = lsu_forward_hit ? lsu_forward_data : load_mem_data1;
        end
    end
end

always @(*) begin
    dispatch0_valid = 1'b0;
    dispatch1_valid = 1'b0;
    slot0_class = CLASS_NOP;
    slot1_class = CLASS_NOP;
    slot0_has_dest = 1'b0;
    slot1_has_dest = 1'b0;
    slot0_dest_phys = alloc_tag0;
    slot1_dest_phys = alloc_tag1;
    slot0_old_phys = {PHYS_TAG_W{1'b0}};
    slot1_old_phys = {PHYS_TAG_W{1'b0}};
    slot0_src0_ready = 1'b1;
    slot0_src0_tag = {PHYS_TAG_W{1'b0}};
    slot0_src0_value = 64'd0;
    slot0_src1_ready = 1'b1;
    slot0_src1_tag = {PHYS_TAG_W{1'b0}};
    slot0_src1_value = 64'd0;
    slot0_src2_ready = 1'b1;
    slot0_src2_tag = {PHYS_TAG_W{1'b0}};
    slot0_src2_value = 64'd0;
    slot1_src0_ready = 1'b1;
    slot1_src0_tag = {PHYS_TAG_W{1'b0}};
    slot1_src0_value = 64'd0;
    slot1_src1_ready = 1'b1;
    slot1_src1_tag = {PHYS_TAG_W{1'b0}};
    slot1_src1_value = 64'd0;
    slot1_src2_ready = 1'b1;
    slot1_src2_tag = {PHYS_TAG_W{1'b0}};
    slot1_src2_value = 64'd0;
    slot0_pred_taken = 1'b0;
    slot1_pred_taken = 1'b0;
    slot0_pred_target = pc + 64'd4;
    slot1_pred_target = pc + 64'd8;
    slot0_blocks_second = 1'b0;
    slot1_blocks_fetch = 1'b0;
    next_pc = pc;

    if ((opcode0 == 5'h0F) && (L0 == 12'h000))
        slot0_class = CLASS_HALT;
    else if (opcode0 == 5'h10)
        slot0_class = CLASS_LOAD;
    else if (opcode0 == 5'h13)
        slot0_class = CLASS_STORE;
    else if (call0)
        slot0_class = CLASS_CALL;
    else if (return0)
        slot0_class = CLASS_RETURN;
    else if (br_abs0 || br_rel_reg0 || br_rel_lit0 || br_nz0 || br_gt0)
        slot0_class = CLASS_BRANCH;
    else if (use_fpu0)
        slot0_class = CLASS_FP;
    else if (use_alu0)
        slot0_class = CLASS_INT;

    if ((opcode1 == 5'h0F) && (L1 == 12'h000))
        slot1_class = CLASS_HALT;
    else if (opcode1 == 5'h10)
        slot1_class = CLASS_LOAD;
    else if (opcode1 == 5'h13)
        slot1_class = CLASS_STORE;
    else if (call1)
        slot1_class = CLASS_CALL;
    else if (return1)
        slot1_class = CLASS_RETURN;
    else if (br_abs1 || br_rel_reg1 || br_rel_lit1 || br_nz1 || br_gt1)
        slot1_class = CLASS_BRANCH;
    else if (use_fpu1)
        slot1_class = CLASS_FP;
    else if (use_alu1)
        slot1_class = CLASS_INT;

    slot0_has_dest = (slot0_class == CLASS_INT) || (slot0_class == CLASS_FP) || (slot0_class == CLASS_LOAD);
    slot1_has_dest = (slot1_class == CLASS_INT) || (slot1_class == CLASS_FP) || (slot1_class == CLASS_LOAD);
    slot0_old_phys = rat[rd0];
    slot1_old_phys = rat[rd1];

    if (slot0_class == CLASS_INT) begin
        if (is_literal0) begin
            map_source(rd0, rd0_arch_data, 1'b0, 5'd0, {PHYS_TAG_W{1'b0}}, slot0_src0_ready, slot0_src0_tag, slot0_src0_value);
            slot0_src1_ready = 1'b1;
            slot0_src1_value = zero_ext12(L0);
        end
        else begin
            map_source(rs0, rs0_arch_data, 1'b0, 5'd0, {PHYS_TAG_W{1'b0}}, slot0_src0_ready, slot0_src0_tag, slot0_src0_value);
            if ((opcode0 == 5'h03) || (opcode0 == 5'h11)) begin
                slot0_src1_ready = 1'b1;
                slot0_src1_value = 64'd0;
            end
            else begin
                map_source(rt0, rt0_arch_data, 1'b0, 5'd0, {PHYS_TAG_W{1'b0}}, slot0_src1_ready, slot0_src1_tag, slot0_src1_value);
            end
        end
    end
    else if (slot0_class == CLASS_FP) begin
        map_source(rs0, rs0_arch_data, 1'b0, 5'd0, {PHYS_TAG_W{1'b0}}, slot0_src0_ready, slot0_src0_tag, slot0_src0_value);
        map_source(rt0, rt0_arch_data, 1'b0, 5'd0, {PHYS_TAG_W{1'b0}}, slot0_src1_ready, slot0_src1_tag, slot0_src1_value);
    end
    else if (slot0_class == CLASS_LOAD) begin
        map_source(rs0, rs0_arch_data, 1'b0, 5'd0, {PHYS_TAG_W{1'b0}}, slot0_src0_ready, slot0_src0_tag, slot0_src0_value);
    end
    else if (slot0_class == CLASS_STORE) begin
        map_source(rd0, rd0_arch_data, 1'b0, 5'd0, {PHYS_TAG_W{1'b0}}, slot0_src0_ready, slot0_src0_tag, slot0_src0_value);
        map_source(rs0, rs0_arch_data, 1'b0, 5'd0, {PHYS_TAG_W{1'b0}}, slot0_src1_ready, slot0_src1_tag, slot0_src1_value);
    end
    else if (slot0_class == CLASS_BRANCH) begin
        if (br_abs0 || br_rel_reg0) begin
            map_source(rd0, rd0_arch_data, 1'b0, 5'd0, {PHYS_TAG_W{1'b0}}, slot0_src2_ready, slot0_src2_tag, slot0_src2_value);
        end
        else if (br_nz0) begin
            map_source(rs0, rs0_arch_data, 1'b0, 5'd0, {PHYS_TAG_W{1'b0}}, slot0_src0_ready, slot0_src0_tag, slot0_src0_value);
            map_source(rd0, rd0_arch_data, 1'b0, 5'd0, {PHYS_TAG_W{1'b0}}, slot0_src2_ready, slot0_src2_tag, slot0_src2_value);
        end
        else if (br_gt0) begin
            map_source(rs0, rs0_arch_data, 1'b0, 5'd0, {PHYS_TAG_W{1'b0}}, slot0_src0_ready, slot0_src0_tag, slot0_src0_value);
            map_source(rt0, rt0_arch_data, 1'b0, 5'd0, {PHYS_TAG_W{1'b0}}, slot0_src1_ready, slot0_src1_tag, slot0_src1_value);
            map_source(rd0, rd0_arch_data, 1'b0, 5'd0, {PHYS_TAG_W{1'b0}}, slot0_src2_ready, slot0_src2_tag, slot0_src2_value);
        end
    end
    else if (slot0_class == CLASS_CALL) begin
        map_source(5'd31, sp_arch_data, 1'b0, 5'd0, {PHYS_TAG_W{1'b0}}, slot0_src0_ready, slot0_src0_tag, slot0_src0_value);
        map_source(rd0, rd0_arch_data, 1'b0, 5'd0, {PHYS_TAG_W{1'b0}}, slot0_src1_ready, slot0_src1_tag, slot0_src1_value);
    end
    else if (slot0_class == CLASS_RETURN) begin
        map_source(5'd31, sp_arch_data, 1'b0, 5'd0, {PHYS_TAG_W{1'b0}}, slot0_src0_ready, slot0_src0_tag, slot0_src0_value);
    end

    idx0_reg = pred_index(pc);
    if (slot0_class == CLASS_CALL || slot0_class == CLASS_RETURN || slot0_class == CLASS_BRANCH) begin
        if (br_nz0 || br_gt0)
            slot0_pred_taken = bht[idx0_reg][1];
        else
            slot0_pred_taken = 1'b1;

        if (br_rel_lit0)
            slot0_pred_target = pc + sign_ext12(L0);
        else if (br_rel_reg0 && slot0_src2_ready)
            slot0_pred_target = pc + slot0_src2_value;
        else if (call0 && slot0_src1_ready)
            slot0_pred_target = slot0_src1_value;
        else if ((br_abs0 || br_nz0 || br_gt0) && slot0_src2_ready)
            slot0_pred_target = slot0_src2_value;
        else if (btb_valid[idx0_reg] && (btb_tag[idx0_reg] == pc[63:5]))
            slot0_pred_target = btb_target[idx0_reg];
        else
            slot0_pred_target = pc + 64'd4;
    end

    if (!recovery_valid && !hlt && !halt_inflight && (slot0_class != CLASS_NOP)) begin
        if ((rob_count_now < ROB_SIZE) &&
            ((!slot0_has_dest) || (free_count > 0)) &&
            (((slot0_class == CLASS_INT) || (slot0_class == CLASS_BRANCH)) ? int_free0_valid :
             ((slot0_class == CLASS_FP) ? fp_free0_valid :
              ((slot0_class == CLASS_LOAD) || (slot0_class == CLASS_STORE) || (slot0_class == CLASS_CALL) || (slot0_class == CLASS_RETURN)) ? lsq_free0_valid : 1'b1))) begin
            dispatch0_valid = 1'b1;
        end
    end

    slot0_blocks_second = (slot0_class == CLASS_HALT) || ((slot0_class == CLASS_BRANCH || slot0_class == CLASS_CALL || slot0_class == CLASS_RETURN) && slot0_pred_taken);

    if (dispatch0_valid) begin
        if (slot0_class == CLASS_INT || slot0_class == CLASS_FP || slot0_class == CLASS_LOAD)
            slot0_dest_phys = alloc_tag0;
        else
            slot0_dest_phys = {PHYS_TAG_W{1'b0}};
        if (slot0_class == CLASS_BRANCH || slot0_class == CLASS_CALL || slot0_class == CLASS_RETURN)
            slot0_blocks_second = slot0_pred_taken;
    end

    if (slot1_class == CLASS_INT) begin
        if (is_literal1) begin
            map_source(rd1, rd1_arch_data, dispatch0_valid && slot0_has_dest, rd0, alloc_tag0, slot1_src0_ready, slot1_src0_tag, slot1_src0_value);
            slot1_src1_ready = 1'b1;
            slot1_src1_value = zero_ext12(L1);
        end
        else begin
            map_source(rs1, rs1_arch_data, dispatch0_valid && slot0_has_dest, rd0, alloc_tag0, slot1_src0_ready, slot1_src0_tag, slot1_src0_value);
            if ((opcode1 == 5'h03) || (opcode1 == 5'h11)) begin
                slot1_src1_ready = 1'b1;
                slot1_src1_value = 64'd0;
            end
            else begin
                map_source(rt1, rt1_arch_data, dispatch0_valid && slot0_has_dest, rd0, alloc_tag0, slot1_src1_ready, slot1_src1_tag, slot1_src1_value);
            end
        end
    end
    else if (slot1_class == CLASS_FP) begin
        map_source(rs1, rs1_arch_data, dispatch0_valid && slot0_has_dest, rd0, alloc_tag0, slot1_src0_ready, slot1_src0_tag, slot1_src0_value);
        map_source(rt1, rt1_arch_data, dispatch0_valid && slot0_has_dest, rd0, alloc_tag0, slot1_src1_ready, slot1_src1_tag, slot1_src1_value);
    end
    else if (slot1_class == CLASS_LOAD) begin
        map_source(rs1, rs1_arch_data, dispatch0_valid && slot0_has_dest, rd0, alloc_tag0, slot1_src0_ready, slot1_src0_tag, slot1_src0_value);
    end
    else if (slot1_class == CLASS_STORE) begin
        map_source(rd1, rd1_arch_data, dispatch0_valid && slot0_has_dest, rd0, alloc_tag0, slot1_src0_ready, slot1_src0_tag, slot1_src0_value);
        map_source(rs1, rs1_arch_data, dispatch0_valid && slot0_has_dest, rd0, alloc_tag0, slot1_src1_ready, slot1_src1_tag, slot1_src1_value);
    end
    else if (slot1_class == CLASS_BRANCH) begin
        if (br_abs1 || br_rel_reg1) begin
            map_source(rd1, rd1_arch_data, dispatch0_valid && slot0_has_dest, rd0, alloc_tag0, slot1_src2_ready, slot1_src2_tag, slot1_src2_value);
        end
        else if (br_nz1) begin
            map_source(rs1, rs1_arch_data, dispatch0_valid && slot0_has_dest, rd0, alloc_tag0, slot1_src0_ready, slot1_src0_tag, slot1_src0_value);
            map_source(rd1, rd1_arch_data, dispatch0_valid && slot0_has_dest, rd0, alloc_tag0, slot1_src2_ready, slot1_src2_tag, slot1_src2_value);
        end
        else if (br_gt1) begin
            map_source(rs1, rs1_arch_data, dispatch0_valid && slot0_has_dest, rd0, alloc_tag0, slot1_src0_ready, slot1_src0_tag, slot1_src0_value);
            map_source(rt1, rt1_arch_data, dispatch0_valid && slot0_has_dest, rd0, alloc_tag0, slot1_src1_ready, slot1_src1_tag, slot1_src1_value);
            map_source(rd1, rd1_arch_data, dispatch0_valid && slot0_has_dest, rd0, alloc_tag0, slot1_src2_ready, slot1_src2_tag, slot1_src2_value);
        end
    end
    else if (slot1_class == CLASS_CALL) begin
        map_source(5'd31, sp_arch_data, dispatch0_valid && slot0_has_dest, rd0, alloc_tag0, slot1_src0_ready, slot1_src0_tag, slot1_src0_value);
        map_source(rd1, rd1_arch_data, dispatch0_valid && slot0_has_dest, rd0, alloc_tag0, slot1_src1_ready, slot1_src1_tag, slot1_src1_value);
    end
    else if (slot1_class == CLASS_RETURN) begin
        map_source(5'd31, sp_arch_data, dispatch0_valid && slot0_has_dest, rd0, alloc_tag0, slot1_src0_ready, slot1_src0_tag, slot1_src0_value);
    end

    idx1_reg = pred_index(pc + 64'd4);
    if (slot1_class == CLASS_CALL || slot1_class == CLASS_RETURN || slot1_class == CLASS_BRANCH) begin
        if (br_nz1 || br_gt1)
            slot1_pred_taken = bht[idx1_reg][1];
        else
            slot1_pred_taken = 1'b1;

        if (br_rel_lit1)
            slot1_pred_target = (pc + 64'd4) + sign_ext12(L1);
        else if (br_rel_reg1 && slot1_src2_ready)
            slot1_pred_target = (pc + 64'd4) + slot1_src2_value;
        else if (call1 && slot1_src1_ready)
            slot1_pred_target = slot1_src1_value;
        else if ((br_abs1 || br_nz1 || br_gt1) && slot1_src2_ready)
            slot1_pred_target = slot1_src2_value;
        else if (btb_valid[idx1_reg] && (btb_tag[idx1_reg] == ((pc + 64'd4) >> 5)))
            slot1_pred_target = btb_target[idx1_reg];
        else
            slot1_pred_target = pc + 64'd8;
    end

    if (dispatch0_valid && !slot0_blocks_second && (slot1_class != CLASS_NOP) && (rob_count_now < ROB_SIZE - 1)) begin
        use_second_int_slot = ((slot0_class == CLASS_INT) || (slot0_class == CLASS_BRANCH)) && ((slot1_class == CLASS_INT) || (slot1_class == CLASS_BRANCH));
        use_second_fp_slot = (slot0_class == CLASS_FP) && (slot1_class == CLASS_FP);
        use_second_lsq_slot = ((slot0_class == CLASS_LOAD) || (slot0_class == CLASS_STORE) || (slot0_class == CLASS_CALL) || (slot0_class == CLASS_RETURN)) &&
                              ((slot1_class == CLASS_LOAD) || (slot1_class == CLASS_STORE) || (slot1_class == CLASS_CALL) || (slot1_class == CLASS_RETURN));

        if (((slot1_class == CLASS_INT) || (slot1_class == CLASS_BRANCH)) ? (use_second_int_slot ? int_free1_valid : int_free0_valid) :
            ((slot1_class == CLASS_FP) ? (use_second_fp_slot ? fp_free1_valid : fp_free0_valid) :
             ((slot1_class == CLASS_LOAD) || (slot1_class == CLASS_STORE) || (slot1_class == CLASS_CALL) || (slot1_class == CLASS_RETURN)) ? (use_second_lsq_slot ? lsq_free1_valid : lsq_free0_valid) : 1'b1)) begin
            if ((!slot1_has_dest) || (free_count > (slot0_has_dest ? 1 : 0))) begin
                dispatch1_valid = 1'b1;
            end
        end
    end

    if (dispatch1_valid) begin
        if (slot1_has_dest)
            slot1_dest_phys = slot0_has_dest ? alloc_tag1 : alloc_tag0;
        else
            slot1_dest_phys = {PHYS_TAG_W{1'b0}};
        if (dispatch0_valid && slot0_has_dest && (rd1 == rd0))
            slot1_old_phys = alloc_tag0;
        else
            slot1_old_phys = rat[rd1];
        slot1_blocks_fetch = (slot1_class == CLASS_HALT) || ((slot1_class == CLASS_BRANCH || slot1_class == CLASS_CALL || slot1_class == CLASS_RETURN) && slot1_pred_taken);
    end

    if (hlt)
        next_pc = pc;
    else if (recovery_valid)
        next_pc = recovery_target;
    else if (halt_inflight)
        next_pc = pc;
    else if (!dispatch0_valid)
        next_pc = pc;
    else if (slot0_blocks_second)
        next_pc = slot0_pred_taken ? slot0_pred_target : (pc + 64'd4);
    else if (!dispatch1_valid)
        next_pc = pc + 64'd4;
    else if (slot1_blocks_fetch)
        next_pc = slot1_pred_taken ? slot1_pred_target : (pc + 64'd8);
    else
        next_pc = pc + 64'd8;
end

always @(posedge clk or posedge reset) begin
    if (reset) begin
        hlt = 1'b0;
        free_head = 7'd0;
        free_tail = 7'd32;
        free_count = 7'd32;
        rob_head = {ROB_IDX_W{1'b0}};
        rob_tail = {ROB_IDX_W{1'b0}};
        for (i = 0; i < ARCH_REGS; i = i + 1) begin
            rat[i] = {1'b0, i[4:0]};
        end
        for (i = 0; i < PHYS_REGS; i = i + 1) begin
            phys_value[i] = 64'd0;
            phys_ready[i] = 1'b1;
            free_list[i] = i[PHYS_TAG_W-1:0];
        end
        phys_value[31] = 512 * 1024;
        for (i = 0; i < 32; i = i + 1) begin
            free_list[i] = i + 32;
        end
        for (i = 0; i < ROB_SIZE; i = i + 1) begin
            rob_valid[i] = 1'b0;
            rob_ready[i] = 1'b0;
            rob_has_dest[i] = 1'b0;
            rob_dest_arch[i] = 5'd0;
            rob_dest_phys[i] = {PHYS_TAG_W{1'b0}};
            rob_old_phys[i] = {PHYS_TAG_W{1'b0}};
            rob_value[i] = 64'd0;
            rob_pc[i] = 64'd0;
            rob_opcode[i] = 5'd0;
            rob_is_store[i] = 1'b0;
            rob_is_call[i] = 1'b0;
            rob_is_return[i] = 1'b0;
            rob_is_branch[i] = 1'b0;
            rob_is_halt[i] = 1'b0;
            rob_pred_taken[i] = 1'b0;
            rob_pred_target[i] = 64'd0;
            rob_store_addr[i] = 64'd0;
            rob_store_data[i] = 64'd0;
            rob_checkpoint_free_head[i] = 7'd0;
            for (j = 0; j < ARCH_REGS; j = j + 1) begin
                rob_checkpoint_rat[i][j] = {1'b0, j[4:0]};
            end
        end
        for (i = 0; i < INT_RS_SIZE; i = i + 1) begin
            int_rs_valid[i] = 1'b0;
            int_rs_is_branch[i] = 1'b0;
            int_rs_is_cond[i] = 1'b0;
            int_rs_br_abs[i] = 1'b0;
            int_rs_br_rel_reg[i] = 1'b0;
            int_rs_br_rel_lit[i] = 1'b0;
            int_rs_br_nz[i] = 1'b0;
            int_rs_br_gt[i] = 1'b0;
            int_rs_alu_op[i] = 5'd0;
            int_rs_pc[i] = 64'd0;
            int_rs_imm[i] = 64'd0;
            int_rs_rob[i] = {ROB_IDX_W{1'b0}};
            int_rs_has_dest[i] = 1'b0;
            int_rs_dest[i] = {PHYS_TAG_W{1'b0}};
            int_rs_src0_ready[i] = 1'b0;
            int_rs_src0_tag[i] = {PHYS_TAG_W{1'b0}};
            int_rs_src0_value[i] = 64'd0;
            int_rs_src1_ready[i] = 1'b0;
            int_rs_src1_tag[i] = {PHYS_TAG_W{1'b0}};
            int_rs_src1_value[i] = 64'd0;
            int_rs_src2_ready[i] = 1'b0;
            int_rs_src2_tag[i] = {PHYS_TAG_W{1'b0}};
            int_rs_src2_value[i] = 64'd0;
            int_rs_pred_taken[i] = 1'b0;
            int_rs_pred_target[i] = 64'd0;
        end
        for (i = 0; i < FP_RS_SIZE; i = i + 1) begin
            fp_rs_valid[i] = 1'b0;
            fp_rs_op[i] = 5'd0;
            fp_rs_rob[i] = {ROB_IDX_W{1'b0}};
            fp_rs_dest[i] = {PHYS_TAG_W{1'b0}};
            fp_rs_src0_ready[i] = 1'b0;
            fp_rs_src0_tag[i] = {PHYS_TAG_W{1'b0}};
            fp_rs_src0_value[i] = 64'd0;
            fp_rs_src1_ready[i] = 1'b0;
            fp_rs_src1_tag[i] = {PHYS_TAG_W{1'b0}};
            fp_rs_src1_value[i] = 64'd0;
        end
        for (i = 0; i < LSQ_SIZE; i = i + 1) begin
            lsq_valid[i] = 1'b0;
            lsq_is_load[i] = 1'b0;
            lsq_is_store[i] = 1'b0;
            lsq_is_call[i] = 1'b0;
            lsq_is_return[i] = 1'b0;
            lsq_rob[i] = {ROB_IDX_W{1'b0}};
            lsq_dest[i] = {PHYS_TAG_W{1'b0}};
            lsq_pc[i] = 64'd0;
            lsq_imm[i] = 64'd0;
            lsq_src0_ready[i] = 1'b0;
            lsq_src0_tag[i] = {PHYS_TAG_W{1'b0}};
            lsq_src0_value[i] = 64'd0;
            lsq_src1_ready[i] = 1'b0;
            lsq_src1_tag[i] = {PHYS_TAG_W{1'b0}};
            lsq_src1_value[i] = 64'd0;
            lsq_addr_ready[i] = 1'b0;
            lsq_addr[i] = 64'd0;
            lsq_data_ready[i] = 1'b0;
            lsq_data[i] = 64'd0;
            lsq_control_issued[i] = 1'b0;
            lsq_control_done[i] = 1'b0;
            lsq_pred_taken[i] = 1'b0;
            lsq_pred_target[i] = 64'd0;
        end
        for (u = 0; u < 2; u = u + 1) begin
            alu_pipe_valid[u] = 1'b0;
            alu_pipe_has_dest[u] = 1'b0;
            alu_pipe_rob[u] = {ROB_IDX_W{1'b0}};
            alu_pipe_dest[u] = {PHYS_TAG_W{1'b0}};
            alu_pipe_value[u] = 64'd0;
            alu_pipe_is_branch[u] = 1'b0;
            alu_pipe_is_cond[u] = 1'b0;
            alu_pipe_pred_taken[u] = 1'b0;
            alu_pipe_pred_target[u] = 64'd0;
            alu_pipe_actual_taken[u] = 1'b0;
            alu_pipe_actual_target[u] = 64'd0;
            alu_pipe_pc[u] = 64'd0;
            lsu_pipe_valid[u] = 1'b0;
            lsu_pipe_has_dest[u] = 1'b0;
            lsu_pipe_is_call[u] = 1'b0;
            lsu_pipe_is_return[u] = 1'b0;
            lsu_pipe_rob[u] = {ROB_IDX_W{1'b0}};
            lsu_pipe_dest[u] = {PHYS_TAG_W{1'b0}};
            lsu_pipe_value[u] = 64'd0;
            lsu_pipe_pred_taken[u] = 1'b0;
            lsu_pipe_pred_target[u] = 64'd0;
            lsu_pipe_actual_taken[u] = 1'b0;
            lsu_pipe_actual_target[u] = 64'd0;
            lsu_pipe_pc[u] = 64'd0;
            for (s = 0; s < FPU_LAT; s = s + 1) begin
                fpu_pipe_valid[u][s] = 1'b0;
                fpu_pipe_rob[u][s] = {ROB_IDX_W{1'b0}};
                fpu_pipe_dest[u][s] = {PHYS_TAG_W{1'b0}};
            end
        end
        for (i = 0; i < PRED_SIZE; i = i + 1) begin
            bht[i] = 2'b10;
            btb_valid[i] = 1'b0;
            btb_tag[i] = 59'd0;
            btb_target[i] = 64'd0;
        end
    end
    else if (!hlt) begin
        if (alu_pipe_valid[0] && !(recovery_valid && rob_is_younger(rob_head, alu_pipe_rob[0], recovery_rob))) begin
            if (alu_pipe_is_branch[0]) begin
                rob_ready[alu_pipe_rob[0]] = 1'b1;
                if (alu_pipe_is_cond[0]) begin
                    if (alu_pipe_actual_taken[0] && (bht[pred_index(alu_pipe_pc[0])] != 2'b11))
                        bht[pred_index(alu_pipe_pc[0])] = bht[pred_index(alu_pipe_pc[0])] + 1'b1;
                    if (!alu_pipe_actual_taken[0] && (bht[pred_index(alu_pipe_pc[0])] != 2'b00))
                        bht[pred_index(alu_pipe_pc[0])] = bht[pred_index(alu_pipe_pc[0])] - 1'b1;
                end
                if (alu_pipe_actual_taken[0]) begin
                    btb_valid[pred_index(alu_pipe_pc[0])] = 1'b1;
                    btb_tag[pred_index(alu_pipe_pc[0])] = alu_pipe_pc[0][63:5];
                    btb_target[pred_index(alu_pipe_pc[0])] = alu_pipe_actual_target[0];
                end
            end
            else if (alu_pipe_has_dest[0]) begin
                phys_value[alu_pipe_dest[0]] = alu_pipe_value[0];
                phys_ready[alu_pipe_dest[0]] = 1'b1;
                rob_value[alu_pipe_rob[0]] = alu_pipe_value[0];
                rob_ready[alu_pipe_rob[0]] = 1'b1;
                broadcast_result(alu_pipe_dest[0], alu_pipe_value[0]);
            end
        end

        if (alu_pipe_valid[1] && !(recovery_valid && rob_is_younger(rob_head, alu_pipe_rob[1], recovery_rob))) begin
            if (alu_pipe_is_branch[1]) begin
                rob_ready[alu_pipe_rob[1]] = 1'b1;
                if (alu_pipe_is_cond[1]) begin
                    if (alu_pipe_actual_taken[1] && (bht[pred_index(alu_pipe_pc[1])] != 2'b11))
                        bht[pred_index(alu_pipe_pc[1])] = bht[pred_index(alu_pipe_pc[1])] + 1'b1;
                    if (!alu_pipe_actual_taken[1] && (bht[pred_index(alu_pipe_pc[1])] != 2'b00))
                        bht[pred_index(alu_pipe_pc[1])] = bht[pred_index(alu_pipe_pc[1])] - 1'b1;
                end
                if (alu_pipe_actual_taken[1]) begin
                    btb_valid[pred_index(alu_pipe_pc[1])] = 1'b1;
                    btb_tag[pred_index(alu_pipe_pc[1])] = alu_pipe_pc[1][63:5];
                    btb_target[pred_index(alu_pipe_pc[1])] = alu_pipe_actual_target[1];
                end
            end
            else if (alu_pipe_has_dest[1]) begin
                phys_value[alu_pipe_dest[1]] = alu_pipe_value[1];
                phys_ready[alu_pipe_dest[1]] = 1'b1;
                rob_value[alu_pipe_rob[1]] = alu_pipe_value[1];
                rob_ready[alu_pipe_rob[1]] = 1'b1;
                broadcast_result(alu_pipe_dest[1], alu_pipe_value[1]);
            end
        end

        if (fpu0_out_valid && fpu_pipe_valid[0][FPU_LAT - 1] &&
            !(recovery_valid && rob_is_younger(rob_head, fpu_pipe_rob[0][FPU_LAT - 1], recovery_rob))) begin
            phys_value[fpu_pipe_dest[0][FPU_LAT - 1]] = fpu0_result;
            phys_ready[fpu_pipe_dest[0][FPU_LAT - 1]] = 1'b1;
            rob_value[fpu_pipe_rob[0][FPU_LAT - 1]] = fpu0_result;
            rob_ready[fpu_pipe_rob[0][FPU_LAT - 1]] = 1'b1;
            broadcast_result(fpu_pipe_dest[0][FPU_LAT - 1], fpu0_result);
        end

        if (fpu1_out_valid && fpu_pipe_valid[1][FPU_LAT - 1] &&
            !(recovery_valid && rob_is_younger(rob_head, fpu_pipe_rob[1][FPU_LAT - 1], recovery_rob))) begin
            phys_value[fpu_pipe_dest[1][FPU_LAT - 1]] = fpu1_result;
            phys_ready[fpu_pipe_dest[1][FPU_LAT - 1]] = 1'b1;
            rob_value[fpu_pipe_rob[1][FPU_LAT - 1]] = fpu1_result;
            rob_ready[fpu_pipe_rob[1][FPU_LAT - 1]] = 1'b1;
            broadcast_result(fpu_pipe_dest[1][FPU_LAT - 1], fpu1_result);
        end

        for (u = 0; u < 2; u = u + 1) begin
            if (lsu_pipe_valid[u] && !(recovery_valid && rob_is_younger(rob_head, lsu_pipe_rob[u], recovery_rob))) begin
                if (lsu_pipe_has_dest[u]) begin
                    phys_value[lsu_pipe_dest[u]] = lsu_pipe_value[u];
                    phys_ready[lsu_pipe_dest[u]] = 1'b1;
                    rob_value[lsu_pipe_rob[u]] = lsu_pipe_value[u];
                    rob_ready[lsu_pipe_rob[u]] = 1'b1;
                    broadcast_result(lsu_pipe_dest[u], lsu_pipe_value[u]);
                end
                else begin
                    if (lsu_pipe_actual_taken[u]) begin
                        btb_valid[pred_index(lsu_pipe_pc[u])] = 1'b1;
                        btb_tag[pred_index(lsu_pipe_pc[u])] = lsu_pipe_pc[u][63:5];
                        btb_target[pred_index(lsu_pipe_pc[u])] = lsu_pipe_actual_target[u];
                    end
                    if (lsu_pipe_is_return[u]) begin
                        rob_ready[lsu_pipe_rob[u]] = 1'b1;
                    end
                    else begin
                        for (i = 0; i < LSQ_SIZE; i = i + 1) begin
                            if (lsq_valid[i] && lsq_is_call[i] && (lsq_rob[i] == lsu_pipe_rob[u])) begin
                                lsq_control_done[i] = 1'b1;
                            end
                        end
                    end
                end
            end
        end

        for (i = 0; i < LSQ_SIZE; i = i + 1) begin
            if (lsq_valid[i]) begin
                if (!lsq_addr_ready[i] && lsq_src0_ready[i]) begin
                    if (lsq_is_call[i] || lsq_is_return[i])
                        lsq_addr[i] = lsq_src0_value[i] - 64'd8;
                    else
                        lsq_addr[i] = lsq_src0_value[i] + lsq_imm[i];
                    lsq_addr_ready[i] = 1'b1;
                end
                if (!lsq_data_ready[i]) begin
                    if (lsq_is_store[i] && lsq_src1_ready[i]) begin
                        lsq_data[i] = lsq_src1_value[i];
                        lsq_data_ready[i] = 1'b1;
                    end
                    else if (lsq_is_call[i]) begin
                        lsq_data[i] = lsq_pc[i] + 64'd4;
                        lsq_data_ready[i] = 1'b1;
                    end
                end

                if (lsq_is_store[i] && lsq_addr_ready[i] && lsq_data_ready[i]) begin
                    rob_store_addr[lsq_rob[i]] = lsq_addr[i];
                    rob_store_data[lsq_rob[i]] = lsq_data[i];
                    rob_ready[lsq_rob[i]] = 1'b1;
                end
                if (lsq_is_call[i] && lsq_addr_ready[i] && lsq_data_ready[i] && lsq_control_done[i]) begin
                    rob_store_addr[lsq_rob[i]] = lsq_addr[i];
                    rob_store_data[lsq_rob[i]] = lsq_data[i];
                    rob_ready[lsq_rob[i]] = 1'b1;
                end
            end
        end

        if (commit0_valid) begin
            if (commit0_has_dest) begin
                free_list[free_tail] = rob_old_phys[rob_head];
                free_tail = free_inc(free_tail);
                free_count = free_count + 1'b1;
            end
            if (rob_is_halt[rob_head]) begin
                rob_valid[rob_head] = 1'b0;
                hlt = 1'b1;
            end
            else begin
                if (rob_is_store[rob_head] || rob_is_call[rob_head]) begin
                    for (i = 0; i < LSQ_SIZE; i = i + 1) begin
                        if (lsq_valid[i] && (lsq_rob[i] == rob_head)) begin
                            lsq_valid[i] = 1'b0;
                            lsq_control_issued[i] = 1'b0;
                            lsq_control_done[i] = 1'b0;
                        end
                    end
                end
                rob_valid[rob_head] = 1'b0;
                rob_head = rob_inc(rob_head);
            end
        end

        if (!hlt && commit1_fire) begin
            if (commit1_has_dest) begin
                free_list[free_tail] = rob_old_phys[rob_head_plus1];
                free_tail = free_inc(free_tail);
                free_count = free_count + 1'b1;
            end
            if (rob_is_halt[rob_head_plus1]) begin
                rob_valid[rob_head_plus1] = 1'b0;
                rob_head = rob_inc(rob_head_plus1);
                hlt = 1'b1;
            end
            else begin
                if (rob_is_store[rob_head_plus1] || rob_is_call[rob_head_plus1]) begin
                    for (i = 0; i < LSQ_SIZE; i = i + 1) begin
                        if (lsq_valid[i] && (lsq_rob[i] == rob_head_plus1)) begin
                            lsq_valid[i] = 1'b0;
                            lsq_control_issued[i] = 1'b0;
                            lsq_control_done[i] = 1'b0;
                        end
                    end
                end
                rob_valid[rob_head_plus1] = 1'b0;
                rob_head = rob_inc(rob_head_plus1);
            end
        end

        for (u = 0; u < 2; u = u + 1) begin
            for (s = FPU_LAT - 1; s > 0; s = s - 1) begin
                fpu_pipe_valid[u][s] = fpu_pipe_valid[u][s - 1];
                fpu_pipe_rob[u][s] = fpu_pipe_rob[u][s - 1];
                fpu_pipe_dest[u][s] = fpu_pipe_dest[u][s - 1];
            end
            fpu_pipe_valid[u][0] = 1'b0;
        end

        alu_pipe_valid[0] = 1'b0;
        alu_pipe_valid[1] = 1'b0;
        lsu_pipe_valid[0] = 1'b0;
        lsu_pipe_valid[1] = 1'b0;

        if (!hlt && !recovery_valid) begin
            if (issue_int0_valid) begin
                alu_pipe_valid[0] = 1'b1;
                alu_pipe_has_dest[0] = int_rs_has_dest[issue_int0_idx];
                alu_pipe_rob[0] = int_rs_rob[issue_int0_idx];
                alu_pipe_dest[0] = int_rs_dest[issue_int0_idx];
                alu_pipe_value[0] = issue_int0_is_branch ? 64'd0 : alu0_result;
                alu_pipe_is_branch[0] = issue_int0_is_branch;
                alu_pipe_is_cond[0] = issue_int0_is_cond;
                alu_pipe_pred_taken[0] = issue_int0_pred_taken;
                alu_pipe_pred_target[0] = issue_int0_pred_target;
                alu_pipe_actual_taken[0] = issue_int0_actual_taken;
                alu_pipe_actual_target[0] = issue_int0_actual_target;
                alu_pipe_pc[0] = int_rs_pc[issue_int0_idx];
                int_rs_valid[issue_int0_idx] = 1'b0;
            end

            if (issue_int1_valid) begin
                alu_pipe_valid[1] = 1'b1;
                alu_pipe_has_dest[1] = int_rs_has_dest[issue_int1_idx];
                alu_pipe_rob[1] = int_rs_rob[issue_int1_idx];
                alu_pipe_dest[1] = int_rs_dest[issue_int1_idx];
                alu_pipe_value[1] = issue_int1_is_branch ? 64'd0 : alu1_result;
                alu_pipe_is_branch[1] = issue_int1_is_branch;
                alu_pipe_is_cond[1] = issue_int1_is_cond;
                alu_pipe_pred_taken[1] = issue_int1_pred_taken;
                alu_pipe_pred_target[1] = issue_int1_pred_target;
                alu_pipe_actual_taken[1] = issue_int1_actual_taken;
                alu_pipe_actual_target[1] = issue_int1_actual_target;
                alu_pipe_pc[1] = int_rs_pc[issue_int1_idx];
                int_rs_valid[issue_int1_idx] = 1'b0;
            end

            if (issue_fp0_valid) begin
                fpu_pipe_valid[0][0] = 1'b1;
                fpu_pipe_rob[0][0] = fp_rs_rob[issue_fp0_idx];
                fpu_pipe_dest[0][0] = fp_rs_dest[issue_fp0_idx];
                fp_rs_valid[issue_fp0_idx] = 1'b0;
            end

            if (issue_fp1_valid) begin
                fpu_pipe_valid[1][0] = 1'b1;
                fpu_pipe_rob[1][0] = fp_rs_rob[issue_fp1_idx];
                fpu_pipe_dest[1][0] = fp_rs_dest[issue_fp1_idx];
                fp_rs_valid[issue_fp1_idx] = 1'b0;
            end

            if (issue_lsu0_valid) begin
                lsu_pipe_valid[0] = 1'b1;
                lsu_pipe_has_dest[0] = issue_lsu0_has_dest;
                lsu_pipe_is_call[0] = issue_lsu0_is_call;
                lsu_pipe_is_return[0] = issue_lsu0_is_return;
                lsu_pipe_rob[0] = lsq_rob[issue_lsu0_idx];
                lsu_pipe_dest[0] = lsq_dest[issue_lsu0_idx];
                lsu_pipe_value[0] = issue_lsu0_value;
                lsu_pipe_pred_taken[0] = issue_lsu0_pred_taken;
                lsu_pipe_pred_target[0] = issue_lsu0_pred_target;
                lsu_pipe_actual_taken[0] = issue_lsu0_actual_taken;
                lsu_pipe_actual_target[0] = issue_lsu0_actual_target;
                lsu_pipe_pc[0] = lsq_pc[issue_lsu0_idx];
                if (lsq_is_call[issue_lsu0_idx]) begin
                    lsq_control_issued[issue_lsu0_idx] = 1'b1;
                end
                else begin
                    lsq_valid[issue_lsu0_idx] = 1'b0;
                end
            end

            if (issue_lsu1_valid) begin
                lsu_pipe_valid[1] = 1'b1;
                lsu_pipe_has_dest[1] = issue_lsu1_has_dest;
                lsu_pipe_is_call[1] = issue_lsu1_is_call;
                lsu_pipe_is_return[1] = issue_lsu1_is_return;
                lsu_pipe_rob[1] = lsq_rob[issue_lsu1_idx];
                lsu_pipe_dest[1] = lsq_dest[issue_lsu1_idx];
                lsu_pipe_value[1] = issue_lsu1_value;
                lsu_pipe_pred_taken[1] = issue_lsu1_pred_taken;
                lsu_pipe_pred_target[1] = issue_lsu1_pred_target;
                lsu_pipe_actual_taken[1] = issue_lsu1_actual_taken;
                lsu_pipe_actual_target[1] = issue_lsu1_actual_target;
                lsu_pipe_pc[1] = lsq_pc[issue_lsu1_idx];
                if (lsq_is_call[issue_lsu1_idx]) begin
                    lsq_control_issued[issue_lsu1_idx] = 1'b1;
                end
                else begin
                    lsq_valid[issue_lsu1_idx] = 1'b0;
                end
            end
        end

        if (!hlt && recovery_valid) begin
            for (i = 0; i < ARCH_REGS; i = i + 1) begin
                rat[i] = rob_checkpoint_rat[recovery_rob][i];
            end
            free_head = rob_checkpoint_free_head[recovery_rob];
            free_count = free_count_from_ptrs(rob_checkpoint_free_head[recovery_rob], free_tail);
            rob_tail = rob_inc(recovery_rob);

            for (i = 0; i < ROB_SIZE; i = i + 1) begin
                if (rob_valid[i] && rob_is_younger(rob_head, i[ROB_IDX_W-1:0], recovery_rob)) begin
                    rob_valid[i] = 1'b0;
                    rob_ready[i] = 1'b0;
                    rob_has_dest[i] = 1'b0;
                    rob_is_store[i] = 1'b0;
                    rob_is_call[i] = 1'b0;
                    rob_is_return[i] = 1'b0;
                    rob_is_branch[i] = 1'b0;
                    rob_is_halt[i] = 1'b0;
                end
            end

            for (i = 0; i < INT_RS_SIZE; i = i + 1) begin
                if (int_rs_valid[i] && rob_is_younger(rob_head, int_rs_rob[i], recovery_rob))
                    int_rs_valid[i] = 1'b0;
            end
            for (i = 0; i < FP_RS_SIZE; i = i + 1) begin
                if (fp_rs_valid[i] && rob_is_younger(rob_head, fp_rs_rob[i], recovery_rob))
                    fp_rs_valid[i] = 1'b0;
            end
            for (i = 0; i < LSQ_SIZE; i = i + 1) begin
                if (lsq_valid[i] && rob_is_younger(rob_head, lsq_rob[i], recovery_rob)) begin
                    lsq_valid[i] = 1'b0;
                    lsq_control_issued[i] = 1'b0;
                    lsq_control_done[i] = 1'b0;
                end
            end
            for (u = 0; u < 2; u = u + 1) begin
                if (alu_pipe_valid[u] && rob_is_younger(rob_head, alu_pipe_rob[u], recovery_rob))
                    alu_pipe_valid[u] = 1'b0;
                if (lsu_pipe_valid[u] && rob_is_younger(rob_head, lsu_pipe_rob[u], recovery_rob))
                    lsu_pipe_valid[u] = 1'b0;
                for (s = 0; s < FPU_LAT; s = s + 1) begin
                    if (fpu_pipe_valid[u][s] && rob_is_younger(rob_head, fpu_pipe_rob[u][s], recovery_rob))
                        fpu_pipe_valid[u][s] = 1'b0;
                end
            end
        end
        else if (!hlt) begin
            if (dispatch0_valid) begin
                rob_valid[rob_tail] = 1'b1;
                rob_ready[rob_tail] = (slot0_class == CLASS_HALT);
                rob_has_dest[rob_tail] = slot0_has_dest;
                rob_dest_arch[rob_tail] = rd0;
                rob_dest_phys[rob_tail] = slot0_dest_phys;
                rob_old_phys[rob_tail] = slot0_old_phys;
                rob_value[rob_tail] = 64'd0;
                rob_pc[rob_tail] = pc;
                rob_opcode[rob_tail] = opcode0;
                rob_is_store[rob_tail] = (slot0_class == CLASS_STORE);
                rob_is_call[rob_tail] = (slot0_class == CLASS_CALL);
                rob_is_return[rob_tail] = (slot0_class == CLASS_RETURN);
                rob_is_branch[rob_tail] = (slot0_class == CLASS_BRANCH);
                rob_is_halt[rob_tail] = (slot0_class == CLASS_HALT);
                rob_pred_taken[rob_tail] = slot0_pred_taken;
                rob_pred_target[rob_tail] = slot0_pred_target;
                rob_store_addr[rob_tail] = 64'd0;
                rob_store_data[rob_tail] = 64'd0;

                if (slot0_has_dest) begin
                    rat[rd0] = slot0_dest_phys;
                    phys_ready[slot0_dest_phys] = 1'b0;
                    free_head = free_inc(free_head);
                    free_count = free_count - 1'b1;
                end

                if (slot0_class == CLASS_INT || slot0_class == CLASS_BRANCH) begin
                    int_rs_valid[int_free0_idx] = 1'b1;
                    int_rs_is_branch[int_free0_idx] = (slot0_class == CLASS_BRANCH);
                    int_rs_is_cond[int_free0_idx] = br_nz0 || br_gt0;
                    int_rs_br_abs[int_free0_idx] = br_abs0;
                    int_rs_br_rel_reg[int_free0_idx] = br_rel_reg0;
                    int_rs_br_rel_lit[int_free0_idx] = br_rel_lit0;
                    int_rs_br_nz[int_free0_idx] = br_nz0;
                    int_rs_br_gt[int_free0_idx] = br_gt0;
                    int_rs_alu_op[int_free0_idx] = alu_op0;
                    int_rs_pc[int_free0_idx] = pc;
                    int_rs_imm[int_free0_idx] = sign_ext12(L0);
                    int_rs_rob[int_free0_idx] = rob_tail;
                    int_rs_has_dest[int_free0_idx] = slot0_has_dest;
                    int_rs_dest[int_free0_idx] = slot0_dest_phys;
                    int_rs_src0_ready[int_free0_idx] = slot0_src0_ready || (!slot0_src0_ready && phys_ready[slot0_src0_tag]);
                    int_rs_src0_tag[int_free0_idx] = slot0_src0_tag;
                    if (slot0_src0_ready)
                        int_rs_src0_value[int_free0_idx] = slot0_src0_value;
                    else if (phys_ready[slot0_src0_tag])
                        int_rs_src0_value[int_free0_idx] = phys_value[slot0_src0_tag];
                    else
                        int_rs_src0_value[int_free0_idx] = slot0_src0_value;
                    int_rs_src1_ready[int_free0_idx] = slot0_src1_ready || (!slot0_src1_ready && phys_ready[slot0_src1_tag]);
                    int_rs_src1_tag[int_free0_idx] = slot0_src1_tag;
                    if (slot0_src1_ready)
                        int_rs_src1_value[int_free0_idx] = slot0_src1_value;
                    else if (phys_ready[slot0_src1_tag])
                        int_rs_src1_value[int_free0_idx] = phys_value[slot0_src1_tag];
                    else
                        int_rs_src1_value[int_free0_idx] = slot0_src1_value;
                    int_rs_src2_ready[int_free0_idx] = slot0_src2_ready || (!slot0_src2_ready && phys_ready[slot0_src2_tag]);
                    int_rs_src2_tag[int_free0_idx] = slot0_src2_tag;
                    if (slot0_src2_ready)
                        int_rs_src2_value[int_free0_idx] = slot0_src2_value;
                    else if (phys_ready[slot0_src2_tag])
                        int_rs_src2_value[int_free0_idx] = phys_value[slot0_src2_tag];
                    else
                        int_rs_src2_value[int_free0_idx] = slot0_src2_value;
                    int_rs_pred_taken[int_free0_idx] = slot0_pred_taken;
                    int_rs_pred_target[int_free0_idx] = slot0_pred_target;
                end
                else if (slot0_class == CLASS_FP) begin
                    fp_rs_valid[fp_free0_idx] = 1'b1;
                    fp_rs_op[fp_free0_idx] = fpu_op0;
                    fp_rs_rob[fp_free0_idx] = rob_tail;
                    fp_rs_dest[fp_free0_idx] = slot0_dest_phys;
                    fp_rs_src0_ready[fp_free0_idx] = slot0_src0_ready || (!slot0_src0_ready && phys_ready[slot0_src0_tag]);
                    fp_rs_src0_tag[fp_free0_idx] = slot0_src0_tag;
                    if (slot0_src0_ready)
                        fp_rs_src0_value[fp_free0_idx] = slot0_src0_value;
                    else if (phys_ready[slot0_src0_tag])
                        fp_rs_src0_value[fp_free0_idx] = phys_value[slot0_src0_tag];
                    else
                        fp_rs_src0_value[fp_free0_idx] = slot0_src0_value;
                    fp_rs_src1_ready[fp_free0_idx] = slot0_src1_ready || (!slot0_src1_ready && phys_ready[slot0_src1_tag]);
                    fp_rs_src1_tag[fp_free0_idx] = slot0_src1_tag;
                    if (slot0_src1_ready)
                        fp_rs_src1_value[fp_free0_idx] = slot0_src1_value;
                    else if (phys_ready[slot0_src1_tag])
                        fp_rs_src1_value[fp_free0_idx] = phys_value[slot0_src1_tag];
                    else
                        fp_rs_src1_value[fp_free0_idx] = slot0_src1_value;
                end
                else if (slot0_class == CLASS_LOAD || slot0_class == CLASS_STORE || slot0_class == CLASS_CALL || slot0_class == CLASS_RETURN) begin
                    lsq_valid[lsq_free0_idx] = 1'b1;
                    lsq_is_load[lsq_free0_idx] = (slot0_class == CLASS_LOAD);
                    lsq_is_store[lsq_free0_idx] = (slot0_class == CLASS_STORE);
                    lsq_is_call[lsq_free0_idx] = (slot0_class == CLASS_CALL);
                    lsq_is_return[lsq_free0_idx] = (slot0_class == CLASS_RETURN);
                    lsq_rob[lsq_free0_idx] = rob_tail;
                    lsq_dest[lsq_free0_idx] = slot0_dest_phys;
                    lsq_pc[lsq_free0_idx] = pc;
                    if (slot0_class == CLASS_CALL || slot0_class == CLASS_RETURN)
                        lsq_imm[lsq_free0_idx] = -64'd8;
                    else
                        lsq_imm[lsq_free0_idx] = zero_ext12(L0);
                    lsq_src0_ready[lsq_free0_idx] = slot0_src0_ready || (!slot0_src0_ready && phys_ready[slot0_src0_tag]);
                    lsq_src0_tag[lsq_free0_idx] = slot0_src0_tag;
                    if (slot0_src0_ready)
                        lsq_src0_value[lsq_free0_idx] = slot0_src0_value;
                    else if (phys_ready[slot0_src0_tag])
                        lsq_src0_value[lsq_free0_idx] = phys_value[slot0_src0_tag];
                    else
                        lsq_src0_value[lsq_free0_idx] = slot0_src0_value;
                    lsq_src1_ready[lsq_free0_idx] = slot0_src1_ready || (!slot0_src1_ready && phys_ready[slot0_src1_tag]);
                    lsq_src1_tag[lsq_free0_idx] = slot0_src1_tag;
                    if (slot0_src1_ready)
                        lsq_src1_value[lsq_free0_idx] = slot0_src1_value;
                    else if (phys_ready[slot0_src1_tag])
                        lsq_src1_value[lsq_free0_idx] = phys_value[slot0_src1_tag];
                    else
                        lsq_src1_value[lsq_free0_idx] = slot0_src1_value;
                    lsq_addr_ready[lsq_free0_idx] = 1'b0;
                    lsq_addr[lsq_free0_idx] = 64'd0;
                    lsq_data_ready[lsq_free0_idx] = 1'b0;
                    lsq_data[lsq_free0_idx] = 64'd0;
                    lsq_control_issued[lsq_free0_idx] = 1'b0;
                    lsq_control_done[lsq_free0_idx] = 1'b0;
                    lsq_pred_taken[lsq_free0_idx] = slot0_pred_taken;
                    lsq_pred_target[lsq_free0_idx] = slot0_pred_target;
                end

                if (slot0_class == CLASS_BRANCH || slot0_class == CLASS_CALL || slot0_class == CLASS_RETURN) begin
                    rob_checkpoint_free_head[rob_tail] = free_head;
                    for (j = 0; j < ARCH_REGS; j = j + 1) begin
                        rob_checkpoint_rat[rob_tail][j] = rat[j];
                    end
                end

                rob_tail = rob_inc(rob_tail);
            end

            if (dispatch1_valid) begin
                int_slot1_idx_reg = (((slot0_class == CLASS_INT) || (slot0_class == CLASS_BRANCH)) && ((slot1_class == CLASS_INT) || (slot1_class == CLASS_BRANCH))) ? int_free1_idx : int_free0_idx;
                fp_slot1_idx_reg = ((slot0_class == CLASS_FP) && (slot1_class == CLASS_FP)) ? fp_free1_idx : fp_free0_idx;
                lsq_slot1_idx_reg = (((slot0_class == CLASS_LOAD) || (slot0_class == CLASS_STORE) || (slot0_class == CLASS_CALL) || (slot0_class == CLASS_RETURN)) &&
                                 ((slot1_class == CLASS_LOAD) || (slot1_class == CLASS_STORE) || (slot1_class == CLASS_CALL) || (slot1_class == CLASS_RETURN))) ? lsq_free1_idx : lsq_free0_idx;

                rob_valid[rob_tail] = 1'b1;
                rob_ready[rob_tail] = (slot1_class == CLASS_HALT);
                rob_has_dest[rob_tail] = slot1_has_dest;
                rob_dest_arch[rob_tail] = rd1;
                rob_dest_phys[rob_tail] = slot1_dest_phys;
                rob_old_phys[rob_tail] = slot1_old_phys;
                rob_value[rob_tail] = 64'd0;
                rob_pc[rob_tail] = pc + 64'd4;
                rob_opcode[rob_tail] = opcode1;
                rob_is_store[rob_tail] = (slot1_class == CLASS_STORE);
                rob_is_call[rob_tail] = (slot1_class == CLASS_CALL);
                rob_is_return[rob_tail] = (slot1_class == CLASS_RETURN);
                rob_is_branch[rob_tail] = (slot1_class == CLASS_BRANCH);
                rob_is_halt[rob_tail] = (slot1_class == CLASS_HALT);
                rob_pred_taken[rob_tail] = slot1_pred_taken;
                rob_pred_target[rob_tail] = slot1_pred_target;
                rob_store_addr[rob_tail] = 64'd0;
                rob_store_data[rob_tail] = 64'd0;

                if (slot1_has_dest) begin
                    rat[rd1] = slot1_dest_phys;
                    phys_ready[slot1_dest_phys] = 1'b0;
                    free_head = free_inc(free_head);
                    free_count = free_count - 1'b1;
                end

                if (slot1_class == CLASS_INT || slot1_class == CLASS_BRANCH) begin
                    int_rs_valid[int_slot1_idx_reg] = 1'b1;
                    int_rs_is_branch[int_slot1_idx_reg] = (slot1_class == CLASS_BRANCH);
                    int_rs_is_cond[int_slot1_idx_reg] = br_nz1 || br_gt1;
                    int_rs_br_abs[int_slot1_idx_reg] = br_abs1;
                    int_rs_br_rel_reg[int_slot1_idx_reg] = br_rel_reg1;
                    int_rs_br_rel_lit[int_slot1_idx_reg] = br_rel_lit1;
                    int_rs_br_nz[int_slot1_idx_reg] = br_nz1;
                    int_rs_br_gt[int_slot1_idx_reg] = br_gt1;
                    int_rs_alu_op[int_slot1_idx_reg] = alu_op1;
                    int_rs_pc[int_slot1_idx_reg] = pc + 64'd4;
                    int_rs_imm[int_slot1_idx_reg] = sign_ext12(L1);
                    int_rs_rob[int_slot1_idx_reg] = rob_tail;
                    int_rs_has_dest[int_slot1_idx_reg] = slot1_has_dest;
                    int_rs_dest[int_slot1_idx_reg] = slot1_dest_phys;
                    int_rs_src0_ready[int_slot1_idx_reg] = slot1_src0_ready || (!slot1_src0_ready && phys_ready[slot1_src0_tag]);
                    int_rs_src0_tag[int_slot1_idx_reg] = slot1_src0_tag;
                    if (slot1_src0_ready)
                        int_rs_src0_value[int_slot1_idx_reg] = slot1_src0_value;
                    else if (phys_ready[slot1_src0_tag])
                        int_rs_src0_value[int_slot1_idx_reg] = phys_value[slot1_src0_tag];
                    else
                        int_rs_src0_value[int_slot1_idx_reg] = slot1_src0_value;
                    int_rs_src1_ready[int_slot1_idx_reg] = slot1_src1_ready || (!slot1_src1_ready && phys_ready[slot1_src1_tag]);
                    int_rs_src1_tag[int_slot1_idx_reg] = slot1_src1_tag;
                    if (slot1_src1_ready)
                        int_rs_src1_value[int_slot1_idx_reg] = slot1_src1_value;
                    else if (phys_ready[slot1_src1_tag])
                        int_rs_src1_value[int_slot1_idx_reg] = phys_value[slot1_src1_tag];
                    else
                        int_rs_src1_value[int_slot1_idx_reg] = slot1_src1_value;
                    int_rs_src2_ready[int_slot1_idx_reg] = slot1_src2_ready || (!slot1_src2_ready && phys_ready[slot1_src2_tag]);
                    int_rs_src2_tag[int_slot1_idx_reg] = slot1_src2_tag;
                    if (slot1_src2_ready)
                        int_rs_src2_value[int_slot1_idx_reg] = slot1_src2_value;
                    else if (phys_ready[slot1_src2_tag])
                        int_rs_src2_value[int_slot1_idx_reg] = phys_value[slot1_src2_tag];
                    else
                        int_rs_src2_value[int_slot1_idx_reg] = slot1_src2_value;
                    int_rs_pred_taken[int_slot1_idx_reg] = slot1_pred_taken;
                    int_rs_pred_target[int_slot1_idx_reg] = slot1_pred_target;
                end
                else if (slot1_class == CLASS_FP) begin
                    fp_rs_valid[fp_slot1_idx_reg] = 1'b1;
                    fp_rs_op[fp_slot1_idx_reg] = fpu_op1;
                    fp_rs_rob[fp_slot1_idx_reg] = rob_tail;
                    fp_rs_dest[fp_slot1_idx_reg] = slot1_dest_phys;
                    fp_rs_src0_ready[fp_slot1_idx_reg] = slot1_src0_ready || (!slot1_src0_ready && phys_ready[slot1_src0_tag]);
                    fp_rs_src0_tag[fp_slot1_idx_reg] = slot1_src0_tag;
                    if (slot1_src0_ready)
                        fp_rs_src0_value[fp_slot1_idx_reg] = slot1_src0_value;
                    else if (phys_ready[slot1_src0_tag])
                        fp_rs_src0_value[fp_slot1_idx_reg] = phys_value[slot1_src0_tag];
                    else
                        fp_rs_src0_value[fp_slot1_idx_reg] = slot1_src0_value;
                    fp_rs_src1_ready[fp_slot1_idx_reg] = slot1_src1_ready || (!slot1_src1_ready && phys_ready[slot1_src1_tag]);
                    fp_rs_src1_tag[fp_slot1_idx_reg] = slot1_src1_tag;
                    if (slot1_src1_ready)
                        fp_rs_src1_value[fp_slot1_idx_reg] = slot1_src1_value;
                    else if (phys_ready[slot1_src1_tag])
                        fp_rs_src1_value[fp_slot1_idx_reg] = phys_value[slot1_src1_tag];
                    else
                        fp_rs_src1_value[fp_slot1_idx_reg] = slot1_src1_value;
                end
                else if (slot1_class == CLASS_LOAD || slot1_class == CLASS_STORE || slot1_class == CLASS_CALL || slot1_class == CLASS_RETURN) begin
                    lsq_valid[lsq_slot1_idx_reg] = 1'b1;
                    lsq_is_load[lsq_slot1_idx_reg] = (slot1_class == CLASS_LOAD);
                    lsq_is_store[lsq_slot1_idx_reg] = (slot1_class == CLASS_STORE);
                    lsq_is_call[lsq_slot1_idx_reg] = (slot1_class == CLASS_CALL);
                    lsq_is_return[lsq_slot1_idx_reg] = (slot1_class == CLASS_RETURN);
                    lsq_rob[lsq_slot1_idx_reg] = rob_tail;
                    lsq_dest[lsq_slot1_idx_reg] = slot1_dest_phys;
                    lsq_pc[lsq_slot1_idx_reg] = pc + 64'd4;
                    if (slot1_class == CLASS_CALL || slot1_class == CLASS_RETURN)
                        lsq_imm[lsq_slot1_idx_reg] = -64'd8;
                    else
                        lsq_imm[lsq_slot1_idx_reg] = zero_ext12(L1);
                    lsq_src0_ready[lsq_slot1_idx_reg] = slot1_src0_ready || (!slot1_src0_ready && phys_ready[slot1_src0_tag]);
                    lsq_src0_tag[lsq_slot1_idx_reg] = slot1_src0_tag;
                    if (slot1_src0_ready)
                        lsq_src0_value[lsq_slot1_idx_reg] = slot1_src0_value;
                    else if (phys_ready[slot1_src0_tag])
                        lsq_src0_value[lsq_slot1_idx_reg] = phys_value[slot1_src0_tag];
                    else
                        lsq_src0_value[lsq_slot1_idx_reg] = slot1_src0_value;
                    lsq_src1_ready[lsq_slot1_idx_reg] = slot1_src1_ready || (!slot1_src1_ready && phys_ready[slot1_src1_tag]);
                    lsq_src1_tag[lsq_slot1_idx_reg] = slot1_src1_tag;
                    if (slot1_src1_ready)
                        lsq_src1_value[lsq_slot1_idx_reg] = slot1_src1_value;
                    else if (phys_ready[slot1_src1_tag])
                        lsq_src1_value[lsq_slot1_idx_reg] = phys_value[slot1_src1_tag];
                    else
                        lsq_src1_value[lsq_slot1_idx_reg] = slot1_src1_value;
                    lsq_addr_ready[lsq_slot1_idx_reg] = 1'b0;
                    lsq_addr[lsq_slot1_idx_reg] = 64'd0;
                    lsq_data_ready[lsq_slot1_idx_reg] = 1'b0;
                    lsq_data[lsq_slot1_idx_reg] = 64'd0;
                    lsq_control_issued[lsq_slot1_idx_reg] = 1'b0;
                    lsq_control_done[lsq_slot1_idx_reg] = 1'b0;
                    lsq_pred_taken[lsq_slot1_idx_reg] = slot1_pred_taken;
                    lsq_pred_target[lsq_slot1_idx_reg] = slot1_pred_target;
                end

                if (slot1_class == CLASS_BRANCH || slot1_class == CLASS_CALL || slot1_class == CLASS_RETURN) begin
                    rob_checkpoint_free_head[rob_tail] = free_head;
                    for (j = 0; j < ARCH_REGS; j = j + 1) begin
                        rob_checkpoint_rat[rob_tail][j] = rat[j];
                    end
                end

                rob_tail = rob_inc(rob_tail);
            end
        end
    end
end

endmodule
