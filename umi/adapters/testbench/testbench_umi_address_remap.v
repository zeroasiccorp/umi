`timescale 1ns / 1ps
`default_nettype none

`include "switchboard.vh"

module testbench #(
    parameter TARGET     = "DEFAULT",   // pass through variable for hard macro
    parameter TIMEOUT    = 5000        // timeout value (cycles)
)
(
    input clk
);

    parameter integer PERIOD_CLK = 10;
    parameter integer TCW        = 8;
    parameter integer IOW        = 64;
    parameter integer NUMI       = 2;

    // Local parameters
    localparam CW       = 32;          // UMI width
    localparam AW       = 64;          // UMI width
    localparam DW       = 256;
    localparam IDW      = 16;
    localparam IDSB     = 40;
    localparam NMAPS    = 8;

    genvar i;
    wire [IDW*NMAPS-1:0]  old_row_col_address;
    wire [IDW*NMAPS-1:0]  new_row_col_address;

    generate
        for (i = 0; i < NMAPS; i = i + 1) begin
            assign old_row_col_address[(IDW*(i+1))-1 : (IDW*i)] = i;
            assign new_row_col_address[(IDW*(i+1))-1 : (IDW*i)] = ~i;
        end
    endgenerate

    // DUT signals
    wire            umi_stim2dut_valid;
    wire [CW-1:0]   umi_stim2dut_cmd;
    wire [AW-1:0]   umi_stim2dut_dstaddr;
    wire [AW-1:0]   umi_stim2dut_srcaddr;
    wire [DW-1:0]   umi_stim2dut_data;
    wire            umi_stim2dut_ready;

    wire            umi_dut2check_valid;
    wire [CW-1:0]   umi_dut2check_cmd;
    wire [AW-1:0]   umi_dut2check_dstaddr;
    wire [AW-1:0]   umi_dut2check_srcaddr;
    wire [DW-1:0]   umi_dut2check_data;
    wire            umi_dut2check_ready;

    umi_address_remap #(
        .CW         (CW),
        .AW         (AW),
        .DW         (DW),
        .IDW        (IDW),
        .IDSB       (IDSB),
        .NMAPS      (NMAPS)
    ) dut (
        .chipid                 (16'h0004),

        .old_row_col_address    (old_row_col_address),
        .new_row_col_address    (new_row_col_address),

        .set_dstaddress_low     (64'h0000_0600_0000_0080),
        .set_dstaddress_high    (64'h0000_06FF_FFFF_FFFF),
        .set_dstaddress_offset  (64'hFFFF_FFFF_FFFF_FF80),

        .umi_in_valid           (umi_stim2dut_valid),
        .umi_in_cmd             (umi_stim2dut_cmd),
        .umi_in_dstaddr         (umi_stim2dut_dstaddr),
        .umi_in_srcaddr         (umi_stim2dut_srcaddr),
        .umi_in_data            (umi_stim2dut_data[DW-1:0]),
        .umi_in_ready           (umi_stim2dut_ready),

        .umi_out_valid          (umi_dut2check_valid),
        .umi_out_cmd            (umi_dut2check_cmd),
        .umi_out_dstaddr        (umi_dut2check_dstaddr),
        .umi_out_srcaddr        (umi_dut2check_srcaddr),
        .umi_out_data           (umi_dut2check_data),
        .umi_out_ready          (umi_dut2check_ready)
    );

    queue_to_umi_sim #(
        .VALID_MODE_DEFAULT(2)
    ) umi_rx_i (
        .clk        (clk),

        .valid      (umi_stim2dut_valid),
        .cmd        (umi_stim2dut_cmd[CW-1:0]),
        .dstaddr    (umi_stim2dut_dstaddr[AW-1:0]),
        .srcaddr    (umi_stim2dut_srcaddr[AW-1:0]),
        .data       (umi_stim2dut_data),
        .ready      (umi_stim2dut_ready)
    );

    umi_to_queue_sim #(
        .READY_MODE_DEFAULT(2)
    ) umi_tx_i (
        .clk        (clk),

        .valid      (umi_dut2check_valid),
        .cmd        (umi_dut2check_cmd),
        .dstaddr    (umi_dut2check_dstaddr),
        .srcaddr    (umi_dut2check_srcaddr),
        .data       (umi_dut2check_data),
        .ready      (umi_dut2check_ready)
    );

    // Initialize UMI
    integer valid_mode, ready_mode;

    initial begin
        if (!$value$plusargs("valid_mode=%d", valid_mode)) begin
            valid_mode = 2;  // default if not provided as a plusarg
        end

        if (!$value$plusargs("ready_mode=%d", ready_mode)) begin
            ready_mode = 2;  // default if not provided as a plusarg
        end

        umi_rx_i.init("client2rtl_0.q");
        umi_rx_i.set_valid_mode(valid_mode);

        umi_tx_i.init("rtl2client_0.q");
        umi_tx_i.set_ready_mode(ready_mode);
    end

    // control block
    `SB_SETUP_PROBES

    // auto-stop
    auto_stop_sim auto_stop_sim_i (.clk(clk));

endmodule

`default_nettype wire
