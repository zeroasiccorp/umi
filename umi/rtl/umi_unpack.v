/*******************************************************************************
 * Function:  Universal Memory Interface (UMI) Packer
 * Author:    Andreas Olofsson
 ******************************************************************************/
module umi_unpack
  #(parameter AW = 64,
    parameter PW = 256)
   (
    // Input packet
    input [PW-1:0]    packet_in,
    // Decoded signals
    output 	      cmd_write,// write
    output 	      cmd_signal,// signal
    output 	      cmd_read,
    output 	      cmd_atomic_add,
    output 	      cmd_atomic_and,
    output 	      cmd_atomic_or,
    output 	      cmd_atomic_xor,
    output 	      cmd_atomic_swap,
    output 	      cmd_atomic_min,
    output 	      cmd_atomic_max,
    //Command Fields
    output [7:0]      cmd_opcode,// raw opcode
    output [3:0]      cmd_size, // bust length(up to 16)
    output [19:0]     cmd_user, //user field
    //Address/Data
    output [AW-1:0]   dstaddr, // read/write target address
    output [AW-1:0]   srcaddr, // read return address
    output [AW-1:0] data     // write data
    );

endmodule // umi_unpack
