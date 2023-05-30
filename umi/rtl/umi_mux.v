/*******************************************************************************
 * Function:  UMI Mux (one-hot)
 * Author:    Andreas Olofsson
 * License:
 *
 * Documentation:
 *
 * - Selects between N inputs
 * - Assumes one-hot selects
 *
 ******************************************************************************/
module umi_mux
  #(parameter DW = 256, // UMI transaction width
    parameter CW = 32,
    parameter AW = 64,
    parameter N = 4     // number of inputs
    )
   (// Incoming UMI
    input [N-1:0]    umi_in_valid,
    input [N*CW-1:0] umi_in_cmd,
    input [N*AW-1:0] umi_in_dstaddr,
    input [N*AW-1:0] umi_in_srcaddr,
    input [N*DW-1:0] umi_in_data,
    output [N-1:0]   umi_in_ready,
    // Outgoing UMI
    output 	     umi_out_valid,
    input 	     umi_out_ready,
    output [CW-1:0]  umi_out_cmd,
    output [AW-1:0]  umi_out_dstaddr,
    output [AW-1:0]  umi_out_srcaddr,
    output [DW-1:0]  umi_out_data
    );

   // valid output
   assign umi_out_valid = |umi_in_valid[N-1:0];

   // ready pusback
   assign umi_in_ready[N-1:0] = ~umi_in_valid[N-1:0] |
				(umi_in_valid[N-1:0] & umi_out_ready);

   // packet mux
   la_vmux #(.N(N),
	     .W(CW))
   la_cmd_vmux(.out (umi_out_cmd[CW-1:0]),
	       .sel (umi_in_valid[N-1:0]),
	       .in  (umi_in_cmd[N*CW-1:0]));

   // packet mux
   la_vmux #(.N(N),
	     .W(AW))
   la_dstaddr_vmux(.out (umi_out_dstaddr[AW-1:0]),
	           .sel (umi_in_valid[N-1:0]),
	           .in  (umi_in_dstaddr[N*AW-1:0]));

   // packet mux
   la_vmux #(.N(N),
	     .W(AW))
   la_srcaddr_vmux(.out (umi_out_srcaddr[AW-1:0]),
	           .sel (umi_in_valid[N-1:0]),
	           .in  (umi_in_srcaddr[N*AW-1:0]));

   // packet mux
   la_vmux #(.N(N),
	     .W(DW))
   la_data_vmux(.out (umi_out_data[DW-1:0]),
	        .sel (umi_in_valid[N-1:0]),
	        .in  (umi_in_data[N*DW-1:0]));

   //TODO: add checker for one hot!

endmodule
