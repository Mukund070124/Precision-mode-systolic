`timescale 1ns/1ps
// 16x16 output-stationary matrix-multiplication array using the
// original PE arithmetic, with column-input Booth decoding and encoded-B forwarding.
//
// Each PE accumulates one C[row][col] = SUM(k=0..15) A[row][k]*B[k][col].
// External testbench (or a real memory controller) supplies skewed data:
// at input cycle t, left[row]=A[row][t-row], top[col]=B[t-col][col].
// Out-of-range accesses must have their corresponding valid bit LOW.
//
// IMPORTANT: 1. The mode MUST stay fixed for a tile (00/01/10).
//            2. Pulse clear_tile for >=1 rising edge between tiles.
//            3. A forwarding is original; B carries registered Booth digits.
//            4. C_flat[(row*16+col)*36 +: 36] contains C[row][col].
//            5. tile_done asserts one cycle after final PE's 16th MAC valid.
//            6. There is NO input-skew shift-register bank in this DUT.
module systolic_array_16x16 (
    input  wire          clk,
    input  wire          rst_n,
    input  wire [1:0]    mode_in,
    input  wire          clear_tile,
    input  wire [255:0]  A_left_flat,
    input  wire [255:0]  B_top_flat,
    input  wire [15:0]   A_left_valid,
    input  wire [15:0]   B_top_valid,
    output wire [9215:0] C_flat,
    output reg           tile_done
);
    // Clear existing PE accumulators with the original reserved mode 2'b11.
    wire [1:0] pe_mode = clear_tile ? 2'b11 : mode_in;

    wire [15:0] a_forward [0:15][0:15];
    wire [23:0] booth_forward [0:15][0:15];
    wire [23:0] booth_column_input [0:15];
    wire        v_forward [0:15][0:15];
    wire        mac_valid [0:15][0:15];
    wire        last_pe_valid;

    // 16 banks, one per incoming B column. No Booth decoders inside PEs.
    genvar bc;
    generate for (bc=0;bc<16;bc=bc+1) begin : G_COLUMN_RECODE
        booth_column_encoder u_encoder (
            .b(B_top_flat[bc*16 +: 16]),
            .mode(pe_mode), .booth_digits(booth_column_input[bc])
        );
    end endgenerate

    genvar r, c;
    generate
        for (r = 0; r < 16; r = r + 1) begin : GEN_ROW
            for (c = 0; c < 16; c = c + 1) begin : GEN_COL
                wire [15:0] a_input;
                wire [23:0] b_input;
                wire a_v, b_v;
                wire [35:0] result;
                wire        result_valid;

                if (c == 0) begin : LEFT_EDGE
                    assign a_input = A_left_flat[r*16 +: 16];
                    assign a_v     = A_left_valid[r];
                end else begin : FROM_LEFT
                    assign a_input = a_forward[r][c-1];
                    assign a_v     = v_forward[r][c-1];
                end
                if (r == 0) begin : TOP_EDGE
                    assign b_input = booth_column_input[c];
                    assign b_v     = B_top_valid[c];
                end else begin : FROM_ABOVE
                    assign b_input = booth_forward[r-1][c];
                    assign b_v     = v_forward[r-1][c];
                end

                // With the prescribed row/column input skew, both operand
                // valids are aligned at every PE throughout the wavefront.
                assign mac_valid[r][c] = a_v & b_v;

                mac_top_column u_pe (
                    .clk(clk),
                    .rst_n(rst_n),
                    .A_in(a_input),
                    .B_encoded_in(b_input),
                    .mode_in(pe_mode),
                    .valid_in(mac_valid[r][c]),
                    .load_yold(1'b0),
                    .Yold_init(36'b0),
                    .A_out(a_forward[r][c]),
                    .B_encoded_out(booth_forward[r][c]),
                    .valid_forward(v_forward[r][c]),
                    .PP0(), .PP1(), .PP2(), .PP3(),
                    .PP4(), .PP5(), .PP6(), .PP7(),
                    .y_4(), .y_8(), .y_16(),
                    .Yold_feedback(),
                    .Yout(result),
                    .valid_out(result_valid)
                );
                assign C_flat[((r*16+c)*36) +: 36] = result;
                if (r == 15 && c == 15) begin : LAST_PE
                    assign last_pe_valid = result_valid;
                end
            end
        end
    endgenerate

    // Count the sixteen finished products of PE(15,15). It is the last
    // PE to complete, so by then every other accumulator is finished.
    // The counter sees result_valid one clock later (nonblocking semantics),
    // which is safe: C_flat is stable when tile_done is asserted.
    reg [4:0] last_pe_products;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tile_done        <= 1'b0;
            last_pe_products <= 5'd0;
        end else if (clear_tile || mode_in == 2'b11) begin
            tile_done        <= 1'b0;
            last_pe_products <= 5'd0;
        end else if (!tile_done && last_pe_valid) begin
            if (last_pe_products == 5'd15) begin
                tile_done        <= 1'b1;
                last_pe_products <= 5'd16;
            end else begin
                last_pe_products <= last_pe_products + 5'd1;
            end
        end
    end
endmodule
