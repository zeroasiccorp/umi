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
  #(parameter UW = 256, // UMI transaction width
    parameter CW = 32,
    parameter AW = 64,
    parameter N = 4     // number of inputs
    )
   (// Incoming UMI
    input [N-1:0]    umi_in_valid,
    input [N*CW-1:0] umi_in_cmd,
    input [N*AW-1:0] umi_in_dst_addr,
    input [N*AW-1:0] umi_in_src_addr,
    input [N*UW-1:0] umi_in_payload,
    output [N-1:0]   umi_in_ready,
    // Outgoing UMI
    output 	     umi_out_valid,
    input 	     umi_out_ready,
    output [CW-1:0]  umi_out_cmd,
    output [AW-1:0]  umi_out_dst_addr,
    output [AW-1:0]  umi_out_src_addr,
    output [UW-1:0]  umi_out_payload
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
   la_dst_addr_vmux(.out (umi_out_dst_addr[AW-1:0]),
	            .sel (umi_in_valid[N-1:0]),
	            .in  (umi_in_dst_addr[N*AW-1:0]));

   // packet mux
   la_vmux #(.N(N),
	     .W(AW))
   la_src_addr_vmux(.out (umi_out_src_addr[AW-1:0]),
	            .sel (umi_in_valid[N-1:0]),
	            .in  (umi_in_src_addr[N*AW-1:0]));

   // packet mux
   la_vmux #(.N(N),
	     .W(UW))
   la_payload_vmux(.out (umi_out_payload[UW-1:0]),
	           .sel (umi_in_valid[N-1:0]),
	           .in  (umi_in_payload[N*UW-1:0]));

   //TODO: add checker for one hot!

endmodule
