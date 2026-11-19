`timescale 1ns/1ps
// Column-shared Booth PE / MAC top: 18-bit registered Booth PP rows with latch-based ICG;
// 36-bit PP alignment is combinational, directly feeding original fused adder.
// mode_in: 00 INT4, 01 INT8, 10 INT16, 11 reset.
// Pipeline: input -> 18-bit PP registers -> accumulator register (one PP stage).
module mac_top_column (
    input wire clk,
    input wire rst_n,
    input wire [15:0] A_in,
    input wire [23:0] B_encoded_in,
    input wire [1:0] mode_in,
    input wire valid_in,
    input wire load_yold,
    input wire [35:0] Yold_init,
    output wire [15:0] A_out,
    output wire [23:0] B_encoded_out,
    output reg valid_forward,
    output wire [35:0] PP0,
    output wire [35:0] PP1,
    output wire [35:0] PP2,
    output wire [35:0] PP3,
    output wire [35:0] PP4,
    output wire [35:0] PP5,
    output wire [35:0] PP6,
    output wire [35:0] PP7,
    output wire [11:0] y_4,
    output wire [19:0] y_8,
    output wire [35:0] y_16,
    output wire [35:0] Yold_feedback,
    output wire [35:0] Yout,
    output reg valid_out
);
    wire mode_reset = (mode_in == 2'b11);
    wire booth_enable = valid_in && !mode_reset && !load_yold;

    // Precision-gated A/encoded-B forwarding, shared globally selected mode:
    //   00 INT4  -> [3:0] clocked;  [15:4] masked to zero.
    //   01 INT8  -> [7:0] clocked;  [15:8] masked to zero.
    //   10 INT16 -> all 16 bits clocked.
    //   11 reset -> all groups clocked for synchronous clear.
    // Two existing latch-based clock-gate controls are shared between A and encoded B per PE.
    // Important: do not gate forwarding using valid_in (A_valid & B_valid):
    // systolic A and B streams travel independently through the array.
    // Low nibble registers use the primary clock; their power is a floor.
    reg [3:0] a_lo_reg;
    reg [5:0] b_lo_reg;
    reg [3:0] a_mid_reg;
    reg [5:0] b_mid_reg;
    reg [7:0] a_high_reg;
    reg [11:0] b_high_reg;

    wire forward_en_low  = !mode_reset;
    wire forward_en_mid  = (mode_in == 2'b01) || (mode_in == 2'b10);
    wire forward_en_high = (mode_in == 2'b10);
    wire clk_forward_mid, clk_forward_high;

    // Include mode=11 in gated clock enables, so the inactive upper register
    // slices can be synchronously cleared on the reset-mode rising edge.
    latch_clock_gate u_forward_icg_mid (
        .clk(clk), .gate_enable(forward_en_mid || mode_reset),
        .gated_clk(clk_forward_mid)
    );
    latch_clock_gate u_forward_icg_high (
        .clk(clk), .gate_enable(forward_en_high || mode_reset),
        .gated_clk(clk_forward_high)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_lo_reg <= 4'b0;
            b_lo_reg <= 6'b0;
            valid_forward <= 1'b0;
        end else if (mode_reset) begin
            a_lo_reg <= 4'b0;
            b_lo_reg <= 6'b0;
            valid_forward <= 1'b0;
        end else begin
            a_lo_reg <= A_in[3:0];
            b_lo_reg <= B_encoded_in[5:0];
            valid_forward <= booth_enable;
        end
    end
    always @(posedge clk_forward_mid or negedge rst_n) begin
        if (!rst_n) begin
            a_mid_reg <= 4'b0;
            b_mid_reg <= 6'b0;
        end else if (mode_reset) begin
            a_mid_reg <= 4'b0;
            b_mid_reg <= 6'b0;
        end else begin
            a_mid_reg <= A_in[7:4];
            b_mid_reg <= B_encoded_in[11:6];
        end
    end
    always @(posedge clk_forward_high or negedge rst_n) begin
        if (!rst_n) begin
            a_high_reg <= 8'b0;
            b_high_reg <= 12'b0;
        end else if (mode_reset) begin
            a_high_reg <= 8'b0;
            b_high_reg <= 12'b0;
        end else begin
            a_high_reg <= A_in[15:8];
            b_high_reg <= B_encoded_in[23:12];
        end
    end

    // Zero-pad inactive lanes. The multiplier separately sign-extends the
    // selected narrow operand internally; forwarding sign extension is NOT
    // required for correct INT4/INT8 signed multiplication.
    assign A_out = mode_reset ? 16'b0 :
        {forward_en_high ? a_high_reg : 8'b0,
         forward_en_mid  ? a_mid_reg  : 4'b0,
         forward_en_low  ? a_lo_reg   : 4'b0};
    // Encoded-B forwarding: same 4/8/16 precision clock enables, but
    // 2/4/8 Booth digits => 6/12/24 bits rather than raw 4/8/16 bits.
    assign B_encoded_out = mode_reset ? 24'b0 :
        {forward_en_high ? b_high_reg : 12'b0,
         forward_en_mid  ? b_mid_reg  : 6'b0,
         forward_en_low  ? b_lo_reg   : 6'b0};

    wire [1:0] mode_s1;
    wire valid_s1;
    booth_multiplier_top_column u_booth_multiplier (
        .clk(clk), .rst_n(rst_n),
        .a(A_in), .b_encoded(B_encoded_in),
        .mode(mode_in), .enable(booth_enable),
        .pp0(PP0), .pp1(PP1), .pp2(PP2), .pp3(PP3),
        .pp4(PP4), .pp5(PP5), .pp6(PP6), .pp7(PP7),
        .mode_s1(mode_s1), .valid_s1(valid_s1)
    );

    // This valid is for 18-bit registered PP data, not the removed stage-2.
    wire acc_enable = valid_s1 && !load_yold && !mode_reset;

    // UNCHANGED original CSA + carry-select fused adder structure.
    // Use registered transaction mode during MAC, but mode_in for explicit
    // reset/load. Otherwise an immediately-following load after mode=11
    // can accidentally be interpreted as an accumulator reset.
    wire [1:0] adder_mode = (mode_reset || load_yold) ? mode_in : mode_s1;
    precision_configurable_booth_fused_adder #(.BLOCK_SIZE(4)) u_fused_adder (
        .clk(clk), .rst_n(rst_n),
        .acc_enable(acc_enable), .load_yold(load_yold),
        .mode(adder_mode), .Yold(Yold_init),
        .PP0(PP0), .PP1(PP1), .PP2(PP2), .PP3(PP3),
        .PP4(PP4), .PP5(PP5), .PP6(PP6), .PP7(PP7),
        .y_4(y_4), .y_8(y_8), .y_16(y_16),
        .yold_feedback(Yold_feedback)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            valid_out <= 1'b0;
        else if (mode_reset)
            valid_out <= 1'b0;
        else
            valid_out <= acc_enable;
    end

    assign Yout =
        (mode_in == 2'b00) ? {24'b0, Yold_feedback[11:0]} :
        (mode_in == 2'b01) ? {16'b0, Yold_feedback[19:0]} :
        (mode_in == 2'b10) ? Yold_feedback :
        36'b0;
endmodule
