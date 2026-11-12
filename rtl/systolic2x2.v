`timescale 1ns/1ps
// systolic2x2.v -- 2x2 output-stationary systolic MAC array (see SPEC.md)
// Verilog-2005. C = A x B, 8-bit signed in, 32-bit signed out.
// Input: 2 consecutive in_valid beats per matrix (k=0 then k=1), II>=4.
// out_valid is a 1-cycle pulse in cycle 4 after the first input beat.

module pe (
    input  wire        clk,
    input  wire        rst_n,
    input  wire signed [7:0]  a_in,
    input  wire signed [7:0]  b_in,
    input  wire        en,     // accumulate this cycle
    input  wire        first,  // restart accumulation (acc = product)
    output reg  signed [7:0]  a_out,  // a passed right, one register stage
    output reg  signed [7:0]  b_out,  // b passed down, one register stage
    output reg  signed [31:0] acc
);
    wire signed [15:0] prod = a_in * b_in;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
     a_out <= 8'sd0;
     b_out <= 8'sd0;
     acc   <= 32'sd0;
        end else begin
     a_out <= a_in;
     b_out <= b_in;
     if (en) begin
         if (first) acc <= {{16{prod[15]}}, prod};
  else       acc <= acc + {{16{prod[15]}}, prod};
            end
        end
    end
endmodule

module systolic2x2 (
    input  wire clk,
    input  wire rst_n,
    input  wire        in_valid,
    input  wire signed [7:0]  a0,
    input  wire signed [7:0]  a1,
    input  wire signed [7:0]  b0,
    input  wire signed [7:0]  b1,
    output wire signed [31:0] c00,
    output wire signed [31:0] c01,
    output wire signed [31:0] c10,
    output wire signed [31:0] c11,
    output reg  out_valid
);
    // beat phase: 0 -> next valid beat is k=0 (first), 1 -> k=1 (last)
    reg phase;
    reg f1, l1, f2, l2;
    // skew registers: row 1 of A and column 1 of B delayed by one cycle
    reg signed [7:0] a1_d, b1_d;

    wire f0 = in_valid & ~phase;
    wire l0 = in_valid &  phase;

    wire signed [7:0] a_r00, a_r10, a_r01, a_r11;  // a_out of each PE
    wire signed [7:0] b_r00, b_r10, b_r01, b_r11;  // b_out of each PE

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
     phase     <= 1'b0;
     f1 <= 1'b0; l1 <= 1'b0;
     f2 <= 1'b0; l2 <= 1'b0;
            a1_d <= 8'sd0; b1_d <= 8'sd0;
     out_valid <= 1'b0;
 end else begin
     if (in_valid) phase <= ~phase;
     f1 <= f0; l1 <= l0;
     f2 <= f1; l2 <= l1;
     a1_d <= a1;
     b1_d <= b1;
            out_valid <= l2;
        end
    end

    //        clk rst_n a_in  b_in  en        first a_out b_out acc
    pe pe00 (clk, rst_n, a0,    b0,   f0 | l0, f0,  a_r00, b_r00, c00);
    pe pe01 (clk, rst_n, a_r00, b1_d, f1 | l1, f1,  a_r01, b_r01, c01);
    pe pe10 (clk, rst_n, a1_d,  b_r00, f1 | l1, f1, a_r10, b_r10, c10);
    pe pe11 (clk, rst_n, a_r10, b_r01, f2 | l2, f2, a_r11, b_r11, c11);
endmodule
