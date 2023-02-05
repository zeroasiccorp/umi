/*******************************************************************************
 * Function:  Universal Memory Interface (UMI) Unpack(er)
 * Author:    Andreas Olofsson
 * License:
 *
 * Documentation:
 *
 * Higher priority write/response (packet[0]==1)
 *
 * 1. stores
 * 2. read (load) responses
 * 3. atomic response
 * 4. acks
 * 5. other responses
 *
 * Lower priority read/request (packet[0]==0)
 *
 * 1. loads
 * 2. atomic request
 * 3. stores/writes that need acks
 *
 ******************************************************************************/
module umi_unpack
  #(parameter AW = 64,
    parameter UW = 256)
   (
    // Input packet
    input [UW-1:0]    packet,
    // Control
    output 	      write, // write transaction
    output [7:0]      command, // raw opcode
    output [3:0]      size, // transaction size
    output [19:0]     options, // raw command
    //Address/Data
    output [AW-1:0]   dstaddr, // read/write target address
    output [AW-1:0]   srcaddr, // read return address
    output [4*AW-1:0] data // write data
    );

   // data field unpacker
   generate
      if(AW==64 & UW==256) begin : p256
	 assign write           = packet[0];
	 assign command[7:0]    = packet[7:0];
	 assign size[3:0]       = packet[11:8];
	 assign options[19:0]   = packet[31:12];
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
