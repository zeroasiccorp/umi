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
    localparam CW        = 32;          // UMI width
    localparam AW        = 64;          // UMI width
    localparam IDW       = 128;
    localparam ODW       = 512;

    // SIM Ctrl signals
    wire            nreset;
    wire            go;
    reg  [15:0]     nreset_vec = 16'h0000;

    // Reset initialization
    always @(posedge clk) begin
        nreset_vec <= {nreset_vec[14:0], 1'b1};
    end

    assign nreset = nreset_vec[14];
    assign go = nreset_vec[15];

    // DUT signals
    wire            umi_stim2dut_valid;
    wire [CW-1:0]   umi_stim2dut_cmd;
    wire [AW-1:0]   umi_stim2dut_dstaddr;
    wire [AW-1:0]   umi_stim2dut_srcaddr;
    wire [IDW-1:0]  umi_stim2dut_data;
    wire            umi_stim2dut_ready;

    wire            umi_dut2check_valid;
    wire [CW-1:0]   umi_dut2check_cmd;
    wire [AW-1:0]   umi_dut2check_dstaddr;
    wire [AW-1:0]   umi_dut2check_srcaddr;
    wire [ODW-1:0]  umi_dut2check_data;
    reg             umi_dut2check_ready;

    always @(posedge clk or negedge nreset) begin
        if(~nreset)
            umi_dut2check_ready <= 1'b0;
        else
            umi_dut2check_ready <= ~umi_dut2check_ready;
    end

    umi_packet_merge_greedy #(
        .CW         (CW),
        .AW         (AW),
        .IDW        (IDW),
        .ODW        (ODW)
    ) dut (
        .clk                (clk),
        .nreset             (nreset),

        .umi_in_valid       (umi_stim2dut_valid),
        .umi_in_cmd         (umi_stim2dut_cmd),
        .umi_in_dstaddr     (umi_stim2dut_dstaddr),
        .umi_in_srcaddr     (umi_stim2dut_srcaddr),
        .umi_in_data        (umi_stim2dut_data),
        .umi_in_ready       (umi_stim2dut_ready),

        .umi_out_valid      (umi_dut2check_valid),
        .umi_out_cmd        (umi_dut2check_cmd),
        .umi_out_dstaddr    (umi_dut2check_dstaddr),
        .umi_out_srcaddr    (umi_dut2check_srcaddr),
        .umi_out_data       (umi_dut2check_data),
        .umi_out_ready      (umi_dut2check_ready)
    );

    queue_to_umi_sim #(
        .VALID_MODE_DEFAULT(2)
    ) umi_rx_i (
        .clk        (clk),

        .valid      (umi_stim2dut_valid),
        .cmd        (umi_stim2dut_cmd[CW-1:0]),
        .dstaddr    (umi_stim2dut_dstaddr[AW-1:0]),
        .srcaddr    (umi_stim2dut_srcaddr[AW-1:0]),
        .data       (umi_stim2dut_data[IDW-1:0]),
        .ready      (umi_stim2dut_ready)
    );

    // Initialize UMI
    integer valid_mode, ready_mode;

    initial begin
        if (!$value$plusargs("valid_mode=%d", valid_mode)) begin
            valid_mode = 2;  // default if not provided as a plusarg
        end

        umi_rx_i.init("client2rtl_0.q");
        umi_rx_i.set_valid_mode(valid_mode);
    end

    // control block
    `SB_SETUP_PROBES

    // auto-stop
    auto_stop_sim #(.CYCLES(50000)) auto_stop_sim_i (.clk(clk));

endmodule

`default_nettype wire
