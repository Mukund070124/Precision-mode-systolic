`timescale 1ns / 1ps
// =============================================================================
// SELF-CHECKING INT8 PRECISION-CONFIGURABLE MAC TESTBENCH
// =============================================================================
// Two batches of 16 signed input pairs (32 MACs total).
// Batch 1: signed boundaries, zeros, mixed signs and Booth recoding cases.
// Batch 2: additional deterministic mixed signed values, WITHOUT clearing Yold.
// Model checks PP0..PP3, active adder, accumulator, Yout, and valid pipeline.
// PP checks and adder checks are made after the pipeline registers settle (#1).
// Assumptions (matching supplied INT4 TB): 2 PP pipeline stages then accumulate,
// mode 2'b01, 20-bit accumulator; Yout zero-extends active accumulator bits.
// Run only ONE tb_mac_top_int* as the simulation top at a time.
// =============================================================================
module tb_mac_top_int8;

    localparam integer PREC = 8;
    localparam integer PROD_W = 16;
    localparam integer ACC_W = 20;
    localparam [1:0] ACTIVE_MODE = 2'b01;
    localparam [35:0] EXPECTED_FIRST = 36'h000006677; // signed 26231
    localparam [35:0] EXPECTED_FINAL = 36'hFFFFF1D6F; // signed -58001

    reg clk = 1'b0;
    always #5 clk = ~clk;       // 10-ns clock period

    reg rst_n;
    reg [15:0] A_in, B_in;
    reg [1:0] mode_in;
    reg valid_in;
    reg load_yold;
    reg [35:0] Yold_init;

    wire [15:0] A_out, B_out;
    wire valid_forward;
    wire [35:0] PP0, PP1, PP2, PP3, PP4, PP5, PP6, PP7;
    wire [11:0] y_4;
    wire [19:0] y_8;
    wire [35:0] y_16;
    wire [35:0] Yold_feedback, Yout;
    wire valid_out;

    // Same port list as your supplied INT4 tb_mac_top.
    mac_top dut (
        .clk(clk), .rst_n(rst_n),
        .A_in(A_in), .B_in(B_in),
        .mode_in(mode_in), .valid_in(valid_in),
        .load_yold(load_yold), .Yold_init(Yold_init),
        .A_out(A_out), .B_out(B_out), .valid_forward(valid_forward),
        .PP0(PP0), .PP1(PP1), .PP2(PP2), .PP3(PP3),
        .PP4(PP4), .PP5(PP5), .PP6(PP6), .PP7(PP7),
        .y_4(y_4), .y_8(y_8), .y_16(y_16),
        .Yold_feedback(Yold_feedback), .Yout(Yout),
        .valid_out(valid_out)
    );

    // -------------------------------------------------------------------------
    // FIXED TEST VECTORS: FIRST 16 + SECOND 16
    // -------------------------------------------------------------------------
    reg signed [PREC-1:0] A_values [0:31];
    reg signed [PREC-1:0] B_values [0:31];
    integer k;
    initial begin
        A_values[ 0] = -8'sd128;
        A_values[ 1] = -8'sd127;
        A_values[ 2] = -8'sd100;
        A_values[ 3] = -8'sd64;
        A_values[ 4] = -8'sd33;
        A_values[ 5] = -8'sd16;
        A_values[ 6] = -8'sd8;
        A_values[ 7] = -8'sd1;
        A_values[ 8] = 8'sd0;
        A_values[ 9] = 8'sd1;
        A_values[10] = 8'sd7;
        A_values[11] = 8'sd16;
        A_values[12] = 8'sd31;
        A_values[13] = 8'sd64;
        A_values[14] = 8'sd100;
        A_values[15] = 8'sd127;

        B_values[ 0] = -8'sd128;
        B_values[ 1] = 8'sd127;
        B_values[ 2] = -8'sd64;
        B_values[ 3] = 8'sd63;
        B_values[ 4] = -8'sd32;
        B_values[ 5] = 8'sd15;
        B_values[ 6] = -8'sd7;
        B_values[ 7] = 8'sd1;
        B_values[ 8] = 8'sd127;
        B_values[ 9] = -8'sd1;
        B_values[10] = 8'sd0;
        B_values[11] = -8'sd16;
        B_values[12] = 8'sd31;
        B_values[13] = -8'sd64;
        B_values[14] = 8'sd100;
        B_values[15] = 8'sd127;

        A_values[16] = -8'sd128;
        A_values[17] = 8'sd127;
        A_values[18] = -8'sd1;
        A_values[19] = 8'sd1;
        A_values[20] = 8'sd0;
        A_values[21] = 8'sd85;
        A_values[22] = -8'sd86;
        A_values[23] = 8'sd64;
        A_values[24] = -8'sd64;
        A_values[25] = 8'sd17;
        A_values[26] = -8'sd17;
        A_values[27] = 8'sd33;
        A_values[28] = -8'sd33;
        A_values[29] = 8'sd111;
        A_values[30] = -8'sd111;
        A_values[31] = 8'sd42;

        B_values[16] = 8'sd127;
        B_values[17] = -8'sd128;
        B_values[18] = -8'sd128;
        B_values[19] = 8'sd127;
        B_values[20] = 8'sd100;
        B_values[21] = -8'sd85;
        B_values[22] = 8'sd86;
        B_values[23] = -8'sd64;
        B_values[24] = 8'sd64;
        B_values[25] = -8'sd17;
        B_values[26] = 8'sd17;
        B_values[27] = -8'sd33;
        B_values[28] = 8'sd33;
        B_values[29] = -8'sd111;
        B_values[30] = 8'sd111;
        B_values[31] = -8'sd42;

    end

    // -------------------------------------------------------------------------
    // INDEPENDENT REFERENCE PIPELINE (not based on DUT PP or DUT y_8)
    // -------------------------------------------------------------------------
    reg signed [PROD_W-1:0] product_s1, product_s2;
    reg signed [PREC-1:0] a_s1, b_s1, a_s2, b_s2;
    reg signed [PREC-1:0] last_a, last_b;
    reg signed [PROD_W-1:0] last_product;
    reg valid_s1_expected, valid_s2_expected, valid_out_expected;
    reg [ACC_W-1:0] expected_acc;

    wire [ACC_W-1:0] expected_product;
    assign expected_product = {{4{product_s2[PROD_W-1]}}, product_s2};
    wire [ACC_W-1:0] expected_adder;
    assign expected_adder = expected_acc + expected_product;
    wire [35:0] expected_Yout;
    assign expected_Yout = expected_acc;  // ZERO-extension, matches supplied INT4 TB

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            product_s1 <= 0; product_s2 <= 0;
            a_s1 <= 0; b_s1 <= 0; a_s2 <= 0; b_s2 <= 0;
            last_a <= 0; last_b <= 0; last_product <= 0;
            valid_s1_expected <= 0;
            valid_s2_expected <= 0;
            valid_out_expected <= 0;
            expected_acc <= 0;
        end else if (mode_in == 2'b11) begin
            product_s1 <= 0; product_s2 <= 0;
            valid_s1_expected <= 0;
            valid_s2_expected <= 0;
            valid_out_expected <= 0;
            expected_acc <= 0;
        end else begin
            // Stage 1: multiplication
            product_s1 <= $signed(A_in[PREC-1:0]) * $signed(B_in[PREC-1:0]);
            a_s1 <= A_in[PREC-1:0];
            b_s1 <= B_in[PREC-1:0];
            valid_s1_expected <= valid_in && !load_yold;

            // Stage 2: Booth PP register equivalent
            product_s2 <= product_s1;
            a_s2 <= a_s1;
            b_s2 <= b_s1;
            valid_s2_expected <= valid_s1_expected;

            // Stage 3: registered MAC accumulation
            valid_out_expected <= valid_s2_expected && !load_yold;
            if (load_yold) begin
                expected_acc <= Yold_init[ACC_W-1:0];
            end else if (valid_s2_expected) begin
                expected_acc <= expected_acc + expected_product;
                last_a <= a_s2;
                last_b <= b_s2;
                last_product <= product_s2;
            end
        end
    end

    // -------------------------------------------------------------------------
    // PARTIAL PRODUCT SUM, ADDER OUTPUT, ACCUMULATOR & PIPELINE CHECKS
    // -------------------------------------------------------------------------
    wire [ACC_W-1:0] PP_SUM;
    assign PP_SUM =
        PP0[19:0] +
        PP1[19:0] +
        PP2[19:0] +
        PP3[19:0];

    wire [ACC_W-1:0] active_adder;
    assign active_adder = y_8;

    integer checked_count = 0;
    integer errors = 0;

    always @(posedge clk) begin
        #1; // after DUT and reference nonblocking assignments
        if (rst_n && mode_in == ACTIVE_MODE) begin
            // Check accumulator storage / Yold write-back every cycle.
            if (Yold_feedback[ACC_W-1:0] !== expected_acc) begin
                errors = errors + 1;
                $display("FAIL: INT8 ACCUMULATOR at %0t: expected=%0d actual=%0d",
                         $time, $signed(expected_acc), $signed(Yold_feedback[ACC_W-1:0]));
                $fatal(1, "INT8 accumulator mismatch");
            end
            if (Yout !== expected_Yout) begin
                errors = errors + 1;
                $display("FAIL: INT8 Yout at %0t: expected=%h actual=%h",
                         $time, expected_Yout, Yout);
                $fatal(1, "INT8 Yout mismatch");
            end
            if (valid_out !== valid_out_expected) begin
                errors = errors + 1;
                $display("FAIL: INT8 VALID at %0t: expected=%b actual=%b",
                         $time, valid_out_expected, valid_out);
                $fatal(1, "INT8 pipeline mismatch");
            end
            // Precision masking (inactive precision result must remain zero).
            if (y_4 !== 12'd0 || y_16 !== 36'd0) begin
                errors = errors + 1;
                $fatal(1, "INT8 inactive precision output not zero");
            end

            if (valid_s2_expected) begin
                // Every active Booth row participates; INT16 uses ALL 8.
                if (PP_SUM !== expected_product) begin
                    errors = errors + 1;
                    $display("FAIL: INT8 BOOTH PP SUM at %0t: expected=%0d actual=%0d",
                             $time, $signed(expected_product), $signed(PP_SUM));
                    $display("PP0=%h PP1=%h PP2=%h PP3=%h PP4=%h PP5=%h PP6=%h PP7=%h",
                             PP0, PP1, PP2, PP3, PP4, PP5, PP6, PP7);
                    $fatal(1, "INT8 Booth multiplier mismatch");
                end
                // Independent arithmetic model checks the combinational adder.
                if (active_adder !== expected_adder) begin
                    errors = errors + 1;
                    $display("FAIL: INT8 ADDER at %0t: expected=%0d actual=%0d",
                             $time, $signed(expected_adder), $signed(active_adder));
                    $fatal(1, "INT8 adder mismatch");
                end
            end
            // INT8: PP4-PP7 are disabled; detect accidental activity.
            if (valid_s2_expected && (
                PP4 !== 36'd0 ||
                PP5 !== 36'd0 ||
                PP6 !== 36'd0 ||
                PP7 !== 36'd0
            )) begin
                $fatal(1, "INT8 inactive PP4..PP7 were not zero");
            end

            if (valid_out_expected) begin
                checked_count = checked_count + 1;
                $display("MAC %02d | A=%0d B=%0d | Product=%0d | Acc=%0d | Yout=%h",
                         checked_count, last_a, last_b, last_product,
                         $signed(expected_acc), Yout);
            end
        end
    end

    // -------------------------------------------------------------------------
    // DRIVE EXACTLY 16 INPUT PAIRS, ONE PER CLOCK CYCLE
    // -------------------------------------------------------------------------
    task send_16;
        input integer start_index;
        integer j;
        begin
            for (j = start_index; j < start_index + 16; j = j + 1) begin
                A_in = {{(16-PREC){A_values[j][PREC-1]}}, A_values[j]};
                B_in = {{(16-PREC){B_values[j][PREC-1]}}, B_values[j]};
                valid_in = 1'b1;
                $display("INPUT %02d | A=%0d B=%0d | Product=%0d",
                         j+1, A_values[j], B_values[j],
                         $signed(A_values[j]) * $signed(B_values[j]));
                @(negedge clk);
            end
            valid_in = 1'b0;
            A_in = 16'd0;
            B_in = 16'd0;
        end
    endtask

    // -------------------------------------------------------------------------
    // MAIN TEST
    // -------------------------------------------------------------------------
    initial begin
        rst_n = 1'b0;
        A_in = 16'd0; B_in = 16'd0;
        mode_in = 2'b11;
        valid_in = 1'b0;
        load_yold = 1'b0;
        Yold_init = 36'd0;

        $display("===================================================");
        $display("STARTING INT8 MAC - 16 INPUTS + 16 FEEDBACK INPUTS");
        $display("===================================================");

        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        mode_in = ACTIVE_MODE;

        // Explicitly initialize Yold at start of this precision mode.
        load_yold = 1'b1;
        Yold_init = 36'd0;
        @(negedge clk);
        load_yold = 1'b0;

        $display("---- BATCH 1: 16 signed boundary/mixed cases ----");
        send_16(0);
        repeat (5) @(negedge clk); // pipeline drain
        #2;

        if (errors != 0 || checked_count != 16 || Yout !== EXPECTED_FIRST) begin
            $display("BATCH 1 FAIL: completed=%0d expected=%h got=%h",
                     checked_count, EXPECTED_FIRST, Yout);
            $fatal(1, "INT8 first batch failed");
        end
        $display("BATCH 1 PASS | 16 MACs | accumulator=%0d", $signed(Yout[ACC_W-1:0]));

        // No reset, no load_yold: second batch MUST continue from first sum.
        $display("---- BATCH 2: 16 more signed cases, preserve Yold ----");
        send_16(16);
        repeat (5) @(negedge clk);
        #2;

        $display("Expected final accumulator: -58001");
        $display("Actual final accumulator:   %0d", $signed(Yout[ACC_W-1:0]));
        $display("MAC operations checked:     %0d", checked_count);

        if (errors == 0 && checked_count == 32 && Yout === EXPECTED_FINAL) begin
            $display("===================================================");
            $display("ALL 32 INT8 MAC TESTS PASSED");
            $display("===================================================");
        end else begin
            $fatal(1, "INT8 FAILED: count=%0d expected=%h actual=%h errors=%0d",
                   checked_count, EXPECTED_FINAL, Yout, errors);
        end
        $finish;
    end

endmodule
