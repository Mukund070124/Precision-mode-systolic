`timescale 1ns/1ps

// Standalone signed INT16 x INT16 radix-4 Booth multiplier.
// Architecture matches the earlier booth_int8_pipelined multiplier-only bundle:
//   S1: 8 Booth rows, 0 / +/-A / +/-2A, registered as 18-bit values.
//   S2: Sign extension, constant offsets 0,2,...,14, AND gating,
//       registered as 32-bit aligned partial products.
//   S3: Carry-save reduction (if required) + final CPA, product register.
// A/B forwarding, Yold accumulator and fused MAC adder are NOT included.
// A sample accepted at edge N produces a registered product after edge N+2.
module booth_int16_pipelined (
    input  wire                clk,
    input  wire                rst_n,
    input  wire signed [15:0] a,
    input  wire signed [15:0] b,
    input  wire                enable,
    output reg  signed [31:0] product,
    output reg                 valid_out
);
    wire row_enable = enable;
    reg row_enable_s1;
    reg valid_s1;
    reg valid_s2;

    wire [17:0] booth_r_s1 [0:7];
    reg  [17:0] row_r_s1 [0:7];
    wire [31:0] sign_ext_s2 [0:7];
    wire [31:0] aligned_s2  [0:7];
    wire [31:0] gated_s2    [0:7];
    reg  [31:0] pp_r_s2    [0:7];

    genvar g;
    generate
        for (g = 0; g < 8; g = g + 1) begin : GEN_ROWS
            wire [2:0] booth_group;
            wire x01, x12;
            wire zero_out, z, neg_out, shift2, correction;
            wire [15:0] a_gated, xor_a;
            wire [17:0] xor_ext, mux_raw;

            if (g == 0) begin : FIRST_GROUP
                assign booth_group = {b[1], b[0], 1'b0};
            end else begin : OTHER_GROUPS
                assign booth_group = {b[2*g+1], b[2*g], b[2*g-1]};
            end

            // Identical Booth decode rules to the provided INT8 standalone RTL.
            assign x01        = booth_group[0] ^ booth_group[1];
            assign x12        = booth_group[1] ^ booth_group[2];
            assign zero_out   = x01 | x12;
            assign z          = zero_out & row_enable;
            assign neg_out    = booth_group[2] & ~(booth_group[1] & booth_group[0]);
            assign shift2     = ~x01 & x12;
            assign correction = neg_out & row_enable;

            // Form the signed +/-A, +/-2A row with one correction bit.
            assign a_gated = a & {16{z}};
            assign xor_a   = a_gated ^ {16{neg_out & z}};
            assign xor_ext = {{2{xor_a[15]}}, xor_a};
            assign mux_raw = shift2 ? {xor_ext[16:0], (neg_out & z)} : xor_ext;
            assign booth_r_s1[g] = mux_raw + {{17{1'b0}}, correction};

            // g is a compile-time genvar: << (2*g) is fixed wiring.
            assign sign_ext_s2[g] = {{14{row_r_s1[g][17]}}, row_r_s1[g]};
            assign aligned_s2[g]  = sign_ext_s2[g] << (2*g);
            assign gated_s2[g]    = aligned_s2[g] & {32{row_enable_s1}};
        end
    endgenerate

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_enable_s1 <= 1'b0;
            valid_s1      <= 1'b0;
            valid_s2      <= 1'b0;
            valid_out     <= 1'b0;
            product       <= 32'sd0;
            for (i = 0; i < 8; i = i + 1) begin
                row_r_s1[i] <= 18'd0;
                pp_r_s2[i]  <= 32'd0;
            end
        end else begin
            // Stage 1 captures the Booth recoded rows.
            row_enable_s1 <= row_enable;
            valid_s1      <= enable;
            for (i = 0; i < 8; i = i + 1)
                row_r_s1[i] <= booth_r_s1[i];

            // Stage 2 captures shifted/gated partial products.
            valid_s2 <= valid_s1;
            for (i = 0; i < 8; i = i + 1)
                pp_r_s2[i] <= gated_s2[i];

            // Stage 3 captures the completed product.
            valid_out <= valid_s2;
            product   <= product_comb;
        end
    end

    // Six 3:2 carry-save compressors reduce 8 operands to 2 operands.
    // Every carry vector is already shifted LEFT by 1 bit.
    // 32-bit arithmetic is exact for signed INT16 x INT16 multiplication.
    wire [31:0] sum_a, carry_a, sum_b, carry_b;
    wire [31:0] sum_c, carry_c, sum_d, carry_d;
    wire [31:0] sum_e, carry_e, sum_f, carry_f;
    wire [31:0] product_comb;

    // First reduction layer: 8 -> 6 operands.
    assign sum_a   = pp_r_s2[0] ^ pp_r_s2[1] ^ pp_r_s2[2];
    assign carry_a = ((pp_r_s2[0] & pp_r_s2[1]) |
                      (pp_r_s2[1] & pp_r_s2[2]) |
                      (pp_r_s2[0] & pp_r_s2[2])) << 1;
    assign sum_b   = pp_r_s2[3] ^ pp_r_s2[4] ^ pp_r_s2[5];
    assign carry_b = ((pp_r_s2[3] & pp_r_s2[4]) |
                      (pp_r_s2[4] & pp_r_s2[5]) |
                      (pp_r_s2[3] & pp_r_s2[5])) << 1;

    // Second reduction layer: 6 -> 4 operands.
    assign sum_c   = sum_a ^ carry_a ^ pp_r_s2[6];
    assign carry_c = ((sum_a & carry_a) |
                      (carry_a & pp_r_s2[6]) |
                      (sum_a & pp_r_s2[6])) << 1;
    assign sum_d   = sum_b ^ carry_b ^ pp_r_s2[7];
    assign carry_d = ((sum_b & carry_b) |
                      (carry_b & pp_r_s2[7]) |
                      (sum_b & pp_r_s2[7])) << 1;

    // Third reduction layer: 4 -> 3 operands.
    assign sum_e   = sum_c ^ carry_c ^ sum_d;
    assign carry_e = ((sum_c & carry_c) |
                      (carry_c & sum_d) |
                      (sum_c & sum_d)) << 1;

    // Fourth reduction layer: 3 -> 2 operands.
    assign sum_f   = sum_e ^ carry_e ^ carry_d;
    assign carry_f = ((sum_e & carry_e) |
                      (carry_e & carry_d) |
                      (sum_e & carry_d)) << 1;

    // Final carry-propagate addition. No accumulator or Yold in this block.
    assign product_comb = sum_f + carry_f;

endmodule
