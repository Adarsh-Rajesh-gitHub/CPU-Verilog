module instruction_fetch(input clk, input reset, input [63:0] next_pc, output reg [63:0] pc);
    always @(posedge clk or posedge reset) begin
        if (reset)
            pc <= 64'h2000;
        else
            pc <= next_pc;
    end
endmodule