`timescale 1ns/1ps
`include "tinker.sv"

//this test isolates one FPU instruction at a time
//iverilog -g2012 -I . -o tb_basic_fpu.out test/tb_basic_fpu.sv
//vvp tb_basic_fpu.out
module tb_basic_fpu;
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

    task show_fp;
        input [63:0] bits;
        begin
            sign = bits[63];
            exponent = bits[62:52];
            mantissa = (bits[62:52] == 0) ? {1'b0, bits[51:0]} : {1'b1, bits[51:0]};
            value = $bitstoreal(bits);
            $display("sign = %0d exponent = %0d mantissa = %h value = %f", sign, exponent, mantissa, value);
        end
    endtask

    initial begin
        clk = 0;

        // FADD
        reset = 1;
        #1;
        reset = 0;
        dut.reg_file.registers[2] = 64'h3FF8000000000000;
        dut.reg_file.registers[3] = 64'h4004000000000000;
        load_instr(64'h2000, {5'h14, 5'd1, 5'd2, 5'd3, 12'd0});
        //1.5 + 2.5 be 4.0
        #20;
        $display("FADD r1 = %h", dut.reg_file.registers[1]);
        show_fp(dut.reg_file.registers[1]);
        $display("----------------------------------");

        // FSUB
        reset = 1;
        #1;
        reset = 0;
        dut.reg_file.registers[2] = 64'h4008000000000000;
        dut.reg_file.registers[3] = 64'h3FF0000000000000;
        load_instr(64'h2000, {5'h15, 5'd1, 5'd2, 5'd3, 12'd0});
        //3.0 - 1.0 should be 2.0
        #20;
        $display("FSUB r1 = %h", dut.reg_file.registers[1]);
        show_fp(dut.reg_file.registers[1]);
        $display("----------------------------------");

        // FMUL
        reset = 1;
        #1;
        reset = 0;
        dut.reg_file.registers[2] = 64'h3FF8000000000000;
        dut.reg_file.registers[3] = 64'h4000000000000000;
        load_instr(64'h2000, {5'h16, 5'd1, 5'd2, 5'd3, 12'd0});
        //1.5 * 2.0 should be 3.0
        #20;
        $display("FMUL r1 = %h", dut.reg_file.registers[1]);
        show_fp(dut.reg_file.registers[1]);
        $display("----------------------------------");

        // FDIV
        reset = 1;
        #1;
        reset = 0;
        dut.reg_file.registers[2] = 64'h4018000000000000;
        dut.reg_file.registers[3] = 64'h4000000000000000;
        load_instr(64'h2000, {5'h17, 5'd1, 5'd2, 5'd3, 12'd0});
        // 3.0
        #20;
        $display("FDIV r1 = %h", dut.reg_file.registers[1]);
        show_fp(dut.reg_file.registers[1]);
        $display("----------------------------------");

        $finish;
    end
endmodule