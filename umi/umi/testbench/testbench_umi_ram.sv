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
                  input clk
                  );

   parameter integer N=5;
   parameter integer CW=32;
   parameter integer AW=64;
   parameter integer DW=256;
   parameter integer CTRLW=8;
   parameter integer RAMDEPTH=512;

   reg                  nreset;
   reg                  go;

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
                       .ready(udev_req_ready[i])
                       );

        umi_tx_sim #(.READY_MODE_DEFAULT(2),
                     .DW(DW)
                     )
        host_umi_tx_i (.clk(clk),
                       .valid(udev_resp_valid[i]),
                       .cmd(udev_resp_cmd[i*CW+:CW]),
                       .dstaddr(udev_resp_dstaddr[i*AW+:AW]),
                       .srcaddr(udev_resp_srcaddr[i*AW+:AW]),
                       .data(udev_resp_data[i*DW+:DW]),
                       .ready(udev_resp_ready[i])
                       );
   end
   endgenerate

   // instantiate dut with UMI ports
   /* umi_ram AUTO_TEMPLATE(
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
             .udev_req_valid      (udev_req_valid[N-1:0]),
             .udev_req_cmd        (udev_req_cmd[N*CW-1:0]),
             .udev_req_dstaddr    (udev_req_dstaddr[N*AW-1:0]),
             .udev_req_srcaddr    (udev_req_srcaddr[N*AW-1:0]),
             .udev_req_data       (udev_req_data[N*DW-1:0]),
             .udev_resp_ready     (udev_resp_ready[N-1:0]));

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

      UMI_AGENTS_GEN[0].host_umi_rx_i.init("host2dut_0.q");
      UMI_AGENTS_GEN[0].host_umi_rx_i.set_valid_mode(valid_mode);
      UMI_AGENTS_GEN[1].host_umi_rx_i.init("host2dut_1.q");
      UMI_AGENTS_GEN[1].host_umi_rx_i.set_valid_mode(valid_mode);
      UMI_AGENTS_GEN[2].host_umi_rx_i.init("host2dut_2.q");
      UMI_AGENTS_GEN[2].host_umi_rx_i.set_valid_mode(valid_mode);
      UMI_AGENTS_GEN[3].host_umi_rx_i.init("host2dut_3.q");
      UMI_AGENTS_GEN[3].host_umi_rx_i.set_valid_mode(valid_mode);
      UMI_AGENTS_GEN[4].host_umi_rx_i.init("host2dut_4.q");
      UMI_AGENTS_GEN[4].host_umi_rx_i.set_valid_mode(valid_mode);

      UMI_AGENTS_GEN[0].host_umi_tx_i.init("dut2host_0.q");
      UMI_AGENTS_GEN[0].host_umi_tx_i.set_ready_mode(ready_mode);
      UMI_AGENTS_GEN[1].host_umi_tx_i.init("dut2host_1.q");
      UMI_AGENTS_GEN[1].host_umi_tx_i.set_ready_mode(ready_mode);
      UMI_AGENTS_GEN[2].host_umi_tx_i.init("dut2host_2.q");
      UMI_AGENTS_GEN[2].host_umi_tx_i.set_ready_mode(ready_mode);
      UMI_AGENTS_GEN[3].host_umi_tx_i.init("dut2host_3.q");
      UMI_AGENTS_GEN[3].host_umi_tx_i.set_ready_mode(ready_mode);
      UMI_AGENTS_GEN[4].host_umi_tx_i.init("dut2host_4.q");
      UMI_AGENTS_GEN[4].host_umi_tx_i.set_ready_mode(ready_mode);
      /* verilator lint_on IGNOREDRETURN */
   end

   // VCD

   initial
     begin
        nreset   = 1'b0;
        go       = 1'b0;
     end // initial begin

   // Bring up reset and the go signal on the first clock cycle
   always @(negedge clk)
     begin
        nreset <= nreset | 1'b1;
        go <= 1'b1;
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

   auto_stop_sim auto_stop_sim_i (.clk(clk));

endmodule
// Local Variables:
// verilog-library-directories:("../rtl" )
// End:

`default_nettype wire
