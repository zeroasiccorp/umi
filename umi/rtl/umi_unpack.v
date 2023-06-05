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
    parameter CW = 32,
    parameter DW = 256)
   (
    // Input packet
    input [CW-1:0]  packet_cmd,
    // Control
    output [7:0]    command, // raw opcode
    output [3:0]    size,    // transaction size
    output [19:0]   options  // raw command
    );

   // data field unpacker
   generate
      if(CW==32) begin : p256
	 assign command[7:0]    = packet_cmd[7:0];
	 assign size[3:0]       = packet_cmd[11:8];
	 assign options[19:0]   = packet_cmd[31:12];
      end
   endgenerate

endmodule // umi_unpack
