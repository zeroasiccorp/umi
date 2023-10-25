`timescale 1ns / 1ps
`default_nettype none

module testbench #(
    parameter ODW       = 64,
    parameter TARGET    = "DEFAULT",   // pass through variable for hard macro
    parameter TIMEOUT   = 5000        // timeout value (cycles)
)
(
    input wire              clk,

    // TileLink
    input  wire             tl_a_ready,
    output wire             tl_a_valid,
    output wire [2:0]       tl_a_opcode,
    output wire [2:0]       tl_a_param,
    output wire [2:0]       tl_a_size,
    output wire [3:0]       tl_a_source,
    output wire [55:0]      tl_a_address,
    output wire [7:0]       tl_a_mask,
    output wire [ODW-1:0]   tl_a_data,
    output wire             tl_a_corrupt,

    output wire             tl_d_ready,
    input  wire             tl_d_valid,
    input  wire [2:0]       tl_d_opcode,
    input  wire [1:0]       tl_d_param,
    input  wire [2:0]       tl_d_size,
    input  wire [3:0]       tl_d_source,
    input  wire             tl_d_sink,
    input  wire             tl_d_denied,
    input  wire [ODW-1:0]   tl_d_data,
    input  wire             tl_d_corrupt
);

    parameter integer PERIOD_CLK = 10;
    parameter integer TCW        = 8;
    parameter integer IOW        = 64;
    parameter integer NUMI       = 2;

    // Local parameters
    localparam CW        = 32;
    localparam AW        = 64;
    localparam IDW       = 128;

    // SIM Ctrl signals
    wire            nreset;
    wire            go;
    reg  [15:0]     nreset_vec = 16'h00;

    // Reset initialization
    always @(posedge clk) begin
        nreset_vec <= {nreset_vec[15:0], 1'b1};
    end

    assign nreset = nreset_vec[14];
    assign go = nreset_vec[15];

    // control block
    initial begin
        if ($test$plusargs("trace")) begin
            $dumpfile("waveform.fst");
            $dumpvars();
        end
    end

    // DUT signals
    wire            umi_rx2dut_valid;
    wire [CW-1:0]   umi_rx2dut_cmd;
    wire [AW-1:0]   umi_rx2dut_dstaddr;
    wire [AW-1:0]   umi_rx2dut_srcaddr;
    wire [IDW-1:0]  umi_rx2dut_data;
    wire            umi_rx2dut_ready;

    wire            umi_dut2tx_valid;
    wire [CW-1:0]   umi_dut2tx_cmd;
    wire [AW-1:0]   umi_dut2tx_dstaddr;
    wire [AW-1:0]   umi_dut2tx_srcaddr;
    wire [IDW-1:0]  umi_dut2tx_data;
    wire            umi_dut2tx_ready;

    umi2tl_np #(
        .CW         (CW),
        .AW         (AW),
        .IDW        (IDW),
        .ODW        (ODW)
    ) dut (
        .clk                (clk),
        .nreset             (nreset),

        .tl_a_ready         (tl_a_ready),
        .tl_a_valid         (tl_a_valid),
        .tl_a_opcode        (tl_a_opcode),
        .tl_a_param         (tl_a_param),
        .tl_a_size          (tl_a_size),
        .tl_a_source        (tl_a_source),
        .tl_a_address       (tl_a_address),
        .tl_a_mask          (tl_a_mask),
        .tl_a_data          (tl_a_data),
        .tl_a_corrupt       (tl_a_corrupt),

        .tl_d_ready         (tl_d_ready),
        .tl_d_valid         (tl_d_valid),
        .tl_d_opcode        (tl_d_opcode),
        .tl_d_param         (tl_d_param),
        .tl_d_size          (tl_d_size),
        .tl_d_source        (tl_d_source),
        .tl_d_sink          (tl_d_sink),
        .tl_d_denied        (tl_d_denied),
        .tl_d_data          (tl_d_data),
        .tl_d_corrupt       (tl_d_corrupt),

        .udev_req_valid     (umi_rx2dut_valid),
        .udev_req_cmd       (umi_rx2dut_cmd),
        .udev_req_dstaddr   (umi_rx2dut_dstaddr),
        .udev_req_srcaddr   (umi_rx2dut_srcaddr),
        .udev_req_data      (umi_rx2dut_data),
        .udev_req_ready     (umi_rx2dut_ready),

        .udev_resp_valid    (umi_dut2tx_valid),
        .udev_resp_cmd      (umi_dut2tx_cmd),
        .udev_resp_dstaddr  (umi_dut2tx_dstaddr),
        .udev_resp_srcaddr  (umi_dut2tx_srcaddr),
        .udev_resp_data     (umi_dut2tx_data),
        .udev_resp_ready    (umi_dut2tx_ready)
    );

    umi_rx_sim #(
        .VALID_MODE_DEFAULT(2)
    ) umi_rx_i (
        .clk        (clk),

        .valid      (umi_rx2dut_valid),
        .cmd        (umi_rx2dut_cmd[CW-1:0]),
        .dstaddr    (umi_rx2dut_dstaddr[AW-1:0]),
        .srcaddr    (umi_rx2dut_srcaddr[AW-1:0]),
        .data       (umi_rx2dut_data[IDW-1:0]),
        .ready      (umi_rx2dut_ready)
    );

    umi_tx_sim #(
        .READY_MODE_DEFAULT(2)
    ) umi_tx_i (
        .clk        (clk),

        .valid      (umi_dut2tx_valid),
        .cmd        (umi_dut2tx_cmd),
        .dstaddr    (umi_dut2tx_dstaddr),
        .srcaddr    (umi_dut2tx_srcaddr),
        .data       ({128'd0, umi_dut2tx_data[127:0]}),
        .ready      (umi_dut2tx_ready)
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

   // auto-stop
   auto_stop_sim #(.CYCLES(50000)) auto_stop_sim_i (.clk(clk));

endmodule

`default_nettype wire
