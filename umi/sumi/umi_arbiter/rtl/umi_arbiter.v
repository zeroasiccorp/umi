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

module umi_arbiter #(parameter N = 4,    // number of inputs
                     parameter PROP = "" // cell selector
                     )
   (// controls
    input          clk,
    input          nreset,
    input [1:0]    mode,     // [00]=priority,[01]=roundrobin,[1x]=reserved
    input [N-1:0]  mask,     // 1 = disable request, 0 = enable request
    input [N-1:0]  requests, // incoming requests
    output [N-1:0] grants    // outgoing grants
    );

   wire                collision;
   reg [N-1:0]         thermometer;
   wire [N-1:0]        spec_requests;
   wire [N-1:0]        block;
   genvar              i,j;

   // NOTE: The thermometer mask works correctly in case of a collision
   // that is followed by a single request from a masked source.
   // Consider, 4 requestors but only 0 and 1 are requesting:
   // cycle 0: req[0] = 1, req[1] = 1, grants[0] = 1, grants[1] = 0, collision = 1, therm = 4'b0000
   // cycle 1: req[0] = 0, req[1] = 1, grants[0] = 0, grants[1] = 1, collision = 0, therm = 4'b0001
   // cycle 2: req[0] = 1, req[1] = 0, grants[0] = 0, grants[1] = 0, collision = 1, therm = 4'b0001
   // cycle 3: req[0] = 1, req[1] = 0, grants[0] = 0, grants[1] = 0, collision = 1, therm = 4'b0011
   // cycle 4: req[0] = 1, req[1] = 0, grants[0] = 0, grants[1] = 0, collision = 1, therm = 4'b0111
   // cycle 5: req[0] = 1, req[1] = 0, grants[0] = 1, grants[1] = 0, collision = 0, therm = 4'b0000
   // Here, after cycle 0, requestor 0 was masked due to a collision with
   // requestor 1. When requestor 0 sends its second request with no other
   // requestors trying, it incurs a 3 cycle penalty for the thermometer to
   // fill up. While the 3 cycle penalty is detrimental to performance the
   // system does not hang.

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

   // Priority block
   assign block[0] = 1'b0;
   for (j=N-1; j>=1; j=j-1)
     begin : ipri
        assign block[j] = |spec_requests[j-1:0];
     end

   assign grants[N-1:0] = spec_requests[N-1:0] & ~block[N-1:0];

   // Detect collision on pushback
   assign collision = |(requests[N-1:0] & ~grants[N-1:0]);

`ifdef VERILATOR
   assert property (@(posedge clk) $onehot0(grants));
`endif

endmodule
