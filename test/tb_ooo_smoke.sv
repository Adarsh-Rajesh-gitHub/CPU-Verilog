`timescale 1ns/1ps
`include "tinker.sv"

module tb_ooo_smoke;
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

        dut.reg_file.registers[2] = 64'd20;
        dut.reg_file.registers[3] = 64'd7;
        dut.reg_file.registers[5] = 64'd9;
        dut.reg_file.registers[6] = 64'd4;
        load_instr(64'h2000, {5'h18, 5'd1, 5'd2, 5'd3, 12'd0});
        load_instr(64'h2004, {5'h1A, 5'd4, 5'd5, 5'd6, 12'd0});
        load_instr(64'h2008, {5'h0F, 5'd0, 5'd0, 5'd0, 12'd0});
        for (cyc = 0; cyc < 20; cyc = cyc + 1) begin
            #20;
            if (hlt) begin
                if ((dut.reg_file.registers[1] == 64'd27) &&
                    (dut.reg_file.registers[4] == 64'd5)) begin
                    $display("PASS dual-issue smoke r1=%0d r4=%0d", dut.reg_file.registers[1], dut.reg_file.registers[4]);
                end
                else begin
                    $display("FAIL dual-issue smoke r1=%0d r4=%0d", dut.reg_file.registers[1], dut.reg_file.registers[4]);
                end
                $finish;
            end
        end

        $display("FAIL smoke timed out r1=%0d r4=%0d hlt=%0d", dut.reg_file.registers[1], dut.reg_file.registers[4], hlt);
        $finish;
    end
endmodule
