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
 ******************************************************************************/

// TODO: remove this timescale
`timescale 1ns/1ps

module axi4_full_rd2umi #(
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
  // AXI4 FULL Read Channels
  //####################################

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

  `include "umi_messages.vh"

  //####################################
  // Registers
  //####################################
  reg [IDW-1:0] ar_id;

  //####################################
  // Wires
  //####################################
  wire ar_fire;

  //####################################
  // Helper signals
  //####################################
  assign ar_fire = s_axi_arvalid & s_axi_arready;

  always @(posedge clk)
    ar_id <= (ar_fire) ? s_axi_arid : ar_id;

  //####################################
  // Data path
  //####################################

  assign uhost_req_valid = s_axi_arvalid;
  assign s_axi_arready = uhost_req_ready;

  umi_pack #(
    .CW(CW)
  ) u_umi_pack (
    // Command inputs
    .cmd_opcode         (UMI_REQ_READ),
    .cmd_size           (s_axi_arsize),
    .cmd_len            (s_axi_arlen),
    .cmd_atype          (8'h00),
    .cmd_prot           (s_axi_arprot),
    .cmd_qos            (s_axi_arqos),
    .cmd_eom            (1'b1),
    .cmd_eof            (1'b0),
    .cmd_user           (2'b00),
    .cmd_err            (2'b00),
    .cmd_ex             (1'b0),
    .cmd_hostid         (5'b00000),
    .cmd_user_extended  (24'h00_0000),
    // Output packet
    .packet_cmd         (uhost_req_cmd)
  );

  assign uhost_req_dstaddr = s_axi_araddr;
  assign uhost_req_srcaddr = HOSTADDR;
  assign uhost_req_data = {DW{1'b0}};

  // Connect UMI Response to AXI4 Read Data Channel
  assign s_axi_rvalid         = uhost_resp_valid;
  assign uhost_resp_ready     = s_axi_rready;

  assign s_axi_rid[IDW-1:0]   = ar_id[IDW-1:0];
  assign s_axi_rdata[DW-1:0]  = uhost_resp_data[DW-1:0];
  assign s_axi_rresp[1:0]     = uhost_resp_cmd[UMI_USER_MSB:UMI_USER_LSB];
  assign s_axi_rlast          = uhost_resp_cmd[UMI_EOM_BIT];

endmodule
