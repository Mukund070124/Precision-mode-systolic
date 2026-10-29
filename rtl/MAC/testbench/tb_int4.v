`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 27.10.2026 23:24:33
// Design Name: 
// Module Name: tb_mac_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module tb_mac_top;

    // =====================================================
    // 1. CLOCK
    // =====================================================

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n;

    // =====================================================
    // 2. DUT INPUTS
    // =====================================================

    reg [15:0] A_in;
    reg [15:0] B_in;

    reg [1:0] mode_in;
    reg valid_in;

    reg load_yold;
    reg [35:0] Yold_init;

    // =====================================================
    // 3. DUT OUTPUTS
    // =====================================================

    wire [15:0] A_out;
    wire [15:0] B_out;
    wire valid_forward;

    wire [35:0] PP0, PP1;
    wire [35:0] PP2, PP3;
    wire [35:0] PP4, PP5;
    wire [35:0] PP6, PP7;

    wire [11:0] y_4;
    wire [19:0] y_8;
    wire [35:0] y_16;

    wire [35:0] Yold_feedback;
    wire [35:0] Yout;

    wire valid_out;

    // =====================================================
    // 4. DUT INSTANTIATION
    // =====================================================

    mac_top dut (

        .clk(clk),
        .rst_n(rst_n),

        .A_in(A_in),
        .B_in(B_in),

        .mode_in(mode_in),
        .valid_in(valid_in),

        .load_yold(load_yold),
        .Yold_init(Yold_init),

        .A_out(A_out),
        .B_out(B_out),
        .valid_forward(valid_forward),

        .PP0(PP0),
        .PP1(PP1),
        .PP2(PP2),
        .PP3(PP3),
        .PP4(PP4),
        .PP5(PP5),
        .PP6(PP6),
        .PP7(PP7),

        .y_4(y_4),
        .y_8(y_8),
        .y_16(y_16),

        .Yold_feedback(Yold_feedback),
        .Yout(Yout),

        .valid_out(valid_out)

    );

    // =====================================================
    // 5. INPUT ARRAYS: 16 A AND 16 B VALUES
    // =====================================================

    reg signed [3:0] A_values [0:15];
    reg signed [3:0] B_values [0:15];

    integer i;

    initial begin

        // A values: -8 to +7

        A_values[0]  = -8;
        A_values[1]  = -7;
        A_values[2]  = -6;
        A_values[3]  = -5;

        A_values[4]  = -4;
        A_values[5]  = -3;
        A_values[6]  = -2;
        A_values[7]  = -1;

        A_values[8]  = 0;
        A_values[9]  = 1;
        A_values[10] = 2;
        A_values[11] = 3;

        A_values[12] = 4;
        A_values[13] = 5;
        A_values[14] = 6;
        A_values[15] = 7;

        // B values: signed INT4 values

        B_values[0]  = -8;
        B_values[1]  = 6;
        B_values[2]  = 5;
        B_values[3]  = 4;

        B_values[4]  = 3;
        B_values[5]  = 2;
        B_values[6]  = 1;
        B_values[7]  = 0;

        B_values[8]  = -1;
        B_values[9]  = -2;
        B_values[10] = -3;
        B_values[11] = -4;

        B_values[12] = -5;
        B_values[13] = -6;
        B_values[14] = -7;
        B_values[15] = 7;

    end


    // =====================================================
    // 6. WAVEFORM MONITORING SIGNALS
    // =====================================================

    // INT4 signed PP values

    wire signed [11:0] PP0_INT4;
    wire signed [11:0] PP1_INT4;

    assign PP0_INT4 = PP0[11:0];
    assign PP1_INT4 = PP1[11:0];

    // Sum of Booth partial products

    wire [11:0] PP_SUM_INT4;

    assign PP_SUM_INT4 =
        PP0[11:0] + PP1[11:0];

    // Signed accumulator output

    wire signed [11:0] ACC_INT4;

    assign ACC_INT4 =
        Yold_feedback[11:0];

    // Signed final output

    wire signed [11:0] Yout_signed;
    assign Yout_signed = Yout[11:0];

    // =====================================================
    // 7. INDEPENDENT REFERENCE PIPELINE
    // =====================================================

    // Expected Booth pipeline:
    //
    // Clock N     : Product enters Stage 1
    // Clock N + 1 : Product enters Stage 2
    // Clock N + 2 : Product accumulates

    reg signed [7:0] product_s1;
    reg signed [7:0] product_s2;

    reg valid_s1_expected;
    reg valid_s2_expected;

    reg valid_out_expected;

    // Track A and B through reference pipeline

    reg signed [3:0] a_s1;
    reg signed [3:0] b_s1;

    reg signed [3:0] a_s2;
    reg signed [3:0] b_s2;

    reg signed [3:0] last_a;
    reg signed [3:0] last_b;

    reg signed [7:0] last_product;

    // Expected accumulator
    reg [11:0] expected_acc;

    // Product sign extended to 12 bits
    wire [11:0] expected_product12;

    assign expected_product12 = {
        {4{product_s2[7]}},
        product_s2
    };

    // Expected combinational adder result
    wire [11:0] expected_y4;

    assign expected_y4 =
        expected_acc + expected_product12;

    // Expected final signed output
    wire [35:0] expected_Yout;

    assign expected_Yout = {24'b0, expected_acc};


    // =====================================================
    // 8. REFERENCE MAC MODEL
    // =====================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            product_s1 <= 0;
            product_s2 <= 0;

            a_s1 <= 0;
            b_s1 <= 0;
            a_s2 <= 0;
            b_s2 <= 0;

            last_a <= 0;
            last_b <= 0;
            last_product <= 0;

            valid_s1_expected <= 0;
            valid_s2_expected <= 0;
            valid_out_expected <= 0;

            expected_acc <= 0;

        end

        else if (mode_in == 2'b11) begin

            product_s1 <= 0;
            product_s2 <= 0;

            valid_s1_expected <= 0;
            valid_s2_expected <= 0;
            valid_out_expected <= 0;

            expected_acc <= 0;

        end

        else begin

            // ---------------------------------------------
            // STAGE 1: MULTIPLICATION
            // ---------------------------------------------

            product_s1 <=
                $signed(A_in[3:0]) *
                $signed(B_in[3:0]);

            a_s1 <= A_in[3:0];
            b_s1 <= B_in[3:0];

            valid_s1_expected <=
                valid_in && !load_yold;


            // ---------------------------------------------
            // STAGE 2: PIPELINE
            // ---------------------------------------------

            product_s2 <= product_s1;

            a_s2 <= a_s1;
            b_s2 <= b_s1;

            valid_s2_expected <=
                valid_s1_expected;


            // ---------------------------------------------
            // STAGE 3: ACCUMULATOR
            // ---------------------------------------------

            valid_out_expected <=
                valid_s2_expected && !load_yold;

            if (load_yold) begin

                expected_acc <= Yold_init[11:0];

            end

            else if (valid_s2_expected) begin

                expected_acc <=
                    expected_acc +
                    {{4{product_s2[7]}}, product_s2};

                last_a <= a_s2;
                last_b <= b_s2;

                last_product <= product_s2;

            end

        end

    end


    // =====================================================
    // 9. AUTOMATIC OUTPUT VERIFICATION
    // =====================================================

    integer checked_count = 0;
    integer errors = 0;

    always @(posedge clk) begin

        // Allow sequential and combinational logic to settle
        #1;

        if (rst_n && mode_in == 2'b00) begin

            // ---------------------------------------------
            // CHECK ACCUMULATOR
            // ---------------------------------------------

            if (Yold_feedback[11:0] !== expected_acc) begin

                errors = errors + 1;

                $display("");
                $display("ERROR: ACCUMULATOR MISMATCH");
                $display("Time = %0t", $time);
                $display("Expected = %0d",
                         $signed(expected_acc));
                $display("Actual = %0d",
                         $signed(ACC_INT4));

                $finish;

            end


            // ---------------------------------------------
            // CHECK SIGN EXTENDED OUTPUT
            // ---------------------------------------------

            if (Yout !== expected_Yout) begin

                errors = errors + 1;

                $display("");
                $display("ERROR: Yout MISMATCH");
                $display("Expected = %h", expected_Yout);
                $display("Actual = %h", Yout);

                $finish;

            end


            // ---------------------------------------------
            // CHECK VALID PIPELINE
            // ---------------------------------------------

            if (valid_out !== valid_out_expected) begin

                errors = errors + 1;

                $display("");
                $display("ERROR: VALID PIPELINE MISMATCH");
                $display("Time = %0t", $time);

                $finish;

            end


            // ---------------------------------------------
            // CHECK BOOTH PP SUM
            // ---------------------------------------------

            if (valid_s2_expected) begin

                if (PP_SUM_INT4 !== expected_product12) begin

                    errors = errors + 1;

                    $display("");
                    $display("ERROR: BOOTH PRODUCT MISMATCH");
                    $display("Time = %0t", $time);

                    $display("PP0 = %0d", PP0_INT4);
                    $display("PP1 = %0d", PP1_INT4);

                    $display("Expected Product = %0d",
                             $signed(product_s2));

                    $display("Actual PP Sum = %0d",
                             $signed(PP_SUM_INT4));

                    $finish;

                end


                // -----------------------------------------
                // CHECK COMBINATIONAL ADDER
                // -----------------------------------------

                if (y_4 !== expected_y4) begin

                    errors = errors + 1;

                    $display("");
                    $display("ERROR: INT4 ADDER MISMATCH");

                    $display("Expected Adder = %0d",
                             $signed(expected_y4));

                    $display("Actual Adder = %0d",
                             $signed(y_4));

                    $finish;

                end

            end


            // ---------------------------------------------
            // PRINT EVERY COMPLETED MAC
            // ---------------------------------------------

            if (valid_out_expected) begin

                checked_count = checked_count + 1;

                $display(
                    "MAC %02d | A=%0d B=%0d | Product=%0d | Acc=%0d | Yout=%0d",
                    checked_count,
                    last_a,
                    last_b,
                    last_product,
                    $signed(expected_acc),
                    Yout_signed
                );

            end

        end

    end


    // =====================================================
    // 10. MAIN TEST
    // =====================================================

    initial begin

        // ---------------------------------------------
        // INITIAL CONDITIONS
        // ---------------------------------------------

        rst_n = 1'b0;

        A_in = 16'd0;
        B_in = 16'd0;

        mode_in = 2'b11;
        valid_in = 1'b0;

        load_yold = 1'b0;
        Yold_init = 36'd0;

        $display("");
        $display("======================================");
        $display("STARTING INT4 MAC TEST");
        $display("16 CONSECUTIVE A AND B INPUT PAIRS");
        $display("======================================");


        // ---------------------------------------------
        // HARDWARE RESET
        // ---------------------------------------------

        repeat (3) @(negedge clk);

        rst_n = 1'b1;


        // ---------------------------------------------
        // SELECT GLOBAL INT4 MODE
        // ---------------------------------------------

        mode_in = 2'b00;


        // ---------------------------------------------
        // INITIALIZE ACCUMULATOR TO ZERO
        // ---------------------------------------------

        load_yold = 1'b1;
        Yold_init = 36'd0;

        @(negedge clk);

        load_yold = 1'b0;


        // ---------------------------------------------
        // 16 CONSECUTIVE CLOCK INPUTS
        // ---------------------------------------------

        $display("");
        $display("Feeding 16 input pairs...");
        $display("");

        for (i = 0; i < 16; i = i + 1) begin

            // Sign extend 4-bit operands to 16-bit
            A_in = {
                {12{A_values[i][3]}},
                A_values[i]
            };

            B_in = {
                {12{B_values[i][3]}},
                B_values[i]
            };

            // Each cycle has valid input data
            valid_in = 1'b1;

            $display(
                "INPUT %02d | A=%0d B=%0d | Expected Product=%0d",
                i + 1,
                A_values[i],
                B_values[i],
                A_values[i] * B_values[i]
            );

            // Hold until the next falling clock edge
            // One new pair is captured on each rising edge
            @(negedge clk);

        end


        // ---------------------------------------------
        // STOP INPUTS
        // ---------------------------------------------

        valid_in = 1'b0;

        A_in = 16'd0;
        B_in = 16'd0;


        // ---------------------------------------------
        // ALLOW PIPELINE TO DRAIN
        // ---------------------------------------------

        repeat (5) @(negedge clk);

        #2;


        // ---------------------------------------------
        // FINAL VERIFICATION
        // ---------------------------------------------

        $display("");
        $display("======================================");
        $display("FINAL INT4 MAC VERIFICATION");
        $display("======================================");

        $display("Expected accumulated result = -111");

        $display(
            "Actual accumulated result   = %0d",
            Yout_signed
        );

        $display(
            "Total MAC operations checked = %0d",
            checked_count
        );


        if (
            errors == 0 &&
            checked_count == 16 &&
            Yout === 36'h000000F91
        ) begin

            $display("");
            $display("======================================");
            $display("ALL 16 INT4 MAC TESTS PASSED");
            $display("======================================");

        end

        else begin

            $display("");
            $display("======================================");
            $display("INT4 MAC TEST FAILED");
            $display("======================================");

        end

        $finish;

    end

endmodule

