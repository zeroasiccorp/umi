/*******************************************************************************
 * Function:  UMI Crossbar
 * Author:    Andreas Olofsson
 * License:   (c) 2023 Zero ASIC Corporation
 *
 * Documentation:
 *
 * N x N crossbar with one-hot selects.
 *
 ******************************************************************************/
module umi_crossbar
  #(parameter TARGET = "DEFAULT", // implementation target
    parameter UW     = 256,       // UMI width
    parameter N      = 1          // UMI ports
    )
   (
    input [UW*N-1:0]  in, // input ports
    input [N*N-1:0]   sel, // one hot selects ([N-1:0]=output port 0)
    output [UW*N-1:0] out  // output ports
    );

   genvar i;
   generate
     for(i=0;i<N;i=i+1)
       begin: imux
	  la_vmux #(.N(N), .W(UW))
	  la_vmux(// Outputs
		  .out	(out[i*UW+:UW]),
		  // Inputs
		  .sel	(sel[i*N+:N]),
		  .in	(in[UW*N-1:0]));

       end
   endgenerate

endmodule // umi_crossbar
