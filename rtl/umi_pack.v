/*******************************************************************************
 * Function:  Universal Memory Interface (UMI) Packer
 * Author:    Andreas Olofsson
 ******************************************************************************/
module umi_pack
  #(parameter AW = 64)
   (
    //Command Inputs
    input [7:0]       opcode_in,
    input [3:0]       size_in,// number of bytes to transfer
    input [19:0]      user_in, //user control field
    //Address/Data
    input [AW-1:0]    dstaddr_in, //destination address
    input [AW-1:0]    srcaddr_in, //source address (for reads)
    input [4*AW-1:0]  data_in, //data
    //Output packet
    output [4*AW-1:0] packet_out
    );


endmodule // umi_pack
