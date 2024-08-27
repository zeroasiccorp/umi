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
 * - Dynamically configurable arbiter (fixed, roundrobin, reserve,...)
 *
 ******************************************************************************/

module umi_arbiter
  #(parameter N      = 4,         // number of inputs
    parameter TARGET = "DEFAULT"  // SIM, ASIC, FPGA, ...
    )
   (// controls
    input              clk,
    input              nreset,
    input [1:0]        mode, // [00]=priority,[01]=roundrobin,[1x]=reserved
    input [N-1:0]      mask, // 1 = disable request, 0 = enable request
    input [N-1:0]      requests, // incoming requests
    output reg [N-1:0] grants  // outgoing grants
    );

   wire                collision;
   reg [N-1:0]         thermometer;
   wire [N-1:0]        spec_requests;
   genvar              i;

   // Thermometer mask that gets hotter with every collision
   // wraps to zero when all ones
   generate if (N > 1)
     begin
        always @ (posedge clk or negedge nreset)
          if (~nreset)
            thermometer[N-1:0] <= {N{1'b0}};
          else if(collision & (mode[1:0]==2'b10))
            thermometer[N-1:0] <= (&thermometer[N-2:0]) ? {N{1'b0}} : {thermometer[N-2:0],1'b1};
     end
   else
     begin
        always @ (posedge clk or negedge nreset)
          if (~nreset)
            thermometer[N-1:0] <= {N{1'b0}};
          else
            thermometer[N-1:0] <= {N{1'b0}};
     end
   endgenerate

   // 1. Create N rotated set of requests
   // 2. Feed requests into fixed priority encoders
   // double width needed for rotation
   assign spec_requests = ~mask[N-1:0] &
                          ~thermometer[N-1:0] &
                           requests[N-1:0];

   // Priority Selection Using Masked Inputs
   umi_priority #(.N(N))
   umi_prioroty(// Outputs
                .grants   (grants[N-1:0]),
                // Inputs
                .requests (spec_requests[N-1:0]));

   // Detect collision on pushback
   assign collision = |(requests[N-1:0] & ~grants[N-1:0]);

`ifdef VERILATOR
   assert property (@(posedge clk) $onehot0(grants));
`endif

endmodule
