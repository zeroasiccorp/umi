/*******************************************************************************
 * Function:  UMI Endpoint
 * Author:    Andreas Olofsson
 * License:
 *
 * Documentation:
 *
 * TODO:
 * - user TYPE to minimize interface for things like registers
 * - add support for burst
 *
 ******************************************************************************/
module umi_endpoint
  #(parameter AW   = 64,
    parameter REG  = 1,         // register read_data
    parameter TYPE = "LIGHT",   // FULL, LIGHT
    parameter DW   = 64,        // width of endpoint data
    parameter UW   = 256)
   (//
    input 	    nreset,
    input 	    clk,
    // Incoming UMI request
    input 	    valid_in,
    input [UW-1:0]  packet_in,
    output 	    ready_out,
    // Outgoing UMI response
    output 	    valid_out,
    output [UW-1:0] packet_out,
    input 	    ready_in,
    // Memory interface
    output [AW-1:0] addr, // memory address
    output 	    write, // write enable
    output 	    read, // read request
    output [31:0]   cmd, // pass through command
    output [DW-1:0] write_data, // data to write
    input [DW-1:0]  read_data  // data response
    );

   localparam PW = UW; // temp alias
   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire			cmd_atomic;		// From umi_unpack of umi_unpack.v
   wire			cmd_atomic_add;		// From umi_unpack of umi_unpack.v
   wire			cmd_atomic_and;		// From umi_unpack of umi_unpack.v
   wire			cmd_atomic_max;		// From umi_unpack of umi_unpack.v
   wire			cmd_atomic_min;		// From umi_unpack of umi_unpack.v
   wire			cmd_atomic_or;		// From umi_unpack of umi_unpack.v
   wire			cmd_atomic_swap;	// From umi_unpack of umi_unpack.v
   wire			cmd_atomic_xor;		// From umi_unpack of umi_unpack.v
   wire			cmd_invalid;		// From umi_unpack of umi_unpack.v
   wire [7:0]		cmd_opcode;		// From umi_unpack of umi_unpack.v
   wire			cmd_read;		// From umi_unpack of umi_unpack.v
   wire [3:0]		cmd_size;		// From umi_unpack of umi_unpack.v
   wire [19:0]		cmd_user;		// From umi_unpack of umi_unpack.v
   wire			cmd_write;		// From umi_unpack of umi_unpack.v
   wire			cmd_write_ack;		// From umi_unpack of umi_unpack.v
   wire			cmd_write_normal;	// From umi_unpack of umi_unpack.v
   wire			cmd_write_response;	// From umi_unpack of umi_unpack.v
   wire			cmd_write_signal;	// From umi_unpack of umi_unpack.v
   wire			cmd_write_stream;	// From umi_unpack of umi_unpack.v
   wire [4*AW-1:0]	data;			// From umi_unpack of umi_unpack.v
   wire [AW-1:0]	dstaddr;		// From umi_unpack of umi_unpack.v
   wire [AW-1:0]	srcaddr;		// From umi_unpack of umi_unpack.v
   // End of automatics

   //########################
   // UMI UNPACK
   //########################

   umi_unpack #(.PW(UW),
		.AW(AW))
   umi_unpack(/*AUTOINST*/
	      // Outputs
	      .cmd_invalid		(cmd_invalid),
	      .cmd_write		(cmd_write),
	      .cmd_read			(cmd_read),
	      .cmd_atomic		(cmd_atomic),
	      .cmd_write_normal		(cmd_write_normal),
	      .cmd_write_signal		(cmd_write_signal),
	      .cmd_write_ack		(cmd_write_ack),
	      .cmd_write_stream		(cmd_write_stream),
	      .cmd_write_response	(cmd_write_response),
	      .cmd_atomic_swap		(cmd_atomic_swap),
	      .cmd_atomic_add		(cmd_atomic_add),
	      .cmd_atomic_and		(cmd_atomic_and),
	      .cmd_atomic_or		(cmd_atomic_or),
	      .cmd_atomic_xor		(cmd_atomic_xor),
	      .cmd_atomic_min		(cmd_atomic_min),
	      .cmd_atomic_max		(cmd_atomic_max),
	      .cmd_opcode		(cmd_opcode[7:0]),
	      .cmd_size			(cmd_size[3:0]),
	      .cmd_user			(cmd_user[19:0]),
	      .dstaddr			(dstaddr[AW-1:0]),
	      .srcaddr			(srcaddr[AW-1:0]),
	      .data			(data[4*AW-1:0]),
	      // Inputs
	      .packet_in		(packet_in[PW-1:0]));

   assign addr[AW-1:0] = dstaddr[AW-1:0];
   assign write        = cmd_write;
   assign read         = cmd_read;
   assign cmd[31:0]    = packet_in[31:0];

   //########################################
   //# Pipeline
   //#######################################

   reg   	    valid_out;
   reg [3:0] 	    size_out;
   reg [19:0] 	    user_out;
   reg [7:0] 	    opcode_out;
   reg [AW-1:0]     dstaddr_out;
   reg [DW-1:0]     read_data_reg;
   wire [4*AW-1:0]  data_out;

   // valid
   always @ (posedge clk or negedge nreset)
     if(!nreset)
       valid_out <= 1'b0;
     else if(ready_in)
       valid_out <= valid_in & cmd_read;

   // ready signal
   assign ready_out = ready_in;

   // turn around transaction
   always @ (posedge clk)
     if(ready_in & valid_in & cmd_read)
       begin
	  dstaddr_out[AW-1:0] <= srcaddr[AW-1:0];
	  size_out[3:0]       <= cmd_size[3:0];
	  opcode_out[7:0]     <= cmd_opcode[3:0];
	  user_out[19:0]      <= cmd_user[19:0];
       end

   // register data
   always @ (posedge clk)
     if (cmd_read)
       read_data_reg[DW-1:0] <= read_data[DW-1:0];

   assign data_out[4*AW-1:0] = (REG==1) ? read_data_reg[DW-1:0] :
			                  read_data[DW-1:0];

   //########################
   // UMI PACK
   //########################

   /*umi_pack  AUTO_TEMPLATE (
    .packet_out  (packet_out[]),
    .srcaddr     ({(AW){1'b0}}),
    .burst       (1'b0),
    .\(.*\)      (\1_out[]),
    );
    */

   umi_pack #(.PW(UW),
	      .AW(AW))
   umi_pack(/*AUTOINST*/
	    // Outputs
	    .packet_out			(packet_out[PW-1:0]),	 // Templated
	    // Inputs
	    .opcode			(opcode_out[7:0]),	 // Templated
	    .size			(size_out[3:0]),	 // Templated
	    .user			(user_out[19:0]),	 // Templated
	    .burst			(1'b0),			 // Templated
	    .dstaddr			(dstaddr_out[AW-1:0]),	 // Templated
	    .srcaddr			({(AW){1'b0}}),		 // Templated
	    .data			(data_out[4*AW-1:0]));	 // Templated


endmodule // umi_endpoint
