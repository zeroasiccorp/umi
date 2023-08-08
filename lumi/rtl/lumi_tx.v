/******************************************************************************
 * Function:  CLINK Transmitter
 * Author:    Andreas Olofsson
 * Copyright: 2020 Zero ASIC Corporation
 * License:
 *
 * Documentation:
 *
 *
 *****************************************************************************/
module clink_tx
  #(
    parameter TARGET = "DEFAULT", // implementation target
    parameter FIFODEPTH = 4,      // fifo depth
    parameter IOW = 64,           // clink rx/tx width
    parameter CW = 32,
    parameter AW = 64,
    parameter DW = 256            // umi data width
    )
   (// basics
    input            clk,               // core clock
    input            ioclk,             // io clock
    input            nreset,            // async active low reset
    input            ionreset,          // tx async active low reset
    input            vss,               // common clground
    input            vdd,               // core supply
    input            vddio,             // io voltage
    input [1:0]      chipdir,           // rotation (00=0,01=90,10=180,11=270)
    input            devicemode,        // 1=device, 0=host
    // csr settings
    input            csr_en,            // link enable
    input            csr_crdt_en,
    input            csr_ddrmode,       // 1 = ddr, 0 = sdr
    input [1:0]      csr_chipletmode,   // 00=110um,01=45um,10=10um,11=1um
    input [7:0]      csr_iowidth,       // pad bus width
    input [3:0]      csr_protocol,      // protocol selector
    input [3:0]      csr_eccmode,       // ecc mode
    input [1:0]      csr_arbmode,       // phy arbiter mode
    input            csr_chaos,         // enable random fifo pushback
    input            csr_bpfifo,        // bypass tx fifo
    input            csr_bpprotocol,    // bypass tx proto
    input            csr_bpio,          // bypass tx IO
    // status signals
    output           csr_respfull,
    output           csr_respempty,
    output           csr_reqfull,
    output           csr_reqempty,
    // pad/bump signals
    output [IOW-1:0] io_txdata,         // link data to pads
    output [3:0]     io_txctrl,         // link ctrl (valid) to pads
    input [3:0]      io_txstatus,       // flow control from pads
    // core signals
    input            umi_resp_in_valid, //write
    input [CW-1:0]   umi_resp_in_cmd,
    input [AW-1:0]   umi_resp_in_dstaddr,
    input [AW-1:0]   umi_resp_in_srcaddr,
    input [DW-1:0]   umi_resp_in_data,
    output           umi_resp_in_ready,
    input            umi_req_in_valid,  //read
    input [CW-1:0]   umi_req_in_cmd,
    input [AW-1:0]   umi_req_in_dstaddr,
    input [AW-1:0]   umi_req_in_srcaddr,
    input [DW-1:0]   umi_req_in_data,
    output           umi_req_in_ready,
    // Credit interface
    output [31:0]    csr_crdt_status,
    input [15:0]     csr_crdt_intrvl,
    input [15:0]     loc_crdt_req,
    input [15:0]     loc_crdt_resp,
    input [15:0]     rmt_crdt_req,
    input [15:0]     rmt_crdt_resp
    /*AUTOINPUT*/
    /*AUTOOUTPUT*/
    );

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [CW-1:0]        umi_req_mac2phy_cmd;
   wire [DW-1:0]        umi_req_mac2phy_data;
   wire [AW-1:0]        umi_req_mac2phy_dstaddr;
   wire                 umi_req_mac2phy_ready;
   wire [AW-1:0]        umi_req_mac2phy_srcaddr;
   wire                 umi_req_mac2phy_valid;
   wire [CW-1:0]        umi_resp_mac2phy_cmd;
   wire [DW-1:0]        umi_resp_mac2phy_data;
   wire [AW-1:0]        umi_resp_mac2phy_dstaddr;
   wire                 umi_resp_mac2phy_ready;
   wire [AW-1:0]        umi_resp_mac2phy_srcaddr;
   wire                 umi_resp_mac2phy_valid;
   // End of automatics

   //#####################
   //# UMI_RESP MAC
   //#####################

   /*clink_txmac  AUTO_TEMPLATE (
    .umi_out_\(.*\)  (umi_@"(substring vl-cell-name 6)"_mac2phy_\1[]),
    .umi_in_\(.*\)   (umi_@"(substring vl-cell-name 6)"_in_\1[]),
    .csr_empty       (csr_@"(substring vl-cell-name 6)"empty),
    .csr_full        (csr_@"(substring vl-cell-name 6)"full),
    );
    */

   clink_txmac #(.DW(DW),
		 .AW(AW),
		 .CW(CW),
		 .TARGET(TARGET))
   txmac_resp(/*AUTOINST*/
              // Outputs
              .csr_empty        (csr_respempty),         // Templated
              .csr_full         (csr_respfull),          // Templated
              .umi_in_ready     (umi_resp_in_ready),     // Templated
              .umi_out_valid    (umi_resp_mac2phy_valid), // Templated
              .umi_out_cmd      (umi_resp_mac2phy_cmd[CW-1:0]), // Templated
              .umi_out_dstaddr  (umi_resp_mac2phy_dstaddr[AW-1:0]), // Templated
              .umi_out_srcaddr  (umi_resp_mac2phy_srcaddr[AW-1:0]), // Templated
              .umi_out_data     (umi_resp_mac2phy_data[DW-1:0]), // Templated
              // Inputs
              .clk              (clk),
              .nreset           (nreset),
              .ioclk            (ioclk),
              .ionreset         (ionreset),
              .devicemode       (devicemode),
              .chipdir          (chipdir[1:0]),
              .csr_protocol     (csr_protocol[3:0]),
              .csr_eccmode      (csr_eccmode[3:0]),
              .csr_bpprotocol   (csr_bpprotocol),
              .csr_bpfifo       (csr_bpfifo),
              .csr_chaos        (csr_chaos),
              .vss              (vss),
              .vdd              (vdd),
              .umi_in_valid     (umi_resp_in_valid),     // Templated
              .umi_in_cmd       (umi_resp_in_cmd[CW-1:0]), // Templated
              .umi_in_dstaddr   (umi_resp_in_dstaddr[AW-1:0]), // Templated
              .umi_in_srcaddr   (umi_resp_in_srcaddr[AW-1:0]), // Templated
              .umi_in_data      (umi_resp_in_data[DW-1:0]), // Templated
              .umi_out_ready    (umi_resp_mac2phy_ready)); // Templated

   //#####################
   //# UMI_REQ MAC
   //#####################

   clink_txmac #(.DW(DW),
		 .AW(AW),
		 .CW(CW),
		 .TARGET(TARGET))
   txmac_req(/*AUTOINST*/
             // Outputs
             .csr_empty         (csr_reqempty),          // Templated
             .csr_full          (csr_reqfull),           // Templated
             .umi_in_ready      (umi_req_in_ready),      // Templated
             .umi_out_valid     (umi_req_mac2phy_valid), // Templated
             .umi_out_cmd       (umi_req_mac2phy_cmd[CW-1:0]), // Templated
             .umi_out_dstaddr   (umi_req_mac2phy_dstaddr[AW-1:0]), // Templated
             .umi_out_srcaddr   (umi_req_mac2phy_srcaddr[AW-1:0]), // Templated
             .umi_out_data      (umi_req_mac2phy_data[DW-1:0]), // Templated
             // Inputs
             .clk               (clk),
             .nreset            (nreset),
             .ioclk             (ioclk),
             .ionreset          (ionreset),
             .devicemode        (devicemode),
             .chipdir           (chipdir[1:0]),
             .csr_protocol      (csr_protocol[3:0]),
             .csr_eccmode       (csr_eccmode[3:0]),
             .csr_bpprotocol    (csr_bpprotocol),
             .csr_bpfifo        (csr_bpfifo),
             .csr_chaos         (csr_chaos),
             .vss               (vss),
             .vdd               (vdd),
             .umi_in_valid      (umi_req_in_valid),      // Templated
             .umi_in_cmd        (umi_req_in_cmd[CW-1:0]), // Templated
             .umi_in_dstaddr    (umi_req_in_dstaddr[AW-1:0]), // Templated
             .umi_in_srcaddr    (umi_req_in_srcaddr[AW-1:0]), // Templated
             .umi_in_data       (umi_req_in_data[DW-1:0]), // Templated
             .umi_out_ready     (umi_req_mac2phy_ready)); // Templated

   /*clink_txphy  AUTO_TEMPLATE (
    .csr_txcrd_stat     (),
    .\(.*\)_in_\(.*\)   (\1_mac2phy_\2[]),
    )
    */

   clink_txphy #(.DW(DW),
		 .AW(AW),
		 .CW(CW),
		 .IOW(IOW),
		 .TARGET(TARGET))
   clink_txphy(/*AUTOINST*/
               // Outputs
               .umi_req_in_ready(umi_req_mac2phy_ready), // Templated
               .umi_resp_in_ready(umi_resp_mac2phy_ready), // Templated
               .io_txdata       (io_txdata[IOW-1:0]),
               .io_txctrl       (io_txctrl[3:0]),
               .csr_crdt_status (csr_crdt_status[31:0]),
               // Inputs
               .ioclk           (ioclk),
               .ionreset        (ionreset),
               .devicemode      (devicemode),
               .chipdir         (chipdir[1:0]),
               .csr_en          (csr_en),
               .csr_crdt_en     (csr_crdt_en),
               .csr_chipletmode (csr_chipletmode[1:0]),
               .csr_ddrmode     (csr_ddrmode),
               .csr_iowidth     (csr_iowidth[7:0]),
               .csr_eccmode     (csr_eccmode[3:0]),
               .csr_arbmode     (csr_arbmode[1:0]),
               .csr_bpio        (csr_bpio),
               .vss             (vss),
               .vdd             (vdd),
               .vddio           (vddio),
               .umi_req_in_valid(umi_req_mac2phy_valid), // Templated
               .umi_req_in_cmd  (umi_req_mac2phy_cmd[CW-1:0]), // Templated
               .umi_req_in_dstaddr(umi_req_mac2phy_dstaddr[AW-1:0]), // Templated
               .umi_req_in_srcaddr(umi_req_mac2phy_srcaddr[AW-1:0]), // Templated
               .umi_req_in_data (umi_req_mac2phy_data[DW-1:0]), // Templated
               .umi_resp_in_valid(umi_resp_mac2phy_valid), // Templated
               .umi_resp_in_cmd (umi_resp_mac2phy_cmd[CW-1:0]), // Templated
               .umi_resp_in_dstaddr(umi_resp_mac2phy_dstaddr[AW-1:0]), // Templated
               .umi_resp_in_srcaddr(umi_resp_mac2phy_srcaddr[AW-1:0]), // Templated
               .umi_resp_in_data(umi_resp_mac2phy_data[DW-1:0]), // Templated
               .io_txstatus     (io_txstatus[3:0]),
               .csr_crdt_intrvl (csr_crdt_intrvl[15:0]),
               .rmt_crdt_req    (rmt_crdt_req[15:0]),
               .rmt_crdt_resp   (rmt_crdt_resp[15:0]),
               .loc_crdt_req    (loc_crdt_req[15:0]),
               .loc_crdt_resp   (loc_crdt_resp[15:0]));

endmodule // clink_tx
// Local Variables:
// verilog-library-directories:("." "../../../umi/umi/rtl")
// End:
