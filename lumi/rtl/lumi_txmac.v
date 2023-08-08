/******************************************************************************
 * Function:  CLINK TX Datapath
 * Author:    Andreas Olofsson
 * Copyright: (c) 2022 Zero ASIC Corporation
 * License:
 *
 * Documentation:
 * -Samples I/O inputs and converts to a standardized packet width
 *
 *****************************************************************************/
module clink_txmac
  #(parameter TARGET = "DEFAULT", // implementation target
    parameter FIFODEPTH = 4,      // fifo depth
    // for development only (fixed )
    parameter DW = 256,           // umi data width
    parameter CW = 32,            // umi data width
    parameter AW = 64             // address width
    )
   (// control signals
    input           clk,            // core side clock
    input           nreset,         // async active low reset
    input           ioclk,          // io side clk
    input           ionreset,       //io side reset
    input           devicemode,     //1=host, 0=device
    input [1:0]     chipdir,        // chiplet direction
    input [3:0]     csr_protocol,   // protocol selector
    input [3:0]     csr_eccmode,    // error correction mode
    input           csr_bpprotocol, // bypass protocol
    input           csr_bpfifo,     // bypass fifo
    input           csr_chaos,
    input           vss,            // common ground
    input           vdd,            // core supply
    // status
    output          csr_empty,
    output          csr_full,
    // core side
    input           umi_in_valid,
    input [CW-1:0]  umi_in_cmd,
    input [AW-1:0]  umi_in_dstaddr,
    input [AW-1:0]  umi_in_srcaddr,
    input [DW-1:0]  umi_in_data,
    output          umi_in_ready,
    // io side
    output          umi_out_valid,
    output [CW-1:0] umi_out_cmd,
    output [AW-1:0] umi_out_dstaddr,
    output [AW-1:0] umi_out_srcaddr,
    output [DW-1:0] umi_out_data,
    input           umi_out_ready
    );

   // local wires
   wire 	    umi_proto2fifo_valid;
   wire [CW-1:0]    umi_proto2fifo_cmd;
   wire [AW-1:0]    umi_proto2fifo_dstaddr;
   wire [AW-1:0]    umi_proto2fifo_srcaddr;
   wire [DW-1:0]    umi_proto2fifo_data;
   wire             umi_proto2fifoready;

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [7:0]           umi_in_atype;
   wire                 umi_in_eof;
   wire                 umi_in_eom;
   wire [1:0]           umi_in_err;
   wire                 umi_in_ex;
   wire [4:0]           umi_in_hostid;
   wire [7:0]           umi_in_len;
   wire [4:0]           umi_in_opcode;
   wire [1:0]           umi_in_prot;
   wire [3:0]           umi_in_qos;
   wire [2:0]           umi_in_size;
   wire [1:0]           umi_in_user;
   wire [23:0]          umi_in_user_extended;
   wire                 umi_proto2fifo_ready;
   // End of automatics

   //#######################################
   // UMI UNPACK - not used for now but keeping as it will probably be needed
   //#######################################

   /*umi_unpack AUTO_TEMPLATE (
    .packet_\(.*\) (umi_in_\1[]),
    .cmd_\(.*\)    (umi_in_\1[]),
    )
    */

   umi_unpack #(.CW(CW))
   umi_unpack(/*AUTOINST*/
              // Outputs
              .cmd_opcode       (umi_in_opcode[4:0]),    // Templated
              .cmd_size         (umi_in_size[2:0]),      // Templated
              .cmd_len          (umi_in_len[7:0]),       // Templated
              .cmd_atype        (umi_in_atype[7:0]),     // Templated
              .cmd_qos          (umi_in_qos[3:0]),       // Templated
              .cmd_prot         (umi_in_prot[1:0]),      // Templated
              .cmd_eom          (umi_in_eom),            // Templated
              .cmd_eof          (umi_in_eof),            // Templated
              .cmd_ex           (umi_in_ex),             // Templated
              .cmd_user         (umi_in_user[1:0]),      // Templated
              .cmd_user_extended(umi_in_user_extended[23:0]), // Templated
              .cmd_err          (umi_in_err[1:0]),       // Templated
              .cmd_hostid       (umi_in_hostid[4:0]),    // Templated
              // Inputs
              .packet_cmd       (umi_in_cmd[CW-1:0]));   // Templated

   //######################################
   // PROTOCOL ENGINE
   //######################################

   //TODO: implement all protocols
   //1. Bursting (auto-addressing)
   //2. Streaming
   //3. Ethernet, ...

   assign umi_proto2fifo_valid           = csr_bpprotocol ? umi_in_valid :
				           umi_in_valid;

   assign umi_proto2fifo_cmd[CW-1:0]     = csr_bpprotocol ? umi_in_cmd[CW-1:0] :
				           umi_in_cmd[CW-1:0];

   assign umi_proto2fifo_dstaddr[AW-1:0] = csr_bpprotocol ? umi_in_dstaddr[AW-1:0] :
				           umi_in_dstaddr[AW-1:0];

   assign umi_proto2fifo_srcaddr[AW-1:0] = csr_bpprotocol ? umi_in_srcaddr[AW-1:0] :
				           umi_in_srcaddr[AW-1:0];

   assign umi_proto2fifo_data[DW-1:0]    = csr_bpprotocol ? umi_in_data[DW-1:0] :
				           umi_in_data[DW-1:0];

   assign umi_in_ready                   = csr_bpprotocol ? umi_proto2fifo_ready :
				           umi_proto2fifo_ready;

   //######################################
   //# Synchronization FIFO
   //######################################

   /*umi_fifo  AUTO_TEMPLATE (
    .umi_in_\(.*\)  (umi_proto2fifo_\1[]),
    .fifo_\(.*\)    (csr_\1),
    .bypass         (csr_bpfifo),
    );
    */

   umi_fifo  #(.DW(DW),
	       .AW(AW),
	       .CW(CW),
	       .DEPTH(FIFODEPTH))
   umi_fifo(.umi_in_clk		(clk),
	    .umi_in_nreset	(nreset),
	    .umi_out_clk	(ioclk),
	    .umi_out_nreset	(ionreset),
	    .chaosmode          (csr_chaos),
	    /*AUTOINST*/
            // Outputs
            .fifo_full          (csr_full),              // Templated
            .fifo_empty         (csr_empty),             // Templated
            .umi_in_ready       (umi_proto2fifo_ready),  // Templated
            .umi_out_valid      (umi_out_valid),
            .umi_out_cmd        (umi_out_cmd[CW-1:0]),
            .umi_out_dstaddr    (umi_out_dstaddr[AW-1:0]),
            .umi_out_srcaddr    (umi_out_srcaddr[AW-1:0]),
            .umi_out_data       (umi_out_data[DW-1:0]),
            // Inputs
            .bypass             (csr_bpfifo),            // Templated
            .umi_in_valid       (umi_proto2fifo_valid),  // Templated
            .umi_in_cmd         (umi_proto2fifo_cmd[CW-1:0]), // Templated
            .umi_in_dstaddr     (umi_proto2fifo_dstaddr[AW-1:0]), // Templated
            .umi_in_srcaddr     (umi_proto2fifo_srcaddr[AW-1:0]), // Templated
            .umi_in_data        (umi_proto2fifo_data[DW-1:0]), // Templated
            .umi_out_ready      (umi_out_ready),
            .vdd                (vdd),
            .vss                (vss));

endmodule
// Local Variables:
// verilog-library-directories:("." "../../../umi/umi/rtl/")
// End:
