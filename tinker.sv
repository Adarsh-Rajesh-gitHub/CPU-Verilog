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

//for multicycle cpu implementation
reg [2:0] state;
// 0 - fetch, 1 - decode, 2 - execute, 3 - writeback

wire [63:0] pc;
reg [63:0] next_pc;
wire [31:0] instruction;

wire [4:0] opcode, rd, rs, rt;
wire [11:0] L;

wire use_alu, use_fpu, is_literal, reg_write;
wire br_abs, br_rel_reg, br_rel_lit, br_nz, br_gt, call_inst, return_inst;
wire [4:0] alu_op, fpu_op;

wire [63:0] rd_data, rs_data, rt_data, r31_data;

wire [63:0] literal_ext;
wire [63:0] branch_offset;
wire [63:0] mem_addr;
wire [63:0] mem_write_data;
wire [63:0] mem_data;
wire mem_write;


//for multicycle implementation
reg [31:0] inst_latched;
reg [63:0] A_latched, B_latched, ALU_A_latched, ALU_B_latched;
reg [63:0] ResultReg_latched;
wire halt_inst;
wire mov_load_inst, mov_store_inst;


assign literal_ext = {52'b0, L};
assign branch_offset = {{52{L[11]}}, L};

wire [63:0] alu_result, fpu_result;
reg [63:0] D_latched, SP_latched;

reg [63:0] mem_addr_reg;
reg [63:0] mem_write_data_reg;

assign mem_addr = mem_addr_reg;
assign mem_write_data = mem_write_data_reg;

always @(*) begin
    mem_addr_reg = 64'd0;
    mem_write_data_reg = 64'd0;

    if(return_inst || call_inst) begin
        mem_addr_reg = SP_latched - 64'd8;
    end
    else if(mov_load_inst) begin
        mem_addr_reg = A_latched + literal_ext;
    end
    else if(mov_store_inst) begin
        mem_addr_reg = D_latched + literal_ext;
    end

    if(call_inst) begin
        mem_write_data_reg = pc + 64'd4;
    end
    else if(mov_store_inst) begin
        mem_write_data_reg = A_latched;
    end
end

assign mem_write = !hlt && (state == 2) && (call_inst || mov_store_inst);


always @(*) begin
    next_pc = pc;
    if(hlt) begin
        next_pc = pc;
    end
    else if(state == 3) begin
        next_pc = pc + 64'd4;
    end
    else if(state == 2) begin
        if(halt_inst)
            next_pc = pc;
        else if(return_inst)
            next_pc = mem_data;
        else if(call_inst)
            next_pc = D_latched;
        else if(br_abs)
            next_pc = D_latched;
        else if(br_rel_reg)
            next_pc = pc + D_latched;
        else if(br_rel_lit)
            next_pc = pc + branch_offset;
        else if(br_nz) begin
            if(A_latched != 64'd0)
                next_pc = D_latched;
            else
                next_pc = pc + 64'd4;
        end
        else if(br_gt) begin
            if ($signed(A_latched) > $signed(B_latched))
                next_pc = D_latched;
            else
                next_pc = pc + 64'd4;
        end
        else if(mov_store_inst)
            next_pc = pc + 64'd4;   
        else if(mov_load_inst)
            next_pc = pc;           
        else if(!use_alu && !use_fpu) begin
            next_pc = pc + 64'd4;
        end
    end
end


instruction_fetch fetch(.clk(clk), .reset(reset), .next_pc(next_pc), .pc(pc));
memory memory(.clk(clk), .reset(reset), .pc(pc), .instruction(instruction), .data_addr(mem_addr), .write_data(mem_write_data), .mem_write(mem_write), .data_read(mem_data));

assign mov_load_inst  = (opcode == 5'h10);
assign mov_store_inst = (opcode == 5'h13);   

instruction_decoder decoder(.instruction(inst_latched), .opcode(opcode), .rd(rd), .rs(rs), .rt(rt), .L(L), .use_alu(use_alu), .use_fpu(use_fpu), .is_literal(is_literal), .br_abs(br_abs), .br_rel_reg(br_rel_reg), .br_rel_lit(br_rel_lit), .br_nz(br_nz), .br_gt(br_gt), .call_inst(call_inst), .return_inst(return_inst), .alu_op(alu_op), .fpu_op(fpu_op), .reg_write(reg_write));
wire reg_write_final;
assign reg_write_final = !hlt && (state == 3) && reg_write;
assign halt_inst = (opcode == 5'h0f) && (L == 12'h000);
register_file reg_file(.clk(clk), .reset(reset), .rd(rd), .rs(rs), .rt(rt), .write_data(ResultReg_latched), .reg_write(reg_write_final), .rd_data(rd_data), .rs_data(rs_data), .rt_data(rt_data), .r31_data(r31_data));
alu alu(.alu_op(alu_op), .a(ALU_A_latched), .b(ALU_B_latched), .result(alu_result));
fpu fpu(.fpu_op(fpu_op), .a(A_latched), .b(B_latched), .result(fpu_result));


always @(posedge clk or posedge reset) begin
        if (reset) begin
            hlt <= 1'b0;
            state <= 0;
            inst_latched <= 32'd0;
            A_latched  <= 64'd0;
            B_latched  <= 64'd0;
            ALU_A_latched <= 64'd0;
            ALU_B_latched <= 64'd0;
            ResultReg_latched <= 64'd0;
            D_latched <= 64'd0;
            SP_latched <= 64'd0;
        end
        else if(hlt) begin
            //do nothing
        end
        else begin
            if (state == 0) begin
                inst_latched <= instruction;
                state <= 1;
            end
            else if (state == 1) begin
                A_latched  <= rs_data;
                B_latched  <= rt_data;
                ALU_A_latched <= is_literal ? rd_data : rs_data;
                ALU_B_latched <= is_literal ? literal_ext : rt_data;
                D_latched  <= rd_data;
                SP_latched <= r31_data;
                state <= 2;
            end
            else if (state == 2) begin
                if (halt_inst) begin
                    hlt <= 1'b1;
                    state <= 2;
                end
                else if (mov_load_inst) begin
                    ResultReg_latched <= mem_data;
                    state <= 3;                
                end
                else if (mov_store_inst) begin
                    state <= 0;                 
                end
                else if (use_alu) begin
                    ResultReg_latched <= alu_result;
                    state <= 3;
                end
                else if (use_fpu) begin
                    ResultReg_latched <= fpu_result;
                    state <= 3;
                end
                else begin
                    state <= 0;
                end
            end
            else if (state == 3) begin
                state <= 0;
            end
            else begin
                state <= 0;
            end
        end
    end

endmodule