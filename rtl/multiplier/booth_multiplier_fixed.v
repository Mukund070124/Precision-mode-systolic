`timescale 1ns/1ps
// Fixed-precision signed radix-4 Booth multiplier. NO MAC, NO Yold, NO
// accumulator, NO clock-gating, and NO aligned-PP registers.
//
// W=4:  two 18-bit Booth row registers -> 8-bit CPA.
// W=8:  four 18-bit Booth row registers -> 2 CSA levels -> 16-bit CPA.
// W=16: eight 18-bit Booth row registers -> 6 CSAs -> 32-bit CPA.
//
// Inputs at a rising edge are recoded into exactly W/2 18-bit registers.
// Their signed, statically shifted values immediately feed the adder tree.
// product is COMBINATIONAL FROM REGISTERED ROWS: valid_out is asserted
// after the SAME rising edge (one pipeline capture, no product flop).
// 'valid_in' does not gate the clock or row-register D input.
module booth_multiplier_fixed #(
    parameter W = 4,
    parameter OUT_W = 2*W,
    parameter ROWS = W/2
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire signed [W-1:0]     a,
    input  wire signed [W-1:0]     b,
    input  wire                    valid_in,
    output wire signed [OUT_W-1:0] product,
    output reg                     valid_out
);
    wire [17:0] row_before_ff [0:ROWS-1];
    reg  [17:0] row_reg       [0:ROWS-1];
    wire [OUT_W-1:0] aligned_pp [0:ROWS-1];

    genvar g;
    generate
        for (g=0; g<ROWS; g=g+1) begin: GEN_ROWS
            wire [2:0] group_bits;
            wire x01, x12, z, neg_out, shift2, neg_gated;
            wire [15:0] a16;
            wire [15:0] a_gated, xor16;
            wire [17:0] xor18, mux18;
            wire signed [31:0] signed_row32;

            if (g == 0) begin: FIRST_GROUP
                assign group_bits = {b[1], b[0], 1'b0};
            end else begin: OTHER_GROUPS
                assign group_bits = {b[2*g+1], b[2*g], b[2*g-1]};
            end

            // Same 0/+A/-A/+2A/-2A Booth correction as the original PE.
            // z is intrinsic Booth zero-recode, NOT external clock gating.
            assign x01 = group_bits[0] ^ group_bits[1];
            assign x12 = group_bits[1] ^ group_bits[2];
            assign z = x01 | x12;
            assign neg_out = group_bits[2] & ~(group_bits[1] & group_bits[0]);
            assign shift2 = ~x01 & x12;
            assign neg_gated = neg_out & z;
            assign a16 = {{(16-W){a[W-1]}}, a};
            assign a_gated = a16 & {16{z}};
            assign xor16 = a_gated ^ {16{neg_gated}};
            assign xor18 = {{2{xor16[15]}}, xor16};
            assign mux18 = shift2 ? {xor18[16:0],neg_gated} : xor18;
            assign row_before_ff[g] = mux18 + {{17{1'b0}},neg_out};

            // 18-bit row register (Genus may optimize redundant sign bits).
            // Explicitly NO gated clock, NO enable-conditioned FF update.
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) row_reg[g] <= 18'd0;
                else        row_reg[g] <= row_before_ff[g];
            end

            // Sign extension and <<2*g are constant wiring. No PP flops.
            assign signed_row32 = {{14{row_reg[g][17]}},row_reg[g]};
            assign aligned_pp[g] = signed_row32 <<< (2*g);
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) valid_out <= 1'b0;
        else        valid_out <= valid_in;
    end

    // 3:2 carry-save compressor; shifted carry vector is modulo 2^OUT_W.
    // Only used as pure combinational reduction inside the multiplier.
    generate
        if (W == 4) begin: REDUCE2
            assign product = aligned_pp[0] + aligned_pp[1];
        end else if (W == 8) begin: REDUCE4
            wire [OUT_W-1:0] s1,c1,s2,c2;
            assign s1 = aligned_pp[0] ^ aligned_pp[1] ^ aligned_pp[2];
            assign c1 = ((aligned_pp[0]&aligned_pp[1]) |
                         (aligned_pp[1]&aligned_pp[2]) |
                         (aligned_pp[0]&aligned_pp[2])) << 1;
            assign s2 = s1 ^ c1 ^ aligned_pp[3];
            assign c2 = ((s1&c1)|(c1&aligned_pp[3])|(s1&aligned_pp[3])) << 1;
            assign product = s2 + c2;
        end else if (W == 16) begin: REDUCE8
            wire [OUT_W-1:0] sa,ca,sb,cb,sc,cc,sd,cd,se,ce,sf,cf;
            assign sa = aligned_pp[0] ^ aligned_pp[1] ^ aligned_pp[2];
            assign ca = ((aligned_pp[0]&aligned_pp[1]) |
                         (aligned_pp[1]&aligned_pp[2]) |
                         (aligned_pp[0]&aligned_pp[2])) << 1;
            assign sb = aligned_pp[3] ^ aligned_pp[4] ^ aligned_pp[5];
            assign cb = ((aligned_pp[3]&aligned_pp[4]) |
                         (aligned_pp[4]&aligned_pp[5]) |
                         (aligned_pp[3]&aligned_pp[5])) << 1;
            assign sc = sa ^ ca ^ aligned_pp[6];
            assign cc = ((sa&ca)|(ca&aligned_pp[6])|(sa&aligned_pp[6])) << 1;
            assign sd = sb ^ cb ^ aligned_pp[7];
            assign cd = ((sb&cb)|(cb&aligned_pp[7])|(sb&aligned_pp[7])) << 1;
            assign se = sc ^ cc ^ sd;
            assign ce = ((sc&cc)|(cc&sd)|(sc&sd)) << 1;
            assign sf = se ^ ce ^ cd;
            assign cf = ((se&ce)|(ce&cd)|(se&cd)) << 1;
            assign product = sf + cf;
        end else begin: UNSUPPORTED
            assign product = {OUT_W{1'b0}};
        end
    endgenerate
endmodule
