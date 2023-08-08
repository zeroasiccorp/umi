/******************************************************************************
 * Function:  CLINK Receiver
 * Author:    Andreas Olofsson
 * Copyright: (c) 2022 Zero ASIC Corporation
 * License:
 *
 * Documentation:
 *
 *
 *
 *****************************************************************************/
module clink_rx
  #(parameter TARGET = "DEFAULT", // implementation target
    parameter FIFODEPTH = 4,      // fifo depth
    parameter IOW = 64,           // clink rx/tx width
    parameter CW = 32,            // umi cmd width
    parameter AW = 64,            // umi addr width
    parameter DW = 256,           // umi data width
    parameter CRDTFIFOD = 64      // Fifo size need to account for 64B over 2B link
    )
   (// local control
    input           clk,             // core clock
    input           ioclk,           // rx clock
    input           nreset,          // async active low reset
    input           ionreset,        // rx async active low reset
    input           vss,             // common ground
    input           vdd,             // core supply
    input           vddio,           // io voltage
    input           devicemode,      // 1=device, 0=host
    input [1:0]     chipdir,         // rotation (00=0,01=90,10=180,11=270)
    input           csr_en,          // link enable
    input [1:0]     csr_chipletmode, // 00=110um,01=45um,10=10um,11=1um
    input           csr_ddrmode,     // 1 = ddr, 0 = sdr
    input [7:0]     csr_iowidth,     // pad bus width
    input [3:0]     csr_eccmode,     // pad bus width
    input [3:0]     csr_protocol,    // protocol selector
    input           csr_chaos,       // enable random fifo pushback
    input           csr_bpio,        // bypass rx io shift register
    input           csr_bpfifo,      // bypass rx fifo
    input           csr_bpprotocol,  // bypass rx protocol engine
    // status signals
    output          csr_respfull,
    output          csr_respempty,
    output          csr_reqfull,
    output          csr_reqempty,
    // Feedback clock (TODO)
    output          clkfb,           // feedback clock from RX
    // pad signals
    input [IOW-1:0] io_rxdata,       // link data from pads
    input [3:0]     io_rxctrl,       // link ctrl(valid) from pads
    output [3:0]    io_rxstatus,     // flow control to pads
    // Write/response to core
    output          umi_resp_out_valid,
    output [CW-1:0] umi_resp_out_cmd,
    output [AW-1:0] umi_resp_out_dstaddr,
    output [AW-1:0] umi_resp_out_srcaddr,
    output [DW-1:0] umi_resp_out_data,
    input           umi_resp_out_ready,
    // Read/request to core
    output          umi_req_out_valid,
    output [CW-1:0] umi_req_out_cmd,
    output [AW-1:0] umi_req_out_dstaddr,
    output [AW-1:0] umi_req_out_srcaddr,
    output [DW-1:0] umi_req_out_data,
    input           umi_req_out_ready,
    // Credit interface
    input [15:0]    csr_crdt_req_init,
    input [15:0]    csr_crdt_resp_init,
    output [15:0]   loc_crdt_req,
    output [15:0]   loc_crdt_resp,
    output [15:0]   rmt_crdt_req,
    output [15:0]   rmt_crdt_resp
    /*AUTOINPUT*/
    /*AUTOOUTPUT*/
    );

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [CW-1:0]        umi_req_phy2mac_cmd;
   wire [DW-1:0]        umi_req_phy2mac_data;
   wire [AW-1:0]        umi_req_phy2mac_dstaddr;
   wire                 umi_req_phy2mac_ready;
   wire [AW-1:0]        umi_req_phy2mac_srcaddr;
   wire                 umi_req_phy2mac_valid;
   wire [CW-1:0]        umi_resp_phy2mac_cmd;
   wire [DW-1:0]        umi_resp_phy2mac_data;
   wire [AW-1:0]        umi_resp_phy2mac_dstaddr;
   wire                 umi_resp_phy2mac_ready;
   wire [AW-1:0]        umi_resp_phy2mac_srcaddr;
   wire                 umi_resp_phy2mac_valid;
   // End of automatics

   //#####################
   //# PHY
   //#####################

   /*clink_rxphy  AUTO_TEMPLATE (
    .umi\(.*\)_out_\(.*\) (umi\1_phy2mac_\2[]),
    )
    */

   clink_rxphy #(.DW(DW),
		 .AW(AW),
		 .CW(CW),
		 .IOW(IOW),
		 .TARGET(TARGET),
                 .CRDTFIFOD(CRDTFIFOD))
   clink_rxphy(/*AUTOINST*/
               // Outputs
               .io_rxstatus     (io_rxstatus[3:0]),
               .clkfb           (clkfb),
               .umi_resp_out_cmd(umi_resp_phy2mac_cmd[CW-1:0]), // Templated
               .umi_resp_out_dstaddr(umi_resp_phy2mac_dstaddr[AW-1:0]), // Templated
               .umi_resp_out_srcaddr(umi_resp_phy2mac_srcaddr[AW-1:0]), // Templated
               .umi_resp_out_data(umi_resp_phy2mac_data[DW-1:0]), // Templated
               .umi_resp_out_valid(umi_resp_phy2mac_valid), // Templated
               .umi_req_out_cmd (umi_req_phy2mac_cmd[CW-1:0]), // Templated
               .umi_req_out_dstaddr(umi_req_phy2mac_dstaddr[AW-1:0]), // Templated
               .umi_req_out_srcaddr(umi_req_phy2mac_srcaddr[AW-1:0]), // Templated
               .umi_req_out_data(umi_req_phy2mac_data[DW-1:0]), // Templated
               .umi_req_out_valid(umi_req_phy2mac_valid), // Templated
               .loc_crdt_req    (loc_crdt_req[15:0]),
               .loc_crdt_resp   (loc_crdt_resp[15:0]),
               .rmt_crdt_req    (rmt_crdt_req[15:0]),
               .rmt_crdt_resp   (rmt_crdt_resp[15:0]),
               // Inputs
               .ioclk           (ioclk),
               .ionreset        (ionreset),
               .devicemode      (devicemode),
               .chipdir         (chipdir[1:0]),
               .csr_en          (csr_en),
               .csr_chipletmode (csr_chipletmode[1:0]),
               .csr_ddrmode     (csr_ddrmode),
               .csr_iowidth     (csr_iowidth[7:0]),
               .csr_eccmode     (csr_eccmode[3:0]),
               .csr_bpio        (csr_bpio),
               .vss             (vss),
               .vdd             (vdd),
               .vddio           (vddio),
               .io_rxdata       (io_rxdata[IOW-1:0]),
               .io_rxctrl       (io_rxctrl[3:0]),
               .umi_resp_out_ready(umi_resp_phy2mac_ready), // Templated
               .umi_req_out_ready(umi_req_phy2mac_ready), // Templated
               .csr_crdt_req_init(csr_crdt_req_init[15:0]),
               .csr_crdt_resp_init(csr_crdt_resp_init[15:0]));


   //#####################
   //# UMI_RESP MAC
   //#####################

   /*clink_rxmac  AUTO_TEMPLATE (
    .umi_out_\(.*\)  (@"(substring vl-cell-name  6)"_out_\1[]),
    .umi_in_\(.*\)   (@"(substring vl-cell-name  6)"_phy2mac_\1[]),
    .csr_empty       (csr_@"(substring vl-cell-name  10)"empty),
    .csr_full        (csr_@"(substring vl-cell-name  10)"full),
    );
    */

   clink_rxmac #(.DW(DW),
		 .AW(AW),
		 .CW(CW),
		 .TARGET(TARGET))
   rxmac_umi_resp(
		  /*AUTOINST*/
                  // Outputs
                  .csr_empty            (csr_respempty),         // Templated
                  .csr_full             (csr_respfull),          // Templated
                  .umi_in_ready         (umi_resp_phy2mac_ready), // Templated
                  .umi_out_valid        (umi_resp_out_valid),    // Templated
                  .umi_out_cmd          (umi_resp_out_cmd[CW-1:0]), // Templated
                  .umi_out_dstaddr      (umi_resp_out_dstaddr[AW-1:0]), // Templated
                  .umi_out_srcaddr      (umi_resp_out_srcaddr[AW-1:0]), // Templated
                  .umi_out_data         (umi_resp_out_data[DW-1:0]), // Templated
                  // Inputs
                  .clk                  (clk),
                  .nreset               (nreset),
                  .ioclk                (ioclk),
                  .ionreset             (ionreset),
                  .devicemode           (devicemode),
                  .chipdir              (chipdir[1:0]),
                  .csr_protocol         (csr_protocol[3:0]),
                  .csr_eccmode          (csr_eccmode[3:0]),
                  .csr_bpprotocol       (csr_bpprotocol),
                  .csr_bpfifo           (csr_bpfifo),
                  .csr_chaos            (csr_chaos),
                  .vss                  (vss),
                  .vdd                  (vdd),
                  .umi_in_cmd           (umi_resp_phy2mac_cmd[CW-1:0]), // Templated
                  .umi_in_dstaddr       (umi_resp_phy2mac_dstaddr[AW-1:0]), // Templated
                  .umi_in_srcaddr       (umi_resp_phy2mac_srcaddr[AW-1:0]), // Templated
                  .umi_in_data          (umi_resp_phy2mac_data[DW-1:0]), // Templated
                  .umi_in_valid         (umi_resp_phy2mac_valid), // Templated
                  .umi_out_ready        (umi_resp_out_ready));   // Templated


   //#####################
   //# UMI_REQ MAC
   //#####################

   clink_rxmac #(.DW(DW),
		 .AW(AW),
		 .CW(CW),
		 .TARGET(TARGET))
   rxmac_umi_req(/*AUTOINST*/
                 // Outputs
                 .csr_empty             (csr_reqempty),          // Templated
                 .csr_full              (csr_reqfull),           // Templated
                 .umi_in_ready          (umi_req_phy2mac_ready), // Templated
                 .umi_out_valid         (umi_req_out_valid),     // Templated
                 .umi_out_cmd           (umi_req_out_cmd[CW-1:0]), // Templated
                 .umi_out_dstaddr       (umi_req_out_dstaddr[AW-1:0]), // Templated
                 .umi_out_srcaddr       (umi_req_out_srcaddr[AW-1:0]), // Templated
                 .umi_out_data          (umi_req_out_data[DW-1:0]), // Templated
                 // Inputs
                 .clk                   (clk),
                 .nreset                (nreset),
                 .ioclk                 (ioclk),
                 .ionreset              (ionreset),
                 .devicemode            (devicemode),
                 .chipdir               (chipdir[1:0]),
                 .csr_protocol          (csr_protocol[3:0]),
                 .csr_eccmode           (csr_eccmode[3:0]),
                 .csr_bpprotocol        (csr_bpprotocol),
                 .csr_bpfifo            (csr_bpfifo),
                 .csr_chaos             (csr_chaos),
                 .vss                   (vss),
                 .vdd                   (vdd),
                 .umi_in_cmd            (umi_req_phy2mac_cmd[CW-1:0]), // Templated
                 .umi_in_dstaddr        (umi_req_phy2mac_dstaddr[AW-1:0]), // Templated
                 .umi_in_srcaddr        (umi_req_phy2mac_srcaddr[AW-1:0]), // Templated
                 .umi_in_data           (umi_req_phy2mac_data[DW-1:0]), // Templated
                 .umi_in_valid          (umi_req_phy2mac_valid), // Templated
                 .umi_out_ready         (umi_req_out_ready));    // Templated

endmodule // clink_rx
// Local Variables:
// verilog-library-directories:("." "../../../umi/umi/rtl")
// End:
