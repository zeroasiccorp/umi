/*******************************************************************************
 * Function:  UMI Pipeline Stage
 * Author:    Andreas Olofsson
 * License:
 *
 * Documentation:
 *
 * -This module create a single cycle umi pipeline.
 *
 * -The "umi_in_ready" output is ommitted to amke it clear that the ready signal
 * must be broadcasted externally.
 *
 * -We don't reset the packet
 *
 ******************************************************************************/
module umi_pipeline
  #(parameter UW  = 256
    )
   (// clock, reset
    input 		clk,
    input 		nreset,
    // Incoming UMI request
    input 		umi_in_valid,
    input [UW-1:0] 	umi_in_packet,
    // Outgoing UMI response
    output reg 		umi_out_valid,
    output reg [UW-1:0] umi_out_packet,
    input 		umi_out_ready
    );

   // valid
   always @ (posedge clk or negedge nreset)
     if(!nreset)
       umi_out_valid <= 'b0;
     else if (umi_out_ready)
       umi_out_valid <= umi_in_valid;

   // packet
   always @ (posedge clk)
     if (umi_out_ready & umi_in_valid)
       umi_out_packet[UW-1:0] <= umi_in_packet[UW-1:0];

endmodule
