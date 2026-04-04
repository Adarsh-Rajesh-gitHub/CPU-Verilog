`timescale 1ns/1ps
`include "tinker.sv"

//this test isolates one ALU instruction at a time
//iverilog -g2012 -I . -o tb_basic_alu.out test/tb_basic_alu.sv vvp tb_basic_alu.out
module tb_basic_alu;
    reg clk;
    reg reset;

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

        // AND
        reset = 1;
        #1;
        reset = 0;
        dut.reg_file.registers[2] = 64'hF0F0;
        dut.reg_file.registers[3] = 64'h0FF0;
        //only contain the 2nd F as that's in common
        load_instr(64'h2000, {5'h00, 5'd1, 5'd2, 5'd3, 12'd0});
        #20;
        $display("AND  r1 = %h", dut.reg_file.registers[1]);
        $display("----------------------------------");

        // OR
        reset = 1;
        #1;
        reset = 0;
        dut.reg_file.registers[2] = 64'hF0F0;
        dut.reg_file.registers[3] = 64'h0FF0;
        load_instr(64'h2000, {5'h01, 5'd1, 5'd2, 5'd3, 12'd0});
        //have 4th -2nd F
        #20;
        $display("OR   r1 = %h", dut.reg_file.registers[1]);
        $display("----------------------------------");

        // XOR
        reset = 1;
        #1;
        reset = 0;
        dut.reg_file.registers[2] = 64'hF0F0;
        dut.reg_file.registers[3] = 64'h0FF0;
        load_instr(64'h2000, {5'h02, 5'd1, 5'd2, 5'd3, 12'd0});
        //have only two fs when the other was not f and one was f
        #20;
        $display("XOR  r1 = %h", dut.reg_file.registers[1]);
        $display("----------------------------------");

        // NOT
        reset = 1;
        #1;
        reset = 0;
        dut.reg_file.registers[2] = 64'h00000000000000FF;
        load_instr(64'h2000, {5'h03, 5'd1, 5'd2, 5'd0, 12'd0});
        //f in part where not f
        #20;
        $display("NOT  r1 = %h", dut.reg_file.registers[1]);
        $display("----------------------------------");

        // ADD
        reset = 1;
        #1;
        reset = 0;
        dut.reg_file.registers[2] = 64'd20;
        dut.reg_file.registers[3] = 64'd7;
        load_instr(64'h2000, {5'h18, 5'd1, 5'd2, 5'd3, 12'd0});
        //27
        #20;
        $display("ADD  r1 = %0d", dut.reg_file.registers[1]);
        $display("----------------------------------");

        // ADDI
        reset = 1;
        #1;
        reset = 0;
        dut.reg_file.registers[1] = 64'd11;
        load_instr(64'h2000, {5'h19, 5'd1, 5'd0, 5'd0, 12'd9});
        //should be 20, 11 += 9
        #20;
        $display("ADDI r1 = %0d", dut.reg_file.registers[1]);
        $display("----------------------------------");

        // SUB
        reset = 1;
        #1;
        reset = 0;
        dut.reg_file.registers[2] = 64'd20;
        dut.reg_file.registers[3] = 64'd7;
        load_instr(64'h2000, {5'h1A, 5'd1, 5'd2, 5'd3, 12'd0});
        //should be 13
        #20;
        $display("SUB  r1 = %0d", dut.reg_file.registers[1]);
        $display("----------------------------------");

        // SUBI
        reset = 1;
        #1;
        reset = 0;
        dut.reg_file.registers[1] = 64'd20;
        load_instr(64'h2000, {5'h1B, 5'd1, 5'd0, 5'd0, 12'd4});
        //should be 20-4 = 16
        #20;
        $display("SUBI r1 = %0d", dut.reg_file.registers[1]);
        $display("----------------------------------");

        // SHFTR
        reset = 1;
        #1;
        reset = 0;
        dut.reg_file.registers[2] = 64'd128;
        dut.reg_file.registers[3] = 64'd3;
        load_instr(64'h2000, {5'h04, 5'd1, 5'd2, 5'd3, 12'd0});
        // should be 128 >> 3 so 16
        #20;
        $display("SHFTR r1 = %0d", dut.reg_file.registers[1]);
        $display("----------------------------------");

        // SHFTRI
        reset = 1;
        #1;
        reset = 0;
        dut.reg_file.registers[1] = 64'd128;
        load_instr(64'h2000, {5'h05, 5'd1, 5'd0, 5'd0, 12'd3});
        //should be 16 again
        #20;
        $display("SHFTRI r1 = %0d", dut.reg_file.registers[1]);
        $display("----------------------------------");

        // SHFTL
        reset = 1;
        #1;
        reset = 0;
        dut.reg_file.registers[2] = 64'd5;
        dut.reg_file.registers[3] = 64'd2;
        load_instr(64'h2000, {5'h06, 5'd1, 5'd2, 5'd3, 12'd0});
        //shoudl be 5 * 2^2, 5 << 2
        #20;
        $display("SHFTL r1 = %0d", dut.reg_file.registers[1]);
        $display("----------------------------------");

        // SHFTLI
        reset = 1;
        #1;
        reset = 0;
        dut.reg_file.registers[1] = 64'd5;
        load_instr(64'h2000, {5'h07, 5'd1, 5'd0, 5'd0, 12'd2});
        #20;
        //shoudl be 5 * 2^2, 5 << 2
        $display("SHFTLI r1 = %0d", dut.reg_file.registers[1]);
        $display("----------------------------------");

        // MUL
        reset = 1;
        #1;
        reset = 0;
        dut.reg_file.registers[2] = 64'd6;
        dut.reg_file.registers[3] = 64'd7;
        load_instr(64'h2000, {5'h1C, 5'd1, 5'd2, 5'd3, 12'd0});
        #20;
        //should be 42
        $display("MUL  r1 = %0d", dut.reg_file.registers[1]);
        $display("----------------------------------");

        // DIV
        reset = 1;
        #1;
        reset = 0;
        dut.reg_file.registers[2] = 64'd42;
        dut.reg_file.registers[3] = 64'd7;
        load_instr(64'h2000, {5'h1D, 5'd1, 5'd2, 5'd3, 12'd0});
        #20;
        //shoudl be 6
        $display("DIV  r1 = %0d", dut.reg_file.registers[1]);
        $display("----------------------------------");

        $finish;
    end
endmodule