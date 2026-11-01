`timescale 1ps/1ps
// Compile tb_power_common.v and this wrapper with all seven PE RTL sources.
module tb_power_int8;
    tb_power_common #(.MODE(2'b01), .PRECISION(8)) u_test();
endmodule
