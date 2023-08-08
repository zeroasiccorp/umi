/******************************************************************************
 * Function:  CLINK RX Datapath
 * Author:    Andreas Olofsson
 * Copyright: (c) 2022 Zero ASIC Corporation
 * License:
 *
 * Documentation:
 * -Samples I/O inputs and converts to a standardized packet width
 *
 *****************************************************************************/
module clink_rxmac
  #(parameter TARGET = "DEFAULT", // implementation target
    parameter FIFODEPTH = 4,      // fifo depth
    // for development only (fixed )
    parameter DW = 256,           // umi data width
    parameter CW = 32,            // umi data width
    parameter AW = 64             // address width
    )
   (// control signals
    input           clk,
    input           nreset,         // async active low reset
    input           ioclk,          // io side clk
    input           ionreset,       //io side reset
    input           devicemode,     //1=host, 0=device
    input [1:0]     chipdir,        // chiplet direction
    input [3:0]     csr_protocol,   // protocol selector
    input [3:0]     csr_eccmode,    // error correction mode
    input           csr_bpprotocol, // bypass protocol
    input           csr_bpfifo,
    input           csr_chaos,
    input           vss,            // common ground
    input           vdd,            // core supply
    // status
    output          csr_empty,
    output          csr_full,
    // From phy
    input [CW-1:0]  umi_in_cmd,
    input [AW-1:0]  umi_in_dstaddr,
    input [AW-1:0]  umi_in_srcaddr,
    input [DW-1:0]  umi_in_data,
    input           umi_in_valid,
    output          umi_in_ready,
    // To Core
    output          umi_out_valid,
    output [CW-1:0] umi_out_cmd,
    output [AW-1:0] umi_out_dstaddr,
    output [AW-1:0] umi_out_srcaddr,
    output [DW-1:0] umi_out_data,
    input           umi_out_ready
    );


   // local wires
   wire 	    umi_fifo2proto_ready;
   wire [CW-1:0]    umi_fifo2proto_cmd;
   wire [AW-1:0]    umi_fifo2proto_dstaddr;
   wire [AW-1:0]    umi_fifo2proto_srcaddr;
   wire [DW-1:0]    umi_fifo2proto_data;
   wire             umi_fifo2proto_valid;

   /*AUTOWIRE*/

   //########################
   //# Synchronization FIFO
   //#########################

   /*umi_fifo  AUTO_TEMPLATE (
    .umi_out_\(.*\) (umi_fifo2proto_\1[]),
    .fifo_\(.*\)    (csr_\1),
    .bypass         (csr_bpfifo),
    );
    */


   umi_fifo  #(.DW(DW),
	       .AW(AW),
	       .CW(CW),
	       .DEPTH(FIFODEPTH))
   umi_fifo(.umi_in_clk		(ioclk),
	    .umi_in_nreset	(ionreset),
	    .umi_out_clk	(clk),
	    .umi_out_nreset	(nreset),
	    .chaosmode          (csr_chaos),
	    /*AUTOINST*/
            // Outputs
            .fifo_full          (csr_full),              // Templated
            .fifo_empty         (csr_empty),             // Templated
            .umi_in_ready       (umi_in_ready),
            .umi_out_valid      (umi_fifo2proto_valid),  // Templated
            .umi_out_cmd        (umi_fifo2proto_cmd[CW-1:0]), // Templated
            .umi_out_dstaddr    (umi_fifo2proto_dstaddr[AW-1:0]), // Templated
            .umi_out_srcaddr    (umi_fifo2proto_srcaddr[AW-1:0]), // Templated
            .umi_out_data       (umi_fifo2proto_data[DW-1:0]), // Templated
            // Inputs
            .bypass             (csr_bpfifo),            // Templated
            .umi_in_valid       (umi_in_valid),
            .umi_in_cmd         (umi_in_cmd[CW-1:0]),
            .umi_in_dstaddr     (umi_in_dstaddr[AW-1:0]),
            .umi_in_srcaddr     (umi_in_srcaddr[AW-1:0]),
            .umi_in_data        (umi_in_data[DW-1:0]),
            .umi_out_ready      (umi_fifo2proto_ready),  // Templated
            .vdd                (vdd),
            .vss                (vss));


   //######################################
   // PROTOCOL ENGINE
   //######################################
   //TODO: implement all protocols
   //1. Bursting (auto-addressing)
   //2. Streaming
   //3. Ethernet, ...

   assign umi_out_valid            = csr_bpprotocol ?
                                     umi_fifo2proto_valid :
				     umi_fifo2proto_valid;

   assign umi_out_cmd[CW-1:0]      = csr_bpprotocol ?
                                     umi_fifo2proto_cmd[CW-1:0] :
				     umi_fifo2proto_cmd[CW-1:0];

   assign umi_out_dstaddr[AW-1:0] = csr_bpprotocol ?
                                    umi_fifo2proto_dstaddr[AW-1:0] :
				    umi_fifo2proto_dstaddr[AW-1:0];

   assign umi_out_srcaddr[AW-1:0] = csr_bpprotocol ?
                                    umi_fifo2proto_srcaddr[AW-1:0] :
				    umi_fifo2proto_srcaddr[AW-1:0];

   assign umi_out_data[DW-1:0]  = csr_bpprotocol ?
                                  umi_fifo2proto_data[DW-1:0] :
				  umi_fifo2proto_data[DW-1:0];

   assign umi_fifo2proto_ready     = csr_bpprotocol ?
                                     umi_out_ready :
				     umi_out_ready;


endmodule
// Local Variables:
// verilog-library-directories:("." "../../../umi/umi/rtl/")
// End:
