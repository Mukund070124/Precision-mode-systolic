
`timescale 1ns/1ps

// ============================================================
// MODULE 1: CARRY SAVE ADDER
// ============================================================

module csa #(parameter N = 16)(
    input  wire [N-1:0] A, B, C,
    output wire [N-1:0] SUM,
    output wire [N:0] CARRY,
    output wire [N:0] FINAL
);

    wire [N-1:0] carry_gen;

    assign SUM = A ^ B ^ C;

    assign carry_gen =
        (A & B) | (B & C) | (A & C);

    // Carry is already shifted by one bit
    assign CARRY = {carry_gen, 1'b0};

    // Optional output, not used in datapath
    assign FINAL = {1'b0, SUM} + CARRY;

endmodule


// ============================================================
// MODULE 2: CARRY SELECT ADDER
// ============================================================

module carry_select_adder #(
    parameter N = 16,
    parameter BLOCK_SIZE = 4
)(
    input wire [N-1:0] A, B,
    input wire CIN,
    output wire [N-1:0] SUM,
    output wire COUT
);

    localparam NUM_BLOCKS =
        (N + BLOCK_SIZE - 1) / BLOCK_SIZE;

    wire [NUM_BLOCKS:0] carry;

    assign carry[0] = CIN;

    genvar i;

    generate
        for (i = 0; i < NUM_BLOCKS; i = i + 1)
        begin : CS_BLOCK

            localparam START = i * BLOCK_SIZE;

            localparam WIDTH =
                ((N - START) < BLOCK_SIZE)
                ? (N - START) : BLOCK_SIZE;

            wire [WIDTH:0] sum_cin0;
            wire [WIDTH:0] sum_cin1;

            assign sum_cin0 =
                {1'b0, A[START +: WIDTH]} +
                {1'b0, B[START +: WIDTH]};

            assign sum_cin1 =
                {1'b0, A[START +: WIDTH]} +
                {1'b0, B[START +: WIDTH]} +
                1'b1;

            assign {
                carry[i+1],
                SUM[START +: WIDTH]
            } = carry[i] ? sum_cin1 : sum_cin0;

        end
    endgenerate

    assign COUT = carry[NUM_BLOCKS];

endmodule


// ============================================================
// MODULE 3: CSA CARRY INJECTION
// ============================================================

module csa_carry_inject #(parameter N = 16)(
    input wire [N:0] shifted_carry,
    input wire previous_cpa_cout,
    input wire enable,

    output wire [N-1:0] cpa_operand,
    output wire carry_above_lane
);

    assign cpa_operand = {
        shifted_carry[N-1:1],
        previous_cpa_cout & enable
    };

    assign carry_above_lane = shifted_carry[N];

endmodule


// ============================================================
// MODULE 4: PRECISION CONFIGURABLE BOOTH FUSED ADDER
// ============================================================

module precision_configurable_booth_fused_adder #(
    parameter BLOCK_SIZE = 4
)(
    // Clock and reset
    input wire clk,
    input wire rst_n,

    // Accumulator control
    input wire acc_enable,
    input wire load_yold,

    // Precision selection
    input wire [1:0] mode,

    // Initial accumulator value
    input wire [35:0] Yold,

    // Eight registered partial products
    input wire [35:0] PP0,
    input wire [35:0] PP1,
    input wire [35:0] PP2,
    input wire [35:0] PP3,
    input wire [35:0] PP4,
    input wire [35:0] PP5,
    input wire [35:0] PP6,
    input wire [35:0] PP7,

    // Precision-specific adder results
    output wire [11:0] y_4,
    output wire [19:0] y_8,
    output wire [35:0] y_16,

    // Accumulator register output
    output wire [35:0] yold_feedback
);

    // ========================================================
    // 1. MODE DECODING
    // ========================================================

    wire en_4;
    wire en_8;
    wire en_16;
    wire pass_to_8;

    assign en_4  = (mode == 2'b00);
    assign en_8  = (mode == 2'b01);
    assign en_16 = (mode == 2'b10);

    assign pass_to_8 = en_8 | en_16;


    // ========================================================
    // 2. ACCUMULATOR FEEDBACK REGISTER
    // ========================================================

    reg [35:0] yold_reg;

    assign yold_feedback = yold_reg;

    always @(posedge clk or negedge rst_n) begin

        // Asynchronous reset
        if (!rst_n) begin
            yold_reg <= 36'b0;
        end

        // Mode 11: synchronous accumulator reset
        else if (mode == 2'b11) begin
            yold_reg <= 36'b0;
        end

        // Load initial accumulator value
        else if (load_yold) begin
            yold_reg <= Yold;
        end

        // Accumulate only valid input
        else if (acc_enable) begin

            case (mode)

                // INT4: update lower 12 bits
                2'b00: begin
                    yold_reg[11:0] <= y_4;
                end

                // INT8: update lower 20 bits
                2'b01: begin
                    yold_reg[19:0] <= y_8;
                end

                // INT16: update entire 36 bits
                2'b10: begin
                    yold_reg[35:0] <= y_16;
                end

                default: begin
                    yold_reg <= 36'b0;
                end

            endcase

        end

        // Otherwise hold previous Yold

    end


    // ========================================================
    // 3. INPUT BIT SLICING
    // ========================================================

    // First 12 bits: INT4 branch
    wire [11:0] yold_4 = yold_reg[11:0];
    wire [11:0] pp0_4  = PP0[11:0];
    wire [11:0] pp1_4  = PP1[11:0];

    // Next 8 bits: INT8 branch
    wire [7:0] yold_8_lo = yold_reg[19:12];
    wire [7:0] pp0_8_lo  = PP0[19:12];
    wire [7:0] pp1_8_lo  = PP1[19:12];

    // Upper 16 bits: INT16 branch
    wire [15:0] yold_16 = yold_reg[35:20];
    wire [15:0] pp0_16  = PP0[35:20];
    wire [15:0] pp1_16  = PP1[35:20];

    // PP2 and PP3
    wire [19:0] pp2_8 = PP2[19:0];
    wire [19:0] pp3_8 = PP3[19:0];

    wire [15:0] pp2_16 = PP2[35:20];
    wire [15:0] pp3_16 = PP3[35:20];

    // PP4 to PP7: two 18-bit halves
    wire [17:0] pp4_16_hi = PP4[35:18];
    wire [17:0] pp4_16_lo = PP4[17:0];

    wire [17:0] pp5_16_hi = PP5[35:18];
    wire [17:0] pp5_16_lo = PP5[17:0];

    wire [17:0] pp6_16_hi = PP6[35:18];
    wire [17:0] pp6_16_lo = PP6[17:0];

    wire [17:0] pp7_16_hi = PP7[35:18];
    wire [17:0] pp7_16_lo = PP7[17:0];


    // ========================================================
    // 4. INT4 BRANCH: 12-BIT CSA + CPA
    // ========================================================

    wire [11:0] s4;
    wire [12:0] carry4;

    wire [11:0] res4;
    wire co4;

    // 12-bit CSA
    csa #(.N(12)) csa4 (
        .A(yold_4),
        .B(pp0_4),
        .C(pp1_4),
        .SUM(s4),
        .CARRY(carry4),
        .FINAL()
    );

    // 12-bit carry-select CPA
    carry_select_adder #(
        .N(12),
        .BLOCK_SIZE(BLOCK_SIZE)
    ) cpa4 (
        .A(s4),
        .B(carry4[11:0]),
        .CIN(1'b0),
        .SUM(res4),
        .COUT(co4)
    );

    assign y_4 = res4 & {12{en_4}};


    // ========================================================
    // 5. INT8 BRANCH: NEXT 8-BIT CSA + CPA
    // ========================================================

    wire [7:0] s8;
    wire [8:0] carry8;

    wire [7:0] c8_input;
    wire [7:0] lo8;

    wire co8;
    wire cin8;

    // Previous 12-bit CPA carry
    assign cin8 = co4 & pass_to_8;

    // 8-bit CSA
    csa #(.N(8)) csa8 (
        .A(yold_8_lo),
        .B(pp0_8_lo),
        .C(pp1_8_lo),
        .SUM(s8),
        .CARRY(carry8),
        .FINAL()
    );

    // Previous 12-bit CSA overflow into bit 0
    assign c8_input = {
        carry8[7:1],
        carry4[12] & pass_to_8
    };

    // 8-bit carry-select CPA
    carry_select_adder #(
        .N(8),
        .BLOCK_SIZE(BLOCK_SIZE)
    ) cpa8 (
        .A(s8),
        .B(c8_input),
        .CIN(cin8),
        .SUM(lo8),
        .COUT(co8)
    );


    // ========================================================
    // 6. FIRST CONCATENATION: 20 BITS
    // ========================================================

    wire [11:0] low12_for_concat;

    assign low12_for_concat =
        res4 & {12{pass_to_8}};

    // Upper 8 bits followed by lower 12 bits
    wire [19:0] concat20;

    assign concat20 = {
        lo8,
        low12_for_concat
    };

    // PP2 + PP3
    wire [19:0] pp23_20;
    wire co_pp23;

    carry_select_adder #(
        .N(20),
        .BLOCK_SIZE(BLOCK_SIZE)
    ) cpa_pp23_20 (
        .A(pp2_8),
        .B(pp3_8),
        .CIN(1'b0),
        .SUM(pp23_20),
        .COUT(co_pp23)
    );

    // Combined lower 20-bit result
    wire [19:0] result8_raw;
    wire co8final;

    carry_select_adder #(
        .N(20),
        .BLOCK_SIZE(BLOCK_SIZE)
    ) cpa8_final (
        .A(concat20),
        .B(pp23_20),
        .CIN(1'b0),
        .SUM(result8_raw),
        .COUT(co8final)
    );

    assign y_8 =
        result8_raw & {20{en_8}};


    // ========================================================
    // 7. INT16 UPPER BRANCH: FIRST 16-BIT CSA
    // ========================================================

    wire [15:0] s16a;
    wire [16:0] ca16a;

    wire [15:0] c16a;
    wire ov16a;

    csa #(.N(16)) csa16a (
        .A(yold_16),
        .B(pp0_16),
        .C(pp1_16),
        .SUM(s16a),
        .CARRY(ca16a),
        .FINAL()
    );

    // Inject carry from 8-bit CSA
    csa_carry_inject #(.N(16)) inj16a (
        .shifted_carry(ca16a),
        .previous_cpa_cout(carry8[8]),
        .enable(en_16),
        .cpa_operand(c16a),
        .carry_above_lane(ov16a)
    );


    // ========================================================
    // 8. INT16 UPPER BRANCH: SECOND 16-BIT CSA
    // ========================================================

    wire [15:0] s16b;
    wire [16:0] ca16b;

    wire [15:0] c16b;
    wire ov16b;

    csa #(.N(16)) csa16b (
        .A(s16a),
        .B(c16a),
        .C(pp2_16),
        .SUM(s16b),
        .CARRY(ca16b),
        .FINAL()
    );

    // Inject carry from 8-bit CPA
    csa_carry_inject #(.N(16)) inj16b (
        .shifted_carry(ca16b),
        .previous_cpa_cout(co8),
        .enable(en_16),
        .cpa_operand(c16b),
        .carry_above_lane(ov16b)
    );


    // ========================================================
    // 9. INT16 UPPER BRANCH: THIRD 16-BIT CSA
    // ========================================================

    wire [15:0] s16c;
    wire [16:0] ca16c;

    wire [15:0] c16c;
    wire ov16c;

    csa #(.N(16)) csa16c (
        .A(s16b),
        .B(c16b),
        .C(pp3_16),
        .SUM(s16c),
        .CARRY(ca16c),
        .FINAL()
    );

    // Inject carry from PP2 + PP3 addition
    csa_carry_inject #(.N(16)) inj16bc (
        .shifted_carry(ca16c),
        .previous_cpa_cout(co_pp23),
        .enable(en_16),
        .cpa_operand(c16c),
        .carry_above_lane(ov16c)
    );


    // ========================================================
    // 10. FINAL 16-BIT CPA
    // ========================================================

    wire [15:0] res16;
    wire co16;

    // Carry from 20-bit CPA
    wire cin16;

    assign cin16 = co8final & en_16;

    carry_select_adder #(
        .N(16),
        .BLOCK_SIZE(BLOCK_SIZE)
    ) cpa16 (
        .A(s16c),
        .B(c16c),
        .CIN(cin16),
        .SUM(res16),
        .COUT(co16)
    );


    // ========================================================
    // 11. SECOND CONCATENATION: 36 BITS
    // ========================================================

    wire [19:0] int8_to_int16;

    assign int8_to_int16 =
        result8_raw & {20{en_16}};

    wire [35:0] concat_upper36;

    assign concat_upper36 = {
        res16,
        int8_to_int16
    };


    // ========================================================
    // 12. INT16 LOWER BRANCH: PP4 TO PP7
    // ========================================================

    wire [17:0] p45;
    wire [17:0] p67;

    wire [17:0] s18a;
    wire [17:0] s18b;

    wire [18:0] ca18a;
    wire [18:0] ca18b;

    wire [17:0] c18a;
    wire [17:0] c18b;

    wire [17:0] upper18;
    wire [17:0] lower18;

    wire co45;
    wire co67;
    wire co_lower18;
    wire co_upper18;

    wire ov18a;
    wire ov18b;


    // ========================================================
    // 13. PP4 + PP5 LOWER 18-BIT CPA
    // ========================================================

    carry_select_adder #(
        .N(18),
        .BLOCK_SIZE(BLOCK_SIZE)
    ) cpa45 (
        .A(pp4_16_lo),
        .B(pp5_16_lo),
        .CIN(1'b0),
        .SUM(p45),
        .COUT(co45)
    );


    // ========================================================
    // 14. PP6 + PP7 LOWER 18-BIT CPA
    // ========================================================

    carry_select_adder #(
        .N(18),
        .BLOCK_SIZE(BLOCK_SIZE)
    ) cpa67 (
        .A(pp6_16_lo),
        .B(pp7_16_lo),
        .CIN(1'b0),
        .SUM(p67),
        .COUT(co67)
    );


    // ========================================================
    // 15. FIRST 18-BIT CSA
    // ========================================================

    csa #(.N(18)) csa18a (
        .A(pp4_16_hi),
        .B(pp5_16_hi),
        .C(pp6_16_hi),
        .SUM(s18a),
        .CARRY(ca18a),
        .FINAL()
    );

    csa_carry_inject #(.N(18)) inj18a (
        .shifted_carry(ca18a),
        .previous_cpa_cout(co45),
        .enable(en_16),
        .cpa_operand(c18a),
        .carry_above_lane(ov18a)
    );


    // ========================================================
    // 16. LOWER 18-BIT CPA
    // ========================================================

    carry_select_adder #(
        .N(18),
        .BLOCK_SIZE(BLOCK_SIZE)
    ) cpa18lower (
        .A(p45),
        .B(p67),
        .CIN(1'b0),
        .SUM(lower18),
        .COUT(co_lower18)
    );


    // ========================================================
    // 17. SECOND 18-BIT CSA
    // ========================================================

    csa #(.N(18)) csa18b (
        .A(s18a),
        .B(c18a),
        .C(pp7_16_hi),
        .SUM(s18b),
        .CARRY(ca18b),
        .FINAL()
    );

    csa_carry_inject #(.N(18)) inj18b (
        .shifted_carry(ca18b),
        .previous_cpa_cout(co_lower18),
        .enable(en_16),
        .cpa_operand(c18b),
        .carry_above_lane(ov18b)
    );


    // ========================================================
    // 18. UPPER 18-BIT CPA
    // ========================================================

    carry_select_adder #(
        .N(18),
        .BLOCK_SIZE(BLOCK_SIZE)
    ) cpa18upper (
        .A(s18b),
        .B(c18b),
        .CIN(co67),
        .SUM(upper18),
        .COUT(co_upper18)
    );


    // ========================================================
    // 19. CONCATENATE LOWER INT16 BRANCH
    // ========================================================

    wire [35:0] concat_lower36;

    assign concat_lower36 = {
        upper18,
        lower18
    };


    // ========================================================
    // 20. FINAL INT16 36-BIT CPA
    // ========================================================

    wire [35:0] result16_raw;
    wire co36;

    carry_select_adder #(
        .N(36),
        .BLOCK_SIZE(BLOCK_SIZE)
    ) cpa36 (
        .A(concat_upper36),
        .B(concat_lower36),
        .CIN(1'b0),
        .SUM(result16_raw),
        .COUT(co36)
    );

    assign y_16 =
        result16_raw & {36{en_16}};

endmodule
