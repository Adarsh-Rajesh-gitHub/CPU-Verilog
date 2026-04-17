`timescale 1ns/1ps
`include "tinker.sv"

module tb_load_smoke;
    reg clk;
    reg reset;
    wire hlt;
    integer cyc;

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

        dut.memory.bytes[64] = 8'h88;
        dut.memory.bytes[65] = 8'h77;
        dut.memory.bytes[66] = 8'h66;
        dut.memory.bytes[67] = 8'h55;
        dut.memory.bytes[68] = 8'h44;
        dut.memory.bytes[69] = 8'h33;
        dut.memory.bytes[70] = 8'h22;
        dut.memory.bytes[71] = 8'h11;

        load_instr(64'h2000, {5'h12, 5'd0, 5'd0, 5'd0, 12'd64});
        load_instr(64'h2004, {5'h10, 5'd1, 5'd0, 5'd0, 12'd0});
        load_instr(64'h2008, {5'h0F, 5'd0, 5'd0, 5'd0, 12'd0});

        for (cyc = 0; cyc < 30; cyc = cyc + 1) begin
            #20;
            $display("cyc=%0d pc=%h hlt=%0d r0=%h r1=%h head=%0d tail=%0d", cyc, dut.fetch.pc, hlt, dut.reg_file.registers[0], dut.reg_file.registers[1], dut.rob_head, dut.rob_tail);
            if (hlt) begin
                $finish;
            end
        end

        $finish;
    end
endmodule
