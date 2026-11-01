`timescale 1ns/1ps
module tb_int4;
 tb_fixed_multiplier #(.W(4),.TEST_COUNT(65536),.DIRECTED(16384),
 .RANDOM_COUNT(32768),.SPARSE(8192),.REPEATED(4096),.STRESS(4096)) u_test();
endmodule
