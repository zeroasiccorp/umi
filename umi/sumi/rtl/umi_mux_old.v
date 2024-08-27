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
 * ##Documentation##
 *
 * - Selects between N inputs
 * - Assumes one-hot selects
 * - WARNING: input ready is combinatorially connected to the output ready.
 *
 ******************************************************************************/



module umi_mux_old
  #(parameter DW = 256, // UMI transaction width
    parameter CW = 32,
    parameter AW = 64,
    parameter N = 4     // number of inputs
    )
   (// Incoming UMI
    input [N-1:0]    umi_in_valid,
    input [N*CW-1:0] umi_in_cmd,
    input [N*AW-1:0] umi_in_dstaddr,
    input [N*AW-1:0] umi_in_srcaddr,
    input [N*DW-1:0] umi_in_data,
    output [N-1:0]   umi_in_ready,
    // Outgoing UMI
    output           umi_out_valid,
    input            umi_out_ready,
    output [CW-1:0]  umi_out_cmd,
    output [AW-1:0]  umi_out_dstaddr,
    output [AW-1:0]  umi_out_srcaddr,
    output [DW-1:0]  umi_out_data
    );

   // valid output
   assign umi_out_valid = |umi_in_valid[N-1:0];

   // ready pusback
   assign umi_in_ready[N-1:0] = {N{umi_out_ready}};

   // packet mux
   la_vmux #(.N(N),
             .W(CW))
   la_cmd_vmux(.out (umi_out_cmd[CW-1:0]),
               .sel (umi_in_valid[N-1:0]),
               .in  (umi_in_cmd[N*CW-1:0]));

   // packet mux
   la_vmux #(.N(N),
             .W(AW))
   la_dstaddr_vmux(.out (umi_out_dstaddr[AW-1:0]),
                   .sel (umi_in_valid[N-1:0]),
                   .in  (umi_in_dstaddr[N*AW-1:0]));

   // packet mux
   la_vmux #(.N(N),
             .W(AW))
   la_srcaddr_vmux(.out (umi_out_srcaddr[AW-1:0]),
                   .sel (umi_in_valid[N-1:0]),
                   .in  (umi_in_srcaddr[N*AW-1:0]));

   // packet mux
   la_vmux #(.N(N),
             .W(DW))
   la_data_vmux(.out (umi_out_data[DW-1:0]),
                .sel (umi_in_valid[N-1:0]),
                .in  (umi_in_data[N*DW-1:0]));

endmodule
