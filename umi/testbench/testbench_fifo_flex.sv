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
 * - Simple fifo flex testbench
 *
 ******************************************************************************/


`default_nettype none

module testbench (
                  input clk
                  );

   parameter integer IDW=128;
   parameter integer ODW=32;
   parameter integer AW=64;
   parameter integer CW=32;
   parameter integer CTRLW=8;
   parameter integer DEPTH=512;
   parameter integer ASYNC=0;

   `ifndef SPLIT
     `define SPLIT 0
   `endif

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [CW-1:0]        umi_req_out_cmd;
   wire [ODW-1:0]       umi_req_out_data;
   wire [AW-1:0]        umi_req_out_dstaddr;
   wire                 umi_req_out_ready;
   wire [AW-1:0]        umi_req_out_srcaddr;
   wire                 umi_req_out_valid;
   wire [CW-1:0]        umi_resp_in_cmd;
   wire [ODW-1:0]       umi_resp_in_data;
   wire [AW-1:0]        umi_resp_in_dstaddr;
   wire                 umi_resp_in_ready;
   wire [AW-1:0]        umi_resp_in_srcaddr;
   wire                 umi_resp_in_valid;
   // End of automatics
   wire                 nreset;

   wire [CTRLW-1:0]     sram_ctrl = 8'b0;

   wire                 umi_resp_out_ready;
   wire [CW-1:0]        umi_resp_out_cmd;
   wire [IDW-1:0]       umi_resp_out_data;
   wire [AW-1:0]        umi_resp_out_dstaddr;
   wire [AW-1:0]        umi_resp_out_srcaddr;
   wire                 umi_resp_out_valid;

   wire                 umi_req_in_ready;
   wire [CW-1:0]        umi_req_in_cmd;
   wire [IDW-1:0]       umi_req_in_data;
   wire [AW-1:0]        umi_req_in_dstaddr;
   wire [AW-1:0]        umi_req_in_srcaddr;
   wire                 umi_req_in_valid;

   ///////////////////////////////////////////
   // Host side umi agents
   ///////////////////////////////////////////

   umi_rx_sim #(.VALID_MODE_DEFAULT(2),
                .DW(IDW)
                )
   host_umi_rx_i (.clk(clk),
                  .data(umi_req_in_data[IDW-1:0]),
                  .srcaddr(umi_req_in_srcaddr[AW-1:0]),
                  .dstaddr(umi_req_in_dstaddr[AW-1:0]),
                  .cmd(umi_req_in_cmd[CW-1:0]),
                  .ready(umi_req_in_ready),
                  .valid(umi_req_in_valid)
                  );

   umi_tx_sim #(.READY_MODE_DEFAULT(2),
                .DW(IDW)
                )
   host_umi_tx_i (.clk(clk),
                  .data(umi_resp_out_data[IDW-1:0]),
                  .srcaddr(umi_resp_out_srcaddr[AW-1:0]),
                  .dstaddr(umi_resp_out_dstaddr[AW-1:0]),
                  .cmd(umi_resp_out_cmd[CW-1:0]),
                  .ready(umi_resp_out_ready),
                  .valid(umi_resp_out_valid)
                  );

   wire bypass = 1'b0;
   wire chaosmode = 0;

   // instantiate dut with UMI ports
   /* umi_fifo_flex AUTO_TEMPLATE(
    .umi_.*_clk     (clk),
    .umi_.*_nreset  (nreset),
    .umi_in_\(.*\)  (umi_req_in_\1[]),
    .umi_out_\(.*\) (umi_req_out_\1[]),
    .v.*            (),
    .fifo_.*        (),
    );*/
   umi_fifo_flex #(.ASYNC(ASYNC),
                   .SPLIT(`SPLIT),
                   .IDW(IDW),
                   .ODW(ODW),
                   .CW(CW),
                   .AW(AW),
                   .DEPTH(DEPTH))
   umi_fifo_flex_rx_i(/*AUTOINST*/
                      // Outputs
                      .fifo_full        (),                      // Templated
                      .fifo_empty       (),                      // Templated
                      .umi_in_ready     (umi_req_in_ready),      // Templated
                      .umi_out_valid    (umi_req_out_valid),     // Templated
                      .umi_out_cmd      (umi_req_out_cmd[CW-1:0]), // Templated
                      .umi_out_dstaddr  (umi_req_out_dstaddr[AW-1:0]), // Templated
                      .umi_out_srcaddr  (umi_req_out_srcaddr[AW-1:0]), // Templated
                      .umi_out_data     (umi_req_out_data[ODW-1:0]), // Templated
                      // Inputs
                      .bypass           (bypass),
                      .chaosmode        (chaosmode),
                      .umi_in_clk       (clk),                   // Templated
                      .umi_in_nreset    (nreset),                // Templated
                      .umi_in_valid     (umi_req_in_valid),      // Templated
                      .umi_in_cmd       (umi_req_in_cmd[CW-1:0]), // Templated
                      .umi_in_dstaddr   (umi_req_in_dstaddr[AW-1:0]), // Templated
                      .umi_in_srcaddr   (umi_req_in_srcaddr[AW-1:0]), // Templated
                      .umi_in_data      (umi_req_in_data[IDW-1:0]), // Templated
                      .umi_out_clk      (clk),                   // Templated
                      .umi_out_nreset   (nreset),                // Templated
                      .umi_out_ready    (umi_req_out_ready),     // Templated
                      .vdd              (),                      // Templated
                      .vss              ());                     // Templated

   /* umi_mem_agent AUTO_TEMPLATE(
    .udev_req_data    (umi_req_out_data[ODW-1:0]),
    .udev_req_\(.*\)  (umi_req_out_\1[]),
    .udev_resp_data   (umi_resp_in_data[ODW-1:0]),
    .udev_resp_\(.*\) (umi_resp_in_\1[]),
    );*/

   umi_mem_agent #(.CW(CW),
                   .AW(AW),
                   .DW(ODW),
                   .CTRLW(CTRLW))
   umi_mem_agent_i(/*AUTOINST*/
                   // Outputs
                   .udev_req_ready      (umi_req_out_ready),     // Templated
                   .udev_resp_valid     (umi_resp_in_valid),     // Templated
                   .udev_resp_cmd       (umi_resp_in_cmd[CW-1:0]), // Templated
                   .udev_resp_dstaddr   (umi_resp_in_dstaddr[AW-1:0]), // Templated
                   .udev_resp_srcaddr   (umi_resp_in_srcaddr[AW-1:0]), // Templated
                   .udev_resp_data      (umi_resp_in_data[ODW-1:0]), // Templated
                   // Inputs
                   .clk                 (clk),
                   .nreset              (nreset),
                   .sram_ctrl           (sram_ctrl[CTRLW-1:0]),
                   .udev_req_valid      (umi_req_out_valid),     // Templated
                   .udev_req_cmd        (umi_req_out_cmd[CW-1:0]), // Templated
                   .udev_req_dstaddr    (umi_req_out_dstaddr[AW-1:0]), // Templated
                   .udev_req_srcaddr    (umi_req_out_srcaddr[AW-1:0]), // Templated
                   .udev_req_data       (umi_req_out_data[ODW-1:0]), // Templated
                   .udev_resp_ready     (umi_resp_in_ready));    // Templated

   /* umi_fifo_flex AUTO_TEMPLATE(
    .umi_.*_clk     (clk),
    .umi_.*_nreset  (nreset),
    .umi_in_data    (umi_resp_in_data[ODW-1:0]),
    .umi_in_\(.*\)  (umi_resp_in_\1[]),
    .umi_out_data   (umi_resp_out_data[IDW-1:0]),
    .umi_out_\(.*\) (umi_resp_out_\1[]),
    .v.*            (),
    .fifo_.*        (),
    );*/
   umi_fifo_flex #(.ASYNC(ASYNC),
                   .SPLIT(`SPLIT),
                   .IDW(ODW),
                   .ODW(IDW),
                   .CW(CW),
                   .AW(AW),
                   .DEPTH(DEPTH))
   umi_fifo_flex_tx_i(/*AUTOINST*/
                      // Outputs
                      .fifo_full        (),                      // Templated
                      .fifo_empty       (),                      // Templated
                      .umi_in_ready     (umi_resp_in_ready),     // Templated
                      .umi_out_valid    (umi_resp_out_valid),    // Templated
                      .umi_out_cmd      (umi_resp_out_cmd[CW-1:0]), // Templated
                      .umi_out_dstaddr  (umi_resp_out_dstaddr[AW-1:0]), // Templated
                      .umi_out_srcaddr  (umi_resp_out_srcaddr[AW-1:0]), // Templated
                      .umi_out_data     (umi_resp_out_data[IDW-1:0]), // Templated
                      // Inputs
                      .bypass           (bypass),
                      .chaosmode        (chaosmode),
                      .umi_in_clk       (clk),                   // Templated
                      .umi_in_nreset    (nreset),                // Templated
                      .umi_in_valid     (umi_resp_in_valid),     // Templated
                      .umi_in_cmd       (umi_resp_in_cmd[CW-1:0]), // Templated
                      .umi_in_dstaddr   (umi_resp_in_dstaddr[AW-1:0]), // Templated
                      .umi_in_srcaddr   (umi_resp_in_srcaddr[AW-1:0]), // Templated
                      .umi_in_data      (umi_resp_in_data[ODW-1:0]), // Templated
                      .umi_out_clk      (clk),                   // Templated
                      .umi_out_nreset   (nreset),                // Templated
                      .umi_out_ready    (umi_resp_out_ready),    // Templated
                      .vdd              (),                      // Templated
                      .vss              ());                     // Templated

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

   // VCD

   reg [15:0] nreset_r;
   assign nreset = ~nreset_r[15];

   initial
     begin
        nreset_r = 16'hFFFF;
     end // initial begin

   always @(negedge clk)
     begin
        nreset_r <= nreset_r << 1;
     end

   // control block
   initial
     begin
        if ($test$plusargs("trace"))
          begin
             $dumpfile("testbench.fst");
             $dumpvars(0, testbench);
          end
     end

   // auto-stop

   auto_stop_sim #(.CYCLES(500000)) auto_stop_sim_i (.clk(clk));

endmodule
// Local Variables:
// verilog-library-directories:("../rtl")
// End:

`default_nettype wire
