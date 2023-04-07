/*******************************************************************************
 * Function:  UMI NxN Crossbar
 * Author:    Andreas Olofsson
 * License:   (c) 2023 Zero ASIC Corporation
 *
 * Documentation:
 *
 * The input request vector is a concatenated onenot vectors of inputs
 * requesting outputs ports per the order below.
 *
 * [0]     = input 0   requesting output 0
 * [1]     = input 1   requesting output 0
 * [2]     = input 2   requesting output 0
 * [N-1]   = input N-1 requesting output 0
 * [N]     = input 0   requesting output 1
 * [N+1]   = input 1   requesting output 1
 * [N+2]   = input 2   requesting output 1
 * [2*N-1] = input N-1 requesting output 1
 * ...
 *
 ******************************************************************************/
module umi_crossbar
  #(parameter TARGET = "DEFAULT", // implementation target
    parameter UW     = 256,       // UMI width
    parameter N      = 2          // Total UMI ports
    )
   (// controls
    input 	       clk,
    input 	       nreset,
    input [1:0]        mode, // arbiter mode (0=fixed)
    // Incoming UMI
    input [N*N-1:0]    umi_in_request,
    input [N*UW-1:0]   umi_in_packet,
    output reg [N-1:0] umi_in_ready,
    // Outgoing UMI
    output [N-1:0]     umi_out_valid,
    output [N*UW-1:0]  umi_out_packet,
    input [N-1:0]      umi_out_ready
    );

   wire [N*N-1:0]    grants;
   wire [N*N-1:0]    ready;
   genvar 	     i;

   //##############################
   // Arbiters for all outputs
   //##############################

   for (i=0;i<N;i=i+1)
     begin
	umi_arbiter #(.TARGET(TARGET),
		      .N(N))
	umi_arbiter (// Outputs
		     .grants   (grants[N*i+:N]),
		     // Inputs
		     .clk      (clk),
		     .nreset   (nreset),
		     .mode     (mode[1:0]),
		     .mask     ({N{1'b0}}),
		     .requests (umi_in_request[N*i+:N]));

	assign umi_out_valid[i] = |grants[N*i+:N];

     end // for (i=0;i<N;i=i+1)

   //##############################
   // Ready
   //##############################

   assign ready[N*N-1:0] = ~umi_in_request[N*N-1:0] |
			   ({N{umi_out_ready}} &
			    umi_in_request[N*N-1:0] &
			    grants[N*N-1:0]);

   integer j,k;
   always @*
     begin
	umi_in_ready[N-1:0] = {N{1'b1}};
	for (j=0;j<N;j=j+1)
	  for (k=0;k<N;k=k+1)
	    umi_in_ready[j] = umi_in_ready[j] & ready[j+k*N];
     end

   //##############################
   // Mux on all outputs
   //##############################

   for(i=0;i<N;i=i+1)
     begin: imux
	la_vmux #(.N(N),
		  .W(UW))
	la_vmux(// Outputs
		.out (umi_out_packet[i*UW+:UW]), //.out (umi_out_packet[i*UW+:UW]),
		// Inputs
		.sel (grants[i*N+:N]),
		.in  (umi_in_packet[UW*N-1:0]));

     end

endmodule // umi_crossbar
