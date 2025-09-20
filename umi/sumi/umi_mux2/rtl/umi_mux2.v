/******************************************************************************
 * Copyright 2025 Zero ASIC Corporation
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
 * 2:1 UMI mux with a single select (ie arbiter is external)
 *
 *****************************************************************************/

module umi_mux2
  #(parameter DW = 128, // umi data width
    parameter CW = 32,  // umi command width
    parameter AW = 6    // umi address width
    )
   (// controls
    input            sel, //1=in1, 0=in0. input UMI order is {in1, in0}
    // incoming UMI
    input [1:0]      umi_in_valid,
    input [2*CW-1:0] umi_in_cmd,
    input [2*AW-1:0] umi_in_dstaddr,
    input [2*AW-1:0] umi_in_srcaddr,
    input [2*DW-1:0] umi_in_data,
    output [1:0]     umi_in_ready,
    // outgoing UMI
    output           umi_out_valid,
    output [CW-1:0]  umi_out_cmd,
    output [AW-1:0]  umi_out_dstaddr,
    output [AW-1:0]  umi_out_srcaddr,
    output [DW-1:0]  umi_out_data,
    input            umi_out_ready
    );

   wire [1:0]    grants;

   //##############################
   // One Hot Output Mux
   //##############################

   // data
   la_vmux2b #(.W(DW))
   la_data_vmux(// Outputs
                .out (umi_out_data[DW-1:0]),
                // Inputs
                .sel (sel),
                .in0  (umi_in_data[DW-1:0]),
                .in1  (umi_in_data[2*DW-1:DW]));

   // srcaddr
   la_vmux2b #(.W(AW))
   la_src_vmux(// Outputs
               .out (umi_out_srcaddr[AW-1:0]),
               // Inputs
               .sel (sel),
               .in0  (umi_in_srcaddr[AW-1:0]),
               .in1  (umi_in_srcaddr[2*AW-1:AW]));

   // dstaddr
   la_vmux2b #(.W(AW))
   la_dst_vmux(// Outputs
               .out (umi_out_dstaddr[AW-1:0]),
               // Inputs
               .sel (sel),
               .in0  (umi_in_dstaddr[AW-1:0]),
               .in1  (umi_in_dstaddr[2*AW-1:AW]));

   // command
   la_vmux2b #(.W(CW))
   la_cmd_vmux(// Outputs
               .out (umi_out_cmd[CW-1:0]),
               // Inputs
               .sel (sel),
               .in0  (umi_in_cmd[CW-1:0]),
               .in1  (umi_in_cmd[2*CW-1:CW]));

   //##############################
   // Ready/Valid
   //##############################

   assign umi_out_valid = (sel  & umi_in_valid[1]) |
                          (~sel & umi_in_valid[0]);

   assign umi_in_ready[0] = ~umi_in_valid[0] | (~sel & umi_out_ready);
   assign umi_in_ready[1] = ~umi_in_valid[1] | (sel & umi_out_ready);

endmodule
