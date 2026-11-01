`timescale 1ns/1ps
module tb_int16;
 tb_fixed_multiplier #(.W(16),.TEST_COUNT(16384),.DIRECTED(1024),
 .RANDOM_COUNT(8192),.SPARSE(4096),.REPEATED(2048),.STRESS(1024)) u_test();
endmodule
