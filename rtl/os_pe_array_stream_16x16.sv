`timescale 1ns/1ps

// 16x16 output-stationary array with first/last-K tag propagation.
module os_pe_array_stream_16x16 #(
    parameter ARRAY_SIZE = 16,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 32,
    parameter NUM_DSP_PE = 112
) (
    input  wire                                      clk,
    input  wire                                      rst_n,
    input  wire                                      i_clear_data,
    input  wire                                      i_clear_acc,
    input  wire [ARRAY_SIZE*DATA_WIDTH-1:0]          i_a_vector,
    input  wire [ARRAY_SIZE-1:0]                     i_a_valid,
    input  wire [ARRAY_SIZE-1:0]                     i_a_first,
    input  wire [ARRAY_SIZE-1:0]                     i_a_last,
    input  wire [ARRAY_SIZE*DATA_WIDTH-1:0]          i_b_vector,
    input  wire [ARRAY_SIZE-1:0]                     i_b_valid,
    input  wire [ARRAY_SIZE-1:0]                     i_b_first,
    input  wire [ARRAY_SIZE-1:0]                     i_b_last,
    output reg  [ARRAY_SIZE*ARRAY_SIZE*ACC_WIDTH-1:0] o_acc_flat,
    output reg  [ARRAY_SIZE*ARRAY_SIZE*ACC_WIDTH-1:0] o_result_flat,
    output reg  [ARRAY_SIZE*ARRAY_SIZE-1:0]           o_result_valid,
    output reg                                        o_active
);

wire [DATA_WIDTH-1:0] a_in       [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
wire [DATA_WIDTH-1:0] a_out      [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
wire                  a_v_in     [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
wire                  a_v_out    [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
wire                  a_first_in [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
wire                  a_first_out[0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
wire                  a_last_in  [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
wire                  a_last_out [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];

wire [DATA_WIDTH-1:0] b_in       [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
wire [DATA_WIDTH-1:0] b_out      [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
wire                  b_v_in     [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
wire                  b_v_out    [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
wire                  b_first_in [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
wire                  b_first_out[0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
wire                  b_last_in  [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
wire                  b_last_out [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];

wire [ACC_WIDTH-1:0] acc         [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
wire [ACC_WIDTH-1:0] result      [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
wire                 result_valid[0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];

integer rr;
integer cc;
genvar r;
genvar c;

always @(*) begin
    o_acc_flat     = '0;
    o_result_flat  = '0;
    o_result_valid = '0;
    o_active       = 1'b0;
    for (rr = 0; rr < ARRAY_SIZE; rr = rr + 1) begin
        for (cc = 0; cc < ARRAY_SIZE; cc = cc + 1) begin
            o_acc_flat[(rr*ARRAY_SIZE+cc)*ACC_WIDTH +: ACC_WIDTH] =
                acc[rr][cc];
            o_result_flat[(rr*ARRAY_SIZE+cc)*ACC_WIDTH +: ACC_WIDTH] =
                result[rr][cc];
            o_result_valid[rr*ARRAY_SIZE+cc] = result_valid[rr][cc];
            o_active = o_active | a_v_in[rr][cc] | a_v_out[rr][cc]
                                | b_v_in[rr][cc] | b_v_out[rr][cc];
        end
    end
end

generate
    for (r = 0; r < ARRAY_SIZE; r = r + 1) begin : g_boundary_a
        assign a_in[r][0]       = i_a_vector[r*DATA_WIDTH +: DATA_WIDTH];
        assign a_v_in[r][0]     = i_a_valid[r];
        assign a_first_in[r][0] = i_a_first[r];
        assign a_last_in[r][0]  = i_a_last[r];
        for (c = 1; c < ARRAY_SIZE; c = c + 1) begin : g_a_link
            assign a_in[r][c]       = a_out[r][c-1];
            assign a_v_in[r][c]     = a_v_out[r][c-1];
            assign a_first_in[r][c] = a_first_out[r][c-1];
            assign a_last_in[r][c]  = a_last_out[r][c-1];
        end
    end

    for (c = 0; c < ARRAY_SIZE; c = c + 1) begin : g_boundary_b
        assign b_in[0][c]       = i_b_vector[c*DATA_WIDTH +: DATA_WIDTH];
        assign b_v_in[0][c]     = i_b_valid[c];
        assign b_first_in[0][c] = i_b_first[c];
        assign b_last_in[0][c]  = i_b_last[c];
        for (r = 1; r < ARRAY_SIZE; r = r + 1) begin : g_b_link
            assign b_in[r][c]       = b_out[r-1][c];
            assign b_v_in[r][c]     = b_v_out[r-1][c];
            assign b_first_in[r][c] = b_first_out[r-1][c];
            assign b_last_in[r][c]  = b_last_out[r-1][c];
        end
    end

    for (r = 0; r < ARRAY_SIZE; r = r + 1) begin : g_pe_row
        for (c = 0; c < ARRAY_SIZE; c = c + 1) begin : g_pe_col
            os_pe_stream #(
                .DATA_WIDTH(DATA_WIDTH),
                .ACC_WIDTH(ACC_WIDTH),
                .USE_DSP((r*ARRAY_SIZE+c) < NUM_DSP_PE)
            ) u_pe (
                .clk(clk),
                .rst_n(rst_n),
                .i_clear_data(i_clear_data),
                .i_clear_acc(i_clear_acc),
                .i_a(a_in[r][c]),
                .i_a_valid(a_v_in[r][c]),
                .i_a_first(a_first_in[r][c]),
                .i_a_last(a_last_in[r][c]),
                .i_b(b_in[r][c]),
                .i_b_valid(b_v_in[r][c]),
                .i_b_first(b_first_in[r][c]),
                .i_b_last(b_last_in[r][c]),
                .o_a(a_out[r][c]),
                .o_a_valid(a_v_out[r][c]),
                .o_a_first(a_first_out[r][c]),
                .o_a_last(a_last_out[r][c]),
                .o_b(b_out[r][c]),
                .o_b_valid(b_v_out[r][c]),
                .o_b_first(b_first_out[r][c]),
                .o_b_last(b_last_out[r][c]),
                .o_acc(acc[r][c]),
                .o_result(result[r][c]),
                .o_result_valid(result_valid[r][c])
            );
        end
    end
endgenerate

endmodule
