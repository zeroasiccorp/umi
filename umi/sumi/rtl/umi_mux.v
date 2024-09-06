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
 * N:1 UMI transaction mux with arbiter and flow control.
 *
 ******************************************************************************/

module umi_mux
  #(parameter N  = 2,   // mumber of inputs
    parameter DW = 128, // umi data width
    parameter CW = 32,  // umi command width
    parameter AW = 6   // umi address width
    )
   (// controls
    input             clk,
    input             nreset,
    input [1:0]       arbmode, // arbiter mode (0=fixed)
    input [N-1:0]     arbmask, // arbiter mask (1=input is masked)
    // incoming UMI
    input [N-1:0]     umi_in_valid,
    input [N*CW-1:0]  umi_in_cmd,
    input [N*AW-1:0]  umi_in_dstaddr,
    input [N*AW-1:0]  umi_in_srcaddr,
    input [N*DW-1:0]  umi_in_data,
    output reg [N-1:0] umi_in_ready,
    // outgoing UMI
    output            umi_out_valid,
    output [CW-1:0]   umi_out_cmd,
    output [AW-1:0]   umi_out_dstaddr,
    output [AW-1:0]   umi_out_srcaddr,
    output [DW-1:0]   umi_out_data,
    input             umi_out_ready
    );

   wire [N-1:0]    grants;

   //##############################
   // Valid Arbiter
   //##############################

   umi_arbiter #(.N(N))
   umi_arbiter (// Outputs
                .grants   (grants[N-1:0]),
                // Inputs
                .clk      (clk),
                .nreset   (nreset),
                .mode     (arbmode[1:0]),
                .mask     (arbmask[N-1:0]),
                .requests (umi_in_valid[N-1:0]));

   assign umi_out_valid = |grants[N-1:0];

   //##############################
   // Ready
   //##############################


   // valid[j] | out_ready[j] | grant[j] | in_ready
   //------------------------------------------------
   //     0             x           x      | 1
   //     1             0           x      | 0
   //     1             1           0      | 0
   //     1             1           1      | 1

   integer j;
   always @(*)
     begin
        umi_in_ready[N-1:0] = {N{1'b1}};
        for (j=0;j<N;j=j+1)
          umi_in_ready[j] = umi_in_ready[j] & ~(umi_in_valid[j] &
                                                (~grants[j] | ~umi_out_ready));
     end

   //##############################
   // Output Mux
   //##############################

   // data
   la_vmux #(.N(N),
             .W(DW))
   la_data_vmux(// Outputs
                .out (umi_out_data[DW-1:0]),
                // Inputs
                .sel (grants[N-1:0]),
                .in  (umi_in_data[N*DW-1:0]));

   // srcaddr
   la_vmux #(.N(N),
             .W(AW))
   la_src_vmux(// Outputs
               .out (umi_out_srcaddr[AW-1:0]),
               // Inputs
               .sel (grants[N-1:0]),
               .in  (umi_in_srcaddr[N*AW-1:0]));

   // dstaddr
   la_vmux #(.N(N),
             .W(AW))
   la_dst_vmux(// Outputs
               .out (umi_out_dstaddr[AW-1:0]),
               // Inputs
               .sel (grants[N-1:0]),
               .in  (umi_in_dstaddr[N*AW-1:0]));

   // command
   la_vmux #(.N(N),
             .W(CW))
   la_cmd_vmux(// Outputs
               .out (umi_out_cmd[CW-1:0]),
               // Inputs
               .sel (grants[N-1:0]),
               .in  (umi_in_cmd[N*CW-1:0]));

endmodule
