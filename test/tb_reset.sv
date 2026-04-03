`timescale 1ns/1ps
`include "tinker.sv"
module tb_reset;
    reg clk;
    reg reset;

    tinker_core dut(.clk(clk), .reset(reset));

    always #10 clk = ~clk;

    initial begin
        reset = 1;
        clk = 0;
        reset = 0;
        
        $display("pc  = %h", dut.fetch.pc);
        $display("r0  = %h", dut.reg_file.registers[0]);
        $display("r1  = %h", dut.reg_file.registers[1]);
        $display("r31 = %h", dut.reg_file.registers[31]);

        #200;

        $display("pc  = %h", dut.fetch.pc);
        $display("r0  = %h", dut.reg_file.registers[0]);
        $display("r1  = %h", dut.reg_file.registers[1]);
        $display("r31 = %h", dut.reg_file.registers[31]);

        reset = 0;

        $display("pc  = %h", dut.fetch.pc);
        $display("r0  = %h", dut.reg_file.registers[0]);
        $display("r1  = %h", dut.reg_file.registers[1]);
        $display("r31 = %h", dut.reg_file.registers[31]);

        $finish;
    end
endmodule