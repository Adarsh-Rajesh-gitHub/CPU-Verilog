`timescale 1ns/1ps
`include "tinker.sv"

module tb_branch_loop_debug;
    reg clk;
    reg reset;
    wire hlt;
    integer cyc;
    integer idx;
    reg printed_after_loads;
    reg printed_first_brnz;

    tinker_core dut(.clk(clk), .reset(reset), .hlt(hlt));

    always #10 clk = ~clk;

    task load_word;
        input [63:0] addr;
        input [31:0] word;
        begin
            dut.memory.bytes[addr] = word[7:0];
            dut.memory.bytes[addr + 1] = word[15:8];
            dut.memory.bytes[addr + 2] = word[23:16];
            dut.memory.bytes[addr + 3] = word[31:24];
        end
    endtask

    initial begin
        clk = 0;
        reset = 1;
        printed_after_loads = 0;
        printed_first_brnz = 0;
        #1;
        reset = 0;

        // branch_loop benchmark from Gradescope memory image
        load_word(64'h2000, 32'h15294000);
        load_word(64'h2004, 32'hCD000000);
        load_word(64'h2008, 32'h3D00000C);
        load_word(64'h200C, 32'hCD000000);
        load_word(64'h2010, 32'h3D00000C);
        load_word(64'h2014, 32'hCD000000);
        load_word(64'h2018, 32'h3D00000C);
        load_word(64'h201C, 32'hCD000000);
        load_word(64'h2020, 32'h3D00000C);
        load_word(64'h2024, 32'hCD000213);
        load_word(64'h2028, 32'h3D000004);
        load_word(64'h202C, 32'hCD000000);
        load_word(64'h2030, 32'h15AD6000);
        load_word(64'h2034, 32'hCD800000);
        load_word(64'h2038, 32'h3D80000C);
        load_word(64'h203C, 32'hCD800000);
        load_word(64'h2040, 32'h3D80000C);
        load_word(64'h2044, 32'hCD800000);
        load_word(64'h2048, 32'h3D80000C);
        load_word(64'h204C, 32'hCD800000);
        load_word(64'h2050, 32'h3D80000C);
        load_word(64'h2054, 32'hCD800213);
        load_word(64'h2058, 32'h3D800004);
        load_word(64'h205C, 32'hCD800004);
        load_word(64'h2060, 32'h15EF7000);
        load_word(64'h2064, 32'hCDC00000);
        load_word(64'h2068, 32'h3DC0000C);
        load_word(64'h206C, 32'hCDC00000);
        load_word(64'h2070, 32'h3DC0000C);
        load_word(64'h2074, 32'hCDC00000);
        load_word(64'h2078, 32'h3DC0000C);
        load_word(64'h207C, 32'hCDC00000);
        load_word(64'h2080, 32'h3DC0000C);
        load_word(64'h2084, 32'hCDC00213);
        load_word(64'h2088, 32'h3DC00004);
        load_word(64'h208C, 32'hCDC00008);
        load_word(64'h2090, 32'h16318000);
        load_word(64'h2094, 32'hCE000000);
        load_word(64'h2098, 32'h3E00000C);
        load_word(64'h209C, 32'hCE000000);
        load_word(64'h20A0, 32'h3E00000C);
        load_word(64'h20A4, 32'hCE000000);
        load_word(64'h20A8, 32'h3E00000C);
        load_word(64'h20AC, 32'hCE000000);
        load_word(64'h20B0, 32'h3E00000C);
        load_word(64'h20B4, 32'hCE000213);
        load_word(64'h20B8, 32'h3E000004);
        load_word(64'h20BC, 32'hCE00000C);
        load_word(64'h20C0, 32'h16739000);
        load_word(64'h20C4, 32'hCE400000);
        load_word(64'h20C8, 32'h3E40000C);
        load_word(64'h20CC, 32'hCE400000);
        load_word(64'h20D0, 32'h3E40000C);
        load_word(64'h20D4, 32'hCE400000);
        load_word(64'h20D8, 32'h3E40000C);
        load_word(64'h20DC, 32'hCE400000);
        load_word(64'h20E0, 32'h3E40000C);
        load_word(64'h20E4, 32'hCE400214);
        load_word(64'h20E8, 32'h3E400004);
        load_word(64'h20EC, 32'hCE400000);
        load_word(64'h20F0, 32'h16B5A000);
        load_word(64'h20F4, 32'hCE800000);
        load_word(64'h20F8, 32'h3E80000C);
        load_word(64'h20FC, 32'hCE800000);
        load_word(64'h2100, 32'h3E80000C);
        load_word(64'h2104, 32'hCE800000);
        load_word(64'h2108, 32'h3E80000C);
        load_word(64'h210C, 32'hCE800000);
        load_word(64'h2110, 32'h3E80000C);
        load_word(64'h2114, 32'hCE800212);
        load_word(64'h2118, 32'h3E800004);
        load_word(64'h211C, 32'hCE800004);
        load_word(64'h2120, 32'h954007FF);
        load_word(64'h2124, 32'hDD400001);
        load_word(64'h2128, 32'h5D2A0000);
        load_word(64'h212C, 32'h78000000);
        load_word(64'h2130, 32'h45800000);
        load_word(64'h2134, 32'h45C00000);
        load_word(64'h2138, 32'h46000000);
        load_word(64'h213C, 32'h46400000);
        load_word(64'h2140, 32'h46800000);

        for (cyc = 0; cyc < 60000; cyc = cyc + 1) begin
            #20;

            if (!printed_after_loads &&
                (dut.reg_file.registers[20] == 64'd8496) &&
                (dut.reg_file.registers[22] == 64'd8500) &&
                (dut.reg_file.registers[23] == 64'd8504) &&
                (dut.reg_file.registers[24] == 64'd8508) &&
                (dut.reg_file.registers[25] == 64'd8512) &&
                (dut.reg_file.registers[26] == 64'd8484)) begin
                printed_after_loads = 1'b1;
                $display("AFTER_LOADS r20=%0d r22=%0d r23=%0d r24=%0d r25=%0d r26=%0d r21=%0d fetch_pc=%h",
                    dut.reg_file.registers[20], dut.reg_file.registers[22], dut.reg_file.registers[23],
                    dut.reg_file.registers[24], dut.reg_file.registers[25], dut.reg_file.registers[26],
                    dut.reg_file.registers[21], dut.fetch.pc);
            end

            if (!printed_first_brnz && dut.issue_int0_valid && dut.issue_int0_is_branch &&
                (dut.int_rs_pc[dut.issue_int0_idx] == 64'h2128) && dut.issue_int0_actual_taken) begin
                printed_first_brnz = 1'b1;
                $display("FIRST_BRNZ slot=0 r20=%0d r22=%0d r23=%0d r24=%0d r25=%0d r26=%0d r21=%0d fetch_pc=%h target=%h cond=%h pred_target=%h",
                    dut.reg_file.registers[20], dut.reg_file.registers[22], dut.reg_file.registers[23],
                    dut.reg_file.registers[24], dut.reg_file.registers[25], dut.reg_file.registers[26],
                    dut.reg_file.registers[21], dut.fetch.pc, dut.issue_int0_actual_target,
                    dut.int_rs_src0_value[dut.issue_int0_idx], dut.issue_int0_pred_target);
            end

            if (!printed_first_brnz && dut.issue_int1_valid && dut.issue_int1_is_branch &&
                (dut.int_rs_pc[dut.issue_int1_idx] == 64'h2128) && dut.issue_int1_actual_taken) begin
                printed_first_brnz = 1'b1;
                $display("FIRST_BRNZ slot=1 r20=%0d r22=%0d r23=%0d r24=%0d r25=%0d r26=%0d r21=%0d fetch_pc=%h target=%h cond=%h pred_target=%h",
                    dut.reg_file.registers[20], dut.reg_file.registers[22], dut.reg_file.registers[23],
                    dut.reg_file.registers[24], dut.reg_file.registers[25], dut.reg_file.registers[26],
                    dut.reg_file.registers[21], dut.fetch.pc, dut.issue_int1_actual_target,
                    dut.int_rs_src0_value[dut.issue_int1_idx], dut.issue_int1_pred_target);
            end

            if (hlt) begin
                $display("HALT cycle=%0d pc=%h r21=%0d", cyc, dut.fetch.pc, dut.reg_file.registers[21]);
                $finish;
            end
        end

        $display("TIMEOUT pc=%h r20=%0d r22=%0d r23=%0d r24=%0d r25=%0d r26=%0d r21=%0d",
            dut.fetch.pc, dut.reg_file.registers[20], dut.reg_file.registers[22], dut.reg_file.registers[23],
            dut.reg_file.registers[24], dut.reg_file.registers[25], dut.reg_file.registers[26],
            dut.reg_file.registers[21]);
        $display("RAT r22 tag=%0d ready=%0d value=%h rob_head=%0d rob_tail=%0d free_count=%0d",
            dut.rat[22], dut.phys_ready[dut.rat[22]], dut.phys_value[dut.rat[22]],
            dut.rob_head, dut.rob_tail, dut.free_count);
        for (idx = 0; idx < 8; idx = idx + 1) begin
            if (dut.int_rs_valid[idx]) begin
                $display("INT_RS[%0d] pc=%h rob=%0d dest=%0d s0r=%0d s0t=%0d s0v=%h s1r=%0d s1t=%0d s1v=%h",
                    idx, dut.int_rs_pc[idx], dut.int_rs_rob[idx], dut.int_rs_dest[idx],
                    dut.int_rs_src0_ready[idx], dut.int_rs_src0_tag[idx], dut.int_rs_src0_value[idx],
                    dut.int_rs_src1_ready[idx], dut.int_rs_src1_tag[idx], dut.int_rs_src1_value[idx]);
            end
        end
        for (idx = 0; idx < 16; idx = idx + 1) begin
            if (dut.rob_valid[idx]) begin
                $display("ROB[%0d] ready=%0d pc=%h op=%h has_dest=%0d arch=%0d phys=%0d old=%0d value=%h",
                    idx, dut.rob_ready[idx], dut.rob_pc[idx], dut.rob_opcode[idx], dut.rob_has_dest[idx],
                    dut.rob_dest_arch[idx], dut.rob_dest_phys[idx], dut.rob_old_phys[idx], dut.rob_value[idx]);
            end
        end
        $finish;
    end
endmodule
