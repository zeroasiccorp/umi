/*******************************************************************************
 * Function:  UMI Endpoint
 * Author:    Andreas Olofsson
 * License:
 *
 * Documentation:
 *
 *
 ******************************************************************************/
module umi_endpoint
  #(parameter REG  = 1,         // 1=insert register on read_data
    parameter TYPE = "LIGHT",   // FULL, LIGHT
    // standard parameters
    parameter AW   = 64,
    parameter DW   = 64,        // width of endpoint data
    parameter UW   = 256)
   (//
    input 	    nreset,
    input 	    clk,
    // Incoming UMI request
    input 	    umi_in_valid,
    input [UW-1:0]  umi_in_packet,
    output 	    umi_in_ready,
    // Outgoing UMI response
    output 	    umi_out_valid,
    output [UW-1:0] umi_out_packet,
    input 	    umi_out_ready,
    // Memory interface
    output [AW-1:0] addr, // memory address
    output 	    write, // write enable
    output 	    read, // read request
    output [31:0]   cmd, // pass through command
    output [DW-1:0] write_data, // data to write
    input 	    ready, // device is ready
    input [DW-1:0]  read_data  // data response
    );


   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire			cmd_atomic;		// From umi_decode of umi_decode.v
   wire			cmd_atomic_add;		// From umi_decode of umi_decode.v
   wire			cmd_atomic_and;		// From umi_decode of umi_decode.v
   wire			cmd_atomic_max;		// From umi_decode of umi_decode.v
   wire			cmd_atomic_maxu;	// From umi_decode of umi_decode.v
   wire			cmd_atomic_min;		// From umi_decode of umi_decode.v
   wire			cmd_atomic_minu;	// From umi_decode of umi_decode.v
   wire			cmd_atomic_or;		// From umi_decode of umi_decode.v
   wire			cmd_atomic_swap;	// From umi_decode of umi_decode.v
   wire			cmd_atomic_xor;		// From umi_decode of umi_decode.v
   wire			cmd_invalid;		// From umi_decode of umi_decode.v
   wire			cmd_read;		// From umi_decode of umi_decode.v
   wire			cmd_write_ack;		// From umi_decode of umi_decode.v
   wire			cmd_write_normal;	// From umi_decode of umi_decode.v
   wire			cmd_write_response;	// From umi_decode of umi_decode.v
   wire			cmd_write_signal;	// From umi_decode of umi_decode.v
   wire			cmd_write_stream;	// From umi_decode of umi_decode.v
   wire [6:0]		umi_in_command;		// From umi_unpack of umi_unpack.v
   wire [4*AW-1:0]	umi_in_data;		// From umi_unpack of umi_unpack.v
   wire [AW-1:0]	umi_in_dstaddr;		// From umi_unpack of umi_unpack.v
   wire [19:0]		umi_in_options;		// From umi_unpack of umi_unpack.v
   wire [3:0]		umi_in_size;		// From umi_unpack of umi_unpack.v
   wire [AW-1:0]	umi_in_srcaddr;		// From umi_unpack of umi_unpack.v
   wire			umi_in_write;		// From umi_unpack of umi_unpack.v
   // End of automatics

   //########################
   // REQUEST UNPACK
   //########################

   /*umi_unpack AUTO_TEMPLATE (
    .\(.*\) (umi_in_\1[]),
    )
    */

   umi_unpack #(.UW(UW),
		.AW(AW))
   umi_unpack(/*AUTOINST*/
	      // Outputs
	      .write			(umi_in_write),		 // Templated
	      .command			(umi_in_command[6:0]),	 // Templated
	      .size			(umi_in_size[3:0]),	 // Templated
	      .options			(umi_in_options[19:0]),	 // Templated
	      .dstaddr			(umi_in_dstaddr[AW-1:0]), // Templated
	      .srcaddr			(umi_in_srcaddr[AW-1:0]), // Templated
	      .data			(umi_in_data[4*AW-1:0]), // Templated
	      // Inputs
	      .packet			(umi_in_packet[UW-1:0])); // Templated


   umi_decode
     umi_decode (.write			(umi_in_write),
		 .command		(umi_in_command[6:0]),
		 /*AUTOINST*/
		 // Outputs
		 .cmd_invalid		(cmd_invalid),
		 .cmd_read		(cmd_read),
		 .cmd_atomic		(cmd_atomic),
		 .cmd_write_normal	(cmd_write_normal),
		 .cmd_write_signal	(cmd_write_signal),
		 .cmd_write_ack		(cmd_write_ack),
		 .cmd_write_stream	(cmd_write_stream),
		 .cmd_write_response	(cmd_write_response),
		 .cmd_atomic_swap	(cmd_atomic_swap),
		 .cmd_atomic_add	(cmd_atomic_add),
		 .cmd_atomic_and	(cmd_atomic_and),
		 .cmd_atomic_or		(cmd_atomic_or),
		 .cmd_atomic_xor	(cmd_atomic_xor),
		 .cmd_atomic_min	(cmd_atomic_min),
		 .cmd_atomic_max	(cmd_atomic_max),
		 .cmd_atomic_minu	(cmd_atomic_minu),
		 .cmd_atomic_maxu	(cmd_atomic_maxu));

   assign read                = cmd_read;
   assign addr[AW-1:0]        = umi_in_dstaddr[AW-1:0];
   assign write_data[DW-1:0]  = umi_in_data[DW-1:0];

   //########################################
   //# Pipeline REQUEST ACCESS
   //#######################################

   reg   	    valid_out_reg;
   reg  	    write_out;
   reg [6:0] 	    command_out;
   reg [3:0] 	    size_out;
   reg [19:0] 	    options_out;
   reg [AW-1:0]     dstaddr_out;
   reg [DW-1:0]     read_data_reg;
   wire [4*AW-1:0]  data_out;

   // valid
   always @ (posedge clk or negedge nreset)
     if(!nreset)
       valid_out_reg <= 1'b0;
     else if (umi_out_ready)
       valid_out_reg <= umi_in_valid & cmd_read;

   // turn around transaction
   always @ (posedge clk)
     if(umi_in_valid & cmd_read & umi_out_ready)
       begin
	  dstaddr_out[AW-1:0] <= umi_in_srcaddr[AW-1:0];
	  write_out           <= umi_in_write;
	  command_out[6:0]    <= umi_in_command[6:0];
	  size_out[3:0]       <= umi_in_size[3:0];
	  options_out[19:0]   <= umi_in_options[19:0];
       end

   // register data
   always @ (posedge clk)
     if (cmd_read)
       read_data_reg[DW-1:0] <= read_data[DW-1:0];

   assign data_out[4*AW-1:0] = (REG) ? read_data_reg[DW-1:0] :
			               read_data[DW-1:0];

   //########################
   // RESPONSE
   //########################

   /*umi_pack  AUTO_TEMPLATE (
    .packet_out  (packet_out[]),
    .srcaddr     ({(AW){1'b0}}),
    .burst       (1'b0),
    .\(.*\)      (\1_out[]),
    );
    */

   umi_pack #(.UW(UW),
	      .AW(AW))
   umi_pack(.packet			(umi_out_packet[UW-1:0]),
	    /*AUTOINST*/
	    // Inputs
	    .write			(write_out),		 // Templated
	    .command			(command_out[6:0]),	 // Templated
	    .size			(size_out[3:0]),	 // Templated
	    .options			(options_out[19:0]),	 // Templated
	    .burst			(1'b0),			 // Templated
	    .dstaddr			(dstaddr_out[AW-1:0]),	 // Templated
	    .srcaddr			({(AW){1'b0}}),		 // Templated
	    .data			(data_out[4*AW-1:0]));	 // Templated

   assign umi_out_valid = valid_out_reg;

   assign umi_in_ready = ready & (~read | umi_out_ready) ;


endmodule // umi_endpoint
