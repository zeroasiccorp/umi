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
 * - Priority selector
 * - Index zero has highest priority.
 *
 ******************************************************************************/

module umi_priority
  #(parameter N   = 4    // number of inputs
    )
   (input [N-1:0]  requests, // request vector ([0] is highest priority)
    output [N-1:0] grants    // outgoing grant vector
    );

   wire [N-1:0]   mask;
   genvar         j;

   // priority maskx
   assign mask[0] = 1'b0;
   for (j=N-1; j>=1; j=j-1)
     begin : ipri
        assign mask[j] = |requests[j-1:0];
     end

   // priority grant circuit
   assign grants[N-1:0] = requests[N-1:0] & ~mask[N-1:0];

endmodule // umi_priority
