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
   input [6:0] command,
   input       write,
   // Decoded signals
   output      cmd_invalid,// invalid transaction
   output      cmd_read_request, // read request
   output      cmd_write_posted,// write indicator
   output      cmd_write_signal,// write with eot signal
   output      cmd_write_ack,// write with acknowledge
   output      cmd_write_stream,// write stream
   output      cmd_write_response,// write response
   output      cmd_atomic,// read-modify-write
   output      cmd_atomic_swap,
   output      cmd_atomic_add,
   output      cmd_atomic_and,
   output      cmd_atomic_or,
   output      cmd_atomic_xor,
   output      cmd_atomic_min,
   output      cmd_atomic_max,
   output      cmd_atomic_minu,
   output      cmd_atomic_maxu
   );

`include "umi_messages.vh"

   // Command grouping
   assign cmd_invalid        = (command[7:0]==INVALID);
   assign cmd_read_request   = (command[7:0]==READ_REQUEST);
   assign cmd_atomic         = (command[3:0]==ATOMIC);

   // Write controls
   assign cmd_write_posted   = (command[7:0]==WRITE_POSTED);
   assign cmd_write_response = (command[7:0]==WRITE_RESPONSE);
   assign cmd_write_signal   = (command[7:0]==WRITE_SIGNAL);
   assign cmd_write_stream   = (command[7:0]==WRITE_STREAM);
   assign cmd_write_ack      = (command[7:0]==WRITE_ACK);

   // Atomics
   assign cmd_atomic_add     = (command[7:0]==ATOMIC_ADD);
   assign cmd_atomic_and     = (command[7:0]==ATOMIC_AND);
   assign cmd_atomic_or      = (command[7:0]==ATOMIC_OR);
   assign cmd_atomic_xor     = (command[7:0]==ATOMIC_XOR);
   assign cmd_atomic_max     = (command[7:0]==ATOMIC_MAX);
   assign cmd_atomic_min     = (command[7:0]==ATOMIC_MIN);
   assign cmd_atomic_maxu    = (command[7:0]==ATOMIC_MAXU);
   assign cmd_atomic_minu    = (command[7:0]==ATOMIC_MINU);
   assign cmd_atomic_swap    = (command[7:0]==ATOMIC_SWAP);

endmodule // umi_decode
