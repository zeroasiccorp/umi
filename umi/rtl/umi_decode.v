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
   output      cmd_read, // read request
   output      cmd_atomic,// read-modify-write
   output      cmd_write_normal,// write indicator
   output      cmd_write_signal,// write with eot signal
   output      cmd_write_ack,// write with acknowledge
   output      cmd_write_stream,// write stream
   output      cmd_write_response,// write response
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

   // Command grouping
   assign cmd_invalid     = ~|command[6:0];
   assign cmd_read        =  ~write & ~cmd_invalid;
   assign cmd_atomic      = cmd_read & (command[2:0]==3'b010);

   // Write controls
   assign cmd_write_normal   = write & (command[2:0]==3'b000);
   assign cmd_write_response = write & (command[2:0]==3'b001);
   assign cmd_write_signal   = write & (command[2:0]==3'b010);
   assign cmd_write_stream   = write & (command[2:0]==3'b011);
   assign cmd_write_ack      = write & (command[2:0]==3'b100);
   //assign cmd_res0         = write & (command[2:0]==3'b101);
   //assign cmd_res1         = write & (command[2:0]==3'b110);
   //assign cmd_res2         = write & (command[2:0]==3'b111);

   // Atomics
   assign cmd_atomic_add  = cmd_atomic & (command[6:3]==4'b0000);
   assign cmd_atomic_and  = cmd_atomic & (command[6:3]==4'b0001);
   assign cmd_atomic_or   = cmd_atomic & (command[6:3]==4'b0010);
   assign cmd_atomic_xor  = cmd_atomic & (command[6:3]==4'b0011);
   assign cmd_atomic_max  = cmd_atomic & (command[6:3]==4'b0100);
   assign cmd_atomic_min  = cmd_atomic & (command[6:3]==4'b0101);
   assign cmd_atomic_maxu = cmd_atomic & (command[6:3]==4'b0110);
   assign cmd_atomic_minu = cmd_atomic & (command[6:3]==4'b0111);
   assign cmd_atomic_swap = cmd_atomic & (command[6:3]==4'b1000);

endmodule // umi_decode
