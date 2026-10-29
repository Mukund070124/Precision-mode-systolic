`timescale 1ns/1ps

// Standalone signed INT4 x INT4 radix-4 Booth multiplier.
// Architecture matches the earlier booth_int8_pipelined multiplier-only bundle:
//   S1: 2 Booth rows, 0 / +/-A / +/-2A, registered as 6-bit values.
//   S2: Sign extension, constant offsets 0,2,...,2, AND gating,
//       registered as 8-bit aligned partial products.
//   S3: Carry-save reduction (if required) + final CPA, product register.
// A/B forwarding, Yold accumulator and fused MAC adder are NOT included.
// A sample accepted at edge N produces a registered product after edge N+2.
module booth_int4_pipelined (
    input  wire                clk,
    input  wire                rst_n,
    input  wire signed [3:0] a,
    input  wire signed [3:0] b,
    input  wire                enable,
    output reg  signed [7:0] product,
    output reg                 valid_out
);
    wire row_enable = enable;
    reg row_enable_s1;
    reg valid_s1;
    reg valid_s2;

    wire [5:0] booth_r_s1 [0:1];
    reg  [5:0] row_r_s1 [0:1];
    wire [7:0] sign_ext_s2 [0:1];
    wire [7:0] aligned_s2  [0:1];
    wire [7:0] gated_s2    [0:1];
    reg  [7:0] pp_r_s2    [0:1];

    genvar g;
    generate
        for (g = 0; g < 2; g = g + 1) begin : GEN_ROWS
            wire [2:0] booth_group;
            wire x01, x12;
            wire zero_out, z, neg_out, shift2, correction;
            wire [3:0] a_gated, xor_a;
            wire [5:0] xor_ext, mux_raw;

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
            assign a_gated = a & {4{z}};
            assign xor_a   = a_gated ^ {4{neg_out & z}};
            assign xor_ext = {{2{xor_a[3]}}, xor_a};
            assign mux_raw = shift2 ? {xor_ext[4:0], (neg_out & z)} : xor_ext;
            assign booth_r_s1[g] = mux_raw + {{5{1'b0}}, correction};

            // g is a compile-time genvar: << (2*g) is fixed wiring.
            assign sign_ext_s2[g] = {{2{row_r_s1[g][5]}}, row_r_s1[g]};
            assign aligned_s2[g]  = sign_ext_s2[g] << (2*g);
            assign gated_s2[g]    = aligned_s2[g] & {8{row_enable_s1}};
        end
    endgenerate

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_enable_s1 <= 1'b0;
            valid_s1      <= 1'b0;
            valid_s2      <= 1'b0;
            valid_out     <= 1'b0;
            product       <= 8'sd0;
            for (i = 0; i < 2; i = i + 1) begin
                row_r_s1[i] <= 6'd0;
                pp_r_s2[i]  <= 8'd0;
            end
        end else begin
            // Stage 1 captures the Booth recoded rows.
            row_enable_s1 <= row_enable;
            valid_s1      <= enable;
            for (i = 0; i < 2; i = i + 1)
                row_r_s1[i] <= booth_r_s1[i];

            // Stage 2 captures shifted/gated partial products.
            valid_s2 <= valid_s1;
            for (i = 0; i < 2; i = i + 1)
                pp_r_s2[i] <= gated_s2[i];

            // Stage 3 captures the completed product.
            valid_out <= valid_s2;
            product   <= product_comb;
        end
    end

    // Two signed radix-4 partial products: final 8-bit carry-propagate sum.
    // Truncation is modulo 2^8, exactly enough for signed 4x4 multiplication.
    wire [7:0] product_comb;
    assign product_comb = pp_r_s2[0] + pp_r_s2[1];

endmodule
