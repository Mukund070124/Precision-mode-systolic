`timescale 1ns/1ps
// Integrated controller + original streaming core interface.
// For fair PPA comparison with friend's conventional array, synthesize
// systolic_array_16x16. For autonomous-control PPA, synthesize this top.
module column_shared_tensor_unit_16x16 (
    input wire clk, rst_n, start, stream_last,
    input wire [1:0] mode_in,
    input wire [255:0] A_left_flat, B_top_flat,
    input wire [15:0] A_left_valid, B_top_valid,
    output wire [9215:0] C_flat,
    output wire busy, done, run_active
);
    wire core_clear, core_done;
    wire [1:0] active_mode;
    column_control_fsm u_ctrl (
        .clk(clk), .rst_n(rst_n), .start(start),
        .stream_last(stream_last), .core_tile_done(core_done),
        .mode_in(mode_in), .clear_tile(core_clear),
        .run_active(run_active), .busy(busy), .done(done),
        .active_mode(active_mode)
    );
    systolic_array_16x16 u_array (
        .clk(clk), .rst_n(rst_n), .mode_in(active_mode),
        .clear_tile(core_clear),
        .A_left_flat(run_active ? A_left_flat : 256'b0),
        .B_top_flat(run_active ? B_top_flat : 256'b0),
        .A_left_valid(run_active ? A_left_valid : 16'b0),
        .B_top_valid(run_active ? B_top_valid : 16'b0),
        .C_flat(C_flat), .tile_done(core_done)
    );
endmodule
