`timescale 1ns/1ps
`include "tinker.sv"

module tb_branch_store_flush_smoke;
    reg clk;
    reg reset;
    wire hlt;
    integer cyc;
    reg [63:0] mem_word;

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

        dut.reg_file.registers[0] = 64'd64;
        dut.reg_file.registers[1] = 64'd1;
        dut.reg_file.registers[2] = 64'h2010;
        dut.reg_file.registers[3] = 64'd99;

        dut.memory.bytes[64] = 8'd7;
        dut.memory.bytes[65] = 8'd0;
        dut.memory.bytes[66] = 8'd0;
        dut.memory.bytes[67] = 8'd0;
        dut.memory.bytes[68] = 8'd0;
        dut.memory.bytes[69] = 8'd0;
        dut.memory.bytes[70] = 8'd0;
        dut.memory.bytes[71] = 8'd0;

        load_instr(64'h2000, {5'h0B, 5'd2, 5'd1, 5'd0, 12'd0});
        load_instr(64'h2004, {5'h13, 5'd0, 5'd3, 5'd0, 12'd0});
        load_instr(64'h2008, {5'h0F, 5'd0, 5'd0, 5'd0, 12'd0});
        load_instr(64'h2010, {5'h10, 5'd4, 5'd0, 5'd0, 12'd0});
        load_instr(64'h2014, {5'h0F, 5'd0, 5'd0, 5'd0, 12'd0});

        for (cyc = 0; cyc < 60; cyc = cyc + 1) begin
            #20;
            if (hlt) begin
                mem_word = {
                    dut.memory.bytes[71],
                    dut.memory.bytes[70],
                    dut.memory.bytes[69],
                    dut.memory.bytes[68],
                    dut.memory.bytes[67],
                    dut.memory.bytes[66],
                    dut.memory.bytes[65],
                    dut.memory.bytes[64]
                };
                if ((dut.reg_file.registers[4] == 64'd7) && (mem_word == 64'd7)) begin
                    $display("PASS branch-store-flush smoke r4=%0d mem=%0d", dut.reg_file.registers[4], mem_word);
                end
                else begin
                    $display("FAIL branch-store-flush smoke r4=%0d mem=%0d", dut.reg_file.registers[4], mem_word);
                end
                $finish;
            end
        end

        $display("FAIL branch-store-flush timed out");
        $finish;
    end
endmodule
