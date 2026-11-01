`timescale 1ns/1ps
module tb_int8;
 tb_fixed_multiplier #(.W(8),.TEST_COUNT(32768),.DIRECTED(2048),
 .RANDOM_COUNT(16384),.SPARSE(8192),.REPEATED(4096),.STRESS(2048)) u_test();
endmodule
