`timescale 1ns / 1ps
// Stage 1: one 18-bit registered Booth row. The ORIGINAL Booth arithmetic
// is retained; the only change is latch-based gating of the register clock.
module booth_pp_generator18_column (
    input  wire        clk,
    input  wire        rst_n,      // asynchronous clear, including mode=11
    input  wire [15:0] a,
    input  wire [2:0]  booth_digit,
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
    wire gated_clk;

    // Decoded ONCE at the B column boundary, then registered per PE row.
    // Exactly reproduces original decoder signals with row_enable gating.
    assign zero_out = booth_digit[2];
    assign z = zero_out & row_enable;
    assign neg_out = booth_digit[1];
    assign shift2 = booth_digit[0];
    assign correction = neg_out & row_enable;

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

    latch_clock_gate u_icg_18bit (
        .clk(clk),
        .gate_enable(row_enable),
        .gated_clk(gated_clk)
    );

    always @(posedge gated_clk or negedge rst_n) begin
        if (!rst_n)
            R_reg <= 18'b0;
        else
            R_reg <= R_corrected;
    end
endmodule
