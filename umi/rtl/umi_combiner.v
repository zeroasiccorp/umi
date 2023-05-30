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
    parameter CW   = 32,
    parameter UW   = 256)
   (// controls
    input 	    clk,
    input 	    nreset,
    // Input (0), Higher Priority
    input 	    umi_resp_in_valid,
    input [CW-1:0]  umi_resp_in_cmd,
    input [AW-1:0]  umi_resp_in_dst_addr,
    input [AW-1:0]  umi_resp_in_src_addr,
    input [UW-1:0]  umi_resp_in_payload,
    output 	    umi_resp_in_ready,
    // Input (1)
    input 	    umi_req_in_valid,
    input [CW-1:0]  umi_req_in_cmd,
    input [AW-1:0]  umi_req_in_dst_addr,
    input [AW-1:0]  umi_req_in_src_addr,
    input [UW-1:0]  umi_req_in_payload,
    output 	    umi_req_in_ready,
    // Output
    output 	    umi_out_valid,
    output [CW-1:0] umi_out_cmd,
    output [AW-1:0] umi_out_dst_addr,
    output [AW-1:0] umi_out_src_addr,
    output [UW-1:0] umi_out_payload,
    input 	    umi_out_ready
    );

   // local wires
   wire 	    umi_resp_ready;
   wire 	    umi_req_ready;

   umi_mux #(.N(2))
   umi_mux (// Outputs
	    .umi_in_ready	({umi_req_ready,umi_resp_ready}),
	    .umi_out_valid	(umi_out_valid),
            .umi_out_cmd        (umi_out_cmd[CW-1:0]),
            .umi_out_dst_addr   (umi_out_dst_addr[AW-1:0]),
            .umi_out_src_addr   (umi_out_src_addr[AW-1:0]),
            .umi_out_payload    (umi_out_payload[UW-1:0]),
	    // Inputs
	    .clk		(clk),
	    .nreset		(nreset),
	    .mode		(2'b00),
	    .mask		(2'b00),
	    .umi_in_valid	({umi_req_in_valid, umi_resp_in_valid}),
	    .umi_in_cmd 	({umi_req_in_cmd, umi_resp_in_cmd}),
	    .umi_in_dst_addr	({umi_req_in_dst_addr, umi_resp_in_dst_addr}),
	    .umi_in_src_addr	({umi_req_in_src_addr, umi_resp_in_src_addr}),
	    .umi_in_payload	({umi_req_in_payload, umi_resp_in_payload}),
            /*AUTOINST*/
            // Inputs
            .umi_out_ready      (umi_out_ready));

   // Flow through pushback
   assign umi_resp_in_ready = umi_out_ready & umi_resp_ready;
   assign umi_req_in_ready = umi_out_ready & umi_req_ready;

endmodule // umi_splitter
