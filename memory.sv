module memory(input clk, input reset, input [63:0] pc, output [31:0] instruction, input [63:0] data_addr, input [63:0] write_data, input mem_write, output [63:0] data_read);
    parameter MEM_SIZE = 512 * 1024;
    reg [7:0] bytes [0:MEM_SIZE-1];

    assign instruction = {bytes[pc], bytes[pc + 1], bytes[pc + 2], bytes[pc + 3]};
    assign data_read = {bytes[data_addr], bytes[data_addr + 1], bytes[data_addr + 2], bytes[data_addr + 3], bytes[data_addr + 4], bytes[data_addr + 5], bytes[data_addr + 6], bytes[data_addr + 7]};

    always @(posedge clk) begin
        if (mem_write) begin
            bytes[data_addr] <= write_data[63:56];
            bytes[data_addr + 1] <= write_data[55:48];
            bytes[data_addr + 2] <= write_data[47:40];
            bytes[data_addr + 3] <= write_data[39:32];
            bytes[data_addr + 4] <= write_data[31:24];
            bytes[data_addr + 5] <= write_data[23:16];
            bytes[data_addr + 6] <= write_data[15:8];
            bytes[data_addr + 7] <= write_data[7:0];
        end
    end
endmodule