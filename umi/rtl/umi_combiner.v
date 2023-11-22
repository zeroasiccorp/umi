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
 * - Combines request and response inputs.
 * - No cycles allowed since this would deadlock
 * - Traffic source must be self throttling
 * - Input valids must be mutuall exclusive
 *
 ******************************************************************************/

module umi_combiner
  #(// standard parameters
    parameter AW   = 64,
    parameter CW   = 32,
    parameter DW   = 256)
   (// controls
    input           clk,
    input           nreset,
    // Input (0), Higher Priority
    input           umi_resp_in_valid,
    input [CW-1:0]  umi_resp_in_cmd,
    input [AW-1:0]  umi_resp_in_dstaddr,
    input [AW-1:0]  umi_resp_in_srcaddr,
    input [DW-1:0]  umi_resp_in_data,
    output          umi_resp_in_ready,
    // Input (1)
    input           umi_req_in_valid,
    input [CW-1:0]  umi_req_in_cmd,
    input [AW-1:0]  umi_req_in_dstaddr,
    input [AW-1:0]  umi_req_in_srcaddr,
    input [DW-1:0]  umi_req_in_data,
    output          umi_req_in_ready,
    // Output
    output          umi_out_valid,
    output [CW-1:0] umi_out_cmd,
    output [AW-1:0] umi_out_dstaddr,
    output [AW-1:0] umi_out_srcaddr,
    output [DW-1:0] umi_out_data,
    input           umi_out_ready
    );

   // local wires
   wire             umi_resp_ready;
   wire             umi_req_ready;

   umi_mux #(.N(2))
   umi_mux (// Outputs
            .umi_in_ready      ({umi_req_ready,umi_resp_ready}),
            .umi_out_valid     (umi_out_valid),
            .umi_out_cmd       (umi_out_cmd[CW-1:0]),
            .umi_out_dstaddr   (umi_out_dstaddr[AW-1:0]),
            .umi_out_srcaddr   (umi_out_srcaddr[AW-1:0]),
            .umi_out_data      (umi_out_data[DW-1:0]),
            // Inputs
            .umi_in_valid      ({umi_req_in_valid, umi_resp_in_valid}),
            .umi_in_cmd        ({umi_req_in_cmd, umi_resp_in_cmd}),
            .umi_in_dstaddr    ({umi_req_in_dstaddr, umi_resp_in_dstaddr}),
            .umi_in_srcaddr    ({umi_req_in_srcaddr, umi_resp_in_srcaddr}),
            .umi_in_data       ({umi_req_in_data, umi_resp_in_data}),
            /*AUTOINST*/
            // Inputs
            .umi_out_ready      (umi_out_ready));

   // Flow through pushback
   assign umi_resp_in_ready = umi_out_ready & umi_resp_ready;
   assign umi_req_in_ready = umi_out_ready & umi_req_ready;

endmodule // umi_splitter
