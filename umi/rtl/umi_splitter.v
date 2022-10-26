/*******************************************************************************
 * Function:  UMI Traffic Splitter
 * Author:    Andreas Olofsson
 * License:
 *
 * Documentation:
 *
 * - Splits up traffic based on type.
 * - UMI 0 carries high priority traffic ("writes")
 * - UMI 1 carries low priority traffic ("read requests")
 * - No cycles allowed since this would deadlock
 * - Traffic source must be self throttling
 *
 ******************************************************************************/
module umi_splitter
  #(// standard parameters
    parameter AW   = 64,
    parameter UW   = 256)
   (// UMI Input
    input 	    umi_in_valid,
    input [UW-1:0]  umi_in_packet,
    // UMI Output (0)
    output 	    umi0_out_valid,
    output [UW-1:0] umi0_out_packet,
    // UMI Output (1)
    output 	    umi1_out_valid,
    output [UW-1:0] umi1_out_packet
    );

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [6:0]		command;		// From umi_unpack of umi_unpack.v
   wire [4*AW-1:0]	data;			// From umi_unpack of umi_unpack.v
   wire [AW-1:0]	dstaddr;		// From umi_unpack of umi_unpack.v
   wire [19:0]		options;		// From umi_unpack of umi_unpack.v
   wire [3:0]		size;			// From umi_unpack of umi_unpack.v
   wire [AW-1:0]	srcaddr;		// From umi_unpack of umi_unpack.v
   wire			write;			// From umi_unpack of umi_unpack.v
   // End of automatics

   //########################
   // UNPACK INPUT
   //########################

   umi_unpack #(.UW(UW),
		.AW(AW))
   umi_unpack(.packet			(umi_in_packet[UW-1:0]),
	      /*AUTOINST*/
	      // Outputs
	      .write			(write),
	      .command			(command[6:0]),
	      .size			(size[3:0]),
	      .options			(options[19:0]),
	      .dstaddr			(dstaddr[AW-1:0]),
	      .srcaddr			(srcaddr[AW-1:0]),
	      .data			(data[4*AW-1:0]));

   // Write traffic sent to umi0
   assign umi0_out_valid = umi_in_valid & write;
   assign umi1_out_valid = umi_in_valid & ~write;

   // Broadcasting packet
   assign umi0_out_packet[UW-1:0] = umi_in_packet[UW-1:0];
   assign umi1_out_packet[UW-1:0] = umi_in_packet[UW-1:0];

endmodule // umi_splitter
