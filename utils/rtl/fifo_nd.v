/******************************************************************************
 * Function:  First word fall through FIFO
 * Author:    Wenting Zhang
 * Copyright: 2022 Zero ASIC Corporation. All rights reserved.
 * License:
 *
 * Documentation:
 *   1-cycle latency. Does not use SRAM macro, only for small size data.
 *
 *****************************************************************************/
module fifo_nd (clk, rst, a_data, a_valid, a_ready, a_almost_full, a_full,
        b_data, b_valid, b_ready);

    parameter WIDTH = 64;
    parameter ABITS = 2;
    localparam DEPTH = (1 << ABITS);

    input  wire             clk;
    input  wire             rst;
    input  wire [WIDTH-1:0] a_data;
    input  wire             a_valid;
    output wire             a_ready;
    output wire             a_almost_full;
    output wire             a_full;
    output wire [WIDTH-1:0] b_data;
    output wire             b_valid;
    input  wire             b_ready;

    reg [WIDTH-1:0] fifo [0:DEPTH-1];
    reg [ABITS:0] fifo_level;
    reg [ABITS-1:0] wr_ptr;
    reg [ABITS-1:0] rd_ptr;

    wire a_active = a_ready && a_valid;
    wire b_active = b_ready && b_valid;

    wire fifo_empty = fifo_level == 0;
    wire fifo_almost_full = fifo_level == DEPTH - 1;
    wire fifo_full = fifo_level == DEPTH;

    always @(posedge clk) begin
        if (a_ready && a_valid)
            fifo[wr_ptr] <= a_data;
        if (a_active && !b_active)
            fifo_level <= fifo_level + 1;
        else if (!a_active && b_active)
            fifo_level <= fifo_level - 1;
        if (a_active)
            wr_ptr <= wr_ptr + 1;
        if (b_active)
            rd_ptr <= rd_ptr + 1;
        
        if (rst) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            fifo_level <= 0;
        end
    end
    assign b_valid = !fifo_empty;
    assign b_data = fifo[rd_ptr];
    assign a_ready = !fifo_full;
    assign a_almost_full = fifo_almost_full && !b_ready;
    assign a_full = fifo_full;

endmodule
