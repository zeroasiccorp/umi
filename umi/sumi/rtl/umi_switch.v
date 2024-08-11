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
 *
 * - Pipelined non-blocking swith with M outputs and N inputs
 *
 * - The order and masking is as follows
 *
 * [0]     = input 0   requesting output 0
 * [1]     = input 1   requesting output 0
 * [2]     = input 2   requesting output 0
 * [N-1]   = input N-1 requesting output 0
 * [N]     = input 0   requesting output 1
 * [N+1]   = input 1   requesting output 1
 * [N+2]   = input 2   requesting output 1
 * [2*N-1] = input N-1 requesting output 1
 *
 *
 ******************************************************************************/

module umi_switch
  #(parameter DW = 256, // umi data width
    parameter CW = 32,  // umi command width
    parameter AW = 64,  // umi adress width
    parameter N = 3,    // number of input ports
    parameter M = 6     // number of outputs ports
    )
   (// controls
    input              clk,
    input              nreset,
    input [1:0]        arbmode, // arbiter mode (0=fixed)
    input [N*M-1:0]    arbmask, // (1=mask/disable path)
    // Incoming UMI
    input [N*M-1:0]    umi_in_request,
    input [N*CW-1:0]   umi_in_cmd,
    input [N*AW-1:0]   umi_in_dstaddr,
    input [N*AW-1:0]   umi_in_srcaddr,
    input [N*DW-1:0]   umi_in_data,
    output reg [N-1:0] umi_in_ready,
    // Outgoing UMI
    output [M-1:0]     umi_out_valid,
    output [M*CW-1:0]  umi_out_cmd,
    output [M*AW-1:0]  umi_out_dstaddr,
    output [M*AW-1:0]  umi_out_srcaddr,
    output [M*DW-1:0]  umi_out_data,
    input [M-1:0]      umi_out_ready
    );

   genvar i;

   wire [M*N-1:0] umi_ready;

   //#######################################################
   // Output Ports
   //#######################################################

   // data broadcasted to all output ports for M inputs
   // N individual requests sent to each port
   // M*N ready signals generated

   for (i=0;i<M;i=i+1)
     begin
        umi_port #(.N(N),
                   .DW(DW),
                   .CW(CW),
                   .AW(AW))
        out (// Outputs
             .umi_in_ready          (umi_ready[i*N+:N]),
             .umi_out_valid         (umi_out_valid[i]),
             .umi_out_cmd           (umi_out_cmd[i*CW+:CW]),
             .umi_out_dstaddr       (umi_out_dstaddr[i*AW+:AW]),
             .umi_out_srcaddr       (umi_out_srcaddr[i*AW+:AW]),
             .umi_out_data          (umi_out_data[i*DW+:DW]),
             // Inputs
             .clk                   (clk),
             .nreset                (nreset),
             .arbmode               (arbmode[1:0]),
             .arbmask               (arbmask[i*N+:N]),
             .umi_in_request        (umi_in_request[i*N+:N]),
             .umi_in_cmd            (umi_in_cmd[N*CW-1:0]),
             .umi_in_dstaddr        (umi_in_dstaddr[N*AW-1:0]),
             .umi_in_srcaddr        (umi_in_srcaddr[N*AW-1:0]),
             .umi_in_data           (umi_in_data[N*DW-1:0]),
             .umi_out_ready         (umi_out_ready[i]));
     end

   //#########################################
   // Merge ready signals from all ports
   //##########################################

   integer j,k;
   always @(*)
     begin
        umi_in_ready[N-1:0] = {N{1'b1}};
        for (j=0;j<N;j=j+1)
          for (k=0;k<M;k=k+1)
            umi_in_ready[j] = umi_in_ready[j] & umi_ready[j+N*k];
     end

endmodule
