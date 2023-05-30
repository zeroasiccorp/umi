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
    parameter UW = 256,           // UMI width
    parameter CW = 32,
    parameter AW = 64,
    parameter N = 2               // Total UMI ports
    )
   (// controls
    input              clk,
    input              nreset,
    input [1:0]        mode, // arbiter mode (0=fixed)
    input [N*N-1:0]    mask, // arbiter mode (0=fixed)
    // Incoming UMI
    input [N*N-1:0]    umi_in_request,
    input [N*CW-1:0]   umi_in_cmd,
    input [N*AW-1:0]   umi_in_dst_addr,
    input [N*AW-1:0]   umi_in_src_addr,
    input [N*UW-1:0]   umi_in_payload,
    output reg [N-1:0] umi_in_ready,
    // Outgoing UMI
    output [N-1:0]     umi_out_valid,
    output [N*CW-1:0]  umi_out_cmd,
    output [N*AW-1:0]  umi_out_dst_addr,
    output [N*AW-1:0]  umi_out_src_addr,
    output [N*UW-1:0]  umi_out_payload,
    input [N-1:0]      umi_out_ready
    );

   wire [N*N-1:0]    grants;
   wire [N*N-1:0]    ready;
   wire [N*N-1:0]    umi_out_sel;
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
		     .mask     (mask[N*i+:N]),
		     .requests (umi_in_request[N*i+:N]));

	assign umi_out_valid[i] = |grants[N*i+:N];
     end // for (i=0;i<N;i=i+1)

   // masking final select to help synthesis pruning
   // TODO: check in syn if this is strictly needed

   assign umi_out_sel[N*N-1:0] = grants[N*N-1:0] & ~mask[N*N-1:0];

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
     begin: ivmux
	la_vmux #(.N(N),
		  .W(UW))
	la_payload_vmux(// Outputs
		        .out (umi_out_payload[i*UW+:UW]),
		        // Inputs
		        .sel (umi_out_sel[i*N+:N]),
		        .in  (umi_in_payload[N*UW-1:0]));

	la_vmux #(.N(N),
		  .W(AW))
	la_src_vmux(// Outputs
		    .out (umi_out_src_addr[i*AW+:AW]),
		    // Inputs
		    .sel (umi_out_sel[i*N+:N]),
		    .in  (umi_in_src_addr[N*AW-1:0]));

	la_vmux #(.N(N),
		  .W(AW))
	la_dst_vmux(// Outputs
		    .out (umi_out_dst_addr[i*AW+:AW]),
		    // Inputs
		    .sel (umi_out_sel[i*N+:N]),
		    .in  (umi_in_dst_addr[N*AW-1:0]));

	la_vmux #(.N(N),
		  .W(CW))
	la_cmd_vmux(// Outputs
		    .out (umi_out_cmd[i*CW+:CW]),
		    // Inputs
		    .sel (umi_out_sel[i*N+:N]),
		    .in  (umi_in_cmd[N*CW-1:0]));
     end

endmodule // umi_crossbar
