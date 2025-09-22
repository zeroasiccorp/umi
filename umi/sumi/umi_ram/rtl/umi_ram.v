/******************************************************************************
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
 * - Implements a simple memory array with multiple UMI access ports
 * - The array allows only a single read or write per cycle
 *
 ****************************************************************************/

module umi_ram
  #(parameter N = 1,              // number of UMI ports
    parameter DW = 256,           // umi packet width
    parameter AW = 64,            // address width
    parameter CW = 32,            // command width
    parameter IDOFF = 40,         // offset into AW for unique UMI port ID
    parameter RAMDEPTH = 512,
    parameter CTRLW = 8,
    parameter SRAMTYPE = "DEFAULT"
    )
   (// global controls
    input               clk,    // clock signals
    input               nreset, // async active low reset
    input  [CTRLW-1:0]  sram_ctrl, // Control signal for SRAM
    input  [1:0]        mode,   // [00]=priority,[10]=roundrobin,[x1]=reserved
    // Device port
    input  [N-1:0]      udev_req_valid,
    input  [N*CW-1:0]   udev_req_cmd,
    input  [N*AW-1:0]   udev_req_dstaddr,
    input  [N*AW-1:0]   udev_req_srcaddr,
    input  [N*DW-1:0]   udev_req_data,
    output [N-1:0]      udev_req_ready,
    output [N-1:0]      udev_resp_valid,
    output [N*CW-1:0]   udev_resp_cmd,
    output [N*AW-1:0]   udev_resp_dstaddr,
    output [N*AW-1:0]   udev_resp_srcaddr,
    output [N*DW-1:0]   udev_resp_data,
    input  [N-1:0]      udev_resp_ready
    );

   /*AUTOREG*/

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [CW-1:0]        mem_resp_cmd;
   wire [DW-1:0]        mem_resp_data;
   wire [AW-1:0]        mem_resp_dstaddr;
   wire [AW-1:0]        mem_resp_srcaddr;
   wire                 mem_resp_valid;
   wire [CW-1:0]        umi_out_cmd;
   wire [DW-1:0]        umi_out_data;
   wire [AW-1:0]        umi_out_dstaddr;
   wire                 umi_out_ready;
   wire [AW-1:0]        umi_out_srcaddr;
   wire                 umi_out_valid;
   // End of automatics
   wire                 mem_resp_ready;

   //##################################################################
   //# UMI ENDPOINT (Pipelined Request/Response)
   //##################################################################

   /*umi_mux AUTO_TEMPLATE(
    .arbmode       (mode),
    .arbmask       ({N{1'b0}}),
    .umi_in_\(.*\) (udev_req_\1[]),
    );*/

   umi_mux #(.CW(CW),
             .AW(AW),
             .DW(DW),
             .N(N))
   umi_mux(/*AUTOINST*/
           // Outputs
           .umi_in_ready        (udev_req_ready[N-1:0]),   // Templated
           .umi_out_valid       (umi_out_valid),
           .umi_out_cmd         (umi_out_cmd[CW-1:0]),
           .umi_out_dstaddr     (umi_out_dstaddr[AW-1:0]),
           .umi_out_srcaddr     (umi_out_srcaddr[AW-1:0]),
           .umi_out_data        (umi_out_data[DW-1:0]),
           // Inputs
           .clk                 (clk),
           .nreset              (nreset),
           .arbmode             (mode),
           .arbmask             ({N{1'b0}}),
           .umi_in_valid        (udev_req_valid[N-1:0]), // Templated
           .umi_in_cmd          (udev_req_cmd[N*CW-1:0]), // Templated
           .umi_in_dstaddr      (udev_req_dstaddr[N*AW-1:0]), // Templated
           .umi_in_srcaddr      (udev_req_srcaddr[N*AW-1:0]), // Templated
           .umi_in_data         (udev_req_data[N*DW-1:0]), // Templated
           .umi_out_ready       (umi_out_ready));

   assign udev_resp_valid[N-1:0]      = mem_resp_dstaddr[IDOFF+:N] & {N{mem_resp_valid}};
   assign mem_resp_ready              = |(mem_resp_dstaddr[IDOFF+:N] & udev_resp_ready[N-1:0]) |
                                        ~mem_resp_valid;
   assign udev_resp_cmd[N*CW-1:0]     = {N{mem_resp_cmd[CW-1:0]}};
   assign udev_resp_dstaddr[N*AW-1:0] = {N{mem_resp_dstaddr[AW-1:0]}};
   assign udev_resp_srcaddr[N*AW-1:0] = {N{mem_resp_srcaddr[AW-1:0]}};
   assign udev_resp_data[N*DW-1:0]    = {N{mem_resp_data[DW-1:0]}};

   umi_memagent #(.CW(CW),
                  .AW(AW),
                  .DW(DW),
                  .RAMDEPTH(RAMDEPTH),
                  .CTRLW(CTRLW),
                  .SRAMTYPE(SRAMTYPE))
   umi_memagent (.clk                   (clk),
                 .nreset                (nreset),
                 .sram_ctrl             (sram_ctrl),
                 .udev_req_valid        (umi_out_valid),
                 .udev_req_cmd          (umi_out_cmd[CW-1:0]),
                 .udev_req_dstaddr      (umi_out_dstaddr[AW-1:0]),
                 .udev_req_srcaddr      (umi_out_srcaddr[AW-1:0]),
                 .udev_req_data         (umi_out_data[DW-1:0]),
                 .udev_req_ready        (umi_out_ready),
                 .udev_resp_valid       (mem_resp_valid),
                 .udev_resp_cmd         (mem_resp_cmd[CW-1:0]),
                 .udev_resp_dstaddr     (mem_resp_dstaddr[AW-1:0]),
                 .udev_resp_srcaddr     (mem_resp_srcaddr[AW-1:0]),
                 .udev_resp_data        (mem_resp_data[DW-1:0]),
                 .udev_resp_ready       (mem_resp_ready));

endmodule
// Local Variables:
// verilog-library-directories:("./")
// End:
