`timescale 1ns / 1ps
// One encoder BANK per B column, combinational, not an extra pipeline stage.
// d[3*i +: 3] = {nonzero, negative, double} for Booth group i.
// The original booth_decoder is instantiated only here (16*8 instances).
module booth_column_encoder (
    input wire [15:0] b,
    input wire [1:0] mode,
    output wire [23:0] booth_digits
);
    wire [15:0] active_b =
        (mode == 2'b00) ? {{12{b[3]}},b[3:0]} :
        (mode == 2'b01) ? {{8{b[7]}},b[7:0]} :
        (mode == 2'b10) ? b : 16'b0;
    genvar g;
    generate for (g=0;g<8;g=g+1) begin : G
        wire [2:0] group_bits;
        wire nonzero, negative, double_bit;
        if (g == 0) begin : G0
            assign group_bits = {active_b[1:0],1'b0};
        end else begin : GN
            assign group_bits = {active_b[2*g+1],active_b[2*g],active_b[2*g-1]};
        end
        booth_decoder decoder (
            .booth_group(group_bits), .en(1'b1),
            .zero_out(nonzero), .z(),
            .neg_out(negative), .shift2(double_bit), .correction()
        );
        assign booth_digits[3*g +: 3] = {nonzero,negative,double_bit};
    end endgenerate
endmodule
