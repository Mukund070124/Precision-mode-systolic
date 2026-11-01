`timescale 1ns/1ps
// Glitch-free positive-edge clock gating: the enable latch is transparent
// ONLY while clk is low; ANDing its held output with clk is glitch-free
// provided the input control meets the latch's timing requirements.
// Implement as a characterized library ICG for a real physical design.
module latch_clock_gate (
    input wire clk,
    input wire gate_enable,
    output wire gated_clk
);
    reg enable_latched;
    always @(*) begin
        if (!clk)
            enable_latched = gate_enable;
    end
    assign gated_clk = clk & enable_latched;
endmodule
