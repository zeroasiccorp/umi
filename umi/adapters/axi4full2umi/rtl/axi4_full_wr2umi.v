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
 * - TODO: Flush out documentation
 *
 ******************************************************************************/
`timescale 1ns/1ps
module axi4_full_wr2umi #(
  parameter           CW = 32,
  parameter           DW = 128,
  parameter           AW = 64,
  parameter           IDW = 8,
  /* Note the bottom STRBW bits of HOSTADDR are ignored
   * Per UMI spec the recommendation is to set the bottom
   * STRBW bits of srcaddr to the AXI write channels strobe value */
  parameter [AW-1:0]  HOSTADDR = {AW{1'b0}},
  // Helper params don't touch
  parameter STRBW = DW/8
)(
  input clk,
  input nreset,

  //####################################
  // AXI4 FULL Write Channels
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

  `include "umi_messages.vh"

  localparam STRB_LOG2 = $clog2(STRBW);

  localparam SW = 3;
  localparam [SW-1:0]
    IDLE            = 'd0,
    UMI_WRITE       = 'd1,
    WAIT_UMI_RESP   = 'd2,
    SEND_B_RESP     = 'd3;

  /* Maximum theoretical bytes per AXI transaction
   * AXI4 supports a maximum burst length of 256 beats
   * and a maximum data width of 128 bytes. */
  localparam MAX_BYTES_PER_TRANS = (1 << 7) * 256;

  // bytes_left register width
  localparam BLW = $clog2(MAX_BYTES_PER_TRANS);

  integer i;

  //####################################
  // Registers
  //####################################
  reg [SW-1:0] state;
  reg [AW-1:0] dst_addr;

  reg [1:0] umi_cmd_prot;
  reg [3:0] umi_cmd_qos;

  reg [BLW-1:0] bytes_left;

  reg [IDW-1:0] aw_id;

  //####################################
  // Wires
  //####################################
  reg [SW-1:0] next_state;

  wire aw_fire;
  wire b_resp_fire;

  wire umi_req_fire;
  wire umi_resp_fire;

  reg [STRB_LOG2:0] w_strb_sum;

  wire [7:0] umi_cmd_len;

  wire [8:0]            aw_len_inc;
  wire [8+(2**3-1):0]   aw_trans_bytes_pre;
  wire [BLW-1:0]        aw_trans_bytes;

  wire no_bytes_left;



  //####################################
  // Helper signals
  //####################################
  assign aw_fire = s_axi_awvalid & s_axi_awready;
  assign b_resp_fire = s_axi_bvalid & s_axi_bready;

  assign umi_req_fire = uhost_req_valid & uhost_req_ready;
  assign umi_resp_fire = uhost_resp_valid & uhost_resp_ready;

  always @(posedge clk)
    // Per UMI spec lower two bits of AXI4 prot can be mapped to umi_cmd_prot
    umi_cmd_prot[1:0] <= aw_fire ? s_axi_awprot[1:0] : umi_cmd_prot[1:0];

  always @(posedge clk)
    // Per UMI spec AXI4 qos can be mapped directly to umi_cmd_qos
    umi_cmd_qos[3:0] <= aw_fire ? s_axi_awqos[3:0] : umi_cmd_qos[3:0];

  always @(posedge clk)
    aw_id[IDW-1:0] <= aw_fire ? s_axi_awid[IDW-1:0] : aw_id[IDW-1:0];

  // Figure out transaction length
  always @(*) begin
    w_strb_sum = 0;
    for (i = 0; i < STRBW; i = i + 1)
      w_strb_sum = w_strb_sum + s_axi_wstrb[i];
  end

  assign umi_cmd_len = w_strb_sum - 1;

  // Keep track of how many bytes are left to send over umi_req
  assign aw_len_inc[8:0] = s_axi_awlen[7:0] + 1'b1;
  assign aw_trans_bytes_pre[8+(2**3-1):0] = {{(2**3-1){1'b0}}, aw_len_inc[8:0]} << s_axi_awsize[2:0];
  assign aw_trans_bytes[BLW-1:0] = aw_trans_bytes_pre[BLW-1:0];

  always @(posedge clk)
    if (aw_fire)
      bytes_left[BLW-1:0] <= aw_trans_bytes[BLW-1:0];
    else if (umi_req_fire)
      if (s_axi_wlast)
        bytes_left[BLW-1:0] <= {BLW{1'b0}};
      else
        bytes_left[BLW-1:0] <= bytes_left[BLW-1:0] - w_strb_sum[STRB_LOG2:0];

  assign no_bytes_left = (bytes_left[BLW-1:0] == {BLW{1'b0}});

  // Load destination address when AW fires, increment when UMI req fires
  always @(posedge clk)
    if (aw_fire)
      dst_addr[AW-1:0] <= s_axi_awaddr[AW-1:0];
    else if (umi_req_fire)
      dst_addr[AW-1:0] <= dst_addr[AW-1:0] + w_strb_sum[STRB_LOG2:0];

  //####################################
  // Data path
  //####################################

  // Handshakes only occur on UMI req channel in UMI_WRITE state
  assign uhost_req_valid = (state == UMI_WRITE) & s_axi_wvalid;
  assign s_axi_wready    = (state == UMI_WRITE) & uhost_req_ready;

  umi_pack #(
    .CW   (CW)
  ) u_umi_pack (
    .cmd_opcode         (UMI_REQ_WRITE),
    /* Size can be tied zero because AXI4 Spec
     * sets the maximum AXI4 data width to 128 bytes.
     * Therefore for any valid AXI4 master only the UMI
     * length field is needed to encode the transfer size. */
    .cmd_size           (3'b0),
    .cmd_len            (umi_cmd_len),
    .cmd_atype          (8'b0),
    .cmd_prot           (umi_cmd_prot),
    .cmd_qos            (umi_cmd_qos),
    .cmd_eom            (s_axi_wlast),
    .cmd_eof            (1'b0),
    .cmd_user           (2'b0),
    .cmd_err            (2'b00),
    .cmd_ex             (1'b0),
    .cmd_hostid         (5'b0),
    .cmd_user_extended  (24'b0),
    .packet_cmd         (uhost_req_cmd)
  );

  assign uhost_req_srcaddr[AW-1:0] = {HOSTADDR[AW-1:STRBW], s_axi_wstrb[STRBW-1:0]};

  assign uhost_req_dstaddr[AW-1:0] = dst_addr[AW-1:0];

  assign uhost_req_data[DW-1:0] = s_axi_wdata[DW-1:0];

  assign uhost_resp_ready = (state == WAIT_UMI_RESP);


  /*
   * FSM HERE:
   * - IDLE: Wait for AXI4 AW transaction
   * - UMI_WRITE: Send UMI write request
   * - WAIT_UMI_RESP: Wait for UMI Response
   * - SEND_B_RESP: Send AXI4 Write Response
   */

  assign s_axi_awready = (state == IDLE);
  assign s_axi_bvalid = (state == SEND_B_RESP);

  always @(*)
    case (state)
      IDLE:
        next_state = s_axi_awvalid ? UMI_WRITE : IDLE;

      UMI_WRITE:
        next_state = umi_req_fire ? WAIT_UMI_RESP : UMI_WRITE;

      WAIT_UMI_RESP:
        if (umi_resp_fire)
          next_state = no_bytes_left ? SEND_B_RESP : UMI_WRITE;
        else
          next_state = WAIT_UMI_RESP;

      SEND_B_RESP:
        next_state = b_resp_fire ? IDLE : SEND_B_RESP;

      default:
        next_state = IDLE;

    endcase

  always @(posedge clk or negedge nreset)
    if (~nreset)
      state <= IDLE;
    else
      state <= next_state;

  // TODO: Handle errors
  assign s_axi_bresp = 2'b00;
  assign s_axi_bid[IDW-1:0] = aw_id[IDW-1:0];

  // TODO: ADD ERROR CHECKING THAT DW is NEVER > 128 * 8 (max width of axi4 full bus)


endmodule
