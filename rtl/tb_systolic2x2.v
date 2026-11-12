// tb_systolic2x2.v -- self-checking testbench for systolic2x2 (SPEC.md sections 3,5)
// Reads vectors.hex (12 words/group: A00 A01 A10 A11 B00 B01 B10 B11 C00 C01 C10 C11)
// Checks every cycle: out_valid must be 1 exactly in cycle 4g'+4 (relative timing from SPEC 5.3)
// and c00..c11 must equal the golden C in that cycle. Fails with $fatal (non-zero exit).
`timescale 1ns/1ps

module tb_systolic2x2;
    parameter NG = 80;

    reg clk;
    reg rst_n;
    reg in_valid;
    reg signed [7:0] a0, a1, b0, b1;
    wire signed [31:0] c00, c01, c10, c11;
    wire out_valid;

    reg [31:0] mem [0:12*NG-1];

    integer errors;
    integer checks;
    integer ov_count;
    integer cyc;
    integer g;
    integer r;

    systolic2x2 dut (
        .clk(clk), .rst_n(rst_n), .in_valid(in_valid),
        .a0(a0), .a1(a1), .b0(b0), .b1(b1),
        .c00(c00), .c01(c01), .c10(c10), .c11(c11),
        .out_valid(out_valid)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task check_eq32;
 input [8*4-1:0] name;
        input signed [31:0] got;
        input signed [31:0] exp;
        input integer grp;
        input integer cycle;
        begin
     checks = checks + 1;
     if (got !== exp) begin
         errors = errors + 1;
  $display("ERROR group %0d cycle %0d %0s: got %0d expected %0d",
    grp, cycle, name, got, exp);
     end
        end
    endtask

    task check_bit;
        input [8*8-1:0] name;
        input got;
        input exp;
        input integer cycle;
        begin
     checks = checks + 1;
     if (got !== exp) begin
  errors = errors + 1;
         $display("ERROR cycle %0d %0s: got %b expected %b", cycle, name, got, exp);
     end
        end
    endtask

    // check outputs of cycle cc; group gg is the group whose result is due (or -1)
    task check_cycle;
        input integer cc;
        input integer gg;
        begin
     if (gg >= 0) begin
  check_bit("out_valid", out_valid, 1'b1, cc);
         check_eq32("c00", c00, mem[12*gg+8],  gg, cc);
         check_eq32("c01", c01, mem[12*gg+9],  gg, cc);
  check_eq32("c10", c10, mem[12*gg+10], gg, cc);
         check_eq32("c11", c11, mem[12*gg+11], gg, cc);
  ov_count = ov_count + 1;
     end else begin
  check_bit("out_valid", out_valid, 1'b0, cc);
     end
        end
    endtask

    // drive inputs for cycle cc (called at negedge, stable across following posedge)
    task drive_cycle;
        input integer cc;
 input integer spacing;
        input integer ngrp;
        integer gi;
        integer ph;
        begin
     gi = cc / spacing;
     ph = cc % spacing;
     if (gi < ngrp && ph < 2) begin
         in_valid = 1'b1;
         a0 = mem[12*gi + ph][7:0];   // A[0][k]  (A00 / A01)
         a1 = mem[12*gi + 2 + ph][7:0];      // A[1][k]  (A10 / A11)
  b0 = mem[12*gi + 4 + 2*ph][7:0];    // B[k][0]  (B00 / B10)
         b1 = mem[12*gi + 5 + 2*ph][7:0];    // B[k][1]  (B01 / B11)
     end else begin
  in_valid = 1'b0;
  // garbage on data pins while in_valid=0 must be ignored
         a0 = $random; a1 = $random; b0 = $random; b1 = $random;
     end
        end
    endtask

    // run ngrp groups with given start-to-start spacing (>=4), checking every cycle
    task run_phase;
        input integer spacing;
 input integer ngrp;
        integer cc;
        integer due;
        begin
     for (cc = 0; cc < ngrp * spacing + 8; cc = cc + 1) begin
         @(negedge clk);
         due = -1;
  if (cc >= 4 && ((cc - 4) % spacing) == 0 && ((cc - 4) / spacing) < ngrp)
      due = (cc - 4) / spacing;
         check_cycle(cc, due);
         drive_cycle(cc, spacing, ngrp);
            end
     @(negedge clk);
     in_valid = 1'b0;
 end
    endtask

    task check_reset_state;
        input integer tag;
        begin
     check_bit("rst_ov", out_valid, 1'b0, tag);
     check_eq32("rstc00", c00, 32'sd0, -1, tag);
     check_eq32("rstc01", c01, 32'sd0, -1, tag);
     check_eq32("rstc10", c10, 32'sd0, -1, tag);
     check_eq32("rstc11", c11, 32'sd0, -1, tag);
        end
    endtask

    initial begin
 $dumpfile("tb_systolic2x2.vcd");
        $dumpvars(0, tb_systolic2x2);
 errors = 0; checks = 0; ov_count = 0;
        $readmemh("vectors.hex", mem);
        // sanity: vector file actually loaded
        if (^mem[12*NG-1] === 1'bx || ^mem[0] === 1'bx) begin
     $display("FATAL: vectors.hex not loaded");
     $fatal(1, "vectors.hex not loaded");
        end

        rst_n = 1'b0; in_valid = 1'b0; a0 = 0; a1 = 0; b0 = 0; b1 = 0;
        repeat (3) @(negedge clk);
        check_reset_state(-1);

        rst_n = 1'b1;
 $display("PHASE1: %0d groups, spacing 4 (back-to-back, min II)", NG);
        run_phase(4, NG);

        $display("PHASE2: %0d groups, spacing 7 (idle gaps)", NG);
        run_phase(7, NG);

        // PHASE3: async reset in the middle of a group, then clean groups
        $display("PHASE3: async reset mid-group, then 6 groups at spacing 4");
        @(negedge clk);
 in_valid = 1'b1;
        a0 = mem[0][7:0]; a1 = mem[2][7:0]; b0 = mem[4][7:0]; b1 = mem[5][7:0];   // beat k=0 of group 0
        @(negedge clk);
        in_valid = 1'b0;
 #2 rst_n = 1'b0;    // asynchronous assertion away from the clock edge
        #1 check_reset_state(-2);  // must clear immediately, without a clock edge
        @(negedge clk);
 check_reset_state(-3);
        rst_n = 1'b1;
 run_phase(4, 6);

 // PHASE4: 100 more random-spacing... deterministic spacing 5 with 20 groups
        $display("PHASE4: 20 groups, spacing 5");
        run_phase(5, 20);

 repeat (3) @(negedge clk);
 $display("SUMMARY: checks=%0d out_valid_pulses=%0d errors=%0d", checks, ov_count, errors);
        if (ov_count != 80 + 80 + 6 + 20) begin
     errors = errors + 1;
     $display("ERROR: out_valid pulse count %0d != 186", ov_count);
        end
        if (errors != 0) begin
     $display("TEST FAILED errors=%0d", errors);
     $fatal(1, "TEST FAILED");
        end else begin
     $display("TEST PASSED errors=0");
        end
        $finish;
    end

    // watchdog
    initial begin
 #5000000;
        $display("TIMEOUT");
        $fatal(1, "timeout");
    end
endmodule
