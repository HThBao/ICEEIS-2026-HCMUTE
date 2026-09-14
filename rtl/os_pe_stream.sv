`timescale 1ns/1ps

// Output-stationary PE with first/last-K tags.
// The final psum is registered when the last K operand pair reaches this PE.
module os_pe_stream #(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 32,
    parameter USE_DSP    = 1
) (
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          i_clear_data,
    input  wire                          i_clear_acc,

    input  wire signed [DATA_WIDTH-1:0]  i_a,
    input  wire                          i_a_valid,
    input  wire                          i_a_first,
    input  wire                          i_a_last,
    input  wire signed [DATA_WIDTH-1:0]  i_b,
    input  wire                          i_b_valid,
    input  wire                          i_b_first,
    input  wire                          i_b_last,

    output reg signed [DATA_WIDTH-1:0]   o_a,
    output reg                           o_a_valid,
    output reg                           o_a_first,
    output reg                           o_a_last,
    output reg signed [DATA_WIDTH-1:0]   o_b,
    output reg                           o_b_valid,
    output reg                           o_b_first,
    output reg                           o_b_last,

    output reg signed [ACC_WIDTH-1:0]    o_acc,
    output wire signed [ACC_WIDTH-1:0]   o_result,
    output reg                           o_result_valid
);

wire signed [(2*DATA_WIDTH)-1:0] product;
wire signed [ACC_WIDTH-1:0] product_ext;
wire signed [ACC_WIDTH-1:0] accumulated_sum;
wire operand_fire;
wire first_fire;
wire last_fire;

generate
    if (USE_DSP != 0) begin : g_dsp_multiplier
        (* multstyle = "dsp" *) wire signed [(2*DATA_WIDTH)-1:0] product_impl;
        assign product_impl = i_a * i_b;
        assign product = product_impl;
    end else begin : g_logic_multiplier
        (* multstyle = "logic" *) wire signed [(2*DATA_WIDTH)-1:0] product_impl;
        assign product_impl = i_a * i_b;
        assign product = product_impl;
    end
endgenerate

assign product_ext = {{(ACC_WIDTH-(2*DATA_WIDTH)){product[2*DATA_WIDTH-1]}},
                      product};
assign operand_fire   = i_a_valid && i_b_valid;
assign first_fire     = operand_fire && i_a_first && i_b_first;
assign last_fire      = operand_fire && i_a_last && i_b_last;
assign accumulated_sum = first_fire ? product_ext : (o_acc + product_ext);
assign o_result = o_acc;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        o_a            <= '0;
        o_a_valid      <= 1'b0;
        o_a_first      <= 1'b0;
        o_a_last       <= 1'b0;
        o_b            <= '0;
        o_b_valid      <= 1'b0;
        o_b_first      <= 1'b0;
        o_b_last       <= 1'b0;
        o_acc          <= '0;
        o_result_valid <= 1'b0;
    end else begin
        o_result_valid <= 1'b0;

        if (i_clear_data) begin
            o_a       <= '0;
            o_a_valid <= 1'b0;
            o_a_first <= 1'b0;
            o_a_last  <= 1'b0;
            o_b       <= '0;
            o_b_valid <= 1'b0;
            o_b_first <= 1'b0;
            o_b_last  <= 1'b0;
        end else begin
            o_a       <= i_a;
            o_a_valid <= i_a_valid;
            o_a_first <= i_a_first;
            o_a_last  <= i_a_last;
            o_b       <= i_b;
            o_b_valid <= i_b_valid;
            o_b_first <= i_b_first;
            o_b_last  <= i_b_last;
        end

        if (i_clear_acc) begin
            o_acc <= '0;
        end else if (operand_fire) begin
            o_acc <= accumulated_sum;
            if (last_fire) begin
                o_result_valid <= 1'b1;
            end
        end
    end
end

initial begin
    if (ACC_WIDTH < 2*DATA_WIDTH)
        $error("ACC_WIDTH must be at least 2*DATA_WIDTH");
end

endmodule
