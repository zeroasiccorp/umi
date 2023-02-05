/*******************************************************************************
 * Function:  UMI Mux
 * Author:    Andreas Olofsson
 * License:
 *
 * Documentation:
 *
 * - Selects between N inputs
 * - Input 0 has highest priority
 *
 ******************************************************************************/
module umi_mux
  #(parameter UW  = 256, // UMI transaction width
    parameter N   = 4    // number of inputs
    )
   (// controls
    input 		clk,
    input 		nreset,
    input [1:0] 	mode, // arbiter mode (0=fixed)
    input [N-1:0] 	mask, // 1=disables input request
    // Incoming UMI
    input [N-1:0] 	umi_in_valid,
    input [N*UW-1:0] 	umi_in_packet,
    output [N-1:0] 	umi_in_ready,
    // Outgoing UMI
    output 		umi_out_valid,
    output reg [UW-1:0] umi_out_packet
    );

   // local wires
   wire [N-1:0]       grants;

   /*AUTOWIRE*/

   //##############################
   // Valid Selection
   //##############################

   umi_arbiter #(.N(N))
   umi_arbiter(// outputs
	       .grants		(grants[N-1:0]),
	       // Inputs
	       .clk		(clk),
	       .nreset		(nreset),
	       .mode		(mode[1:0]),
	       .mask		(mask[N-1:0]),
	       .requests	(umi_in_valid[N-1:0]));

   assign umi_out_valid = |grants[N-1:0];

   assign umi_in_ready[N-1:0] = ~umi_in_valid[N-1:0] |
				(umi_in_valid[N-1:0] & grants[N-1:0]);

   //##############################
   // Packet Mux
   //##############################

   // Select outgoing packet
   integer 	      i;
   always @*
     begin
	umi_out_packet[UW-1:0] = 'b0;
	for(i=0;i<N;i=i+1)
	  begin
	     umi_out_packet[UW-1:0] = umi_out_packet |
	                              {UW{grants[i]}} & umi_in_packet[i*UW+:UW];
	  end
     end

endmodule
