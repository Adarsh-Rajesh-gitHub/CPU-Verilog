module memory(input clk, input reset, input [63:0] pc, output [31:0] instruction);
    parameter MEM_SIZE = 512 * 1024;
    reg [7:0] bytes [0:MEM_SIZE-1];

    assign instruction = {bytes[pc], bytes[pc + 1], bytes[pc + 2], bytes[pc + 3]};
endmodule