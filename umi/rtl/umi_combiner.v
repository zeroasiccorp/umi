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
   (// controls
    input 	    clk,
    input 	    nreset,
    // Input (0), Higher Priority
    input 	    umi0_in_valid,
    input [UW-1:0]  umi0_in_packet,
    output 	    umi0_in_ready,
    // Input (1)
    input 	    umi1_in_valid,
    input [UW-1:0]  umi1_in_packet,
    output 	    umi1_in_ready,
    // Output
    output 	    umi_out_valid,
    output [UW-1:0] umi_out_packet,
    input 	    umi_out_ready
    );

   // local wires
   wire 	    umi0_ready;
   wire 	    umi1_ready;

   umi_mux #(.N(2))
   umi_mux (// Outputs
	    .umi_in_ready	({umi1_ready,umi0_ready}),
	    .umi_out_valid	(umi_out_valid),
	    .umi_out_packet	(umi_out_packet[UW-1:0]),
	    // Inputs
	    .clk		(clk),
	    .nreset		(nreset),
	    .mode		(2'b00),
	    .mask		(2'b00),
	    .umi_in_valid	({umi1_in_valid, umi0_in_valid}),
	    .umi_in_packet	({umi1_in_packet, umi0_in_packet}));

   // Flow through pushback
   assign umi0_in_ready = umi_out_ready & umi0_ready;
   assign umi1_in_ready = umi_out_ready & umi1_ready;

endmodule // umi_splitter
