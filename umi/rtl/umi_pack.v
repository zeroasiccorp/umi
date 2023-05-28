/*******************************************************************************
 * Function:  Universal Memory Interface (UMI) Packer
 * Author:    Andreas Olofsson
 * License:
 *
 * Documentation:
 *
 *
 ******************************************************************************/
module umi_pack
  #(parameter AW = 64,
    parameter CW = 32,
    parameter UW = 256)
   (
    // Command inputs
    input [7:0]      command,
    input [3:0]      size,// number of bytes to transfer
    input [19:0]     options, // user options
    input 	     burst, // active burst in process
    // Address/Data
    input [AW-1:0]   dstaddr, // destination address
    input [AW-1:0]   srcaddr, // source address (for reads/atomics)
    input [UW-1:0]   data, // data
    // Output packet
    output [CW-1:0]  packet_cmd,
    output [AW-1:0]  packet_dst_addr,
    output [AW-1:0]  packet_src_addr,
    output [UW-1:0]  packet_payload
    );

   wire [31:0] 	     cmd_out;

   // command packer
   assign cmd_out[7:0]   = command[7:0];
   assign cmd_out[11:8]  = size[3:0];
   assign cmd_out[31:12] = options[19:0];

   // Command decode
   umi_decode
     umi_decode(// Outputs
		.cmd_write		(),
		.cmd_request		(read),
		.cmd_response		(),
		.cmd_invalid		(),
		.cmd_read       	(),
		.cmd_write_posted	(),
		.cmd_write_signal	(),
		.cmd_write_ack		(),
		.cmd_write_stream	(),
		.cmd_write_response	(),
		.cmd_write_multicast	(),
		.cmd_atomic		(),
		.cmd_atomic_swap	(),
		.cmd_atomic_add		(),
		.cmd_atomic_and		(),
		.cmd_atomic_or		(),
		.cmd_atomic_xor		(),
		.cmd_atomic_min		(),
		.cmd_atomic_max		(),
		.cmd_atomic_minu	(),
		.cmd_atomic_maxu	(),
		// Inputs
		.command		(command[7:0]));

   generate
      if(CW == 32 & AW==64 & UW==256) begin : p256
	 assign packet_cmd[31:0] = cmd_out[31:0];
	 assign packet_dst_addr[63:0] = dstaddr[63:0];
	 assign packet_src_addr[63:0] = srcaddr[63:0];
	 assign packet_payload[255:0] = data[255:0];
      end
   endgenerate

endmodule
