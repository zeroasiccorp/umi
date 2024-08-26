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
 * - Select signal selects output port
 * - Inputs broadcasted to all outputs
 * - Ready signal aggregated from otuputs
 *
 * Testing:
 *
 ******************************************************************************/

module umi_router
  #(
    parameter M = 4,    // number of outputs ports
    parameter DW = 128, // umi data width
    parameter CW = 32,  // umi command width
    parameter AW = 64   // umi adress width
    )
   (// Incoming UMI
    input [M-1:0]     umi_in_select, // output selector
    input             umi_in_valid,
    input [CW-1:0]    umi_in_cmd,
    input [AW-1:0]    umi_in_dstaddr,
    input [AW-1:0]    umi_in_srcaddr,
    input [DW-1:0]    umi_in_data,
    output            umi_in_ready,
    // Outgoing UMI
    output [M-1:0]    umi_out_valid,
    output [M*CW-1:0] umi_out_cmd,
    output [M*AW-1:0] umi_out_dstaddr,
    output [M*AW-1:0] umi_out_srcaddr,
    output [M*DW-1:0] umi_out_data,
    input [M-1:0]     umi_out_ready
    );

   // Valid signal
   assign umi_out_valid[M-1:0] = umi_in_valid ? umi_in_select[M-1:0] : 'b0;

   // Ready signal
   assign umi_in_ready = &(~umi_in_select[M-1:0] | umi_out_ready[M-1:0]);

   // Broadcast packet
   assign umi_out_cmd[M*CW-1:0]     = {M{umi_in_cmd[CW-1:0]}};
   assign umi_out_dstaddr[M*AW-1:0] = {M{umi_in_dstaddr[AW-1:0]}};
   assign umi_out_srcaddr[M*AW-1:0] = {M{umi_in_srcaddr[AW-1:0]}};
   assign umi_out_data[M*DW-1:0]    = {M{umi_in_data[DW-1:0]}};

endmodule
