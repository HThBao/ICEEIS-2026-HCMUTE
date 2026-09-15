`timescale 1ns/1ps

// Clean top-level boundary: external FIFO pair + complete PE-array datapath.
module SYSTOLIC_ARRAY_FIFO_TOP #(
    parameter ARRAY_SIZE       = 16,
    parameter DATA_WIDTH       = 8,
    parameter ACC_WIDTH        = 32,
    parameter FIFO_COUNT_WIDTH = 6,
    parameter NUM_DSP_PE       = 256
) (
    input  wire                              clk,
    input  wire                              rst_n,
    input  wire                              i_start,
    input  wire [31:0]                       i_k_size,
    output wire                              o_start_ready,
    output wire                              o_busy,
    input  wire [ARRAY_SIZE*DATA_WIDTH-1:0]  i_a_fifo_q,
    input  wire [FIFO_COUNT_WIDTH-1:0]        i_a_fifo_count,
    output wire                              o_a_fifo_rdreq,
    input  wire [ARRAY_SIZE*DATA_WIDTH-1:0]  i_b_fifo_q,
    input  wire [FIFO_COUNT_WIDTH-1:0]        i_b_fifo_count,
    output wire                              o_b_fifo_rdreq,
    output wire [ARRAY_SIZE*ACC_WIDTH-1:0]   o_c_data,
    output wire [$clog2(ARRAY_SIZE)-1:0]     o_c_row,
    output wire                              o_c_valid,
    input  wire                              i_c_ready,
    output wire                              o_c_last,
    output wire                              o_compute_done,
    output wire                              o_done
);

matmul_os_fifo_pe_wrapper_16x16 #(
    .ARRAY_SIZE(ARRAY_SIZE), .DATA_WIDTH(DATA_WIDTH),
    .ACC_WIDTH(ACC_WIDTH), .BUS_WIDTH(ARRAY_SIZE*DATA_WIDTH),
    .C_BUS_WIDTH(ARRAY_SIZE*ACC_WIDTH),
    .FIFO_COUNT_WIDTH(FIFO_COUNT_WIDTH), .NUM_DSP_PE(NUM_DSP_PE)
) u_fifo_transpose_pe_array (
    .clk(clk), .rst_n(rst_n), .i_start(i_start), .i_k_size(i_k_size),
    .o_start_ready(o_start_ready), .o_busy(o_busy),
    .i_a_fifo_q(i_a_fifo_q), .i_a_fifo_count(i_a_fifo_count),
    .o_a_fifo_rdreq(o_a_fifo_rdreq), .i_b_fifo_q(i_b_fifo_q),
    .i_b_fifo_count(i_b_fifo_count), .o_b_fifo_rdreq(o_b_fifo_rdreq),
    .o_c_data(o_c_data), .o_c_row(o_c_row), .o_c_valid(o_c_valid),
    .i_c_ready(i_c_ready), .o_c_last(o_c_last),
    .o_compute_done(o_compute_done), .o_done(o_done)
);

endmodule
