/*******************************************************************************
 * Function:  UMI Packet Address Field Extractor
 * Author:    Andreas Olofsson
 * License:
 *
 ******************************************************************************/
module umi_addr
  #(parameter AW = 64,
    parameter UW = 256
    )
   (
    input [UW-1:0]  packet, // full packet
    output [AW-1:0] dstaddr // read/write target address
    );

   umi_unpack #(.UW(UW))
   umi_unpack(// Outputs
	      .command	(),
	      .size	(),
	      .options	(),
	      .dstaddr	(dstaddr[AW-1:0]),
	      .srcaddr	(),
	      .data	(),
	      // Inputs
	      .packet	(packet[UW-1:0]));

endmodule
