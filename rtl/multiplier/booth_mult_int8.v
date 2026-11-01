`timescale 1ns/1ps
module booth_mult_int8 (
 input wire clk, input wire rst_n,
 input wire signed [7:0] a, input wire signed [7:0] b,
 input wire valid_in, output wire signed [15:0] product,
 output wire valid_out
);
 booth_multiplier_fixed #(.W(8)) u_mult (
  .clk(clk),.rst_n(rst_n),.a(a),.b(b),
  .valid_in(valid_in),.product(product),.valid_out(valid_out));
endmodule
