`timescale 1ns/1ps

// Two-bank 16x16 INT8 transpose buffer.
// One bank exports A[:,k] while the other bank loads row-major A data.
// Data is selected by address; the complete matrix is never shifted.
module data_transpose_pingpong_128 #(
    parameter DATA_WIDTH  = 8,
    parameter ARRAY_SIZE  = 16,
    parameter BUS_WIDTH   = ARRAY_SIZE*DATA_WIDTH
) (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         i_clear,

    input  wire [BUS_WIDTH-1:0]         i_data,
    input  wire                         i_valid,
    output wire                         o_ready,

    output wire [BUS_WIDTH-1:0]         o_data,
    output wire                         o_valid,
    input  wire                         i_ready,
    output wire                         o_block_first,
    output wire                         o_block_last,
    output wire                         o_busy
);

reg [DATA_WIDTH-1:0] bank0 [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
reg [DATA_WIDTH-1:0] bank1 [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
reg [1:0] bank_full;
reg write_bank;
reg read_bank;
reg [$clog2(ARRAY_SIZE)-1:0] write_row;
reg [$clog2(ARRAY_SIZE)-1:0] read_col;

wire load_fire;
wire export_fire;
integer r;
integer c;
genvar lane;

assign o_ready       = !bank_full[write_bank];
assign o_valid       = bank_full[read_bank];
assign load_fire     = i_valid && o_ready;
assign export_fire   = o_valid && i_ready;
assign o_block_first = o_valid && (read_col == 0);
assign o_block_last  = o_valid && (read_col == ARRAY_SIZE-1);
assign o_busy        = (bank_full != 0) || (write_row != 0);

generate
    for (lane = 0; lane < ARRAY_SIZE; lane = lane + 1) begin : g_read_lane
        assign o_data[lane*DATA_WIDTH +: DATA_WIDTH] =
            read_bank ? bank1[lane][read_col] : bank0[lane][read_col];
    end
endgenerate

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bank_full  <= 2'b00;
        write_bank <= 1'b0;
        read_bank  <= 1'b0;
        write_row  <= '0;
        read_col   <= '0;
    end else if (i_clear) begin
        bank_full  <= 2'b00;
        write_bank <= 1'b0;
        read_bank  <= 1'b0;
        write_row  <= '0;
        read_col   <= '0;
    end else begin
        if (export_fire) begin
            if (read_col == ARRAY_SIZE-1) begin
                bank_full[read_bank] <= 1'b0;
                read_bank <= !read_bank;
                read_col  <= '0;
            end else begin
                read_col <= read_col + 1'b1;
            end
        end

        if (load_fire) begin
            if (write_bank == 1'b0) begin
                for (c = 0; c < ARRAY_SIZE; c = c + 1)
                    bank0[write_row][c] <=
                        i_data[c*DATA_WIDTH +: DATA_WIDTH];
            end else begin
                for (c = 0; c < ARRAY_SIZE; c = c + 1)
                    bank1[write_row][c] <=
                        i_data[c*DATA_WIDTH +: DATA_WIDTH];
            end

            if (write_row == ARRAY_SIZE-1) begin
                bank_full[write_bank] <= 1'b1;
                write_bank <= !write_bank;
                write_row  <= '0;
            end else begin
                write_row <= write_row + 1'b1;
            end
        end
    end
end

initial begin
    if (BUS_WIDTH != ARRAY_SIZE*DATA_WIDTH)
        $error("BUS_WIDTH must equal ARRAY_SIZE*DATA_WIDTH");
end

endmodule
