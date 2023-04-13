/*******************************************************************************
 * Function:  UMI Write Decoder
 * Author:    Andreas Olofsson
 * License:
 *
 * Documentation:
 *
 *
 ******************************************************************************/
module umi_write
  (
   input [7:0] command, // Packet Command
   output      write    // write indicator
   );

   umi_decode
     umi_decode(// Outputs
		.cmd_write		(write),
		.cmd_request		(),
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

endmodule
