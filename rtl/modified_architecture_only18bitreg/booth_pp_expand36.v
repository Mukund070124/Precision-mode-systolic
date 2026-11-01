`timescale 1ns / 1ps
// Stage 2 is REMOVED. This module now contains ONLY combinational wires:
// align 18-bit Booth row into 36-bit columns, then mask inactive lanes.
// There is NO 36-bit PP register and NO extra clock cycle here.
module booth_pp_expand36 #(
    parameter ROW_INDEX = 0
)(
    input  wire [17:0] R_reg,
    input  wire en4_reg,
    input  wire en8_reg,
    input  wire en16_reg,
    output wire [35:0] aligned_R,
    output wire [35:0] expanded_R
);
    generate
        if (ROW_INDEX == 0) begin : PP0
            assign aligned_R = {{18{R_reg[17]}}, R_reg[17:0]};
        end else if (ROW_INDEX == 1) begin : PP1
            assign aligned_R = {{16{R_reg[17]}}, R_reg[17:0], 2'b00};
        end else if (ROW_INDEX == 2) begin : PP2
            assign aligned_R = {{14{R_reg[17]}}, R_reg[17:0], 4'b0000};
        end else if (ROW_INDEX == 3) begin : PP3
            assign aligned_R = {{12{R_reg[17]}}, R_reg[17:0], 6'b000000};
        end else if (ROW_INDEX == 4) begin : PP4
            assign aligned_R = {{10{R_reg[17]}}, R_reg[17:0], 8'b00000000};
        end else if (ROW_INDEX == 5) begin : PP5
            assign aligned_R = {{8{R_reg[17]}}, R_reg[17:0], 10'b0000000000};
        end else if (ROW_INDEX == 6) begin : PP6
            assign aligned_R = {{6{R_reg[17]}}, R_reg[17:0], 12'b000000000000};
        end else if (ROW_INDEX == 7) begin : PP7
            assign aligned_R = {{4{R_reg[17]}}, R_reg[17:0], 14'b00000000000000};
        end else begin : INVALID_ROW
            assign aligned_R = 36'b0;
        end
    endgenerate

    assign expanded_R[11:0]  = aligned_R[11:0]  & {12{en4_reg}};
    assign expanded_R[19:12] = aligned_R[19:12] & {8{en8_reg}};
    assign expanded_R[35:20] = aligned_R[35:20] & {16{en16_reg}};
endmodule
