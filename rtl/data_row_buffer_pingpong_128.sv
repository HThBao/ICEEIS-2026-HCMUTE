`timescale 1ns/1ps

// Two-bank B row buffer.
// One bank exports B[k,:] while the other bank loads the following 16 rows.
module data_row_buffer_pingpong_128 #(
    parameter ARRAY_SIZE = 16,
    parameter DATA_WIDTH = 8,
    parameter BUS_WIDTH  = ARRAY_SIZE*DATA_WIDTH
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

reg [BUS_WIDTH-1:0] bank0 [0:ARRAY_SIZE-1];
reg [BUS_WIDTH-1:0] bank1 [0:ARRAY_SIZE-1];
reg [1:0] bank_full;
reg write_bank;
reg read_bank;
reg [$clog2(ARRAY_SIZE)-1:0] write_row;
reg [$clog2(ARRAY_SIZE)-1:0] read_row;

wire load_fire;
wire export_fire;

assign o_ready       = !bank_full[write_bank];
assign o_valid       = bank_full[read_bank];
assign o_data        = read_bank ? bank1[read_row] : bank0[read_row];
assign load_fire     = i_valid && o_ready;
assign export_fire   = o_valid && i_ready;
assign o_block_first = o_valid && (read_row == 0);
assign o_block_last  = o_valid && (read_row == ARRAY_SIZE-1);
assign o_busy        = (bank_full != 0) || (write_row != 0);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        bank_full  <= 2'b00;
        write_bank <= 1'b0;
        read_bank  <= 1'b0;
        write_row  <= '0;
        read_row   <= '0;
    end else if (i_clear) begin
        bank_full  <= 2'b00;
        write_bank <= 1'b0;
        read_bank  <= 1'b0;
        write_row  <= '0;
        read_row   <= '0;
    end else begin
        if (export_fire) begin
            if (read_row == ARRAY_SIZE-1) begin
                bank_full[read_bank] <= 1'b0;
                read_bank <= !read_bank;
                read_row  <= '0;
            end else begin
                read_row <= read_row + 1'b1;
            end
        end

        if (load_fire) begin
            if (write_bank == 1'b0)
                bank0[write_row] <= i_data;
            else
                bank1[write_row] <= i_data;

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
