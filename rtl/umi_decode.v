/*******************************************************************************
 * Function:  Universal Memory Interface (UMI) Command Decoder
 * Author:    Andreas Olofsson
 * License:
 *
 * Documentation:
 *
 *
 ******************************************************************************/
module umi_decode
  (
   // Packet Command
   input [31:0]  cmd,
   // Read/Write
   output 	 out_write,// write without side effect
   output 	 out_write_signal,// write with signal
   output 	 out_write_ack,// write with acknowledge
   output 	 out_read, // read without side effect
   // Atomics
   output 	 out_atomic_add,
   output 	 out_atomic_and,
   output 	 out_atomic_or,
   output 	 out_atomic_xor,
   output 	 out_atomic_swap,
   output 	 out_atomic_min,
   output 	 out_atomic_max,
   // Partial decode
   output [7:0]  out_opcode,
   output [3:0]  out_length,
   output [19:0] out_user
   );

endmodule // umi_decode
