/*******************************************************************************
 * Copyright 2023 Zero ASIC Corporation
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
 * - Simple fifo testbench
 *
 ******************************************************************************/

`default_nettype none

module testbench (
`ifdef VERILATOR
    input clk
`endif
);

`include "switchboard.vh"

   parameter integer DW=128;
   parameter integer AW=64;
   parameter integer CW=32;
   parameter integer CTRLW=8;
   parameter integer DEPTH=4;

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
   reg [RST_CYCLES:0]   nreset_vec;
   wire                 nreset;
   wire                 initdone;

   assign nreset = nreset_vec[RST_CYCLES-1];
   assign initdone = nreset_vec[RST_CYCLES];

   initial
      nreset_vec = 'b1;
   always @(negedge clk) nreset_vec <= {nreset_vec[RST_CYCLES-1:0], 1'b1};

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [CW-1:0]        umi_req_out_cmd;
   wire [DW-1:0]        umi_req_out_data;
   wire [AW-1:0]        umi_req_out_dstaddr;
   wire                 umi_req_out_ready;
   wire [AW-1:0]        umi_req_out_srcaddr;
   wire                 umi_req_out_valid;
   wire [CW-1:0]        umi_resp_in_cmd;
   wire [DW-1:0]        umi_resp_in_data;
   wire [AW-1:0]        umi_resp_in_dstaddr;
   wire                 umi_resp_in_ready;
   wire [AW-1:0]        umi_resp_in_srcaddr;
   wire                 umi_resp_in_valid;
   // End of automatics

   wire [CTRLW-1:0]  sram_ctrl = 8'b0;

   wire              umi_resp_out_ready;
   wire [CW-1:0]     umi_resp_out_cmd;
   wire [DW-1:0]     umi_resp_out_data;
   wire [AW-1:0]     umi_resp_out_dstaddr;
   wire [AW-1:0]     umi_resp_out_srcaddr;
   wire              umi_resp_out_valid;

   wire              umi_req_in_ready;
   wire [CW-1:0]     umi_req_in_cmd;
   wire [DW-1:0]     umi_req_in_data;
   wire [AW-1:0]     umi_req_in_dstaddr;
   wire [AW-1:0]     umi_req_in_srcaddr;
   wire              umi_req_in_valid;

   ///////////////////////////////////////////
   // Host side umi agents
   ///////////////////////////////////////////

   queue_to_umi_sim #(
                .VALID_MODE_DEFAULT(2),
                .DW(DW)
                )
   host_umi_rx_i (.clk(clk),
                  .reset(~nreset),
                  .data(umi_req_in_data[DW-1:0]),
                  .srcaddr(umi_req_in_srcaddr[AW-1:0]),
                  .dstaddr(umi_req_in_dstaddr[AW-1:0]),
                  .cmd(umi_req_in_cmd[CW-1:0]),
                  .ready(umi_req_in_ready & initdone),
                  .valid(umi_req_in_valid)
                  );

   umi_to_queue_sim #(
                .READY_MODE_DEFAULT(2),
                .DW(DW)
                )
   host_umi_tx_i (.clk(clk),
                  .reset(~nreset),
                  .data(umi_resp_out_data[DW-1:0]),
                  .srcaddr(umi_resp_out_srcaddr[AW-1:0]),
                  .dstaddr(umi_resp_out_dstaddr[AW-1:0]),
                  .cmd(umi_resp_out_cmd[CW-1:0]),
                  .ready(umi_resp_out_ready),
                  .valid(umi_resp_out_valid & initdone)
                  );

   // instantiate dut with UMI ports
   /* umi_fifo AUTO_TEMPLATE(
    .umi_.*_clk     (clk),
    .umi_.*_nreset  (nreset),
    .umi_in_valid   (umi_req_in_valid & initdone),
    .umi_in_\(.*\)  (umi_req_in_\1[]),
    .umi_out_\(.*\) (umi_req_out_\1[]),
    .bypass         ('b0),
    .chaosmode      ('b0),
    .v.*            (),
    .fifo_.*        (),
    );*/
   umi_fifo #(.DW(DW),
              .CW(CW),
              .AW(AW),
              .DEPTH(DEPTH))
   umi_fifo_rx_i(/*AUTOINST*/
                 // Outputs
                 .fifo_full             (),                      // Templated
                 .fifo_almost_full      (),
                 .fifo_empty            (),                      // Templated
                 .umi_in_ready          (umi_req_in_ready),      // Templated
                 .umi_out_valid         (umi_req_out_valid),     // Templated
                 .umi_out_cmd           (umi_req_out_cmd[CW-1:0]), // Templated
                 .umi_out_dstaddr       (umi_req_out_dstaddr[AW-1:0]), // Templated
                 .umi_out_srcaddr       (umi_req_out_srcaddr[AW-1:0]), // Templated
                 .umi_out_data          (umi_req_out_data[DW-1:0]), // Templated
                 // Inputs
                 .bypass                ('b0),                   // Templated
                 .chaosmode             ('b0),                   // Templated
                 .umi_in_clk            (clk),                   // Templated
                 .umi_in_nreset         (nreset),                // Templated
                 .umi_in_valid          (umi_req_in_valid & initdone), // Templated
                 .umi_in_cmd            (umi_req_in_cmd[CW-1:0]), // Templated
                 .umi_in_dstaddr        (umi_req_in_dstaddr[AW-1:0]), // Templated
                 .umi_in_srcaddr        (umi_req_in_srcaddr[AW-1:0]), // Templated
                 .umi_in_data           (umi_req_in_data[DW-1:0]), // Templated
                 .umi_out_clk           (clk),                   // Templated
                 .umi_out_nreset        (nreset),                // Templated
                 .umi_out_ready         (umi_req_out_ready),     // Templated
                 .vdd                   (),                      // Templated
                 .vss                   ());                     // Templated

   /* umi_memagent AUTO_TEMPLATE(
    .udev_req_\(.*\)  (umi_req_out_\1[]),
    .udev_resp_\(.*\) (umi_resp_in_\1[]),
    );*/

   umi_memagent #(.CW(CW),
                   .AW(AW),
                   .DW(DW),
                   .CTRLW(CTRLW))
   umi_memagent_i(/*AUTOINST*/
                   // Outputs
                   .udev_req_ready      (umi_req_out_ready),     // Templated
                   .udev_resp_valid     (umi_resp_in_valid),     // Templated
                   .udev_resp_cmd       (umi_resp_in_cmd[CW-1:0]), // Templated
                   .udev_resp_dstaddr   (umi_resp_in_dstaddr[AW-1:0]), // Templated
                   .udev_resp_srcaddr   (umi_resp_in_srcaddr[AW-1:0]), // Templated
                   .udev_resp_data      (umi_resp_in_data[DW-1:0]), // Templated
                   // Inputs
                   .clk                 (clk),
                   .nreset              (nreset),
                   .sram_ctrl           (sram_ctrl[CTRLW-1:0]),
                   .udev_req_valid      (umi_req_out_valid),     // Templated
                   .udev_req_cmd        (umi_req_out_cmd[CW-1:0]), // Templated
                   .udev_req_dstaddr    (umi_req_out_dstaddr[AW-1:0]), // Templated
                   .udev_req_srcaddr    (umi_req_out_srcaddr[AW-1:0]), // Templated
                   .udev_req_data       (umi_req_out_data[DW-1:0]), // Templated
                   .udev_resp_ready     (umi_resp_in_ready));    // Templated

   /* umi_fifo AUTO_TEMPLATE(
    .umi_.*_clk     (clk),
    .umi_.*_nreset  (nreset),
    .umi_in_\(.*\)  (umi_resp_in_\1[]),
    .umi_out_ready  (umi_resp_out_ready & initdone),
    .umi_out_\(.*\) (umi_resp_out_\1[]),
    .bypass         ('b0),
    .chaosmode      ('b0),
    .v.*            (),
    .fifo_.*        (),
    );*/
   umi_fifo #(.DW(DW),
              .CW(CW),
              .AW(AW),
              .DEPTH(DEPTH))
   umi_fifo_tx_i(/*AUTOINST*/
                 // Outputs
                 .fifo_full             (),                      // Templated
                 .fifo_almost_full      (),
                 .fifo_empty            (),                      // Templated
                 .umi_in_ready          (umi_resp_in_ready),     // Templated
                 .umi_out_valid         (umi_resp_out_valid),    // Templated
                 .umi_out_cmd           (umi_resp_out_cmd[CW-1:0]), // Templated
                 .umi_out_dstaddr       (umi_resp_out_dstaddr[AW-1:0]), // Templated
                 .umi_out_srcaddr       (umi_resp_out_srcaddr[AW-1:0]), // Templated
                 .umi_out_data          (umi_resp_out_data[DW-1:0]), // Templated
                 // Inputs
                 .bypass                ('b0),                   // Templated
                 .chaosmode             ('b0),                   // Templated
                 .umi_in_clk            (clk),                   // Templated
                 .umi_in_nreset         (nreset),                // Templated
                 .umi_in_valid          (umi_resp_in_valid),     // Templated
                 .umi_in_cmd            (umi_resp_in_cmd[CW-1:0]), // Templated
                 .umi_in_dstaddr        (umi_resp_in_dstaddr[AW-1:0]), // Templated
                 .umi_in_srcaddr        (umi_resp_in_srcaddr[AW-1:0]), // Templated
                 .umi_in_data           (umi_resp_in_data[DW-1:0]), // Templated
                 .umi_out_clk           (clk),                   // Templated
                 .umi_out_nreset        (nreset),                // Templated
                 .umi_out_ready         (umi_resp_out_ready & initdone), // Templated
                 .vdd                   (),                      // Templated
                 .vss                   ());                     // Templated

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
   `SB_SETUP_PROBES();

   // auto-stop
   auto_stop_sim auto_stop_sim_i (.clk(clk));

endmodule
// Local Variables:
// verilog-library-directories:("../rtl")
// End:

`default_nettype wire
