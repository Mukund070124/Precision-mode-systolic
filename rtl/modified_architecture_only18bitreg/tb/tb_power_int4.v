`timescale 1ps/1ps
// Compile tb_power_common.v and this wrapper with all seven PE RTL sources.
module tb_power_int4;
    tb_power_common #(.MODE(2'b00), .PRECISION(4)) u_test();
endmodule
