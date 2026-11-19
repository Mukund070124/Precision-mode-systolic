`timescale 1ns/1ps
// Fully integrated, synthesizable source-stream -> hardware skew -> 16x16
// column-shared Booth array, with ONE global control FSM (no per-PE FSMs).
//
// Handshake for each 16x16 tile:
//   (1) Raise start for one clock while !busy.
//   (2) FSM clears existing PE accumulators and all skew registers.
//   (3) Wait for feed_ready / run_active.
//   (4) For EXACTLY 16 consecutive rising edges, present:
//         A_rows_flat[r*16+:16] = A[r][k]
//         B_cols_flat[c*16+:16] = B[k][c]   (k = 0..15)
//       Source supplies UN-SKEWED data; NO external valid or delay network.
//   (5) FSM automatically stops injection, flushes the skew chains,
//       waits for core tile_done, and pulses done (C_flat now final).
//   (6) Hold mode_in stable until start is sampled. Mode is latched per tile.
//
// Not a memory interface: the source must supply 16 A row words and 16 B
// column words every RUN cycle. No dynamic stalls/backpressure during RUN.
// Build/output-stationary PE, accumulation and Booth recoding are unchanged.
module column_shared_skew_fsm_16x16 (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    input  wire [1:0]    mode_in,
    input  wire [255:0]  A_rows_flat,
    input  wire [255:0]  B_cols_flat,
    output wire [9215:0] C_flat,
    output wire          busy,
    output wire          done,
    output wire          run_active,
    output wire          feed_ready
);
    wire core_clear, core_done;
    wire [1:0] active_mode;
    wire [255:0] a_left_skewed, b_top_skewed;
    wire [15:0] a_left_valid, b_top_valid;
    reg [4:0] feed_cycle;
    wire stream_last = run_active && (feed_cycle == 5'd15);
    // DRAIN is busy but no longer run_active. Shift zeros into skew
    // registers during drain to deliver the delayed tail of each input.
    wire drain_shift = busy && !core_clear;

    column_control_fsm u_control (
        .clk(clk), .rst_n(rst_n), .start(start),
        .stream_last(stream_last), .core_tile_done(core_done),
        .mode_in(mode_in), .clear_tile(core_clear),
        .run_active(run_active), .busy(busy), .done(done),
        .active_mode(active_mode)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) feed_cycle <= 5'd0;
        else if (core_clear || !busy) feed_cycle <= 5'd0;
        else if (run_active) feed_cycle <= feed_cycle + 5'd1;
    end
    assign feed_ready = run_active;

    systolic_input_skew_16x16 u_skew (
        .clk(clk), .rst_n(rst_n), .clear(core_clear),
        .shift_enable(drain_shift), .inject_enable(run_active),
        .mode(active_mode), .A_rows_flat(A_rows_flat),
        .B_cols_flat(B_cols_flat),
        .A_left_flat(a_left_skewed), .B_top_flat(b_top_skewed),
        .A_left_valid(a_left_valid), .B_top_valid(b_top_valid)
    );

    systolic_array_16x16 u_array (
        .clk(clk), .rst_n(rst_n), .mode_in(active_mode),
        .clear_tile(core_clear),
        .A_left_flat(a_left_skewed), .B_top_flat(b_top_skewed),
        .A_left_valid(a_left_valid), .B_top_valid(b_top_valid),
        .C_flat(C_flat), .tile_done(core_done)
    );
endmodule
