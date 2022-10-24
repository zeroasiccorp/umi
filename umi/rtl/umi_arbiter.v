/*******************************************************************************
 * Function:  UMI Arbiter
 * Author:    Andreas Olofsson
 * License:
 *
 * Documentation:
 *
 * - Dynamically configurable arbiter (fixed, roundrobin, ...)
 *
 * - mode[1:0]:
 * -     00 = priority
 * -     01 = round robin
 * -     10 = reserved
 * -     11 = reserved
 *
 ******************************************************************************/
module umi_arbiter
  #(parameter UW  = 256, // UMI transaction width
    parameter N   = 4    // number of inputs
    )
   (// controls
    input 	   clk,
    input 	   nreset,
    input [1:0]    mode, // arbiter mode
    input [N-1:0]  mask, // 1=disable input request,0=enable inputn request
    // Incoming UMI request
    input [N-1:0]  umi_in_valid,
    output [N-1:0] umi_in_ready,
    // Outgoing UMI response
    output [N-1:0] umi_out_valid
    );

   wire 	       collision;
   reg [N-1:0] 	       thermometer;
   wire [N-1:0]        spec_requests[0:N-1];
   wire [N-1:0]        spec_grants[0:N-1];
   reg [N-1:0] 	       grants;
   genvar 	       i;

   // Thermometer mask that gets hotter with every
   // collision and wraps on all ones.
   always @ (posedge clk or negedge nreset)
     if (~nreset)
       thermometer[N-1:0] <= {N{1'b0}};
     else if(collision & (mode[1:0]!=00))
       thermometer[N-1:0] <= (&thermometer[N-2:0]) ? 'b0 : {thermometer[N-2:0],1'b1};

   // 1. Create N rotated set of requests
   // 2. Feed requests into fixed priority encoders
   for (i=0;i<N;i=i+1)
     begin
	// double width needed for rotation
	assign spec_requests[i] = ~mask[N-1:0] &
				  ~thermometer[N-1:0] &
				  umi_in_valid[N-1:0];

	// Priority Slection Using Masked Inputs
	umi_priority #(.N(N))
	umi_prioroty(// Outputs
		     .umi_out_valid (spec_grants[i][N-1:0]),
		     // Inputs
		     .umi_in_valid  (spec_requests[i][N-1:0]));
     end

   // Or together all grants
   always @*
     begin : imux
	integer	   i;
	grants[N-1:0] = 'b0;
	for(i=0;i<N;i=i+1)
	  grants[N-1:0] = grants[N-1:0] | spec_grants[i][N-1:0];
     end

   // Valid==Grant
   assign umi_out_valid[N-1:0] = grants[N-1:0];

   // Drive ready low on request and ~grant
   assign umi_in_ready[N-1:0] = ~umi_in_valid[N-1:0] |
				(umi_in_valid[N-1:0] & grants[N-1:0]);

   // Detect collision on pushback
   assign collision = |(umi_in_valid[N-1:0] & ~grants[N-1:0]);

endmodule
