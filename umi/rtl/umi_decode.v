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
   input [7:0] command,
   // Decoded signals
   output      cmd_invalid,// invalid transaction
   output      cmd_read_request, // read request
   output      cmd_write_posted,// write indicator
   output      cmd_write_signal,// write with eot signal
   output      cmd_write_ack,// write with acknowledge
   output      cmd_write_stream,// write stream
   output      cmd_write_response,// write response
   output      cmd_write_multicast,// write multicast
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

   // Invalid
   assign cmd_invalid        = (command[7:0]==UMI_INVALID);

   // reads
   assign cmd_read_request   = (command[3:0]==UMI_REQUEST_READ[3:0]);

   // Write controls
   assign cmd_write_posted    = (command[3:0]==UMI_WRITE_POSTED[3:0]);
   assign cmd_write_response  = (command[3:0]==UMI_WRITE_RESPONSE[3:0]);
   assign cmd_write_signal    = (command[3:0]==UMI_WRITE_SIGNAL[3:0]);
   assign cmd_write_stream    = (command[3:0]==UMI_WRITE_STREAM[3:0]);
   assign cmd_write_ack       = (command[3:0]==UMI_WRITE_ACK[3:0]);

   // Atomics
   assign cmd_atomic         = (command[3:0]==UMI_ATOMIC[3:0]);
   assign cmd_atomic_add     = (command[7:0]==UMI_ATOMIC_ADD);
   assign cmd_atomic_and     = (command[7:0]==UMI_ATOMIC_AND);
   assign cmd_atomic_or      = (command[7:0]==UMI_ATOMIC_OR);
   assign cmd_atomic_xor     = (command[7:0]==UMI_ATOMIC_XOR);
   assign cmd_atomic_max     = (command[7:0]==UMI_ATOMIC_MAX);
   assign cmd_atomic_min     = (command[7:0]==UMI_ATOMIC_MIN);
   assign cmd_atomic_maxu    = (command[7:0]==UMI_ATOMIC_MAXU);
   assign cmd_atomic_minu    = (command[7:0]==UMI_ATOMIC_MINU);
   assign cmd_atomic_swap    = (command[7:0]==UMI_ATOMIC_SWAP);

endmodule // umi_decode
