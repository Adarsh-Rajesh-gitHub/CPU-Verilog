module register_file(input clk, input reset, input [4:0] rd, input [4:0] rs, input [4:0] rt, input [63:0] write_data, input reg_write, output [63:0] rs_data, output [63:0] rt_data);
    //registers
    reg [63:0] registers [0:31];
    always @(posedge clk or posedge reset) begin
        if(reset) begin
            //reset all registers
            integer i;
            for (i = 0; i < 31; i = i + 1) begin
                registers[i] <= 64'b0;
            end
            registers[31] <= 512 * 1024;
        end 
        else if(reg_write) begin
            registers[rd] <= write_data;
        end
    end
    
    assign rs_data = registers[rs];
    assign rt_data = registers[rt];

endmodule