/*******************************************************************************
 * Function:  UMI Traffic Combiner (2:1 Mux)
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
module umi_combiner
  #(// standard parameters
    parameter AW   = 64,
    parameter UW   = 256)
   ( // Input (0), Higher Priority
    input 	    umi0_in_valid,
    input [UW-1:0]  umi0_in_packet,
    // Input (1)
    input 	    umi1_in_valid,
    input [UW-1:0]  umi1_in_packet,
    output 	    umi1_in_ready,
    // Output
    output 	    umi_out_valid,
    output [UW-1:0] umi_out_packet
    );

   //never waits
   wire 	    umi0_in_ready;
   umi_mux #(.N(2))
   umi_mux (// Outputs
	    .umi_in_ready	({umi1_in_ready,umi0_in_ready}),
	    .umi_out_valid	(umi_out_valid),
	    .umi_out_packet	(umi_out_packet[UW-1:0]),
	    // Inputs
	    .clk		(clk),
	    .nreset		(nreset),
	    .mode		(2'b00),
	    .mask		(2'b00),
	    .umi_in_valid	({umi1_in_valid, umi0_in_valid}),
	    .umi_in_packet	({umi1_in_packet, umi0_in_packet}));

endmodule // umi_splitter
