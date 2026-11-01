`timescale 1ps/1ps
// 3.300 ns steady-state power stimulus for the SAME runtime-configurable mac_top.
// Upper input bits are ZERO-PADDED in INT4/INT8 (matching prior Genus assumptions).
// RTL internally sign-extends from the selected precision's sign bit.
// Always check functionality before trusting the trace.
module tb_power_common #(
    parameter [1:0] MODE = 2'b00,
    parameter integer PRECISION = 4
);
    // Accumulator widths follow the unchanged fused adder: 12, 20, 36 bits.
    localparam integer EFFECTIVE_ACC_WIDTH = (PRECISION == 4) ? 12 :
                                             (PRECISION == 8) ? 20 : 36;
    localparam [35:0] ACC_MASK = 36'hFFFFFFFFF >> (36-EFFECTIVE_ACC_WIDTH);
    localparam [15:0] IN_MASK = 16'hFFFF >> (16-PRECISION);
    localparam integer WARM_CYCLES = 64;
    localparam integer MEASURE_PAIRS = 4096;
    reg clk, rst_n, valid_in, load_yold;
    reg [1:0] mode_in;
    reg [15:0] A_in, B_in;
    reg [35:0] Yold_init;
    wire [35:0] Yout, Yold_feedback;
    wire valid_out;
    reg measure_active;
    integer error_count;
    integer input_count;
    integer output_count;
    integer i;
    reg [31:0] rng;
    integer aval, bval;
    integer minval, maxval;

    mac_top dut (
        .clk(clk), .rst_n(rst_n), .A_in(A_in), .B_in(B_in),
        .mode_in(mode_in), .valid_in(valid_in), .load_yold(load_yold),
        .Yold_init(Yold_init), .Yold_feedback(Yold_feedback),
        .Yout(Yout), .valid_out(valid_out)
    );

    // 3300 ps period, rising edges 1650, 4950, ... ps.
    initial clk = 1'b0;
    always #1650 clk = ~clk;

    function [31:0] rng_next;
        input [31:0] old;
        reg [31:0] x;
        begin
            x = old ^ (old << 13);
            x = x ^ (x >> 17);
            x = x ^ (x << 5);
            rng_next = x;
        end
    endfunction

    function signed [31:0] sx_input;
        input [15:0] word;
        begin
            if (PRECISION == 4)
                sx_input = {{28{word[3]}}, word[3:0]};
            else if (PRECISION == 8)
                sx_input = {{24{word[7]}}, word[7:0]};
            else
                sx_input = {{16{word[15]}}, word[15:0]};
        end
    endfunction

    // New workload totals exactly 4096 measured pairs per mode.
    // 0000..0255 = directed (INT4: all 16x16 signed operand pairs)
    // 0256..2303 = independent pseudorandom (2048 pairs)
    // 2304..3327 = zero-heavy/sparse (1024 pairs)
    // 3328..3839 = repeated values held for 8 clocks (512 pairs)
    // 3840..4095 = extreme/boundary/walking-bit stress (256 pairs)
    // This is a MIXED-workload power estimate, NOT random-only power.
    task set_pair;
        input integer n;
        integer bitpos;
        begin
            // Advance seeds even in directed / hold phases; repeatable runs.
            rng = rng_next(rng);
            aval = $signed(rng[15:0]) >>> (16-PRECISION);
            rng = rng_next(rng);
            bval = $signed(rng[15:0]) >>> (16-PRECISION);

            if (n < 256) begin
                if (PRECISION == 4) begin
                    // The first 256 measured samples exhaust every signed
                    // 4-bit A x B combination (-8..+7 for both operands).
                    aval = -8 + (n / 16);
                    bval = -8 + (n % 16);
                end else begin
                    bitpos = (n / 16) % PRECISION;
                    case (n % 16)
                        0: begin aval=0; bval=0; end
                        1: begin aval=minval; bval=minval; end
                        2: begin aval=maxval; bval=maxval; end
                        3: begin aval=minval; bval=maxval; end
                        4: begin aval=maxval; bval=minval; end
                        5: begin aval=-1; bval=1; end
                        6: begin aval=1; bval=-1; end
                        7: begin aval=0; bval=minval; end
                        8: begin aval=minval; bval=0; end
                        9: begin aval=1; bval=1; end
                       10: begin aval=-1; bval=-1; end
                       11: begin aval=16'hAAAA; bval=16'h5555; end
                       12: begin aval=(1 << bitpos); bval=1; end
                       13: begin aval=~(1 << bitpos); bval=-1; end
                       14: begin aval=maxval; bval=0; end
                       15: begin aval=0; bval=maxval; end
                    endcase
                end
            end else if (n < 2304) begin
                // Pure pseudorandom: approximately 0.5 change/clock/bit.
                // Pre-generated aval and bval are already random.
            end else if (n < 3328) begin
                // Sparse/zero-rich; 75% of A words and 75% of B words
                // individually forced to zero in each 16-pair subblock.
                if (((n-2304) % 4) != 0) aval = 0;
                if ((((n-2304) / 4) % 4) != 0) bval = 0;
            end else if (n < 3840) begin
                // Hold each random operand pair constant for 8 cycles.
                if (((n-3328) % 8) != 0) begin
                    aval = $signed(sx_input(A_in));
                    bval = $signed(sx_input(B_in));
                end
            end else begin
                // Last 256 pairs: extremes, opposite signs, walking-bit,
                // zero times nonzero, and alternating bit patterns.
                bitpos = ((n-3840) / 16) % PRECISION;
                case ((n-3840) % 16)
                    0: begin aval=minval; bval=maxval; end
                    1: begin aval=maxval; bval=minval; end
                    2: begin aval=minval; bval=minval; end
                    3: begin aval=maxval; bval=maxval; end
                    4: begin aval=0; bval=0; end
                    5: begin aval=-1; bval=-1; end
                    6: begin aval=-1; bval=maxval; end
                    7: begin aval=maxval; bval=-1; end
                    8: begin aval=(1 << bitpos); bval=1; end
                    9: begin aval=~(1 << bitpos); bval=-1; end
                   10: begin aval=16'hAAAA; bval=16'h5555; end
                   11: begin aval=16'h5555; bval=16'hAAAA; end
                   12: begin aval=0; bval=maxval; end
                   13: begin aval=minval; bval=0; end
                   14: begin aval=1; bval=1; end
                   15: begin aval=1; bval=-1; end
                endcase
            end
            // Same as existing design: inactive high PRIMARY inputs 0.
            // The DUT uses selected precision sign bits internally.
            A_in = aval & IN_MASK;
            B_in = bval & IN_MASK;
            valid_in = 1'b1;
        end
    endtask

    // Independent scoreboard for the one registered Booth PP stage and
    // accumulator register. Test is sampled after non-blocking assignments.
    reg [35:0] model_acc;
    reg signed [63:0] prior_product;
    reg prior_valid;
    reg prior_measured; // Exclude warm-up product from output_count.
    reg expect_out_valid;
    reg signed [31:0] this_a, this_b;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            model_acc = 0;
            prior_product = 0;
            prior_valid = 0;
            prior_measured = 0;
            expect_out_valid = 0;
        end else begin
            expect_out_valid = prior_valid && !load_yold && (mode_in != 2'b11);
            if (mode_in == 2'b11) begin
                model_acc = 0;
                expect_out_valid = 0;
            end else if (load_yold) begin
                model_acc = Yold_init;
                expect_out_valid = 0;
            end else if (prior_valid) begin
                model_acc = (model_acc + prior_product) & ACC_MASK;
            end
            this_a = sx_input(A_in);
            this_b = sx_input(B_in);
            prior_product = this_a * this_b;
            prior_valid = valid_in && !load_yold && (mode_in != 2'b11);
            #1;
            if (Yold_feedback[EFFECTIVE_ACC_WIDTH-1:0] !==
                model_acc[EFFECTIVE_ACC_WIDTH-1:0]) begin
                error_count = error_count + 1;
                if (error_count <= 12)
                    $display("ERROR_ACC mode=%0d time=%0t actual=%h expected=%h A=%h B=%h", 
                             PRECISION, $time, Yold_feedback, model_acc, A_in, B_in);
            end
            if (valid_out !== expect_out_valid) begin
                error_count = error_count + 1;
                if (error_count <= 12)
                    $display("ERROR_VALID mode=%0d time=%0t got=%b expected=%b",
                             PRECISION, $time, valid_out, expect_out_valid);
            end
            // Prior transaction is the one being accumulated now.
            if (expect_out_valid && prior_measured)
                output_count = output_count + 1;
            prior_measured = measure_active && valid_in && !load_yold && (mode_in != 2'b11);
        end
    end

    initial begin
        rst_n = 0; mode_in = 2'b11; valid_in = 0; load_yold = 0;
        A_in = 0; B_in = 0; Yold_init = 0;
        rng = 32'h5A17B39D;
        error_count = 0; input_count = 0; output_count = 0;
        measure_active = 0;
        minval = -(1 << (PRECISION-1));
        maxval =  (1 << (PRECISION-1)) - 1;
        repeat (3) @(negedge clk);     // 9900 ps
        rst_n = 1;
        @(negedge clk);                // 13200 ps
        mode_in = MODE; load_yold = 1; Yold_init = 0;
        @(negedge clk);                // 16500 ps
        load_yold = 0;
        for (i = 0; i < WARM_CYCLES; i = i + 1) begin
            @(negedge clk);
            set_pair(i);
        end
        @(negedge clk);                // 231000 ps: start VCD measurement
        measure_active = 1;
        set_pair(0);
        input_count = input_count + 1;
        for (i = 1; i < MEASURE_PAIRS; i = i + 1) begin
            @(negedge clk);
            set_pair(i);
            input_count = input_count + 1;
        end
        // Drain the last pipelined accumulation; counted as measured output.
        @(negedge clk);
        valid_in = 0;
        A_in = 0; B_in = 0;
        @(negedge clk);                // 13751100 ps: stop VCD measurement
        measure_active = 0;
        #2;
        if (output_count != MEASURE_PAIRS) begin
            error_count = error_count + 1;
            $display("ERROR_OUTPUT_COUNT mode=INT%0d actual=%0d expected=%0d", PRECISION, output_count, MEASURE_PAIRS);
        end
        if (input_count != MEASURE_PAIRS) begin
            error_count = error_count + 1;
            $display("ERROR_INPUT_COUNT mode=INT%0d actual=%0d expected=%0d", PRECISION, input_count, MEASURE_PAIRS);
        end
        if (error_count != 0) begin
            $display("POWER_TRACE_FAIL mode=INT%0d errors=%0d", PRECISION, error_count);
        end else begin
            $display("POWER_TRACE_OK mode=INT%0d inputs=%0d power_window_cycles=%0d checked_outputs=%0d",
                     PRECISION, input_count, MEASURE_PAIRS+1, output_count);
        end
        $display("PROFILE_COUNTS_INT%0d exhaustive_or_directed=256 random=2048 zero_heavy=1024 repeated=512 stress=256", PRECISION);
        $finish;
    end
endmodule
