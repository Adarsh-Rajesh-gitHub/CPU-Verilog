module register_file(
    input clk,
    input reset,
    input [4:0] rd,
    input [4:0] rs,
    input [4:0] rt,
    input [4:0] rd2,
    input [4:0] rs2,
    input [4:0] rt2,
    input [4:0] wr_rd_a,
    input [63:0] write_data,
    input reg_write,
    input [4:0] rd_b,
    input [63:0] write_data_b,
    input reg_write_b,
    output [63:0] rd_data,
    output [63:0] rs_data,
    output [63:0] rt_data,
    output [63:0] rd2_data,
    output [63:0] rs2_data,
    output [63:0] rt2_data,
    output [63:0] r31_data
);
    reg [63:0] registers [0:31];
    integer i;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 31; i = i + 1) begin
                registers[i] <= 64'b0;
            end
            registers[31] <= 512 * 1024;
        end
        else begin
            if (reg_write) begin
                registers[wr_rd_a] <= write_data;
            end
            if (reg_write_b) begin
                registers[rd_b] <= write_data_b;
            end
        end
    end

    assign rd_data = registers[rd];
    assign rs_data = registers[rs];
    assign rt_data = registers[rt];
    assign rd2_data = registers[rd2];
    assign rs2_data = registers[rs2];
    assign rt2_data = registers[rt2];
    assign r31_data = registers[31];
endmodule
