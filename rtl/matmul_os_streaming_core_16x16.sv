`timescale 1ns/1ps

// Continuous-K 16x16 output-stationary core.
// A complete K reduction is one run; there is no drain at each 16-vector bank.
// Final PE results are captured by row and streamed at 512 bits.
module matmul_os_streaming_core_16x16 #(
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

    input  wire [BUS_WIDTH-1:0]          i_a_data,
    input  wire                          i_a_valid,
    output wire                          o_a_ready,
    input  wire [BUS_WIDTH-1:0]          i_b_data,
    input  wire                          i_b_valid,
    output wire                          o_b_ready,

    output reg  [C_BUS_WIDTH-1:0]        o_c_data,
    output wire [$clog2(ARRAY_SIZE)-1:0] o_c_row,
    output wire                          o_c_valid,
    input  wire                          i_c_ready,
    output wire                          o_c_last,
    output reg                           o_compute_done,
    output wire                          o_done
);

localparam S_IDLE  = 2'd0;
localparam S_RUN   = 2'd1;
localparam S_DRAIN = 2'd2;

reg [1:0] state;
reg [31:0] k_size_reg;
reg [31:0] k_count;

reg [ARRAY_SIZE-1:0] row_valid;
reg [$clog2(ARRAY_SIZE)-1:0] read_row;
reg [ACC_WIDTH-1:0] c_bank [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];

wire start_fire;
wire vector_fire;
wire vector_first;
wire vector_last;
wire clear_data_path;
wire clear_acc;
wire [ARRAY_SIZE-1:0] vector_lane_valid;
wire [ARRAY_SIZE-1:0] vector_first_bus;
wire [ARRAY_SIZE-1:0] vector_last_bus;

wire [BUS_WIDTH-1:0] a_skewed;
wire [BUS_WIDTH-1:0] b_skewed;
wire [ARRAY_SIZE-1:0] a_skewed_valid;
wire [ARRAY_SIZE-1:0] b_skewed_valid;
wire [ARRAY_SIZE-1:0] first_skewed;
wire [ARRAY_SIZE-1:0] last_skewed;
wire [ARRAY_SIZE-1:0] first_skewed_valid;
wire [ARRAY_SIZE-1:0] last_skewed_valid;

wire [ARRAY_SIZE*ARRAY_SIZE*ACC_WIDTH-1:0] acc_flat;
wire [ARRAY_SIZE*ARRAY_SIZE*ACC_WIDTH-1:0] result_flat;
wire [ARRAY_SIZE*ARRAY_SIZE-1:0] result_valid;
wire array_active;
wire c_fire;

integer rr;
integer cc;
integer out_col;

assign o_start_ready = (state == S_IDLE) && (row_valid == 0);
assign o_busy         = (state != S_IDLE) || (row_valid != 0);
assign start_fire     = i_start && o_start_ready;

assign o_a_ready  = (state == S_RUN) && i_b_valid;
assign o_b_ready  = (state == S_RUN) && i_a_valid;
assign vector_fire  = (state == S_RUN) && i_a_valid && i_b_valid;
assign vector_first = vector_fire && (k_count == 0);
assign vector_last  = vector_fire && (k_count == k_size_reg-1'b1);

assign clear_data_path = start_fire;
assign clear_acc       = start_fire;
assign vector_lane_valid = {ARRAY_SIZE{vector_fire}};
assign vector_first_bus  = {ARRAY_SIZE{vector_first}};
assign vector_last_bus   = {ARRAY_SIZE{vector_last}};

assign o_c_row   = read_row;
assign o_c_valid = row_valid[read_row];
assign o_c_last  = o_c_valid && (read_row == ARRAY_SIZE-1);
assign c_fire    = o_c_valid && i_c_ready;
assign o_done    = c_fire && (read_row == ARRAY_SIZE-1);

always @(*) begin
    o_c_data = '0;
    for (out_col = 0; out_col < ARRAY_SIZE; out_col = out_col + 1) begin
        o_c_data[out_col*ACC_WIDTH +: ACC_WIDTH] =
            c_bank[read_row][out_col];
    end
end

lane_delay_unit #(
    .NUM_LANES(ARRAY_SIZE),
    .DATA_WIDTH(DATA_WIDTH)
) u_delay_a (
    .clk(clk),
    .rst_n(rst_n),
    .i_clear(clear_data_path),
    .i_data(i_a_data),
    .i_valid(vector_lane_valid),
    .o_data(a_skewed),
    .o_valid(a_skewed_valid)
);

lane_delay_unit #(
    .NUM_LANES(ARRAY_SIZE),
    .DATA_WIDTH(DATA_WIDTH)
) u_delay_b (
    .clk(clk),
    .rst_n(rst_n),
    .i_clear(clear_data_path),
    .i_data(i_b_data),
    .i_valid(vector_lane_valid),
    .o_data(b_skewed),
    .o_valid(b_skewed_valid)
);

lane_delay_unit #(
    .NUM_LANES(ARRAY_SIZE),
    .DATA_WIDTH(1)
) u_delay_first (
    .clk(clk),
    .rst_n(rst_n),
    .i_clear(clear_data_path),
    .i_data(vector_first_bus),
    .i_valid(vector_lane_valid),
    .o_data(first_skewed),
    .o_valid(first_skewed_valid)
);

lane_delay_unit #(
    .NUM_LANES(ARRAY_SIZE),
    .DATA_WIDTH(1)
) u_delay_last (
    .clk(clk),
    .rst_n(rst_n),
    .i_clear(clear_data_path),
    .i_data(vector_last_bus),
    .i_valid(vector_lane_valid),
    .o_data(last_skewed),
    .o_valid(last_skewed_valid)
);

os_pe_array_stream_16x16 #(
    .ARRAY_SIZE(ARRAY_SIZE),
    .DATA_WIDTH(DATA_WIDTH),
    .ACC_WIDTH(ACC_WIDTH),
    .NUM_DSP_PE(NUM_DSP_PE)
) u_pe_array (
    .clk(clk),
    .rst_n(rst_n),
    .i_clear_data(clear_data_path),
    .i_clear_acc(clear_acc),
    .i_a_vector(a_skewed),
    .i_a_valid(a_skewed_valid),
    .i_a_first(first_skewed),
    .i_a_last(last_skewed),
    .i_b_vector(b_skewed),
    .i_b_valid(b_skewed_valid),
    .i_b_first(first_skewed),
    .i_b_last(last_skewed),
    .o_acc_flat(acc_flat),
    .o_result_flat(result_flat),
    .o_result_valid(result_valid),
    .o_active(array_active)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state          <= S_IDLE;
        k_size_reg     <= 32'd16;
        k_count        <= '0;
        row_valid      <= '0;
        read_row       <= '0;
        o_compute_done <= 1'b0;
    end else begin
        o_compute_done <= 1'b0;

        // Capture every PE final result.  PE(r,15) marks the complete row.
        for (rr = 0; rr < ARRAY_SIZE; rr = rr + 1) begin
            for (cc = 0; cc < ARRAY_SIZE; cc = cc + 1) begin
                if (result_valid[rr*ARRAY_SIZE+cc]) begin
                    c_bank[rr][cc] <=
                        result_flat[(rr*ARRAY_SIZE+cc)*ACC_WIDTH +: ACC_WIDTH];
                end
            end
            if (result_valid[rr*ARRAY_SIZE+ARRAY_SIZE-1])
                row_valid[rr] <= 1'b1;
        end

        // Independent 512-bit row output. It may drain while computation runs.
        if (c_fire) begin
            row_valid[read_row] <= 1'b0;

            if (read_row == ARRAY_SIZE-1) begin
                read_row  <= '0;
            end else begin
                read_row <= read_row + 1'b1;
            end
        end

        case (state)
            S_IDLE: begin
                k_count <= '0;
                if (start_fire) begin
                    k_size_reg  <= i_k_size;
                    row_valid   <= '0;
                    state <= S_RUN;
                end
            end

            S_RUN: begin
                if (vector_fire) begin
                    if (vector_last) begin
                        k_count <= '0;
                        state <= S_DRAIN;
                    end else begin
                        k_count <= k_count + 1'b1;
                    end
                end
            end

            S_DRAIN: begin
                if (!array_active) begin
                    o_compute_done <= 1'b1;
                    state <= S_IDLE;
                end
            end

            default: state <= S_IDLE;
        endcase
    end
end

initial begin
    if (BUS_WIDTH != ARRAY_SIZE*DATA_WIDTH)
        $error("BUS_WIDTH must equal ARRAY_SIZE*DATA_WIDTH");
    if (C_BUS_WIDTH != ARRAY_SIZE*ACC_WIDTH)
        $error("C_BUS_WIDTH must equal ARRAY_SIZE*ACC_WIDTH");
end

endmodule
