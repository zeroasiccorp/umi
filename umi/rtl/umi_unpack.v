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
    parameter CW - 32,
    parameter UW = 256)
   (
    // Input packet
    input [CW-1:0]  packet_cmd,
    input [AW-1:0]  packet_src_addr,
    input [AW-1:0]  packet_dst_addr,
    input [UW-1:0]  packet_payload,
    // Control
    output [7:0]    command, // raw opcode
    output [3:0]    size,    // transaction size
    output [19:0]   options, // raw command
    //Address/Data
    output [AW-1:0] dstaddr, // read/write target address
    output [AW-1:0] srcaddr, // read return address
    output [UW-1:0] data     // write data
    );

   // data field unpacker
   generate
      if(CW==32 & AW==64 & UW==256) begin : p256
	 assign command[7:0]    = packet_cmd[7:0];
	 assign size[3:0]       = packet_cmd[11:8];
	 assign options[19:0]   = packet_cmd[31:12];
	 assign dstaddr[63:0]   = packet_dst_addr[63:0];
	 assign srcaddr[63:0]   = packet_src_addr[63:0];
	 assign data[255:0]     = packet_payload[255:0];
      end
   endgenerate

endmodule // umi_unpack
