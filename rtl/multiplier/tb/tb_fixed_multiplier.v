`timescale 1ns/1ps
// Independent signed-multiplication scoreboard: '*' is TESTBENCH ONLY.
// 3.300ns period. Measured samples follow 128 warm-up cycles.
module tb_fixed_multiplier #(
    parameter W = 4,
    parameter TEST_COUNT = 65536,
    parameter DIRECTED = 16384,
    parameter RANDOM_COUNT = 32768,
    parameter SPARSE = 8192,
    parameter REPEATED = 4096,
    parameter STRESS = 4096
);
    localparam MINVAL = -(1 << (W-1));
    localparam MAXVAL =  (1 << (W-1)) - 1;
    localparam WARM_CYCLES = 128;
    reg clk = 1'b0;
    always #1.650 clk = ~clk;
    reg rst_n = 1'b0;
    reg signed [W-1:0] a=0, b=0;
    reg valid_in=0;
    wire signed [(2*W)-1:0] product;
    wire valid_out;
    reg measure_active = 0;
    integer input_count = 0, checked_count = 0, error_count = 0;
    integer n, aval, bval, pos, k;
    reg [31:0] rng = 32'h5A17B39D + W;
    reg signed [31:0] expected;
    reg expect_valid;

    generate
        if (W==4) begin: FIXED4
            booth_mult_int4 dut(.clk(clk),.rst_n(rst_n),.a(a),.b(b),
                                .valid_in(valid_in),.product(product),.valid_out(valid_out));
        end else if (W==8) begin: FIXED8
            booth_mult_int8 dut(.clk(clk),.rst_n(rst_n),.a(a),.b(b),
                                .valid_in(valid_in),.product(product),.valid_out(valid_out));
        end else begin: FIXED16
            booth_mult_int16 dut(.clk(clk),.rst_n(rst_n),.a(a),.b(b),
                                 .valid_in(valid_in),.product(product),.valid_out(valid_out));
        end
    endgenerate

    function [31:0] rng_next;
        input [31:0] old;
        reg [31:0] z;
        begin
            z=old^(old<<13);
            z=z^(z>>17);
            rng_next=z^(z<<5);
        end
    endfunction

    task drive_pair;
        input integer idx;
        begin
            rng = rng_next(rng);
            aval = $signed(rng[15:0]) >>> (16-W);
            rng = rng_next(rng);
            bval = $signed(rng[15:0]) >>> (16-W);
            pos = (idx/16) % W;
            if (idx < DIRECTED) begin
                if (W == 4) begin
                    // 16 x 16 = all 256 signed INT4 combinations;
                    // repeated DIRECTED/256 = 64 times.
                    aval = -8 + ((idx/16)%16);
                    bval = -8 + (idx%16);
                end else begin
                    case (idx%16)
                         0: begin aval=0; bval=0; end
                         1: begin aval=MINVAL; bval=MINVAL; end
                         2: begin aval=MAXVAL; bval=MAXVAL; end
                         3: begin aval=MINVAL; bval=MAXVAL; end
                         4: begin aval=MAXVAL; bval=MINVAL; end
                         5: begin aval=-1; bval=1; end
                         6: begin aval=1; bval=-1; end
                         7: begin aval=0; bval=MINVAL; end
                         8: begin aval=MINVAL; bval=0; end
                         9: begin aval=1; bval=1; end
                        10: begin aval=-1; bval=-1; end
                        11: begin aval='hAAAA; bval='h5555; end
                        12: begin aval=(1<<pos); bval=1; end
                        13: begin aval=~(1<<pos); bval=-1; end
                        14: begin aval=MAXVAL; bval=0; end
                        15: begin aval=0; bval=MAXVAL; end
                    endcase
                end
            end else if (idx < DIRECTED+RANDOM_COUNT) begin
                // Independent pseudo-random signed bit patterns.
            end else if (idx < DIRECTED+RANDOM_COUNT+SPARSE) begin
                k=idx-(DIRECTED+RANDOM_COUNT);
                if ((k%4)!=0) aval=0;
                if (((k/4)%4)!=0) bval=0;
            end else if (idx < DIRECTED+RANDOM_COUNT+SPARSE+REPEATED) begin
                k=idx-(DIRECTED+RANDOM_COUNT+SPARSE);
                if ((k%8)!=0) begin
                    aval = $signed(a);
                    bval = $signed(b);
                end
            end else begin
                // Multiple sign, zero, walking-bit and boundary patterns.
                case (idx%16)
                     0: begin aval=MINVAL; bval=MAXVAL; end
                     1: begin aval=MAXVAL; bval=MINVAL; end
                     2: begin aval=MINVAL; bval=MINVAL; end
                     3: begin aval=MAXVAL; bval=MAXVAL; end
                     4: begin aval=0; bval=0; end
                     5: begin aval=-1; bval=-1; end
                     6: begin aval=-1; bval=MAXVAL; end
                     7: begin aval=MAXVAL; bval=-1; end
                     8: begin aval=1<<pos; bval=1; end
                     9: begin aval=~(1<<pos); bval=-1; end
                    10: begin aval='hAAAA; bval='h5555; end
                    11: begin aval='h5555; bval='hAAAA; end
                    12: begin aval=0; bval=MAXVAL; end
                    13: begin aval=MINVAL; bval=0; end
                    14: begin aval=1; bval=1; end
                    15: begin aval=1; bval=-1; end
                endcase
            end
            a=aval;
            b=bval;
            valid_in=1'b1;
        end
    endtask

    // Check the post-NBA combinational product from registered Booth rows.
    always @(posedge clk) begin
        if (!rst_n) begin
            expect_valid = 0;
        end else begin
            expected = $signed(a) * $signed(b);
            expect_valid = valid_in;
            #0.001;
            if (valid_out !== expect_valid) begin
                error_count=error_count+1;
                if (error_count<=12)
                    $display("ERROR_VALID INT%0d time=%0t got=%b expected=%b",
                             W,$time,valid_out,expect_valid);
            end
            if (expect_valid) begin
                if (product !== expected[(2*W)-1:0]) begin
                    error_count=error_count+1;
                    if (error_count<=12)
                        $display("ERROR_PRODUCT INT%0d time=%0t A=%0d B=%0d got=%0d expected=%0d",
                                 W,$time,$signed(a),$signed(b),$signed(product),expected);
                end
                if (measure_active) checked_count=checked_count+1;
            end
        end
    end

    initial begin
        if (DIRECTED+RANDOM_COUNT+SPARSE+REPEATED+STRESS!=TEST_COUNT)
            $fatal(1,"BAD_PROFILE_COUNTS_INT%0d",W);
        repeat (4) @(negedge clk); // t = 13.200ns
        rst_n=1;
        @(negedge clk);             // t = 16.500ns
        for (n=0; n<WARM_CYCLES; n=n+1) begin
            @(negedge clk);         // first warm pair t=19.800ns
            drive_pair(n+DIRECTED);
        end
        @(negedge clk);             // first measured pair t=442.200ns
        measure_active=1;
        drive_pair(0);
        input_count=input_count+1;
        for (n=1; n<TEST_COUNT; n=n+1) begin
            @(negedge clk);
            drive_pair(n);
            input_count=input_count+1;
        end
        @(negedge clk);
        valid_in=0;
        a=0; b=0;
        repeat (2) @(negedge clk);
        measure_active=0;
        #0.010;
        if (input_count != TEST_COUNT || checked_count != TEST_COUNT)
            error_count=error_count+1;
        if (error_count!=0)
            $display("MULTIPLIER_TRACE_FAIL INT%0d inputs=%0d checked=%0d errors=%0d",
                     W,input_count,checked_count,error_count);
        else
            $display("MULTIPLIER_TRACE_OK INT%0d inputs=%0d checked_outputs=%0d",
                     W,input_count,checked_count);
        $display("PROFILE_INT%0d directed=%0d random=%0d sparse=%0d repeated=%0d stress=%0d",
                 W,DIRECTED,RANDOM_COUNT,SPARSE,REPEATED,STRESS);
        $finish;
    end
endmodule
