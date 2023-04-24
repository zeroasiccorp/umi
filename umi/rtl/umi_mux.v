/*******************************************************************************
 * Function:  UMI Mux (one-hot)
 * Author:    Andreas Olofsson
 * License:
 *
 * Documentation:
 *
 * - Selects between N inputs
 * - Assumes one-hot selects
 *
 ******************************************************************************/
module umi_mux
  #(parameter UW  = 256, // UMI transaction width
    parameter N   = 4    // number of inputs
    )
   (// Incoming UMI
    input [N-1:0]    umi_in_valid,
    input [N*UW-1:0] umi_in_packet,
    output [N-1:0]   umi_in_ready,
    // Outgoing UMI
    output 	     umi_out_valid,
    input 	     umi_out_ready,
    output [UW-1:0]  umi_out_packet
    );

   // valid output
   assign umi_out_valid = |umi_in_valid[N-1:0];

   // ready pusback
   assign umi_in_ready[N-1:0] = ~umi_in_valid[N-1:0] |
				(umi_in_valid[N-1:0] & umi_out_ready);

   // packet mux
   la_vmux #(.N(3),
	     .W(UW))
   la_vmux(.out (umi_out_packet[UW-1:0]),
	   .sel (umi_in_valid[UW-1:0]),
	   .in  (umi_in_packet[N*UW-1:0]));

   //TODO: add checker for one hot!

endmodule
