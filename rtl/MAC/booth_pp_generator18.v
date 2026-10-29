`timescale 1ns / 1ps
module booth_pp_generator18 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] a,
    input  wire [2:0]  booth_group,
    input  wire        row_enable,
    output wire        z,
    output wire        neg_out,
    output wire        shift2,
    output wire        correction,
    output wire [17:0] R_corrected,
    output reg  [17:0] R_reg
);
    wire zero_out;
    wire [15:0] a_gated;
    wire neg_gated;
    wire [15:0] xor16;
    wire [17:0] xor18;
    wire [17:0] mux_raw18;

    booth_decoder decoder (
        .booth_group(booth_group),
        .en(row_enable),
        .zero_out(zero_out),
        .z(z),
        .neg_out(neg_out),
        .shift2(shift2),
        .correction(correction)
    );

    assign a_gated = a & {16{z}};
    assign neg_gated = neg_out & z;
    assign xor16 = a_gated ^ {16{neg_gated}};
    assign xor18 = {{2{xor16[15]}}, xor16};
    assign mux_raw18[0] = shift2 ? neg_gated : xor18[0];

    genvar i;
    generate
        for (i = 1; i < 18; i = i+1) begin : SHIFT_MUX
            assign mux_raw18[i] = shift2 ? xor18[i-1] : xor18[i];
        end
    endgenerate

    assign R_corrected = mux_raw18 + {{17{1'b0}}, correction};
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            R_reg <= 18'b0;
        else
            R_reg <= R_corrected;
    end
endmodule
