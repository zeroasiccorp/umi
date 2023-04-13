/*******************************************************************************
 * Function:  UMI Traffic Splitter
 * Author:    Andreas Olofsson
 * License:
 *
 * Documentation:
 *
 * - Splits up traffic based on type.
 * - Responses (writes) has priority over requests (reads)
 * - Both outputs must be ready for input to go through.("blocking")
 *
 ******************************************************************************/
module umi_splitter
  #(// standard parameters
    parameter AW   = 64,
    parameter UW   = 256)
   (// UMI Input
    input 	    umi_in_valid,
    input [UW-1:0]  umi_in_packet,
    output 	    umi_in_ready,
    // UMI Output
    output 	    umi_resp_out_valid,
    output [UW-1:0] umi_resp_out_packet,
    input 	    umi_resp_out_ready,
    // UMI Output
    output 	    umi_req_out_valid,
    output [UW-1:0] umi_req_out_packet,
    input 	    umi_req_out_ready
    );

   wire 	    write;

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [7:0]		command;
   wire [4*AW-1:0]	data;
   wire [AW-1:0]	dstaddr;
   wire [19:0]		options;
   wire [3:0]		size;
   wire [AW-1:0]	srcaddr;
   // End of automatics

   //########################
   // UNPACK INPUT
   //########################

   umi_unpack #(.UW(UW),
		.AW(AW))
   umi_unpack(.packet			(umi_in_packet[UW-1:0]),
	      /*AUTOINST*/
	      // Outputs
	      .command			(command[7:0]),
	      .size			(size[3:0]),
	      .options			(options[19:0]),
	      .dstaddr			(dstaddr[AW-1:0]),
	      .srcaddr			(srcaddr[AW-1:0]),
	      .data			(data[4*AW-1:0]));

   // write decode
   umi_write umi_write(.write (write), .command	(command[7:0]));

   // Write traffic sent to umi_resp
   assign umi_resp_out_valid = umi_in_valid & write;
   assign umi_req_out_valid = umi_in_valid & ~write;

   // Broadcasting packet
   assign umi_resp_out_packet[UW-1:0] = umi_in_packet[UW-1:0];
   assign umi_req_out_packet[UW-1:0] = umi_in_packet[UW-1:0];

   // Globally blocking ready implementation
   assign umi_in_ready = ~(umi_resp_out_valid & ~umi_resp_out_ready) &
			 ~(umi_req_out_valid & ~umi_req_out_ready);

endmodule // umi_splitter
