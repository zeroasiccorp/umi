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
 * - Power domain isolation buffers testbench
 *
 ******************************************************************************/

`default_nettype none

module testbench (
`ifdef VERILATOR
    input clk
`endif
);

`include "switchboard.vh"

    parameter integer CW    = 32;
    parameter integer AW    = 64;
    parameter integer DW    = 256;
    parameter integer ISO   = 1;

    localparam PERIOD_CLK   = 10;
    localparam RST_CYCLES   = 16;

`ifndef VERILATOR
    // Generate clock for non verilator sim tools
    reg clk;

    initial
        clk  = 1'b0;
    always #(PERIOD_CLK/2) clk = ~clk;
`endif

    // Reset control
    reg [RST_CYCLES:0]      nreset_vec;
    wire                    nreset;
    wire                    initdone;

    assign nreset = nreset_vec[RST_CYCLES-1];
    assign initdone = nreset_vec[RST_CYCLES];

    initial
        nreset_vec = 'b1;
    always @(negedge clk) nreset_vec <= {nreset_vec[RST_CYCLES-1:0], 1'b1};

    wire            isolate;

    wire            umi_ready_iso;
    wire            umi_valid;
    wire [CW-1:0]   umi_cmd;
    wire [AW-1:0]   umi_dstaddr;
    wire [AW-1:0]   umi_srcaddr;
    wire [DW-1:0]   umi_data;

    wire            umi_ready;
    wire            umi_valid_iso;
    wire [CW-1:0]   umi_cmd_iso;
    wire [AW-1:0]   umi_dstaddr_iso;
    wire [AW-1:0]   umi_srcaddr_iso;
    wire [DW-1:0]   umi_data_iso;

   ///////////////////////////////////////////
   // Host side umi agents
   ///////////////////////////////////////////

    queue_to_umi_sim #(
        .VALID_MODE_DEFAULT(2),
        .DW(DW)
    ) host_umi_rx_i (
        .clk        (clk),

        .valid      (umi_valid),
        .cmd        (umi_cmd[CW-1:0]),
        .dstaddr    (umi_dstaddr[AW-1:0]),
        .srcaddr    (umi_srcaddr[AW-1:0]),
        .data       (umi_data[DW-1:0]),
        .ready      (umi_ready_iso & initdone)
    );

    umi_to_queue_sim #(
        .READY_MODE_DEFAULT(2),
        .DW(DW)
    ) host_umi_tx_i (
        .clk        (clk),

        .valid      (umi_valid_iso & initdone),
        .cmd        (umi_cmd_iso[CW-1:0]),
        .dstaddr    (umi_dstaddr_iso[AW-1:0]),
        .srcaddr    (umi_srcaddr_iso[AW-1:0]),
        .data       (umi_data_iso[DW-1:0]),
        .ready      (umi_ready)
    );

    // instantiate dut with UMI ports
    umi_isolate #(
        .CW     (CW),
        .AW     (AW),
        .DW     (DW),
        .ISO    (ISO)
    ) dut (
        .isolate            (1'b0),

        .umi_ready          (umi_ready & initdone),
        .umi_valid          (umi_valid & initdone),
        .umi_cmd            (umi_cmd),
        .umi_dstaddr        (umi_dstaddr),
        .umi_srcaddr        (umi_srcaddr),
        .umi_data           (umi_data),

        .umi_ready_iso      (umi_ready_iso),
        .umi_valid_iso      (umi_valid_iso),
        .umi_cmd_iso        (umi_cmd_iso),
        .umi_dstaddr_iso    (umi_dstaddr_iso),
        .umi_srcaddr_iso    (umi_srcaddr_iso),
        .umi_data_iso       (umi_data_iso)
    );

    // Initialize UMI
    integer valid_mode, ready_mode;

    initial begin
        /* verilator lint_off IGNOREDRETURN */
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
        /* verilator lint_on IGNOREDRETURN */
    end

    // waveform dump
    `SB_SETUP_PROBES

    // auto-stop
    auto_stop_sim auto_stop_sim_i (.clk(clk));

endmodule
// Local Variables:
// verilog-library-directories:("../rtl")
// End:

`default_nettype wire
