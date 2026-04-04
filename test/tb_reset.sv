`timescale 1ns/1ps
`include "tinker.sv"

//this test shows that reset effectively works by resetting the state of pc and the stack pointer
//iverilog -g2012 -I . -o tb_reset.out test/tb_reset.sv
module tb_reset;
    reg clk;
    reg reset;

    tinker_core dut(.clk(clk), .reset(reset));

    always #10 clk = ~clk;

    initial begin
        reset = 1;
        clk = 0;
        #1

        reset = 0;
        
        $display("pc  = %h", dut.fetch.pc);
        $display("r0  = %h", dut.reg_file.registers[0]);
        $display("r1  = %h", dut.reg_file.registers[1]);
        $display("r31 = %h", dut.reg_file.registers[31]);
        $display("----------------------------------");

        #20;
        //changing the stack ptr so I can later see if reset, reset it
        dut.reg_file.registers[31] = 500 * 1024;
        $display("pc  = %h", dut.fetch.pc);
        $display("r0  = %h", dut.reg_file.registers[0]);
        $display("r1  = %h", dut.reg_file.registers[1]);
        $display("r31 = %h", dut.reg_file.registers[31]);
        $display("----------------------------------"); 

        reset = 1;

        #20;

        $display("pc  = %h", dut.fetch.pc);
        $display("r0  = %h", dut.reg_file.registers[0]);
        $display("r1  = %h", dut.reg_file.registers[1]);
        $display("r31 = %h", dut.reg_file.registers[31]);

        $finish;
    end
endmodule