/*******************************************************************************
 * Function:  UMI Packet Address Field Extractor
 * Author:    Andreas Olofsson
 * License:
 *
 ******************************************************************************/
module umi_addr
  #(parameter AW = 64,
    parameter CW = 32,
    parameter UW = 256
    )
   (
    input [CW-1:0]  packet_cmd,
    input [AW-1:0]  packet_src_addr,
    input [AW-1:0]  packet_dst_addr,
    input [UW-1:0]  packet_payload,
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
              .packet_cmd      (packet_cmd[CW-1:0]),
              .packet_dst_addr (packet_dst_addr[AW-1:0]),
              .packet_src_addr (packet_src_addr[AW-1:0]),
	      .packet_payload  (packet_payload[UW-1:0]));

endmodule
