`timescale 1ns / 1ps
module booth_multiplier_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] a,
    input  wire [15:0] b,
    input  wire [1:0]  mode,
    input  wire        enable,
    output wire [35:0] pp0,
    output wire [35:0] pp1,
    output wire [35:0] pp2,
    output wire [35:0] pp3,
    output wire [35:0] pp4,
    output wire [35:0] pp5,
    output wire [35:0] pp6,
    output wire [35:0] pp7,
    output reg  [1:0]  mode_s2,
    output reg         valid_s2
);
    wire mode_reset;
    wire en4, en8, en16;
    assign mode_reset = (mode == 2'b11);
    assign en4  = enable && !mode_reset;
    assign en8  = enable && ((mode == 2'b01) || (mode == 2'b10));
    assign en16 = enable && (mode == 2'b10);

    wire [15:0] active_a;
    wire [15:0] active_b;
    assign active_a =
        (mode == 2'b00) ? {{12{a[3]}}, a[3:0]} :
        (mode == 2'b01) ? {{8{a[7]}}, a[7:0]} :
        (mode == 2'b10) ? a : 16'b0;
    assign active_b =
        (mode == 2'b00) ? {{12{b[3]}}, b[3:0]} :
        (mode == 2'b01) ? {{8{b[7]}}, b[7:0]} :
        (mode == 2'b10) ? b : 16'b0;

    reg en4_reg, en8_reg, en16_reg;
    reg [1:0] mode_s1;
    reg valid_s1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            en4_reg <= 1'b0;
            en8_reg <= 1'b0;
            en16_reg <= 1'b0;
            mode_s1 <= 2'b11;
            mode_s2 <= 2'b11;
            valid_s1 <= 1'b0;
            valid_s2 <= 1'b0;
        end else if (mode_reset) begin
            en4_reg <= 1'b0;
            en8_reg <= 1'b0;
            en16_reg <= 1'b0;
            mode_s1 <= 2'b11;
            mode_s2 <= 2'b11;
            valid_s1 <= 1'b0;
            valid_s2 <= 1'b0;
        end else begin
            en4_reg <= en4;
            en8_reg <= en8;
            en16_reg <= en16;
            mode_s1 <= mode;
            mode_s2 <= mode_s1;
            valid_s1 <= enable;
            valid_s2 <= valid_s1;
        end
    end

    wire [17:0] R_reg_array [0:7];
    wire [35:0] PP_reg_array [0:7];
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : GEN_BOOTH_ROWS
            wire [2:0] booth_group;
            wire row_enable;
            if (i == 0) begin : GROUP0
                assign booth_group = {active_b[1], active_b[0], 1'b0};
            end else begin : GROUP_N
                assign booth_group = {active_b[2*i+1], active_b[2*i], active_b[2*i-1]};
            end
            if (i < 2) begin : ENABLE4
                assign row_enable = en4;
            end else if (i < 4) begin : ENABLE8
                assign row_enable = en8;
            end else begin : ENABLE16
                assign row_enable = en16;
            end
            booth_pp_generator18 generator18 (
                .clk(clk), .rst_n(rst_n),
                .a(active_a), .booth_group(booth_group), .row_enable(row_enable),
                .z(), .neg_out(), .shift2(), .correction(),
                .R_corrected(), .R_reg(R_reg_array[i])
            );
            booth_pp_expand36 #(.ROW_INDEX(i)) expand36 (
                .clk(clk), .rst_n(rst_n), .mode_reset(mode_reset),
                .R_reg(R_reg_array[i]),
                .en4_reg(en4_reg), .en8_reg(en8_reg), .en16_reg(en16_reg),
                .aligned_R(), .expanded_R(), .PP_reg(PP_reg_array[i])
            );
        end
    endgenerate

    assign pp0 = PP_reg_array[0];
    assign pp1 = PP_reg_array[1];
    assign pp2 = PP_reg_array[2];
    assign pp3 = PP_reg_array[3];
    assign pp4 = PP_reg_array[4];
    assign pp5 = PP_reg_array[5];
    assign pp6 = PP_reg_array[6];
    assign pp7 = PP_reg_array[7];
endmodule
