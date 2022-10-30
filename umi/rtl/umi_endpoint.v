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
    input 	      nreset,
    input 	      clk,
    // Write/response
    input 	      umi0_in_valid,
    input [UW-1:0]    umi0_in_packet,
    output 	      umi0_in_ready,
    // Read/request
    input 	      umi1_in_valid,
    input [UW-1:0]    umi1_in_packet,
    output 	      umi1_in_ready,
    // Outgoing UMI write response
    output reg 	      umi0_out_valid,
    output [UW-1:0]   umi0_out_packet,
    input 	      umi0_out_ready,
    // Memory interface
    output [AW-1:0]   loc_addr, // memory address
    output 	      loc_write, // write enable
    output 	      loc_read, // read request
    output [6:0]      loc_cmd, // pass through command
    output [3:0]      loc_size, // pass through command
    output [19:0]     loc_options, // pass through command
    output [4*DW-1:0] loc_wrdata, // data to write
    input [DW-1:0]    loc_rddata, // data response
    input 	      loc_ready  // device is ready
    );

   // local regs
   reg [3:0] 		size_out;
   reg [19:0] 		options_out;
   reg [AW-1:0] 	dstaddr_out;
   reg [DW-1:0] 	data_out;

   // local wires
   wire [AW-1:0] 	loc_srcaddr;
   wire [4*AW-1:0] 	data_mux;

   wire 		umi_ready;
   wire [UW-1:0] 	umi_in_packet;
   wire 		umi_in_valid;

   wire 		umi0_ready;
   wire 		umi1_ready;

   //########################
   // INPUT ARBITER
   //########################

   assign umi0_in_ready = loc_ready;

   assign umi1_in_ready = loc_ready &
			  umi1_ready &
			  ~(umi1_in_valid & ~umi0_out_ready);

   //########################
   // INPUT ARBITER
   //########################

   umi_mux #(.N(2))
   umi_mux(// Outputs
	   .umi_out_valid    (umi_in_valid),
	   .umi_out_packet   (umi_in_packet[UW-1:0]),
	   .umi_in_ready     ({umi1_ready,umi0_ready}),
	   // Inputs
	   .umi_in_packet    ({umi1_in_packet,umi0_in_packet}),
	   .umi_in_valid     ({umi1_in_valid,umi0_in_valid}),
	   .clk		     (clk),
	   .nreset	     (nreset),
	   .mode	     (2'b00),
	   .mask	     (2'b00));

   //########################
   // UMI UNPACK
   //########################

   umi_unpack #(.UW(UW),
		.AW(AW))
   umi_unpack(// Outputs
	      .write	(loc_write),
	      .command	(loc_cmd[6:0]),
	      .size	(loc_size[3:0]),
	      .options	(loc_options[19:0]),
	      .dstaddr	(loc_addr[AW-1:0]),
	      .srcaddr	(loc_srcaddr[AW-1:0]),
	      .data	(loc_wrdata[4*AW-1:0]),
	      // Inputs
	      .packet	(umi_in_packet[UW-1:0]));

   assign loc_read = ~loc_write & umi_in_valid;

   //############################
   //# Outgoing Transaction
   //############################

   //1. Set on incoming valid read
   //2. Keep high as long as incoming read is set
   //3. If no incoming read and output is ready, clear
   always @ (posedge clk or negedge nreset)
     if(!nreset)
       umi0_out_valid <= 1'b0;
     else if (loc_read)
       umi0_out_valid <= 1'b1;
     else if (umi0_out_valid & umi0_out_ready)
       umi0_out_valid <= 1'b0;

   //#############################
   //# Pipeline Packet
   //##############################

   always @ (posedge clk)
     if(loc_read)
       begin
	  data_out[DW-1:0]    <= loc_rddata[DW-1:0];
	  dstaddr_out[AW-1:0] <= loc_srcaddr[AW-1:0];
	  size_out[3:0]       <= loc_size[3:0];
	  options_out[19:0]   <= loc_options[19:0];
       end

   // selectively add pipestage
   assign data_mux[4*AW-1:0] = (REG) ? data_out[DW-1:0] :
			               loc_rddata[DW-1:0];

   // pack up the packet
   umi_pack #(.UW(UW),
	      .AW(AW))
   umi_pack(// Outputs
	    .packet	(umi0_out_packet[UW-1:0]),
	    // Inputs
	    .write	(1'b1),
	    .command    (7'b1),//returns write response
	    .size	(size_out[3:0]),
	    .options	(options_out[19:0]),
	    .burst	(1'b0),
	    .dstaddr	(dstaddr_out[AW-1:0]),
	    .srcaddr	({(AW){1'b0}}),
	    .data	(data_mux[4*AW-1:0]));

endmodule // umi_endpoint
