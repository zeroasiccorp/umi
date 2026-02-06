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
 * This module converts AXI4 Full write transactions to UMI write requests.
 * Each AXI write beat is converted to a UMI REQ_WRITE transaction, with
 * a UMI RESP_WRITE expected for each beat before proceeding to the next.
 *
 * Parameters:
 *   CW       - UMI command width (default 32)
 *   DW       - Data width in bits, must be <= 128 (16 byte strobe fits in SA[15:0])
 *   AW       - Address width in bits (default 64)
 *   IDW      - AXI ID width (default 8)
 *   HOSTADDR - UMI source address base. The bottom STRBW bits are replaced
 *              with the raw AXI write strobe value per UMI spec recommendation.
 *
 * Supported AXI4 Features:
 *   - Write address channel (AW) with ID, address, len, size, burst, prot, qos
 *   - Write data channel (W) with data, strobe, last
 *   - Write response channel (B) with ID and response
 *   - Burst types: FIXED (all beats to same address), INCR (incrementing)
 *   - Variable burst lengths (1-256 beats via AWLEN)
 *   - Variable transfer sizes (via AWSIZE)
 *   - Contiguous write strobes, including non-LSB-aligned (address and data
 *     are adjusted to the first active strobe byte)
 *   - AWPROT[1:0] mapped to UMI PROT field
 *   - AWQOS[3:0] mapped to UMI QOS field
 *   - AXI ID pass-through (AWID -> BID)
 *
 * Unsupported AXI4 Features:
 *   - WRAP burst type (will behave as FIXED)
 *   - AWLOCK (exclusive/locked access) - signal present but ignored
 *   - AWCACHE (memory attributes) - signal present but ignored
 *   - AWPROT[2] (instruction/data) - only AWPROT[1:0] used
 *   - Out-of-order transaction completion
 *   - Write interleaving (s_axi_wid is ignored, transactions are in-order)
 *   - Non-contiguous write strobes (strobes must be contiguous)
 *
 * Error Handling:
 *   - UMI response errors (ERR field != 0) propagate to AXI BRESP
 *   - Unexpected UMI response opcodes (not RESP_WRITE) return SLVERR (2'b10)
 *   - Errors are latched across burst beats; last error latched is reported.
 *
 * Protocol Notes:
 *   - One UMI request per AXI write beat (not per burst)
 *   - Module waits for UMI response before accepting next beat
 *   - Single outstanding AXI transaction supported (no pipelining)
 *   - UMI cmd.size is always 0; transfer size encoded in cmd.len only
 *     (valid since AXI4 max data width of 128 bytes fits in UMI len field)
 *   - Write beats with all-zero strobe are accepted and consumed without
 *     generating a UMI transaction (no request or response for that beat)
 *   - WLAST is not used for flow control; burst completion is determined
 *     solely by counting beats against AWLEN
 *   - For non-LSB-aligned strobes, dstaddr is offset by the index of the
 *     first active strobe byte and data is right-shifted accordingly
 *   - UMI srcaddr lower STRBW bits carry the raw AXI write strobe value
 *   - EOM is always asserted because empty (all-zero strobe) beats can
 *     appear at any position, making the true last data beat unpredictable
 *
 ******************************************************************************/

// TODO: remove this timescale
`timescale 1ns/1ps

module axiwr2umi #(
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

  // Parameter validation: DW must be <= 128 bits (16 bytes) so strobe fits in SA[15:0]
  generate 
    if (DW > 128) begin : gen_dw_check
      initial begin
        $error("DW=%0d exceeds maximum of 128 bits. Strobe width would exceed 16 bits.", DW);
      end
    end
  endgenerate

  localparam STRB_LOG2 = $clog2(STRBW);

  localparam SW = 2;
  localparam [SW-1:0]
    IDLE            = 'd0,
    UMI_WRITE       = 'd1,
    WAIT_UMI_RESP   = 'd2,
    SEND_B_RESP     = 'd3;

  // AXI4 burst types
  localparam [1:0]
    AXI_BURST_FIXED = 2'b00,
    AXI_BURST_INCR  = 2'b01,
    AXI_BURST_WRAP  = 2'b10;

  integer i;

  //####################################
  // Registers
  //####################################
  reg [SW-1:0] state;
  reg [AW-1:0] dst_addr;

  reg [1:0] umi_cmd_prot;
  reg [3:0] umi_cmd_qos;

  reg [8:0] axi_beats_left;

  reg [IDW-1:0] aw_id;
  reg [2:0] aw_size;
  reg [1:0] aw_burst;

  reg [1:0] bresp_err;

  //####################################
  // Wires
  //####################################
  reg [SW-1:0] next_state;

  wire aw_fire;
  wire w_fire;
  wire b_resp_fire;

  wire umi_req_fire;
  wire umi_resp_fire;

  wire empty_wr_beat;

  wire [AW-1:0] bytes_per_beat;

  reg [STRB_LOG2:0]     w_strb_sum;
  wire [7:0]            umi_cmd_len;

  wire no_axi_beats_left;

  wire [1:0] umi_resp_cmd_err;
  wire [4:0] umi_resp_cmd_opcode;

  wire [STRBW-1:0] right_most_strb_bit;
  reg [STRB_LOG2:0] right_most_strb_bit_index;

  //####################################
  // Helper signals
  //####################################
  assign aw_fire = s_axi_awvalid & s_axi_awready;
  assign w_fire = s_axi_wvalid & s_axi_wready;
  assign b_resp_fire = s_axi_bvalid & s_axi_bready;

  assign umi_req_fire = uhost_req_valid & uhost_req_ready;
  assign umi_resp_fire = uhost_resp_valid & uhost_resp_ready;

  assign empty_wr_beat = (s_axi_wstrb == {STRBW{1'b0}});

  always @(posedge clk)
    // Per UMI spec lower two bits of AXI4 prot can be mapped to umi_cmd_prot
    umi_cmd_prot[1:0] <= aw_fire ? s_axi_awprot[1:0] : umi_cmd_prot[1:0];

  always @(posedge clk)
    // Per UMI spec AXI4 qos can be mapped directly to umi_cmd_qos
    umi_cmd_qos[3:0] <= aw_fire ? s_axi_awqos[3:0] : umi_cmd_qos[3:0];

  always @(posedge clk)
    aw_id[IDW-1:0] <= aw_fire ? s_axi_awid[IDW-1:0] : aw_id[IDW-1:0];

  always @(posedge clk)
    aw_size[2:0] <= aw_fire ? s_axi_awsize[2:0] : aw_size[2:0];

  always @(posedge clk)
    aw_burst[1:0] <= aw_fire ? s_axi_awburst[1:0] : aw_burst[1:0];

  // Figure out transaction length
  always @(*) begin
    w_strb_sum = 0;
    for (i = 0; i < STRBW; i = i + 1)
      w_strb_sum = w_strb_sum + s_axi_wstrb[i];
  end

  /* UMI does not support byte strobes, so non-LSB-aligned strobes are handled
   * by finding the first active strobe byte, offsetting dstaddr by that index,
   * and right-shifting wdata to remove the inactive low bytes. */
  assign right_most_strb_bit[STRBW-1:0] = (s_axi_wstrb[STRBW-1:0] & (~s_axi_wstrb[STRBW-1:0] + 1'b1));
  always @(*) begin
    right_most_strb_bit_index[STRB_LOG2:0] = 0;
    for (i = 0; i < STRBW; i = i + 1)
      if (right_most_strb_bit[i])
        right_most_strb_bit_index[STRB_LOG2:0] = i[STRB_LOG2:0];
  end


  assign umi_cmd_len = w_strb_sum - 1;

  // Track remaining AXI beats in transaction
  always @(posedge clk)
    if (aw_fire)
      axi_beats_left[8:0] <= {1'b0, s_axi_awlen[7:0]} + 9'd1;
    else if (w_fire)
      axi_beats_left[8:0] <= axi_beats_left[8:0] - 1'b1;

  assign no_axi_beats_left = (axi_beats_left[8:0] == 9'b0);

  // Load destination address when AW fires, increment when UMI req fires (INCR only)
  assign bytes_per_beat[AW-1:0] = {{(AW-8){1'b0}}, (8'd1 << aw_size[2:0])};
  always @(posedge clk)
    if (aw_fire)
      dst_addr[AW-1:0] <= s_axi_awaddr[AW-1:0];
    else if (w_fire && (aw_burst == AXI_BURST_INCR))
      dst_addr[AW-1:0] <= dst_addr[AW-1:0] + bytes_per_beat[AW-1:0];

  //####################################
  // Data path
  //####################################

  /* Handshake only occurs on UMI req channel in UMI_WRITE
   * state when AXI write interface has data (according to strobe) */
  assign uhost_req_valid = (state == UMI_WRITE) & (~no_axi_beats_left) & s_axi_wvalid & ~empty_wr_beat;
  assign s_axi_wready    = (state == UMI_WRITE) & (~no_axi_beats_left) & (uhost_req_ready | empty_wr_beat);

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
    /* EOM tied high since it is impossible to know which
     * AXI beat will be the last since W_STRB can be set zero. */
    .cmd_eom            (1'b1),
    .cmd_eof            (1'b0),
    .cmd_user           (2'b0),
    .cmd_err            (2'b00),
    .cmd_ex             (1'b0),
    .cmd_hostid         (5'b0),
    .cmd_user_extended  (24'b0),
    .packet_cmd         (uhost_req_cmd)
  );

  assign uhost_req_srcaddr[AW-1:0] = {HOSTADDR[AW-1:STRBW], s_axi_wstrb[STRBW-1:0]};
  // Offset destination address to the first active strobe byte
  assign uhost_req_dstaddr[AW-1:0] = dst_addr[AW-1:0] + right_most_strb_bit_index[STRB_LOG2:0];

  /* Right-shift data to align the first active strobe byte to bit 0
   * uhost_req_data = s_axis_wdata >> (right_most_strb_bit_index * 8) */
  assign uhost_req_data[DW-1:0] = s_axi_wdata[DW-1:0] >> {right_most_strb_bit_index[STRB_LOG2:0], 3'b000};

  assign uhost_resp_ready = (state == WAIT_UMI_RESP);

  // Extract error code from UMI response command
  assign umi_resp_cmd_err[1:0] = uhost_resp_cmd[UMI_USER_MSB:UMI_USER_LSB];
  assign umi_resp_cmd_opcode[4:0] = uhost_resp_cmd[UMI_OPCODE_MSB:UMI_OPCODE_LSB];

  // Latch error across burst - clear on new transaction
  always @(posedge clk)
    if (aw_fire)
      // Clear error on new transaction
      bresp_err[1:0] <= 2'b00;
    else if (umi_resp_fire)
      if (umi_resp_cmd_opcode != UMI_RESP_WRITE)
        // The response should only be UMI_RESP_WRITE, else slave error
        bresp_err[1:0] <= 2'b10;
      else if (umi_resp_cmd_err != 2'b00)
        // Capture error
        bresp_err[1:0] <= umi_resp_cmd_err;

  //####################################
  // FSM logic
  //####################################

  assign s_axi_awready = (state == IDLE);
  assign s_axi_bvalid = (state == SEND_B_RESP);

  always @(*)
    case (state)
      /* IDLE: Wait for AXI write address valid. Capture AW channel fields
       *(address, burst type, ID, prot, qos) on aw_fire, then move to UMI_WRITE. */
      IDLE:
        next_state = s_axi_awvalid ? UMI_WRITE : IDLE;

      // UMI_WRITE: Forward AXI write data beat as UMI REQ_WRITE then wait for response.
      UMI_WRITE:
        if (no_axi_beats_left)
          next_state = SEND_B_RESP;
        else
          next_state = umi_req_fire ? WAIT_UMI_RESP : UMI_WRITE;

      // WAIT_UMI_RESP: Wait for UMI RESP_WRITE.
      WAIT_UMI_RESP:
        next_state = umi_resp_fire ? UMI_WRITE : WAIT_UMI_RESP;

      /* SEND_B_RESP: Assert bvalid with accumulated error status. Wait for
       * bready handshake, then return to IDLE for next transaction. */
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

  assign s_axi_bresp[1:0] = bresp_err[1:0];
  assign s_axi_bid[IDW-1:0] = aw_id[IDW-1:0];

endmodule
