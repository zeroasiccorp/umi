/*******************************************************************************
 * Function:  UMI Priority Selector
 * Author:    Andreas Olofsson
 * License:
 *
 * Documentation:
 *
 * - Index zero has highest priority.
 *
 ******************************************************************************/
module umi_priority
  #(parameter N   = 4    // number of inputs
    )
   (// Inputs Valids (requests)
     input [N-1:0]  umi_in_valid,
    // Output Valids (grants)
     output [N-1:0] umi_out_valid
    );

   wire [N-1:0]   mask;
   genvar 	  j;

   // priority mask
   assign mask[0] = 1'b0;
   for (j=N-1; j>=1; j=j-1)
     begin : ipri
	assign mask[j] = |umi_in_valid[j-1:0];
     end

   //grant circuit
   assign umi_out_valid[N-1:0] = umi_in_valid[N-1:0] & ~mask[N-1:0];

endmodule // umi_priority
