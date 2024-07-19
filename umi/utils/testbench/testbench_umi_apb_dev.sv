/*******************************************************************************
 * Copyright 2024 Zero ASIC Corporation
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * ----
 *
 * Documentation:
 * - UMI to APB converter testbench
 *
 ******************************************************************************/

`default_nettype none

`include "switchboard.vh"

module testbench (
    input clk
);

    parameter integer APB_AW    = 32;
    parameter integer AW        = 64;
    parameter integer CW        = 32;
    parameter integer DW        = 256;
    parameter integer RW        = 32;
    parameter integer CTRLW     = 8;
    parameter integer RAMDEPTH  = 512;

    reg  [15:0]     nreset_vec;
    wire            nreset;

    assign nreset = nreset_vec[1];

    initial begin
         nreset_vec = 16'b1;
    end

    always @(negedge clk)
        nreset_vec <= {nreset_vec[14:0], 1'b1};

    wire                udev_req_valid;
    wire [CW-1:0]       udev_req_cmd;
    wire [AW-1:0]       udev_req_dstaddr;
    wire [AW-1:0]       udev_req_srcaddr;
    wire [DW-1:0]       udev_req_data;
    wire                udev_req_ready;

    wire                udev_resp_valid;
    wire [CW-1:0]       udev_resp_cmd;
    wire [AW-1:0]       udev_resp_dstaddr;
    wire [AW-1:0]       udev_resp_srcaddr;
    wire [DW-1:0]       udev_resp_data;
    wire                udev_resp_ready;

    wire [APB_AW-1:0]   paddr;
    wire [2:0]          pprot;
    wire                psel;
    wire                penable;
    wire                pwrite;
    wire [RW-1:0]       pwdata;
    wire [(RW/8)-1:0]   pwstrb;
    wire                pready;
    wire [RW-1:0]       prdata;
    wire                pslverr;
    reg                 randomize_ready;

    umi_apb_dev #(
        .APB_AW (APB_AW),
        .AW     (AW),
        .CW     (CW),
        .DW     (DW),
        .RW     (RW)
    ) dut (
        .clk                (clk),
        .nreset             (nreset),

        .udev_req_valid     (udev_req_valid),
        .udev_req_cmd       (udev_req_cmd),
        .udev_req_dstaddr   (udev_req_dstaddr),
        .udev_req_srcaddr   (udev_req_srcaddr),
        .udev_req_data      (udev_req_data),
        .udev_req_ready     (udev_req_ready),

        .udev_resp_valid    (udev_resp_valid),
        .udev_resp_cmd      (udev_resp_cmd),
        .udev_resp_dstaddr  (udev_resp_dstaddr),
        .udev_resp_srcaddr  (udev_resp_srcaddr),
        .udev_resp_data     (udev_resp_data),
        .udev_resp_ready    (udev_resp_ready),

        .paddr              (paddr),
        .pprot              (pprot),
        .psel               (psel),
        .penable            (penable),
        .pwrite             (pwrite),
        .pwdata             (pwdata),
        .pwstrb             (pwstrb),
        .pready             (pready),
        .prdata             (prdata),
        .pslverr            (pslverr));

    wire [CTRLW-1:0]  sram_ctrl = 8'b0;

    la_spram #(
        .DW    (RW),
        .AW    ($clog2(RAMDEPTH)),
        .CTRLW (CTRLW),
        .TESTW (128)
    ) la_spram_i(
        // Outputs
        .dout             (prdata),
        // Inputs
        .clk              (clk),
        .ce               (psel),
        .we               (pwrite),
        .wmask            ({RW{1'b1}}),
        .addr             (paddr[$clog2(RW) +: $clog2(RAMDEPTH)]),
        .din              (pwdata),
        .vss              (1'b0),
        .vdd              (1'b1),
        .vddio            (1'b1),
        .ctrl             (sram_ctrl),
        .test             (128'h0));

    assign pready = psel & penable & randomize_ready;

    /* verilator lint_off WIDTHTRUNC */
    always @(posedge clk or negedge nreset) begin
        if (~nreset)
            randomize_ready <= 1'b0;
        else
            randomize_ready <= $random%2;
    end
    /* verilator lint_on WIDTHTRUNC */

   ///////////////////////////////////////////
   // Host side umi agents
   ///////////////////////////////////////////

    umi_rx_sim #(
        .VALID_MODE_DEFAULT (2),
        .DW                 (DW)
    ) host_umi_rx_i (
        .clk        (clk),
        .valid      (udev_req_valid),
        .cmd        (udev_req_cmd[CW-1:0]),
        .dstaddr    (udev_req_dstaddr[AW-1:0]),
        .srcaddr    (udev_req_srcaddr[AW-1:0]),
        .data       (udev_req_data[DW-1:0]),
        .ready      (udev_req_ready));

    umi_tx_sim #(
        .READY_MODE_DEFAULT (2),
        .DW                 (DW)
    ) host_umi_tx_i (
        .clk        (clk),
        .valid      (udev_resp_valid),
        .cmd        (udev_resp_cmd[CW-1:0]),
        .dstaddr    (udev_resp_dstaddr[AW-1:0]),
        .srcaddr    (udev_resp_srcaddr[AW-1:0]),
        .data       (udev_resp_data[DW-1:0]),
        .ready      (udev_resp_ready)
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

        host_umi_rx_i.init("host2dut_0.q");
        host_umi_rx_i.set_valid_mode(valid_mode);

        host_umi_tx_i.init("dut2host_0.q");
        host_umi_tx_i.set_ready_mode(ready_mode);
    end

    // control block
    `SB_SETUP_PROBES

    // auto-stop
    auto_stop_sim auto_stop_sim_i (.clk(clk));

endmodule
// Local Variables:
// verilog-library-directories:("../rtl")
// End:

`default_nettype wire
