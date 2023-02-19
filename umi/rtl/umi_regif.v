/*******************************************************************************
 * Function:  UMI Register Interface
 * Author:    Andreas Olofsson
 * License:
 *
 * Documentation:
 *
 * - oob host responsible for ordering
 * - one read request every two clock cycles
 *
 ******************************************************************************/
module umi_regif
  #(parameter TARGET = "DEFAULT", // compile target
    parameter AW     = 64,        // address width
    parameter UW     = 256,       // packet width
    parameter IDW    = 16,        // ID width
    // derived
    parameter DW     = AW         // data width
    )
   (// clk, reset
    input 	      clk, //clk
    input 	      nreset, //async active low reset
    // OOB access
    input 	      oob_in_valid,
    input [UW-1:0]    oob_in_packet,
    output reg 	      oob_in_ready,
    output reg 	      oob_out_valid,
    output [UW-1:0]   oob_out_packet,
    input 	      oob_out_ready,
    // Read/Write register interface
    output [AW-1:0]   reg_addr, // memory address
    output 	      reg_write, // register write
    output 	      reg_read, // register read
    output [7:0]      reg_cmd, // command (eg. atomics)
    output [3:0]      reg_size, // size (byte, etc)
    output [4*DW-1:0] reg_wrdata, // data to write
    input [DW-1:0]    reg_rddata  // readback data
    );

`include "umi_messages.vh"

   wire [AW-1:0]      reg_srcaddr;
   wire [19:0] 	      reg_options;

   //########################
   // UMI INPUT
   //########################

   umi_unpack #(.UW(UW),
		.AW(AW))
   umi_unpack(// Outputs
	      .write	(write),
	      .command	(reg_cmd[7:0]),
	      .size	(reg_size[3:0]),
	      .options	(reg_options[19:0]),
	      .dstaddr	(reg_addr[AW-1:0]),
	      .srcaddr	(reg_srcaddr[AW-1:0]),
	      .data	(reg_wrdata[4*AW-1:0]),
	      // Inputs
	      .packet	(oob_in_packet[UW-1:0]));

   assign reg_read  = ~write & oob_in_valid;
   assign reg_write = write & oob_in_valid;

   always @ (posedge clk or negedge nreset)
     if(!nreset)
       oob_in_ready <= 1'b1;
     else if (oob_out_valid & oob_out_ready)
       oob_in_ready <= 1'b1;
     else if (reg_read)
       oob_in_ready <= 1'b0;

   //############################
   //# UMI OUTPUT
   //############################

   //1. Set on incoming valid read
   //2. Keep high as long as incoming read is set
   //3. If no incoming read and output is ready, clear
   //4. Pne read every two clock cycles

   always @ (posedge clk or negedge nreset)
     if(!nreset)
       oob_out_valid <= 1'b0;
     else if (reg_read)
       oob_out_valid <= 1'b1;
     else if (oob_out_valid & oob_out_ready)
       oob_out_valid <= 1'b0;

   umi_pack #(.UW(UW),
	      .AW(AW))
   umi_pack(// Outputs
	    .packet	(oob_out_packet[UW-1:0]),
	    // Inputs
	    .write	(1'b1),
	    .command    (UMI_WRITE_RESPONSE),//returns write response
	    .size	(reg_size[3:0]),
	    .options	(reg_options[19:0]),
	    .burst	(1'b0),
	    .dstaddr	(reg_srcaddr[AW-1:0]),
	    .srcaddr	({(AW){1'b0}}),
	    .data	({(4){reg_rddata[DW-1:0]}}));

endmodule // umi_regif
