`timescale 1ns/1ps
// Optional global job controller: not needed for the streaming core itself.
// STREAM_LAST is asserted on the *last accepted input cycle*, and DONE pulses
// once the bottom-right PE completes 16 valid MACs. No per-PE FSMs are added.
module column_control_fsm (
    input wire clk, rst_n, start, stream_last, core_tile_done,
    input wire [1:0] mode_in,
    output wire clear_tile, run_active, busy, done,
    output reg [1:0] active_mode
);
    localparam [2:0] IDLE=3'd0, CLEAR=3'd1, RUN=3'd2,
                     DRAIN=3'd3, COMPLETE=3'd4;
    reg [2:0] state;
    assign clear_tile = (state == CLEAR);
    assign run_active = (state == RUN);
    assign busy = (state == CLEAR || state == RUN || state == DRAIN);
    assign done = (state == COMPLETE);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            active_mode <= 2'b11;
        end else begin
            case (state)
                IDLE: if (start && mode_in != 2'b11) begin
                    active_mode <= mode_in;
                    state <= CLEAR;
                end
                CLEAR: state <= RUN;
                RUN: if (stream_last) state <= DRAIN;
                DRAIN: if (core_tile_done) state <= COMPLETE;
                COMPLETE: if (start && mode_in != 2'b11) begin
                    active_mode <= mode_in;
                    state <= CLEAR;
                end else state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
