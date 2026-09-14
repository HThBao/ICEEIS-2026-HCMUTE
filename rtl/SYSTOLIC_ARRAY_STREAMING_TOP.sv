`timescale 1ns/1ps

// Platform Designer boundary for the optimized dual-stream core.
// A and B are 128-bit Avalon-ST sinks; C is a 512-bit Avalon-ST source.
module SYSTOLIC_ARRAY_STREAMING_TOP #(
    parameter ARRAY_SIZE = 16,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 32,
    parameter NUM_DSP_PE = 256
) (
    input  wire          clk,
    input  wire          rst_n,

    input  wire          i_start,
    input  wire [31:0]   i_k_size,
    output wire          o_start_ready,
    output wire          o_busy,

    input  wire [127:0]  i_a_st_data,
    input  wire          i_a_st_valid,
    output wire          o_a_st_ready,

    input  wire [127:0]  i_b_st_data,
    input  wire          i_b_st_valid,
    output wire          o_b_st_ready,

    output wire [511:0]  o_c_st_data,
    output wire [3:0]    o_c_st_row,
    output wire          o_c_st_valid,
    input  wire          i_c_st_ready,
    output wire          o_c_st_endofpacket,

    output wire          o_compute_done,
    output wire          o_done
);

matmul_os_pingpong_frontend_16x16 #(
    .ARRAY_SIZE(ARRAY_SIZE),
    .DATA_WIDTH(DATA_WIDTH),
    .ACC_WIDTH(ACC_WIDTH),
    .BUS_WIDTH(128),
    .C_BUS_WIDTH(512),
    .NUM_DSP_PE(NUM_DSP_PE)
) u_frontend (
    .clk(clk),
    .rst_n(rst_n),
    .i_start(i_start),
    .i_k_size(i_k_size),
    .o_start_ready(o_start_ready),
    .o_busy(o_busy),
    .i_a_row_data(i_a_st_data),
    .i_a_row_valid(i_a_st_valid),
    .o_a_row_ready(o_a_st_ready),
    .i_b_row_data(i_b_st_data),
    .i_b_row_valid(i_b_st_valid),
    .o_b_row_ready(o_b_st_ready),
    .o_c_data(o_c_st_data),
    .o_c_row(o_c_st_row),
    .o_c_valid(o_c_st_valid),
    .i_c_ready(i_c_st_ready),
    .o_c_last(o_c_st_endofpacket),
    .o_compute_done(o_compute_done),
    .o_done(o_done)
);

endmodule
