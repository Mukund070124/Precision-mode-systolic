`timescale 1ps/1ps
// Compile tb_power_common.v and this wrapper with all seven PE RTL sources.
module tb_power_int16;
    tb_power_common #(.MODE(2'b10), .PRECISION(16)) u_test();
endmodule
