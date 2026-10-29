`timescale 1ns/1ps
module mac_top (
    input wire clk,
    input wire rst_n,
    input wire [15:0] A_in,
    input wire [15:0] B_in,
    input wire [1:0] mode_in,
    input wire valid_in,
    input wire load_yold,
    input wire [35:0] Yold_init,
    output reg [15:0] A_out,
    output reg [15:0] B_out,
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
    wire mode_reset;
    assign mode_reset = (mode_in == 2'b11);
    wire booth_enable;
    assign booth_enable = valid_in && !mode_reset && !load_yold;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            A_out <= 16'b0;
            B_out <= 16'b0;
            valid_forward <= 1'b0;
        end else if (mode_reset) begin
            A_out <= 16'b0;
            B_out <= 16'b0;
            valid_forward <= 1'b0;
        end else begin
            A_out <= A_in;
            B_out <= B_in;
            valid_forward <= booth_enable;
        end
    end

    wire valid_s2;
    booth_multiplier_top u_booth_multiplier (
        .clk(clk), .rst_n(rst_n),
        .a(A_in), .b(B_in),
        .mode(mode_in), .enable(booth_enable),
        .pp0(PP0), .pp1(PP1), .pp2(PP2), .pp3(PP3),
        .pp4(PP4), .pp5(PP5), .pp6(PP6), .pp7(PP7),
        .mode_s2(), .valid_s2(valid_s2)
    );

    wire acc_enable;
    assign acc_enable = valid_s2 && !load_yold && !mode_reset;

    precision_configurable_booth_fused_adder #(.BLOCK_SIZE(4)) u_fused_adder (
        .clk(clk), .rst_n(rst_n),
        .acc_enable(acc_enable), .load_yold(load_yold),
        .mode(mode_in), .Yold(Yold_init),
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
