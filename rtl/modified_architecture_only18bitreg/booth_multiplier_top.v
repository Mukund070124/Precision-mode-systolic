`timescale 1ns / 1ps
// Modified multiplier: ONLY stage-1 18-bit Booth registers remain.
// Registered mode/valid correspond to these 18-bit registers.
// Each of eight aligned 36-bit PP outputs is PURE combinational wiring.
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
    output wire [1:0]  mode_s1,
    output wire        valid_s1
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

    // Separate enable staging, matched to R_reg capture edge.
    reg [1:0] mode_stage1;
    reg       valid_stage1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mode_stage1 <= 2'b11;
            valid_stage1 <= 1'b0;
        end else if (mode_reset) begin
            mode_stage1 <= 2'b11;
            valid_stage1 <= 1'b0;
        end else begin
            mode_stage1 <= mode;
            valid_stage1 <= enable;
        end
    end
    assign mode_s1 = mode_stage1;
    assign valid_s1 = valid_stage1;

    // The actual row enables are captured in transparent-low clock-gate latches.
    // Lane masks follow the REGISTERED transaction mode and its valid bit.
    wire en4_s1, en8_s1, en16_s1;
    assign en4_s1  = valid_stage1 && (mode_stage1 != 2'b11);
    assign en8_s1  = valid_stage1 && ((mode_stage1 == 2'b01) || (mode_stage1 == 2'b10));
    assign en16_s1 = valid_stage1 && (mode_stage1 == 2'b10);

    // Mode 11 clears even the clock-gated stage-1 registers immediately.
    // Change modes through mode=11; load_yold before supplying new data.
    wire row_rst_n = rst_n && !mode_reset;

    wire [17:0] R_reg_array [0:7];
    wire [35:0] PP_wire_array [0:7];
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
                .clk(clk), .rst_n(row_rst_n),
                .a(active_a), .booth_group(booth_group), .row_enable(row_enable),
                .z(), .neg_out(), .shift2(), .correction(),
                .R_corrected(), .R_reg(R_reg_array[i])
            );
            booth_pp_expand36 #(.ROW_INDEX(i)) expand36 (
                .R_reg(R_reg_array[i]),
                .en4_reg(en4_s1), .en8_reg(en8_s1), .en16_reg(en16_s1),
                .aligned_R(), .expanded_R(PP_wire_array[i])
            );
        end
    endgenerate

    assign pp0 = PP_wire_array[0];
    assign pp1 = PP_wire_array[1];
    assign pp2 = PP_wire_array[2];
    assign pp3 = PP_wire_array[3];
    assign pp4 = PP_wire_array[4];
    assign pp5 = PP_wire_array[5];
    assign pp6 = PP_wire_array[6];
    assign pp7 = PP_wire_array[7];
endmodule
