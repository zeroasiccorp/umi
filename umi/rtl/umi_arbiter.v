/*******************************************************************************
 * Function:  UMI Arbiter
 * Author:    Andreas Olofsson
 * License:   (c) 2023 Zero ASIC Corporation
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
  #(parameter N      = 4,         // number of inputs
    parameter TARGET = "DEFAULT"  // SIM, ASIC, FPGA, ...
    )
   (// controls
    input              clk,
    input              nreset,
    input [1:0]        mode, // [00]=priority,[01]=roundrobin,[1x]=reserved
    input [N-1:0]      mask, // 1 = disable request, 0 = enable request
    input [N-1:0]      requests, // incoming requests
    output reg [N-1:0] grants  // outgoing grants
    );

   wire                collision;
   reg [N-1:0]         thermometer;
   wire [N-1:0]        spec_requests[0:N-1];
   wire [N-1:0]        spec_grants[0:N-1];
   genvar              i;

   // Thermometer mask that gets hotter with every collision
   // wraps to zero when all ones
   generate if (N > 1)
     begin
        always @ (posedge clk or negedge nreset)
          if (~nreset)
            thermometer[N-1:0] <= {N{1'b0}};
          else if(collision & (mode[1:0]==2'b10))
            thermometer[N-1:0] <= (&thermometer[N-2:0]) ? {N{1'b0}} : {thermometer[N-2:0],1'b1};
     end
   else
     begin
        always @ (posedge clk or negedge nreset)
          if (~nreset)
            thermometer[N-1:0] <= {N{1'b0}};
          else
            thermometer[N-1:0] <= {N{1'b0}};
     end
   endgenerate

   // 1. Create N rotated set of requests
   // 2. Feed requests into fixed priority encoders
   for (i=0;i<N;i=i+1)
     begin
        // double width needed for rotation
        assign spec_requests[i] = ~mask[N-1:0] &
                                  ~thermometer[N-1:0] &
                                   requests[N-1:0];

        // Priority Slection Using Masked Inputs
        umi_priority #(.N(N))
        umi_prioroty(// Outputs
                     .grants   (spec_grants[i][N-1:0]),
                     // Inputs
                     .requests (spec_requests[i][N-1:0]));
     end

   // Or together all grants
   always @*
     begin : imux
        integer    k;
        grants[N-1:0] = 'b0;
        for(k=0;k<N;k=k+1)
          grants[N-1:0] = grants[N-1:0] | spec_grants[k][N-1:0];
     end

   // Detect collision on pushback
   assign collision = |(requests[N-1:0] & ~grants[N-1:0]);

endmodule
