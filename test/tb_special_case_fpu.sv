`timescale 1ns/1ps
`include "tinker.sv"

//this test isolates special case FPU instruction cases one at a time
//verilog -g2012 -I . -o o.out test/tb_special_case_fpu.sv    
//vvp o.out
module tb_special_case_fpu;
    reg clk;
    reg reset;
    reg sign;
    reg [10:0] exponent;
    reg [52:0] mantissa;
    real value;

    tinker_core dut(.clk(clk), .reset(reset));

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

        // FADD +Zero
        reset = 1;
        #1;
        reset = 0;
        dut.reg_file.registers[2] = 64'h0000000000000000;
        dut.reg_file.registers[3] = 64'h4004000000000000;
        load_instr(64'h2000, {5'h14, 5'd1, 5'd2, 5'd3, 12'd0});
        //0.0 + 2.5 should just be 2.5
        #20;
        $display("FADD +Zero r1 = %h", dut.reg_file.registers[1]);
        $display("----------------------------------");

        // FSUB +Zero
        reset = 1;
        #1;
        reset = 0;
        dut.reg_file.registers[2] = 64'h0000000000000000;
        dut.reg_file.registers[3] = 64'h4000000000000000;
        load_instr(64'h2000, {5'h15, 5'd1, 5'd2, 5'd3, 12'd0});
        //0.0 - 2.0 should be -2.0
        #20;
        $display("FSUB +Zero r1 = %h", dut.reg_file.registers[1]);
        $display("----------------------------------");

        // FMUL +Infinity
        reset = 1;
        #1;
        reset = 0;
        dut.reg_file.registers[2] = 64'h7FF0000000000000;
        dut.reg_file.registers[3] = 64'h4000000000000000;
        load_instr(64'h2000, {5'h16, 5'd1, 5'd2, 5'd3, 12'd0});
        //+inf * 2.0 should stay +inf
        #20;
        $display("FMUL +Infinity r1 = %h", dut.reg_file.registers[1]);
        $display("----------------------------------");

        // FDIV +Infinity
        reset = 1;
        #1;
        reset = 0;
        dut.reg_file.registers[2] = 64'h7FF0000000000000;
        dut.reg_file.registers[3] = 64'h4000000000000000;
        load_instr(64'h2000, {5'h17, 5'd1, 5'd2, 5'd3, 12'd0});
        //+inf / 2.0 should stay +inf
        #20;
        $display("FDIV +Infinity r1 = %h", dut.reg_file.registers[1]);
        $display("----------------------------------");

        // FDIV +Zero
        reset = 1;
        #1;
        reset = 0;
        dut.reg_file.registers[2] = 64'h0000000000000000;
        dut.reg_file.registers[3] = 64'h4000000000000000;
        load_instr(64'h2000, {5'h17, 5'd1, 5'd2, 5'd3, 12'd0});
        //0.0 / 2.0 should stay +0
        #20;
        $display("FDIV +Zero r1 = %h", dut.reg_file.registers[1]);
        $display("----------------------------------");

        // FDIV divide by zero
        reset = 1;
        #1;
        reset = 0;
        dut.reg_file.registers[2] = 64'h4008000000000000;
        dut.reg_file.registers[3] = 64'h0000000000000000;
        load_instr(64'h2000, {5'h17, 5'd1, 5'd2, 5'd3, 12'd0});
        //3.0 / 0.0 should blow up to inf
        #20;
        $display("FDIV divide by zero r1 = %h", dut.reg_file.registers[1]);
        $display("----------------------------------");

        // FADD NaN
        reset = 1;
        #1;
        reset = 0;
        dut.reg_file.registers[2] = 64'h7FF8000000000001;
        dut.reg_file.registers[3] = 64'h4004000000000000;
        load_instr(64'h2000, {5'h14, 5'd1, 5'd2, 5'd3, 12'd0});
        //nan + 2.5 should still be nan
        #20;
        $display("FADD NaN r1 = %h", dut.reg_file.registers[1]);


        $finish;
    end
endmodule