/*******************************************************************************
 * Function:  UMI Register Interface
 * Author:    Andreas Olofsson
 * License:
 *
 * Documentation:
 *
 * The module translates a UMI request into a simple register interface.
 * Read data is returned as UMI response packets. Reads requests can occur
 * at a maximum rate of one transaction every two cycles.
 *
 * Only read/writes <= DW is supported.
 *
 ******************************************************************************/
module umi_regif
  #(parameter TARGET = "DEFAULT", // compile target
    parameter AW = 64,            // address width
    parameter CW = 32,            // address width
    parameter DW = 256,           // data width
    parameter RW = 64,            // register width
    parameter GRPOFFSET = 24,     // group address offset
    parameter GRPAW = 4,          // group address width
    parameter GRPID = 0           // group ID
    )
   (// clk, reset
    input           clk,        //clk
    input           nreset,     //async active low reset
    // UMI access
    input           udev_req_valid,
    input [CW-1:0]  udev_req_cmd,
    input [AW-1:0]  udev_req_dstaddr,
    input [AW-1:0]  udev_req_srcaddr,
    input [DW-1:0]  udev_req_data,
    output reg      udev_req_ready,
    output reg      udev_resp_valid,
    output [CW-1:0] udev_resp_cmd,
    output [AW-1:0] udev_resp_dstaddr,
    output [AW-1:0] udev_resp_srcaddr,
    output [DW-1:0] udev_resp_data,
    input           udev_resp_ready,
    // Read/Write register interface
    output [AW-1:0] reg_addr,   // memory address
    output          reg_write,  // register write
    output          reg_read,   // register read
    output [7:0]    reg_cmd,    // command (eg. atomics)
    output [3:0]    reg_size,   // size (byte, etc)
    output [RW-1:0] reg_wrdata, // data to write
    input [RW-1:0]  reg_rddata  // readback data
    );

`include "umi_messages.vh"

   wire [AW-1:0]      reg_srcaddr;
   wire [19:0] 	      reg_options;

   //########################
   // UMI INPUT
   //########################

   assign reg_addr[AW-1:0]   = udev_req_dstaddr[AW-1:0];
   assign reg_wrdata[RW-1:0] = udev_resp_data[RW-1:0];

   /* umi_unpack AUTO_TEMPLATE(
    .command    (reg_cmd[]),
    .\(.*\)     (reg_\1[]),
    .packet_cmd (udev_req_cmd[]),
    );*/
   umi_unpack #(.DW(DW),
                .CW(CW),
		.AW(AW))
   umi_unpack(/*AUTOINST*/
              // Outputs
              .command          (reg_cmd[7:0]),          // Templated
              .size             (reg_size[3:0]),         // Templated
              .options          (reg_options[19:0]),     // Templated
              // Inputs
              .packet_cmd       (udev_req_cmd[CW-1:0])); // Templated

   umi_write umi_write(.write (write), .command	(reg_cmd[7:0]));

   assign group_match = (reg_addr[GRPOFFSET+:GRPAW]==GRPID[GRPAW-1:0]);

   assign reg_read  = ~write & udev_req_valid & group_match;
   assign reg_write =  write & udev_req_valid & group_match;

   // single cycle stall on every ready
   always @ (posedge clk or negedge nreset)
     if(!nreset)
       udev_req_ready <= 1'b0;
     else if (udev_req_valid & udev_resp_ready)
       udev_req_ready <= ~udev_req_ready;
     else
       udev_req_ready <= 1'b0;

   //############################
   //# UMI OUTPUT
   //############################

   //1. Set on incoming valid read
   //2. Keep high as long as incoming read is set
   //3. If no incoming read and output is ready, clear

   always @ (posedge clk or negedge nreset)
     if(!nreset)
       udev_resp_valid <= 1'b0;
     else if (reg_read)
       udev_resp_valid <= 1'b1;
     else if (udev_resp_valid & udev_resp_ready)
       udev_resp_valid <= 1'b0;

   assign udev_resp_dstaddr[AW-1:0] = reg_srcaddr[AW-1:0];
   assign udev_resp_srcaddr[AW-1:0] = {(AW){1'b0}};
   assign udev_resp_data[DW-1:0]    = {(4){reg_rddata[RW-1:0]}};

   umi_pack #(.DW(DW),
              .CW(CW),
	      .AW(AW))
   umi_pack(// Outputs
            .packet_cmd (udev_resp_cmd[CW-1:0]),
	    // Inputs
	    .command    (UMI_RESP_WRITE),//returns write response
	    .size	(reg_size[3:0]),
	    .options	(reg_options[19:0]),
	    .burst	(1'b0));

endmodule // umi_regif
