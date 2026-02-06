/*******************************************************************************
 * Copyright 2026 Zero ASIC Corporation
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * ----
 *
 * Documentation:
 *
 * This module converts AXI4 Full transactions (read and write) to UMI.
 * It instantiates separate read and write converters, multiplexes their
 * UMI requests onto a single output interface, and demultiplexes UMI
 * responses back to the appropriate converter based on destination address.
 *
 * Architecture:
 *   - axiwr2umi: Converts AXI write channels to UMI REQ_WRITE
 *   - axird2umi: Converts AXI read channels to UMI REQ_READ
 *   - umi_mux (2:1): Arbitrates UMI requests with round-robin policy
 *   - umi_demux (1:2): Routes UMI responses based on dstaddr comparison
 *
 * Parameters:
 *   CW          - UMI command width (default 32)
 *   DW          - Data width in bits, must be <= 128
 *   AW          - Address width in bits (default 64)
 *   IDW         - AXI ID width (default 8)
 *   WR_HOSTADDR - UMI source address for write requests (default 0)
 *   RD_HOSTADDR - UMI source address for read requests (default MSB set)
 *
 * Response Routing:
 *   UMI responses are routed back to the correct channel by comparing
 *   uhost_resp_dstaddr[AW-1:STRBW] against WR_HOSTADDR and RD_HOSTADDR.
 *   The lower STRBW bits are masked out since the write path encodes
 *   the AXI strobe value in those bits. WR_HOSTADDR and RD_HOSTADDR
 *   must differ in their upper [AW-1:STRBW] bits for correct routing.
 *
 ******************************************************************************/

