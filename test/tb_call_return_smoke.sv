`timescale 1ns/1ps
`include "tinker.sv"

module tb_call_return_smoke;
    reg clk;
    reg reset;
    wire hlt;
    integer cyc;
    reg [63:0] sp_addr;
    reg [63:0] ret_word;

    tinker_core dut(.clk(clk), .reset(reset), .hlt(hlt));

    always #10 clk = ~clk;

    task load_instr;
        input [63:0] addr;
        input [31:0] instr;
        begin
            dut.memory.bytes[addr] = instr[7:0];
            dut.memory.bytes[addr + 1] = instr[15:8];
            dut.memory.bytes[addr + 2] = instr[23:16];
            dut.memory.bytes[addr + 3] = instr[31:24];
        end
    endtask

    initial begin
        clk = 0;
        reset = 1;
        #1;
        reset = 0;

        dut.reg_file.registers[2] = 64'h2010;

        load_instr(64'h2000, {5'h0C, 5'd2, 5'd0, 5'd0, 12'd0});
        load_instr(64'h2004, {5'h0F, 5'd0, 5'd0, 5'd0, 12'd0});
        load_instr(64'h2010, {5'h0D, 5'd0, 5'd0, 5'd0, 12'd0});

        for (cyc = 0; cyc < 50; cyc = cyc + 1) begin
            #20;
            if (hlt) begin
                sp_addr = dut.reg_file.registers[31] - 64'd8;
                ret_word = {
                    dut.memory.bytes[sp_addr + 7],
                    dut.memory.bytes[sp_addr + 6],
                    dut.memory.bytes[sp_addr + 5],
                    dut.memory.bytes[sp_addr + 4],
                    dut.memory.bytes[sp_addr + 3],
                    dut.memory.bytes[sp_addr + 2],
                    dut.memory.bytes[sp_addr + 1],
                    dut.memory.bytes[sp_addr]
                };
                if (ret_word == 64'h2004) begin
                    $display("PASS call/return smoke ret=%h", ret_word);
                end
                else begin
                    $display("FAIL call/return smoke ret=%h", ret_word);
                end
                $finish;
            end
        end

        $display("FAIL call/return smoke timed out");
        $finish;
    end
endmodule
