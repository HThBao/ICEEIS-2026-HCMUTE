`timescale 1ns/1ps

// Streaming front end:
// - A uses a two-bank address-based transpose buffer.
// - B uses a two-bank row buffer.
// - All K vectors are sent as one continuous reduction to the PE array.
module matmul_os_pingpong_frontend_16x16 #(
    parameter ARRAY_SIZE  = 16,
    parameter DATA_WIDTH  = 8,
    parameter ACC_WIDTH   = 32,
    parameter BUS_WIDTH   = ARRAY_SIZE*DATA_WIDTH,
    parameter C_BUS_WIDTH = ARRAY_SIZE*ACC_WIDTH,
    parameter NUM_DSP_PE  = 112
) (
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          i_start,
    input  wire [31:0]                   i_k_size,
    output wire                          o_start_ready,
    output wire                          o_busy,

    input  wire [BUS_WIDTH-1:0]          i_a_row_data,
    input  wire                          i_a_row_valid,
    output wire                          o_a_row_ready,
    input  wire [BUS_WIDTH-1:0]          i_b_row_data,
    input  wire                          i_b_row_valid,
    output wire                          o_b_row_ready,

    output wire [C_BUS_WIDTH-1:0]        o_c_data,
    output wire [$clog2(ARRAY_SIZE)-1:0] o_c_row,
    output wire                          o_c_valid,
    input  wire                          i_c_ready,
    output wire                          o_c_last,
    output wire                          o_compute_done,
    output wire                          o_done
);

reg input_active;
reg [31:0] input_count;
reg [31:0] k_size_reg;

wire start_fire;
wire input_pair_fire;
wire a_load_ready;
wire b_load_ready;
wire [BUS_WIDTH-1:0] a_vector;
wire [BUS_WIDTH-1:0] b_vector;
wire a_vector_valid;
wire b_vector_valid;
wire a_vector_ready;
wire b_vector_ready;
wire output_pair_ready;
wire a_block_first;
wire b_block_first;
wire a_block_last;
wire b_block_last;
wire a_buffer_busy;
wire b_buffer_busy;
wire core_start_ready;
wire core_busy;

assign o_start_ready = core_start_ready && !input_active &&
                       !a_buffer_busy && !b_buffer_busy;
assign start_fire = i_start && o_start_ready;
assign o_busy = input_active || a_buffer_busy || b_buffer_busy || core_busy;

// A and B rows always enter as a pair; neither FIFO can advance alone.
assign o_a_row_ready = input_active && a_load_ready && b_load_ready &&
                       i_b_row_valid;
assign o_b_row_ready = input_active && a_load_ready && b_load_ready &&
                       i_a_row_valid;
assign input_pair_fire = i_a_row_valid && i_b_row_valid &&
                         o_a_row_ready && o_b_row_ready;

// Both ping-pong readers advance only when the core accepts the vector pair.
assign output_pair_ready = a_vector_ready && b_vector_ready;

data_transpose_pingpong_128 #(
    .DATA_WIDTH(DATA_WIDTH),
    .ARRAY_SIZE(ARRAY_SIZE),
    .BUS_WIDTH(BUS_WIDTH)
) u_transpose_a (
    .clk(clk),
    .rst_n(rst_n),
    .i_clear(start_fire),
    .i_data(i_a_row_data),
    .i_valid(input_pair_fire),
    .o_ready(a_load_ready),
    .o_data(a_vector),
    .o_valid(a_vector_valid),
    .i_ready(output_pair_ready),
    .o_block_first(a_block_first),
    .o_block_last(a_block_last),
    .o_busy(a_buffer_busy)
);

data_row_buffer_pingpong_128 #(
    .ARRAY_SIZE(ARRAY_SIZE),
    .DATA_WIDTH(DATA_WIDTH),
    .BUS_WIDTH(BUS_WIDTH)
) u_buffer_b (
    .clk(clk),
    .rst_n(rst_n),
    .i_clear(start_fire),
    .i_data(i_b_row_data),
    .i_valid(input_pair_fire),
    .o_ready(b_load_ready),
    .o_data(b_vector),
    .o_valid(b_vector_valid),
    .i_ready(output_pair_ready),
    .o_block_first(b_block_first),
    .o_block_last(b_block_last),
    .o_busy(b_buffer_busy)
);

matmul_os_streaming_core_16x16 #(
    .ARRAY_SIZE(ARRAY_SIZE),
    .DATA_WIDTH(DATA_WIDTH),
    .ACC_WIDTH(ACC_WIDTH),
    .BUS_WIDTH(BUS_WIDTH),
    .C_BUS_WIDTH(C_BUS_WIDTH),
    .NUM_DSP_PE(NUM_DSP_PE)
) u_core (
    .clk(clk),
    .rst_n(rst_n),
    .i_start(start_fire),
    .i_k_size(i_k_size),
    .o_start_ready(core_start_ready),
    .o_busy(core_busy),
    .i_a_data(a_vector),
    .i_a_valid(a_vector_valid && b_vector_valid),
    .o_a_ready(a_vector_ready),
    .i_b_data(b_vector),
    .i_b_valid(a_vector_valid && b_vector_valid),
    .o_b_ready(b_vector_ready),
    .o_c_data(o_c_data),
    .o_c_row(o_c_row),
    .o_c_valid(o_c_valid),
    .i_c_ready(i_c_ready),
    .o_c_last(o_c_last),
    .o_compute_done(o_compute_done),
    .o_done(o_done)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        input_active <= 1'b0;
        input_count  <= '0;
        k_size_reg   <= 32'd16;
    end else begin
        if (start_fire) begin
            input_active <= 1'b1;
            input_count  <= '0;
            k_size_reg   <= i_k_size;
        end else if (input_pair_fire) begin
            if (input_count == k_size_reg-1'b1) begin
                input_active <= 1'b0;
                input_count  <= '0;
            end else begin
                input_count <= input_count + 1'b1;
            end
        end
    end
end

initial begin
    if (BUS_WIDTH != ARRAY_SIZE*DATA_WIDTH)
        $error("BUS_WIDTH must equal ARRAY_SIZE*DATA_WIDTH");
end

endmodule