// TODO: remove this timescale
`timescale 1ns/1ps

module axi2umi #(
  parameter           CW = 32,
  parameter           DW = 128,
  parameter           AW = 64,
  parameter           IDW = 8,
  /* Note the bottom STRBW bits of WR_HOSTADDR are ignored
   * per UMI spec. The spec recommendation is to set the bottom
   * STRBW bits of srcaddr to the AXI write channels strobe value */
  parameter [AW-1:0]  WR_HOSTADDR = {AW{1'b0}},
  parameter [AW-1:0]  RD_HOSTADDR = {1'b1, {(AW-1){1'b0}}},
  // Helper params don't touch
  parameter STRBW = DW/8
)(
  input clk,
  input nreset,

  //####################################
  // AXI4 FULL Interface
  //####################################

  // AXI4 Write Address Channel
  input [IDW-1:0]       s_axi_awid,
  input [AW-1:0]        s_axi_awaddr,
  input [7:0]           s_axi_awlen,
  input [2:0]           s_axi_awsize,
  input [1:0]           s_axi_awburst,
  input                 s_axi_awlock,
  input [3:0]           s_axi_awcache,
  input [2:0]           s_axi_awprot,
  input [3:0]           s_axi_awqos,
  input                 s_axi_awvalid,
  output                s_axi_awready,

  // AXI4 Write Data Channel
  input [IDW-1:0]       s_axi_wid,
  input [DW-1:0]        s_axi_wdata,
  input [STRBW-1:0]     s_axi_wstrb,
  input                 s_axi_wlast,
  input                 s_axi_wvalid,
  output                s_axi_wready,

  // AXI4 Write Response Channel
  output [IDW-1:0]      s_axi_bid,
  output [1:0]          s_axi_bresp,
  output                s_axi_bvalid,
  input                 s_axi_bready,

  // AXI4 Read Address Channel
  input [IDW-1:0]       s_axi_arid,
  input [AW-1:0]        s_axi_araddr,
  input [7:0]           s_axi_arlen,
  input [2:0]           s_axi_arsize,
  input [1:0]           s_axi_arburst,
  input                 s_axi_arlock,
  input [3:0]           s_axi_arcache,
  input [2:0]           s_axi_arprot,
  input [3:0]           s_axi_arqos,
  input                 s_axi_arvalid,
  output                s_axi_arready,

  // AXI4 Read Data Channel
  output [IDW-1:0]      s_axi_rid,
  output [DW-1:0]       s_axi_rdata,
  output [1:0]          s_axi_rresp,
  output                s_axi_rlast,
  output                s_axi_rvalid,
  input                 s_axi_rready,

  //####################################
  // UMI Host Interface
  //####################################

  // UMI Request Channel
  output                uhost_req_valid,
  output [CW-1:0]       uhost_req_cmd,
  output [AW-1:0]       uhost_req_dstaddr,
  output [AW-1:0]       uhost_req_srcaddr,
  output [DW-1:0]       uhost_req_data,
  input                 uhost_req_ready,

  // UMI Response Channel
  input                 uhost_resp_valid,
  input  [CW-1:0]       uhost_resp_cmd,
  input  [AW-1:0]       uhost_resp_dstaddr,
  input  [AW-1:0]       uhost_resp_srcaddr,
  input  [DW-1:0]       uhost_resp_data,
  output                uhost_resp_ready
);

  //####################################
  // Local Parameters
  //####################################
  localparam N = 2;  // Number of UMI request sources (WR + RD)

  //####################################
  // Wires
  //####################################

  // UMI REQ from WR module to mux
  wire              wr_umi_req_valid;
  wire [CW-1:0]     wr_umi_req_cmd;
  wire [AW-1:0]     wr_umi_req_dstaddr;
  wire [AW-1:0]     wr_umi_req_srcaddr;
  wire [DW-1:0]     wr_umi_req_data;
  wire              wr_umi_req_ready;

  // UMI RESP from demux to WR module
  wire              wr_umi_resp_valid;
  wire [CW-1:0]     wr_umi_resp_cmd;
  wire [AW-1:0]     wr_umi_resp_dstaddr;
  wire [AW-1:0]     wr_umi_resp_srcaddr;
  wire [DW-1:0]     wr_umi_resp_data;
  wire              wr_umi_resp_ready;

  // UMI REQ from RD module to mux
  wire              rd_umi_req_valid;
  wire [CW-1:0]     rd_umi_req_cmd;
  wire [AW-1:0]     rd_umi_req_dstaddr;
  wire [AW-1:0]     rd_umi_req_srcaddr;
  wire [DW-1:0]     rd_umi_req_data;
  wire              rd_umi_req_ready;

  // UMI RESP from demux to RD module
  wire              rd_umi_resp_valid;
  wire [CW-1:0]     rd_umi_resp_cmd;
  wire [AW-1:0]     rd_umi_resp_dstaddr;
  wire [AW-1:0]     rd_umi_resp_srcaddr;
  wire [DW-1:0]     rd_umi_resp_data;
  wire              rd_umi_resp_ready;

  // Demux select signal
  wire [N-1:0]      demux_select;

  //####################################
  // AXI4 Full Write to UMI
  //####################################

  axiwr2umi #(
    .CW       (CW),
    .DW       (DW),
    .AW       (AW),
    .IDW      (IDW),
    .HOSTADDR (WR_HOSTADDR)
  ) u_axiwr2umi (
    .clk              (clk),
    .nreset           (nreset),
    // AXI4 Write Address Channel
    .s_axi_awid       (s_axi_awid),
    .s_axi_awaddr     (s_axi_awaddr),
    .s_axi_awlen      (s_axi_awlen),
    .s_axi_awsize     (s_axi_awsize),
    .s_axi_awburst    (s_axi_awburst),
    .s_axi_awlock     (s_axi_awlock),
    .s_axi_awcache    (s_axi_awcache),
    .s_axi_awprot     (s_axi_awprot),
    .s_axi_awqos      (s_axi_awqos),
    .s_axi_awvalid    (s_axi_awvalid),
    .s_axi_awready    (s_axi_awready),
    // AXI4 Write Data Channel
    .s_axi_wid        (s_axi_wid),
    .s_axi_wdata      (s_axi_wdata),
    .s_axi_wstrb      (s_axi_wstrb),
    .s_axi_wlast      (s_axi_wlast),
    .s_axi_wvalid     (s_axi_wvalid),
    .s_axi_wready     (s_axi_wready),
    // AXI4 Write Response Channel
    .s_axi_bid        (s_axi_bid),
    .s_axi_bresp      (s_axi_bresp),
    .s_axi_bvalid     (s_axi_bvalid),
    .s_axi_bready     (s_axi_bready),
    // UMI Request Channel (to mux)
    .uhost_req_valid    (wr_umi_req_valid),
    .uhost_req_cmd      (wr_umi_req_cmd),
    .uhost_req_dstaddr  (wr_umi_req_dstaddr),
    .uhost_req_srcaddr  (wr_umi_req_srcaddr),
    .uhost_req_data     (wr_umi_req_data),
    .uhost_req_ready    (wr_umi_req_ready),
    // UMI Response Channel (from demux)
    .uhost_resp_valid   (wr_umi_resp_valid),
    .uhost_resp_cmd     (wr_umi_resp_cmd),
    .uhost_resp_dstaddr (wr_umi_resp_dstaddr),
    .uhost_resp_srcaddr (wr_umi_resp_srcaddr),
    .uhost_resp_data    (wr_umi_resp_data),
    .uhost_resp_ready   (wr_umi_resp_ready)
  );

  //####################################
  // AXI4 Full Read to UMI
  //####################################

  axird2umi #(
    .CW       (CW),
    .DW       (DW),
    .AW       (AW),
    .IDW      (IDW),
    .HOSTADDR (RD_HOSTADDR)
  ) u_axird2umi (
    .clk              (clk),
    .nreset           (nreset),
    // AXI4 Read Address Channel
    .s_axi_arid       (s_axi_arid),
    .s_axi_araddr     (s_axi_araddr),
    .s_axi_arlen      (s_axi_arlen),
    .s_axi_arsize     (s_axi_arsize),
    .s_axi_arburst    (s_axi_arburst),
    .s_axi_arlock     (s_axi_arlock),
    .s_axi_arcache    (s_axi_arcache),
    .s_axi_arprot     (s_axi_arprot),
    .s_axi_arqos      (s_axi_arqos),
    .s_axi_arvalid    (s_axi_arvalid),
    .s_axi_arready    (s_axi_arready),
    // AXI4 Read Data Channel
    .s_axi_rid        (s_axi_rid),
    .s_axi_rdata      (s_axi_rdata),
    .s_axi_rresp      (s_axi_rresp),
    .s_axi_rlast      (s_axi_rlast),
    .s_axi_rvalid     (s_axi_rvalid),
    .s_axi_rready     (s_axi_rready),
    // UMI Request Channel (to mux)
    .uhost_req_valid      (rd_umi_req_valid),
    .uhost_req_cmd        (rd_umi_req_cmd),
    .uhost_req_dstaddr    (rd_umi_req_dstaddr),
    .uhost_req_srcaddr    (rd_umi_req_srcaddr),
    .uhost_req_data       (rd_umi_req_data),
    .uhost_req_ready      (rd_umi_req_ready),
    // UMI Response Channel (from demux)
    .uhost_resp_valid     (rd_umi_resp_valid),
    .uhost_resp_cmd       (rd_umi_resp_cmd),
    .uhost_resp_dstaddr   (rd_umi_resp_dstaddr),
    .uhost_resp_srcaddr   (rd_umi_resp_srcaddr),
    .uhost_resp_data      (rd_umi_resp_data),
    .uhost_resp_ready     (rd_umi_resp_ready)
  );

  //####################################
  // UMI Request Mux (2:1)
  //####################################

  umi_mux #(
    .N  (N),
    .DW (DW),
    .CW (CW),
    .AW (AW)
  ) u_umi_mux (
    .clk            (clk),
    .nreset         (nreset),
    // Round-robin arbitration
    .arbmode        (2'b01),
    // No masking
    .arbmask        ({N{1'b0}}),
    // Incoming UMI (concatenated: {RD, WR})
    .umi_in_valid   ({rd_umi_req_valid,   wr_umi_req_valid}),
    .umi_in_cmd     ({rd_umi_req_cmd,     wr_umi_req_cmd}),
    .umi_in_dstaddr ({rd_umi_req_dstaddr, wr_umi_req_dstaddr}),
    .umi_in_srcaddr ({rd_umi_req_srcaddr, wr_umi_req_srcaddr}),
    .umi_in_data    ({rd_umi_req_data,    wr_umi_req_data}),
    .umi_in_ready   ({rd_umi_req_ready,   wr_umi_req_ready}),
    // Outgoing UMI (to top-level)
    .umi_out_valid  (uhost_req_valid),
    .umi_out_cmd    (uhost_req_cmd),
    .umi_out_dstaddr(uhost_req_dstaddr),
    .umi_out_srcaddr(uhost_req_srcaddr),
    .umi_out_data   (uhost_req_data),
    .umi_out_ready  (uhost_req_ready)
  );

  //####################################
  // UMI Response Demux (1:2)
  //####################################

  // Select based on comparing upper bits of dstaddr with HOSTADDR values
  // Mask out lower STRBW bits (used for strobe encoding in WR path)
  assign demux_select[0] = (uhost_resp_dstaddr[AW-1:STRBW] == WR_HOSTADDR[AW-1:STRBW]);
  assign demux_select[1] = (uhost_resp_dstaddr[AW-1:STRBW] == RD_HOSTADDR[AW-1:STRBW]);

  umi_demux #(
    .M  (N),
    .DW (DW),
    .CW (CW),
    .AW (AW)
  ) u_umi_demux (
    .select         (demux_select),
    // Incoming UMI (from top-level)
    .umi_in_valid   (uhost_resp_valid),
    .umi_in_cmd     (uhost_resp_cmd),
    .umi_in_dstaddr (uhost_resp_dstaddr),
    .umi_in_srcaddr (uhost_resp_srcaddr),
    .umi_in_data    (uhost_resp_data),
    .umi_in_ready   (uhost_resp_ready),
    // Outgoing UMI (concatenated: {RD, WR})
    .umi_out_valid  ({rd_umi_resp_valid,    wr_umi_resp_valid}),
    .umi_out_cmd    ({rd_umi_resp_cmd,      wr_umi_resp_cmd}),
    .umi_out_dstaddr({rd_umi_resp_dstaddr,  wr_umi_resp_dstaddr}),
    .umi_out_srcaddr({rd_umi_resp_srcaddr,  wr_umi_resp_srcaddr}),
    .umi_out_data   ({rd_umi_resp_data,     wr_umi_resp_data}),
    .umi_out_ready  ({rd_umi_resp_ready,    wr_umi_resp_ready})
  );

endmodule
