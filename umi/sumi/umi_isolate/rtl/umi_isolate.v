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
 * - Power domain isolation buffers
 *
 ******************************************************************************/

module umi_isolate
  #(parameter CW = 32, // umi command width
    parameter AW = 64, // umi address width
    parameter DW = 64, // umi data width
    parameter ISO = 0  // 1 = enable input isolation
    )
   (
    input           isolate,  // 1=clamp inputs to 0
    // floating signals
    input           umi_ready,
    input           umi_valid,
    input [CW-1:0]  umi_cmd,
    input [AW-1:0]  umi_dstaddr,
    input [AW-1:0]  umi_srcaddr,
    input [DW-1:0]  umi_data,
    // clamped signals
    output          umi_ready_iso,
    output          umi_valid_iso,
    output [CW-1:0] umi_cmd_iso,
    output [AW-1:0] umi_dstaddr_iso,
    output [AW-1:0] umi_srcaddr_iso,
    output [DW-1:0] umi_data_iso
    );

   generate
      if(ISO)
        begin : g0
           la_visolo #(.N(1))
           i_ready (.in(umi_ready),
                    .out(umi_ready_iso),
                    .iso(isolate));

           la_visolo #(.N(1))
           i_valid (.in(umi_valid),
                    .out(umi_valid_iso),
                    .iso(isolate));

           la_visolo #(.N(CW))
           i_cmd (.in(umi_cmd[CW-1:0]),
                  .out(umi_cmd_iso[CW-1:0]),
                  .iso(isolate));

           la_visolo #(.N(AW))
           i_dstaddr (.in(umi_dstaddr[AW-1:0]),
                      .out(umi_dstaddr_iso[AW-1:0]),
                      .iso(isolate));

           la_visolo #(.N(AW))
           i_srcaddr (.in(umi_srcaddr[AW-1:0]),
                      .out(umi_srcaddr_iso[AW-1:0]),
                      .iso(isolate));

           la_visolo #(.N(DW))
           i_data (.in(umi_data[DW-1:0]),
                   .out(umi_data_iso[DW-1:0]),
                   .iso(isolate));
        end
      else
        begin : g0
           assign umi_ready_iso           = umi_ready;
           assign umi_valid_iso           = umi_valid;
           assign umi_cmd_iso[CW-1:0]     = umi_cmd[CW-1:0];
           assign umi_dstaddr_iso[AW-1:0] = umi_dstaddr[AW-1:0];
           assign umi_srcaddr_iso[AW-1:0] = umi_srcaddr[AW-1:0];
           assign umi_data_iso[DW-1:0]    = umi_data[DW-1:0];
        end

   endgenerate

endmodule
