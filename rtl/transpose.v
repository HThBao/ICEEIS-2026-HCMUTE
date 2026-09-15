`timescale 1ns/1ps

// FIFO-facing, two-bank matrix buffer.
// The FIFO is non-show-ahead: i_data is valid one cycle after o_rd_rq.
// TRANSPOSE=1 emits matrix columns; TRANSPOSE=0 emits rows unchanged.
module data_transpose #(
    parameter DATA_WIDTH       = 8,
    parameter ARRAY_SIZE       = 16,
    parameter BUS_WIDTH        = ARRAY_SIZE * DATA_WIDTH,
    parameter FIFO_COUNT_WIDTH = 6,
    parameter TRANSPOSE        = 1
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         i_clear,
    input  wire                         i_enable,
    input  wire [BUS_WIDTH-1:0]         i_data,
    input  wire [FIFO_COUNT_WIDTH-1:0]  i_fifo_count,
    output wire                         o_rd_rq,
    output wire [BUS_WIDTH-1:0]         o_data,
    output wire                         o_valid,
    input  wire                         i_ready,
    output wire                         o_block_first,
    output wire                         o_block_last,
    output wire                         o_done,
    output wire                         o_busy
);

localparam INDEX_WIDTH = (ARRAY_SIZE <= 2) ? 1 : $clog2(ARRAY_SIZE);

reg [BUS_WIDTH-1:0] bank0 [0:ARRAY_SIZE-1];
reg [BUS_WIDTH-1:0] bank1 [0:ARRAY_SIZE-1];
reg [1:0] bank_full;
reg write_bank;
reg read_bank;
reg [INDEX_WIDTH:0] request_count;
reg [INDEX_WIDTH-1:0] capture_row;
reg [INDEX_WIDTH-1:0] read_index;
reg read_pending;

wire request_fire;
wire capture_fire;
wire output_fire;
genvar lane;

// request_count tracks issued FIFO pops, including the response in flight.
// This prevents an extra pop while the sixteenth word is being returned.
assign request_fire = i_enable && !bank_full[write_bank] &&
                      (i_fifo_count != 0) &&
                      (request_count < ARRAY_SIZE);
assign o_rd_rq      = request_fire;
assign capture_fire = read_pending;

assign o_valid       = bank_full[read_bank];
assign output_fire   = o_valid && i_ready;
assign o_block_first = o_valid && (read_index == 0);
assign o_block_last  = o_valid && (read_index == ARRAY_SIZE-1);
assign o_done        = output_fire && (read_index == ARRAY_SIZE-1);
assign o_busy        = (bank_full != 0) || read_pending ||
                       (request_count != 0) || (capture_row != 0);

generate
    for (lane = 0; lane < ARRAY_SIZE; lane = lane + 1) begin : g_output_lane
        if (TRANSPOSE != 0) begin : g_transposed
            assign o_data[lane*DATA_WIDTH +: DATA_WIDTH] =
                read_bank
                    ? bank1[lane][read_index*DATA_WIDTH +: DATA_WIDTH]
                    : bank0[lane][read_index*DATA_WIDTH +: DATA_WIDTH];
        end else begin : g_row_major
            assign o_data[lane*DATA_WIDTH +: DATA_WIDTH] =
                read_bank
                    ? bank1[read_index][lane*DATA_WIDTH +: DATA_WIDTH]
                    : bank0[read_index][lane*DATA_WIDTH +: DATA_WIDTH];
        end
    end
endgenerate

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bank_full    <= 2'b00;
        write_bank   <= 1'b0;
        read_bank    <= 1'b0;
        request_count <= '0;
        capture_row  <= '0;
        read_index   <= '0;
        read_pending <= 1'b0;
    end else if (i_clear) begin
        bank_full    <= 2'b00;
        write_bank   <= 1'b0;
        read_bank    <= 1'b0;
        request_count <= '0;
        capture_row  <= '0;
        read_index   <= '0;
        read_pending <= 1'b0;
    end else begin
        read_pending <= request_fire;
        if (request_fire)
            request_count <= request_count + 1'b1;

        if (capture_fire) begin
            if (write_bank == 1'b0)
                bank0[capture_row] <= i_data;
            else
                bank1[capture_row] <= i_data;

            if (capture_row == ARRAY_SIZE-1) begin
                bank_full[write_bank] <= 1'b1;
                write_bank    <= !write_bank;
                request_count <= '0;
                capture_row   <= '0;
            end else begin
                capture_row <= capture_row + 1'b1;
            end
        end

        if (output_fire) begin
            if (read_index == ARRAY_SIZE-1) begin
                bank_full[read_bank] <= 1'b0;
                read_bank  <= !read_bank;
                read_index <= '0;
            end else begin
                read_index <= read_index + 1'b1;
            end
        end
    end
end

initial begin
    if (BUS_WIDTH != ARRAY_SIZE*DATA_WIDTH)
        $error("BUS_WIDTH must equal ARRAY_SIZE*DATA_WIDTH");
end

endmodule
