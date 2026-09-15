`timescale 1ns/1ps

// Single hierarchy block joining two external FIFOs to the PE-array core.
// A is transposed; B stays row-major. Both sides advance atomically.
module matmul_os_fifo_pe_wrapper_16x16 #(
    parameter ARRAY_SIZE       = 16,
    parameter DATA_WIDTH       = 8,
    parameter ACC_WIDTH        = 32,
    parameter BUS_WIDTH        = ARRAY_SIZE*DATA_WIDTH,
    parameter C_BUS_WIDTH      = ARRAY_SIZE*ACC_WIDTH,
    parameter FIFO_COUNT_WIDTH = 6,
    parameter NUM_DSP_PE       = 256
) (
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          i_start,
    input  wire [31:0]                   i_k_size,
    output wire                          o_start_ready,
    output wire                          o_busy,
    input  wire [BUS_WIDTH-1:0]          i_a_fifo_q,
    input  wire [FIFO_COUNT_WIDTH-1:0]   i_a_fifo_count,
    output wire                          o_a_fifo_rdreq,
    input  wire [BUS_WIDTH-1:0]          i_b_fifo_q,
    input  wire [FIFO_COUNT_WIDTH-1:0]   i_b_fifo_count,
    output wire                          o_b_fifo_rdreq,
    output wire [C_BUS_WIDTH-1:0]        o_c_data,
    output wire [$clog2(ARRAY_SIZE)-1:0] o_c_row,
    output wire                          o_c_valid,
    input  wire                          i_c_ready,
    output wire                          o_c_last,
    output wire                          o_compute_done,
    output wire                          o_done
);

reg load_active;
reg [31:0] a_request_count;
reg [31:0] b_request_count;
reg [31:0] k_size_reg;

wire start_fire;
wire a_load_enable;
wire b_load_enable;
wire [BUS_WIDTH-1:0] a_vector;
wire [BUS_WIDTH-1:0] b_vector;
wire a_vector_valid;
wire b_vector_valid;
wire a_vector_ready;
wire b_vector_ready;
wire vector_pair_valid;
wire vector_pair_ready;
wire a_buffer_busy;
wire b_buffer_busy;
wire core_start_ready;
wire core_busy;

assign o_start_ready = core_start_ready && !load_active &&
                       !a_buffer_busy && !b_buffer_busy;
assign start_fire = i_start && o_start_ready;
assign o_busy = load_active || a_buffer_busy || b_buffer_busy || core_busy;
assign a_load_enable = load_active && (a_request_count < k_size_reg);
assign b_load_enable = load_active && (b_request_count < k_size_reg);

// Coupling here is the only connection policy between front end and core.
assign vector_pair_valid = a_vector_valid && b_vector_valid;
assign vector_pair_ready = a_vector_ready && b_vector_ready &&
                           vector_pair_valid;

data_transpose #(
    .DATA_WIDTH(DATA_WIDTH), .ARRAY_SIZE(ARRAY_SIZE),
    .BUS_WIDTH(BUS_WIDTH), .FIFO_COUNT_WIDTH(FIFO_COUNT_WIDTH),
    .TRANSPOSE(1)
) u_a_fifo_transpose (
    .clk(clk), .rst_n(rst_n), .i_clear(start_fire),
    .i_enable(a_load_enable), .i_data(i_a_fifo_q),
    .i_fifo_count(i_a_fifo_count), .o_rd_rq(o_a_fifo_rdreq),
    .o_data(a_vector), .o_valid(a_vector_valid),
    .i_ready(vector_pair_ready), .o_block_first(),
    .o_block_last(), .o_done(), .o_busy(a_buffer_busy)
);

data_transpose #(
    .DATA_WIDTH(DATA_WIDTH), .ARRAY_SIZE(ARRAY_SIZE),
    .BUS_WIDTH(BUS_WIDTH), .FIFO_COUNT_WIDTH(FIFO_COUNT_WIDTH),
    .TRANSPOSE(0)
) u_b_fifo_row_buffer (
    .clk(clk), .rst_n(rst_n), .i_clear(start_fire),
    .i_enable(b_load_enable), .i_data(i_b_fifo_q),
    .i_fifo_count(i_b_fifo_count), .o_rd_rq(o_b_fifo_rdreq),
    .o_data(b_vector), .o_valid(b_vector_valid),
    .i_ready(vector_pair_ready), .o_block_first(),
    .o_block_last(), .o_done(), .o_busy(b_buffer_busy)
);

matmul_os_streaming_core_16x16 #(
    .ARRAY_SIZE(ARRAY_SIZE), .DATA_WIDTH(DATA_WIDTH),
    .ACC_WIDTH(ACC_WIDTH), .BUS_WIDTH(BUS_WIDTH),
    .C_BUS_WIDTH(C_BUS_WIDTH), .NUM_DSP_PE(NUM_DSP_PE)
) u_pe_array_core (
    .clk(clk), .rst_n(rst_n), .i_start(start_fire),
    .i_k_size(i_k_size), .o_start_ready(core_start_ready),
    .o_busy(core_busy), .i_a_data(a_vector),
    .i_a_valid(vector_pair_valid), .o_a_ready(a_vector_ready),
    .i_b_data(b_vector), .i_b_valid(vector_pair_valid),
    .o_b_ready(b_vector_ready), .o_c_data(o_c_data),
    .o_c_row(o_c_row), .o_c_valid(o_c_valid),
    .i_c_ready(i_c_ready), .o_c_last(o_c_last),
    .o_compute_done(o_compute_done), .o_done(o_done)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        load_active     <= 1'b0;
        a_request_count <= '0;
        b_request_count <= '0;
        k_size_reg      <= 32'd16;
    end else if (start_fire) begin
        load_active     <= 1'b1;
        a_request_count <= '0;
        b_request_count <= '0;
        k_size_reg      <= i_k_size;
    end else begin
        if (o_a_fifo_rdreq)
            a_request_count <= a_request_count + 1'b1;
        if (o_b_fifo_rdreq)
            b_request_count <= b_request_count + 1'b1;

        if (((a_request_count == k_size_reg) ||
             ((a_request_count == k_size_reg-1'b1) && o_a_fifo_rdreq)) &&
            ((b_request_count == k_size_reg) ||
             ((b_request_count == k_size_reg-1'b1) && o_b_fifo_rdreq)))
            load_active <= 1'b0;
    end
end

initial begin
    if (BUS_WIDTH != ARRAY_SIZE*DATA_WIDTH)
        $error("BUS_WIDTH must equal ARRAY_SIZE*DATA_WIDTH");
    if (C_BUS_WIDTH != ARRAY_SIZE*ACC_WIDTH)
        $error("C_BUS_WIDTH must equal ARRAY_SIZE*ACC_WIDTH");
end

endmodule
