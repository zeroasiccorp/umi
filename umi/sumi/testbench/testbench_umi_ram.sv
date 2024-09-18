/*******************************************************************************
 * Copyright 2020 Zero ASIC Corporation
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
 * - Simple umi_ram testbench
 *
 ******************************************************************************/

`default_nettype none

module testbench (
`ifdef VERILATOR
    input clk
`endif
);

`include "switchboard.vh"

   parameter integer N=5;
   parameter integer CW=32;
   parameter integer AW=64;
   parameter integer DW=256;
   parameter integer CTRLW=8;
   parameter integer RAMDEPTH=512;

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

   wire [N-1:0]         udev_req_valid;
   wire [N*CW-1:0]      udev_req_cmd;
   wire [N*AW-1:0]      udev_req_dstaddr;
   wire [N*AW-1:0]      udev_req_srcaddr;
   wire [N*DW-1:0]      udev_req_data;
   wire [N-1:0]         udev_req_ready;

   wire [N-1:0]         udev_resp_valid;
   wire [N*CW-1:0]      udev_resp_cmd;
   wire [N*AW-1:0]      udev_resp_dstaddr;
   wire [N*AW-1:0]      udev_resp_srcaddr;
   wire [N*DW-1:0]      udev_resp_data;
   wire [N-1:0]         udev_resp_ready;

   wire [CTRLW-1:0]  sram_ctrl = 8'b0;
   wire [1:0]        mode = 2'b10;

   // Initialize valid and ready modes
   integer valid_mode, ready_mode;

   initial begin
      /* verilator lint_off IGNOREDRETURN */
      if (!$value$plusargs("valid_mode=%d", valid_mode)) begin
         valid_mode = 2;  // default if not provided as a plusarg
      end

      if (!$value$plusargs("ready_mode=%d", ready_mode)) begin
         ready_mode = 2;  // default if not provided as a plusarg
      end
      /* verilator lint_on IGNOREDRETURN */
   end

   ///////////////////////////////////////////
   // Host side umi agents
   ///////////////////////////////////////////

   genvar i;
   generate
   for (i = 0; i < N; i = i + 1) begin : UMI_AGENTS_GEN
        umi_rx_sim #(.VALID_MODE_DEFAULT(2),
                     .DW(DW)
                     )
        host_umi_rx_i (.clk(clk),
                       .valid(udev_req_valid[i]),
                       .cmd(udev_req_cmd[i*CW+:CW]),
                       .dstaddr(udev_req_dstaddr[i*AW+:AW]),
                       .srcaddr(udev_req_srcaddr[i*AW+:AW]),
                       .data(udev_req_data[i*DW+:DW]),
                       .ready(udev_req_ready[i] & initdone)
                       );

        umi_tx_sim #(.READY_MODE_DEFAULT(2),
                     .DW(DW)
                     )
        host_umi_tx_i (.clk(clk),
                       .valid(udev_resp_valid[i] & initdone),
                       .cmd(udev_resp_cmd[i*CW+:CW]),
                       .dstaddr(udev_resp_dstaddr[i*AW+:AW]),
                       .srcaddr(udev_resp_srcaddr[i*AW+:AW]),
                       .data(udev_resp_data[i*DW+:DW]),
                       .ready(udev_resp_ready[i])
                       );

        initial begin
           `ifndef VERILATOR
              #1;
           `endif
           UMI_AGENTS_GEN[i].host_umi_rx_i.init($sformatf("host2dut_%0d.q", i));
           UMI_AGENTS_GEN[i].host_umi_rx_i.set_valid_mode(valid_mode);
           UMI_AGENTS_GEN[i].host_umi_tx_i.init($sformatf("dut2host_%0d.q", i));
           UMI_AGENTS_GEN[i].host_umi_tx_i.set_ready_mode(ready_mode);
        end
   end
   endgenerate

   // instantiate dut with UMI ports
   /* umi_ram AUTO_TEMPLATE(
    .udev_req_valid     (udev_req_valid & {@"vl-width"{initdone}}),
    .udev_resp_ready    (udev_resp_ready & {@"vl-width"{initdone}}),
    );*/
   umi_ram #(.N(N),
             .CW(CW),
             .AW(AW),
             .DW(DW),
             .RAMDEPTH(RAMDEPTH),
             .CTRLW(CTRLW))
   umi_ram_i(/*AUTOINST*/
             // Outputs
             .udev_req_ready      (udev_req_ready[N-1:0]),
             .udev_resp_valid     (udev_resp_valid[N-1:0]),
             .udev_resp_cmd       (udev_resp_cmd[N*CW-1:0]),
             .udev_resp_dstaddr   (udev_resp_dstaddr[N*AW-1:0]),
             .udev_resp_srcaddr   (udev_resp_srcaddr[N*AW-1:0]),
             .udev_resp_data      (udev_resp_data[N*DW-1:0]),
             // Inputs
             .clk                 (clk),
             .nreset              (nreset),
             .mode                (mode),
             .sram_ctrl           (sram_ctrl[CTRLW-1:0]),
             .udev_req_valid      (udev_req_valid[N-1:0] & {N{initdone}}),
             .udev_req_cmd        (udev_req_cmd[N*CW-1:0]),
             .udev_req_dstaddr    (udev_req_dstaddr[N*AW-1:0]),
             .udev_req_srcaddr    (udev_req_srcaddr[N*AW-1:0]),
             .udev_req_data       (udev_req_data[N*DW-1:0]),
             .udev_resp_ready     (udev_resp_ready[N-1:0] & {N{initdone}}));

   // waveform dump
   `SB_SETUP_PROBES

   // auto-stop
   auto_stop_sim auto_stop_sim_i (.clk(clk));

endmodule
// Local Variables:
// verilog-library-directories:("../rtl")
// End:

`default_nettype wire
