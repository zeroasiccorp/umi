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
    parameter UW = 256)
   (
    // Command inputs
    input [7:0]      opcode,
    input [3:0]      size,// number of bytes to transfer
    input [19:0]     user, // user control field
    input 	     burst, // active burst in process
    // Address/Data
    input [AW-1:0]   dstaddr, // destination address
    input [AW-1:0]   srcaddr, // source address (for reads/atomics)
    input [4*AW-1:0] data, // data
    // Output packet
    output [UW-1:0]  packet
    );

   wire [31:0] 	     cmd_out;
   wire [255:0]      data_out;

   // command packer
   assign cmd_out[7:0]   = opcode[7:0];
   assign cmd_out[11:8]  = size[3:0];
   assign cmd_out[31:12] = user[19:0];

   // data/address packer
   wire cmd_read;
   generate
      if(AW==64 & UW==256) begin : p256
	 // see README to understand why...
	 assign data_out[255:0] = {data[159:0], data[255:160]};
	 // driving data baseed on transaction type
	 assign packet[31:0]    = burst ? data_out[31:0]  : cmd_out[31:0];
	 assign packet[63:32]   = burst ? data_out[63:32] : dstaddr[31:0];
	 assign packet[95:64]   = burst ? data_out[95:64] : srcaddr[31:0];
	 assign packet[191:96]  = data_out[191:96];
	 assign packet[223:192] = cmd_read ? srcaddr[63:32] : data_out[223:192];
	 assign packet[255:224] = burst ? data_out[255:224] : dstaddr[63:32];
      end
   endgenerate

   wire			cmd_atomic;
   wire			cmd_atomic_add;
   wire			cmd_atomic_and;
   wire			cmd_atomic_max;
   wire			cmd_atomic_min;
   wire			cmd_atomic_or;
   wire			cmd_atomic_swap;
   wire			cmd_atomic_xor;
   wire			cmd_invalid;
   wire [7:0]		cmd_opcode;
   wire [3:0]		cmd_size;
   wire [19:0]		cmd_user;
   wire			cmd_write;
   wire			cmd_write_ack;
   wire			cmd_write_normal;
   wire			cmd_write_response;
   wire			cmd_write_signal;
   wire			cmd_write_stream;

   umi_decode umi_decode (.cmd			(cmd_out[31:0]),
			  /*AUTOINST*/
			  // Outputs
			  .cmd_invalid		(cmd_invalid),
			  .cmd_write		(cmd_write),
			  .cmd_read		(cmd_read),
			  .cmd_atomic		(cmd_atomic),
			  .cmd_write_normal	(cmd_write_normal),
			  .cmd_write_signal	(cmd_write_signal),
			  .cmd_write_ack	(cmd_write_ack),
			  .cmd_write_stream	(cmd_write_stream),
			  .cmd_write_response	(cmd_write_response),
			  .cmd_atomic_swap	(cmd_atomic_swap),
			  .cmd_atomic_add	(cmd_atomic_add),
			  .cmd_atomic_and	(cmd_atomic_and),
			  .cmd_atomic_or	(cmd_atomic_or),
			  .cmd_atomic_xor	(cmd_atomic_xor),
			  .cmd_atomic_min	(cmd_atomic_min),
			  .cmd_atomic_max	(cmd_atomic_max),
			  .cmd_opcode		(cmd_opcode[7:0]),
			  .cmd_size		(cmd_size[3:0]),
			  .cmd_user		(cmd_user[19:0]));

endmodule // umi_pack
