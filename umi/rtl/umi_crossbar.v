/*******************************************************************************
 * Function:  UMI Crossbar
 * Author:    Andreas Olofsson
 * License:   (c) 2023 Zero ASIC Corporation
 *
 * Documentation:
 *
 * Simple N x N crossbar with one-hot select matrix.
 * 
 * 
 * 
 ******************************************************************************/
module umi_crossbar
  #(parameter TARGET = "DEFAULT", // implementation target
    parameter UW     = 256,       // UMI width
    parameter N      = 1          // UMI ports          
    )
   (
    input [UW*N-1:0] 	 in, // input ports
    input [N*N-1:0] 	 sel, // one hot selects ([N-1:0]=output port 0)
    output reg [UW*N-1:0] out  // output ports  
    );

   for (i=0;i<N;i=i+1)
     begin
	out[i*UW+:UW] = 'b0;
	for (j=0;j<N;j=j+1)
	  out[i*UW+:UW] = out[i*UW+:UW] | (in[i*UW+:UW] & sel)
							      
	       
	

sel[i*N];
	
	  end
     begin

     end
   


endmodule // umi_crossbar
	
// Local Variables:
// verilog-library-directories:("." "../../../lambdalib/ramlib/rtl")
// End:
