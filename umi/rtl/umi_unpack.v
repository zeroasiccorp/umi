/*******************************************************************************
 * Function:  Universal Memory Interface (UMI) Unpack(er)
 * Author:    Andreas Olofsson
 * License:
 *
 * Documentation:
 *
 *
 ******************************************************************************/
module umi_unpack
  #(parameter AW = 64,
    parameter UW = 256)
   (
    // Input packet
    input [UW-1:0]    packet,
    //Address/Data
    output [AW-1:0]   dstaddr, // read/write target address
    output [AW-1:0]   srcaddr, // read return address
    output [4*AW-1:0] data, // write data
    output [31:0]     cmd // raw command
    );

   // data field unpacker
   generate
      if(AW==64 & UW==256) begin : p256
	 assign cmd[31:0]       = packet[31:0];
	 assign dstaddr[31:0]   = packet[63:32];
	 assign dstaddr[63:32]  = packet[255:224];
	 assign srcaddr[31:0]   = packet[95:64];
	 assign srcaddr[63:32]  = packet[223:192];
	 assign data[31:0]      = packet[127:96];
	 assign data[63:32]     = packet[159:128];
	 assign data[95:64]     = packet[191:160];
	 assign data[127:96]    = packet[223:192];
	 assign data[159:128]   = packet[255:224];
	 assign data[191:160]   = packet[31:0];
	 assign data[223:192]   = packet[63:32];
	 assign data[255:224]   = packet[95:64];
      end
   endgenerate

endmodule // umi_unpack
