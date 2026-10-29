`timescale 1ns / 1ps
module booth_decoder (
    input  wire [2:0] booth_group,
    input  wire       en,
    output wire       zero_out,
    output wire       z,
    output wire       neg_out,
    output wire       shift2,
    output wire       correction
);
    wire x01;
    wire x12;
    assign x01 = booth_group[0] ^ booth_group[1];
    assign x12 = booth_group[1] ^ booth_group[2];
    assign zero_out = x01 | x12;
    assign z = zero_out & en;
    assign neg_out = booth_group[2] & ~(booth_group[1] & booth_group[0]);
    assign shift2 = ~x01 & x12;
    assign correction = neg_out & en;
endmodule
