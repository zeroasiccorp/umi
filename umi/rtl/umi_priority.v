/*******************************************************************************
 * Function:  UMI Priority Selector
 * Author:    Andreas Olofsson
 *
 * Copyright (c) 2023 Zero ASIC Corporation
 * This code is licensed under Apache License 2.0 (see LICENSE for details)
 *
 * Documentation:
 *
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
