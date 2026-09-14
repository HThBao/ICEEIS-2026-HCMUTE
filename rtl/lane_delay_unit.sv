`timescale 1ns/1ps

// Lane n is delayed by n cycles. Applying the same rule to the A row lanes
// and B column lanes makes matching k operands meet at PE[row][col].
module lane_delay_unit #(
    parameter NUM_LANES  = 16,
    parameter DATA_WIDTH = 8
) (
    input  wire                                   clk,
    input  wire                                   rst_n,
    input  wire                                   i_clear,
    input  wire [NUM_LANES*DATA_WIDTH-1:0]       i_data,
    input  wire [NUM_LANES-1:0]                  i_valid,
    output wire [NUM_LANES*DATA_WIDTH-1:0]       o_data,
    output wire [NUM_LANES-1:0]                  o_valid
);

    reg [DATA_WIDTH-1:0] data_pipe  [0:NUM_LANES-1][0:NUM_LANES-1];
    reg                  valid_pipe [0:NUM_LANES-1][0:NUM_LANES-1];

    genvar lane;
    generate
        for (lane = 0; lane < NUM_LANES; lane = lane + 1) begin : g_lane
            if (lane == 0) begin : g_no_delay
                assign o_data[0 +: DATA_WIDTH] = i_data[0 +: DATA_WIDTH];
                assign o_valid[0]              = i_valid[0];
            end else begin : g_delay
                integer stage;
                always @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        for (stage = 0; stage < lane; stage = stage + 1) begin
                            data_pipe[lane][stage]  <= '0;
                            valid_pipe[lane][stage] <= 1'b0;
                        end
                    end else if (i_clear) begin
                        for (stage = 0; stage < lane; stage = stage + 1) begin
                            data_pipe[lane][stage]  <= '0;
                            valid_pipe[lane][stage] <= 1'b0;
                        end
                    end else begin
                        data_pipe[lane][0]  <= i_data[lane*DATA_WIDTH +: DATA_WIDTH];
                        valid_pipe[lane][0] <= i_valid[lane];
                        for (stage = 1; stage < lane; stage = stage + 1) begin
                            data_pipe[lane][stage]  <= data_pipe[lane][stage-1];
                            valid_pipe[lane][stage] <= valid_pipe[lane][stage-1];
                        end
                    end
                end

                assign o_data[lane*DATA_WIDTH +: DATA_WIDTH] = data_pipe[lane][lane-1];
                assign o_valid[lane] = valid_pipe[lane][lane-1];
            end
        end
    endgenerate

endmodule
