`timescale 1ns/1ps
// Synthesizable 16x16 input skew.  Source interface: one A word per row
// and one B word per column on EACH of sixteen consecutive RUN clocks.
// A[row][k] and B[k][col] are supplied simultaneously on source clock k.
// Row r/column c are delayed by r/c cycles so the existing output-stationary
// array receives A[r][k] at edge k+r, B[k][c] at edge k+c.
//
// This is a REAL register-based skew network, NOT testbench-only skewing.
// Number of data FFs: 16*(0+...+15)*2 = 3,840, plus 240 valid FFs.
// The first row and column have zero delay; all other delays are registered.
// Requires shift_enable through RUN AND DRAIN; do NOT stop shifting when
// the 16 source cycles finish, or row 15/column 15 will lose data.
//
// The skew data-register clocks are precision-gated in 4/4/8-bit slices;
// inactive upper slices are cleared at every job start, so they remain zero.
// The input values are zero-padded in INT4 / INT8; sign extension is handled
// in the original precision-aware PE multiplier and B column encoder.
module systolic_input_skew_16x16 (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         clear,
    input  wire         shift_enable,
    input  wire         inject_enable,
    input  wire [1:0]   mode,
    input  wire [255:0] A_rows_flat,
    input  wire [255:0] B_cols_flat,
    output wire [255:0] A_left_flat,
    output wire [255:0] B_top_flat,
    output wire [15:0]  A_left_valid,
    output wire [15:0]  B_top_valid
);
    genvar lane;
    generate for (lane=0; lane<16; lane=lane+1) begin : G_SKEW_LANE
        wire [15:0] a_raw = A_rows_flat[lane*16 +: 16];
        wire [15:0] b_raw = B_cols_flat[lane*16 +: 16];
        wire [15:0] a_precision = (mode == 2'b00) ? {12'b0,a_raw[3:0]} :
                                  (mode == 2'b01) ? {8'b0,a_raw[7:0]} :
                                  (mode == 2'b10) ? a_raw : 16'b0;
        wire [15:0] b_precision = (mode == 2'b00) ? {12'b0,b_raw[3:0]} :
                                  (mode == 2'b01) ? {8'b0,b_raw[7:0]} :
                                  (mode == 2'b10) ? b_raw : 16'b0;
        wire [15:0] a_injected = inject_enable ? a_precision : 16'b0;
        wire [15:0] b_injected = inject_enable ? b_precision : 16'b0;
        if (lane == 0) begin : G_ZERO_DELAY
            assign A_left_flat[lane*16 +: 16] = a_injected;
            assign B_top_flat[lane*16 +: 16]  = b_injected;
            assign A_left_valid[lane] = inject_enable;
            assign B_top_valid[lane]  = inject_enable;
        end else begin : G_REGISTERED_DELAY
            // 16-bit data and valid are still propagated through exactly
            // 'lane' registered stages. Only their CLOCK distribution changes.
            reg [15:0] a_d [0:lane-1];
            reg [15:0] b_d [0:lane-1];
            reg        av_d [0:lane-1];
            reg        bv_d [0:lane-1];

            // One set of three ICGs per lane (A and B share each slice clock).
            // Keep all slice clocks active for synchronous CLEAR. Otherwise:
            //   INT4  : bits [3:0] and valid only
            //   INT8  : bits [7:0] and valid only
            //   INT16 : all data bits and valid
            // While IDLE or COMPLETE, shift_enable=0 and ALL skew clocks stop.
            // While DRAIN, shift_enable=1 so the pipeline must keep advancing.
            wire low_clk_en  = clear | shift_enable;
            wire mid_clk_en  = clear | (shift_enable &&
                                      ((mode == 2'b01) || (mode == 2'b10)));
            wire high_clk_en = clear | (shift_enable && (mode == 2'b10));
            wire clk_low, clk_mid, clk_high;

            latch_clock_gate u_skew_gate_low (
                .clk(clk), .gate_enable(low_clk_en), .gated_clk(clk_low)
            );
            latch_clock_gate u_skew_gate_mid (
                .clk(clk), .gate_enable(mid_clk_en), .gated_clk(clk_mid)
            );
            latch_clock_gate u_skew_gate_high (
                .clk(clk), .gate_enable(high_clk_en), .gated_clk(clk_high)
            );

            // Low nibble and valid bits always advance together in RUN/DRAIN.
            integer s_low;
            always @(posedge clk_low or negedge rst_n) begin
                if (!rst_n) begin
                    for (s_low=0; s_low<lane; s_low=s_low+1) begin
                        a_d[s_low][3:0] <= 4'b0;
                        b_d[s_low][3:0] <= 4'b0;
                        av_d[s_low] <= 1'b0;
                        bv_d[s_low] <= 1'b0;
                    end
                end else if (clear) begin
                    for (s_low=0; s_low<lane; s_low=s_low+1) begin
                        a_d[s_low][3:0] <= 4'b0;
                        b_d[s_low][3:0] <= 4'b0;
                        av_d[s_low] <= 1'b0;
                        bv_d[s_low] <= 1'b0;
                    end
                end else if (shift_enable) begin
                    a_d[0][3:0] <= a_injected[3:0];
                    b_d[0][3:0] <= b_injected[3:0];
                    av_d[0] <= inject_enable;
                    bv_d[0] <= inject_enable;
                    for (s_low=1; s_low<lane; s_low=s_low+1) begin
                        a_d[s_low][3:0] <= a_d[s_low-1][3:0];
                        b_d[s_low][3:0] <= b_d[s_low-1][3:0];
                        av_d[s_low] <= av_d[s_low-1];
                        bv_d[s_low] <= bv_d[s_low-1];
                    end
                end
            end

            // Middle nibble: clocks only for INT8/INT16, or for CLEAR.
            integer s_mid;
            always @(posedge clk_mid or negedge rst_n) begin
                if (!rst_n) begin
                    for (s_mid=0; s_mid<lane; s_mid=s_mid+1) begin
                        a_d[s_mid][7:4] <= 4'b0;
                        b_d[s_mid][7:4] <= 4'b0;
                    end
                end else if (clear) begin
                    for (s_mid=0; s_mid<lane; s_mid=s_mid+1) begin
                        a_d[s_mid][7:4] <= 4'b0;
                        b_d[s_mid][7:4] <= 4'b0;
                    end
                end else if (shift_enable) begin
                    a_d[0][7:4] <= a_injected[7:4];
                    b_d[0][7:4] <= b_injected[7:4];
                    for (s_mid=1; s_mid<lane; s_mid=s_mid+1) begin
                        a_d[s_mid][7:4] <= a_d[s_mid-1][7:4];
                        b_d[s_mid][7:4] <= b_d[s_mid-1][7:4];
                    end
                end
            end

            // Upper byte: clocks only for INT16, or for CLEAR.
            integer s_high;
            always @(posedge clk_high or negedge rst_n) begin
                if (!rst_n) begin
                    for (s_high=0; s_high<lane; s_high=s_high+1) begin
                        a_d[s_high][15:8] <= 8'b0;
                        b_d[s_high][15:8] <= 8'b0;
                    end
                end else if (clear) begin
                    for (s_high=0; s_high<lane; s_high=s_high+1) begin
                        a_d[s_high][15:8] <= 8'b0;
                        b_d[s_high][15:8] <= 8'b0;
                    end
                end else if (shift_enable) begin
                    a_d[0][15:8] <= a_injected[15:8];
                    b_d[0][15:8] <= b_injected[15:8];
                    for (s_high=1; s_high<lane; s_high=s_high+1) begin
                        a_d[s_high][15:8] <= a_d[s_high-1][15:8];
                        b_d[s_high][15:8] <= b_d[s_high-1][15:8];
                    end
                end
            end

            assign A_left_flat[lane*16 +: 16] = a_d[lane-1];
            assign B_top_flat[lane*16 +: 16]  = b_d[lane-1];
            assign A_left_valid[lane] = av_d[lane-1];
            assign B_top_valid[lane]  = bv_d[lane-1];
        end
    end endgenerate
endmodule
