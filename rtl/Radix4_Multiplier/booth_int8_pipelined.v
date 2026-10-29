`timescale 1ns/1ps

// Signed INT8 x INT8 radix-4 Booth multiplier (four partial-product rows).
// Pipeline:
//   S1: Booth decode, generate 0 / +/-A / +/-2A, register 4 x 10 bits.
//   S2: Sign extend to 16 bits, fixed shifts 0/2/4/6, AND gate,
//       register 4 x 16 bits.
//   S3: Two 3:2 carry-save reduction levels and final 16-bit CPA,
//       register signed 16-bit product.
// Input sampled on rising edge N -> output appears just after edge N+2.
// valid_out indicates which outputs correspond to enable=1 inputs.
module booth_int8_pipelined (
    input  wire              clk,
    input  wire              rst_n,
    input  wire signed [7:0] a,
    input  wire signed [7:0] b,
    input  wire              enable,
    output reg  signed [15:0] product,
    output reg               valid_out
);

    // For INT8-only operation, all four radix-4 rows are enabled together.
    wire en4 = enable;
    reg  en4_s1;
    reg  valid_s1;
    reg  valid_s2;

    wire [9:0]  booth_r_s1 [0:3];
    reg  [9:0]  row_r_s1   [0:3];
    wire [15:0] aligned_s2 [0:3];
    wire [15:0] gated_s2   [0:3];
    reg  [15:0] pp_r_s2    [0:3];

    genvar g;
    generate
        for (g = 0; g < 4; g = g + 1) begin : GEN_ROWS
            wire [2:0] booth_group;
            wire x01, x12;
            wire zero_out, z, neg_out, shift2, correction;
            wire [7:0] a_gated, xor8;
            wire [9:0] xor10, mux_raw10;
            wire [15:0] sign_extended;

            // Signed radix-4 groups: {b[1],b[0],0}, {b[3],b[2],b[1]}, etc.
            if (g == 0) begin : FIRST_GROUP
                assign booth_group = {b[1], b[0], 1'b0};
            end else begin : OTHER_GROUPS
                assign booth_group = {b[2*g+1], b[2*g], b[2*g-1]};
            end

            // Same Booth decoder equations as in the original RTL.
            assign x01        = booth_group[0] ^ booth_group[1];
            assign x12        = booth_group[1] ^ booth_group[2];
            assign zero_out   = x01 | x12;
            assign z          = zero_out & en4;
            assign neg_out    = booth_group[2] & ~(booth_group[1] & booth_group[0]);
            assign shift2     = ~x01 & x12;
            assign correction = neg_out & en4;

            // Compute 0, +/-A, +/-2A in ten signed bits.
            // For -2A: {sign_extend(~A), 1} + 1 = -2*A.
            assign a_gated   = a & {8{z}};
            assign xor8      = a_gated ^ {8{neg_out & z}};
            assign xor10     = {{2{xor8[7]}}, xor8};
            assign mux_raw10 = shift2 ? {xor10[8:0], (neg_out & z)} : xor10;
            assign booth_r_s1[g] = mux_raw10 + {{9{1'b0}}, correction};

            // Stage 2 fixed shift: synthesizes as wiring, not a barrel shifter.
            assign sign_extended = {{6{row_r_s1[g][9]}}, row_r_s1[g]};
            assign aligned_s2[g] = sign_extended << (2*g);
            assign gated_s2[g]   = aligned_s2[g] & {16{en4_s1}};
        end
    endgenerate

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            en4_s1   <= 1'b0;
            valid_s1 <= 1'b0;
            valid_s2 <= 1'b0;
            valid_out <= 1'b0;
            product   <= 16'sd0;
            for (i = 0; i < 4; i = i + 1) begin
                row_r_s1[i] <= 10'd0;
                pp_r_s2[i]  <= 16'd0;
            end
        end else begin
            // First pipeline boundary: Booth decoded rows.
            en4_s1   <= en4;
            valid_s1 <= enable;
            for (i = 0; i < 4; i = i + 1)
                row_r_s1[i] <= booth_r_s1[i];

            // Second pipeline boundary: aligned and AND-gated rows.
            valid_s2 <= valid_s1;
            for (i = 0; i < 4; i = i + 1)
                pp_r_s2[i] <= gated_s2[i];

            // Third pipeline boundary: completed multiplication.
            valid_out <= valid_s2;
            product   <= product_comb;
        end
    end

    // Final adder network: 4 inputs -> two CSAs -> one carry-propagate adder.
    // Carries are explicitly shifted left one bit; low bit is zero.
    wire [15:0] sum1, carry1;
    wire [15:0] sum2, carry2;
    wire [15:0] product_comb;

    assign sum1   = pp_r_s2[0] ^ pp_r_s2[1] ^ pp_r_s2[2];
    assign carry1 = ((pp_r_s2[0] & pp_r_s2[1]) |
                     (pp_r_s2[1] & pp_r_s2[2]) |
                     (pp_r_s2[0] & pp_r_s2[2])) << 1;

    assign sum2   = sum1 ^ carry1 ^ pp_r_s2[3];
    assign carry2 = ((sum1 & carry1) |
                     (carry1 & pp_r_s2[3]) |
                     (sum1 & pp_r_s2[3])) << 1;

    assign product_comb = sum2 + carry2;
endmodule
