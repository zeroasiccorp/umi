/*******************************************************************************
 * Copyright 2024 Zero ASIC Corporation
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
 * NOTE: This module works on the apb_pclk clock domain. To connect
 * the module with a different clock domain, use the umi_fifo module.
 *
 * The module translates a SUMI request into a APB requester interface.
 * Read data is returned as SUMI response packets. Requests can occur
 * at a maximum rate of one transaction every two cycles!
 *
 * This module can also check if the incoming access is within the designated
 * address range by setting the GRPOFFSET, GRPAW, and GRPID parameter.
 * The address range [GRPOFFSET+:GRPAW] is checked against GRPID for a match.
 * To disable the check, set the GRPAW to 0.
 *
 * Supported: single-word (LEN = 0) reads, writes and posted writes of
 * 2^SIZE <= RW/8 bytes at an address aligned to 2^SIZE. UMI data is LSB
 * aligned; on APB the bytes sit in their address lanes:
 *
 *   - apb_paddr is the request address aligned down to RW/8 bytes, the
 *     byte offset in the word is carried by the lanes
 *   - write: apb_pwdata = data << (8 * offset), apb_pstrb sets the
 *     2^SIZE strobes at the offset (a slave must honor apb_pstrb)
 *   - read: apb_pstrb is 0 (APB4), the response data is the addressed
 *     bytes of apb_prdata shifted down to bit 0, the bytes above 2^SIZE
 *     zero
 *
 * Anything else gets an error response without an APB transfer (UMI
 * spec 3.4): a read, write or atomic with SIZE > RW/8, a misaligned
 * address, LEN > 0, or an atomic returns DEVERR (an atomic returns
 * RESP_RD, as any atomic does), with no data; one outside the group
 * (GRPAW > 0) returns NETERR. A posted write, RDMA or other request that
 * cannot be executed is dropped silently, as the spec allows (no
 * response). apb_pslverr returns DEVERR.
 *
 ******************************************************************************/

module umi2apb #(parameter AW = 64,        // UMI address width
                 parameter CW = 32,        // UMI cmd width
                 parameter DW = 256,       // UMI data width
                 parameter RW = 64,        // APB register width
                 parameter RAW = 64,       // APB address width
                 parameter GRPOFFSET = 24, // group address offset
                 parameter GRPAW = 0,      // group address width
                 parameter GRPID = 0       // group ID
                 )
   (// module operates on apb clk domain
    input             apb_nreset,  // apb asycn nreset
    input             apb_pclk,    // apb clock
    // UMI interface
    input             udev_req_valid,
    input [CW-1:0]    udev_req_cmd,
    input [AW-1:0]    udev_req_dstaddr,
    input [AW-1:0]    udev_req_srcaddr,
    input [DW-1:0]    udev_req_data,
    output            udev_req_ready,
    output reg        udev_resp_valid,
    output [CW-1:0]   udev_resp_cmd,
    output [AW-1:0]   udev_resp_dstaddr,
    output [AW-1:0]   udev_resp_srcaddr,
    output [DW-1:0]   udev_resp_data,
    input             udev_resp_ready,
    // APB interface
    output reg        apb_penable, // enable
    output            apb_pwrite,  // 0=read, 1=write
    output [RAW-1:0]  apb_paddr,   // register address
    output [RW-1:0]   apb_pwdata,  // write data
    output [RW/8-1:0] apb_pstrb,   // strobe
    output [2:0]      apb_pprot,   // protection type
    output            apb_psel,    // select
    input             apb_pready,  // ready
    input [RW-1:0]    apb_prdata,  // read data
    input             apb_pslverr  // error
    );

`include "umi_messages.vh"

   // log2 of the bytes per APB word (the byte offset width)
   localparam OFFW = $clog2(RW/8);

  //####################################
  // Registers
  //####################################
  reg [CW-1:0]    udev_req_cmd_r;
  reg [AW-1:0]    udev_req_dstaddr_r;
  reg [AW-1:0]    udev_req_srcaddr_r;
  reg [RW-1:0]    udev_req_data_r;

  reg [1:0]       err_r;
  reg [RW-1:0]    rdata_r;

  //####################################
  // Wires
  //####################################
  wire            accept;
  wire            group_match;

  wire [CW-1:0]   cmd_packet;
  wire [AW-1:0]   addr_packet;
  wire [RW-1:0]   data_packet;
  wire [4:0]      cmd_opcode;
  wire [2:0]      cmd_size;
  wire [7:0]      cmd_len;
  wire            cmd_read;
  wire            cmd_write;
  wire            cmd_posted;
  wire            cmd_atomic;
  wire [1:0]      cmd_prot;
  wire [OFFW:0]   offset;
  wire [OFFW:0]   size_mask;
  wire            size_ok;
  wire            aligned;
  wire            executable;
  wire            needs_resp;
  wire            apb_start;
  wire            err_start;
  wire [RW/8-1:0] byte_mask;

  wire            apb_bus_fire;
  wire            capture_resp;
  wire            op_read_resp;
  wire [OFFW:0]   resp_offset;
  wire [2:0]      resp_size;
  wire [RW-1:0]   rdata_shift;
  wire [RW-1:0]   rdata_mask;

  //############################
  //# UMI Request
  //############################

  generate
    if (GRPAW != 0)
      assign group_match = (addr_packet[GRPOFFSET+:GRPAW]==GRPID[GRPAW-1:0]);
    else
      assign group_match = 1'b1;
  endgenerate

  // every request offered while idle is taken (executed, answered with an
  // error, or dropped), so none is ever left without a response it needs
  assign accept = udev_req_valid & udev_req_ready;

  // latch the
  always @(posedge apb_pclk)
     if (accept) begin
      udev_req_cmd_r     <= udev_req_cmd;
      udev_req_dstaddr_r <= udev_req_dstaddr;
      udev_req_srcaddr_r <= udev_req_srcaddr;
      udev_req_data_r    <= udev_req_data[RW-1:0];
    end

  // the request: the incoming one in its accept cycle (the APB setup
  // phase), the registered one after
  assign cmd_packet  = accept ? udev_req_cmd : udev_req_cmd_r;
  assign addr_packet = accept ? udev_req_dstaddr : udev_req_dstaddr_r;
  assign data_packet = accept ? udev_req_data[RW-1:0] : udev_req_data_r[RW-1:0];

  assign cmd_opcode = cmd_packet[UMI_OPCODE_MSB:UMI_OPCODE_LSB];
  assign cmd_size   = cmd_packet[UMI_SIZE_MSB:UMI_SIZE_LSB];
  assign cmd_len    = cmd_packet[UMI_LEN_MSB:UMI_LEN_LSB];
  assign cmd_prot   = cmd_packet[UMI_PROT_MSB:UMI_PROT_LSB];

  assign cmd_read   = cmd_opcode==UMI_REQ_READ;
  assign cmd_write  = cmd_opcode==UMI_REQ_WRITE;
  assign cmd_posted = cmd_opcode==UMI_REQ_POSTED;
  assign cmd_atomic = cmd_opcode==UMI_REQ_ATOMIC;

  // byte offset of the access in the APB word
  assign offset[OFFW:0] = {1'b0, addr_packet[OFFW-1:0]};

  // 2^SIZE - 1: the offset bits an aligned access leaves 0
  assign size_mask[OFFW:0] = ~({(OFFW+1){1'b1}} << cmd_size);

  assign size_ok    = ({29'b0, cmd_size} <= OFFW);
  assign aligned    = ~|(offset & size_mask);

  // a single-word read or write of at most RW bits, aligned, in the group
  assign executable = (cmd_read | cmd_write | cmd_posted) & size_ok &
                      aligned & (cmd_len == 8'b0) & group_match;

  // a request that cannot be executed still gets its response (posted
  // writes, RDMA and other requests have none)
  assign needs_resp = cmd_read | cmd_write | cmd_atomic;

  assign apb_start  = accept & executable;
  assign err_start  = accept & ~executable & needs_resp;

  //############################
  //# APB Mapping
  //############################

  // the 2^SIZE byte lanes at the offset
  assign byte_mask[RW/8-1:0] = ~({(RW/8){1'b1}} << (1 << cmd_size)) << offset;

  assign apb_psel    = apb_start | apb_penable;
  assign apb_pwrite  = cmd_write | cmd_posted;
  assign apb_pprot   = {1'b0, cmd_prot[1:0]};
  assign apb_pstrb   = apb_pwrite ? byte_mask[RW/8-1:0] : {(RW/8){1'b0}};

  assign apb_paddr   = {addr_packet[RAW-1:OFFW], {OFFW{1'b0}}};
  assign apb_pwdata  = data_packet[RW-1:0] << {offset, 3'b000};

  always @(posedge apb_pclk or negedge apb_nreset)
    if (~apb_nreset)
      apb_penable <= 1'b0;
    else if (apb_start)
      apb_penable <= 1'b1;
    else if (apb_pready)
      apb_penable <= 1'b0;

  assign udev_req_ready = ~apb_penable & ~udev_resp_valid;

  //############################
  //# UMI Response
  //############################

  assign apb_bus_fire = apb_psel & apb_penable & apb_pready;
  assign capture_resp = apb_bus_fire & ~cmd_posted;

  always @(posedge apb_pclk or negedge apb_nreset)
    if (~apb_nreset)
      udev_resp_valid <= 1'b0;
    else if (capture_resp | err_start)
      udev_resp_valid <= 1'b1;
    else if (udev_resp_ready)
      udev_resp_valid <= 1'b0;

  // the addressed bytes of the read word, shifted down to bit 0, the bytes
  // above 2^SIZE zero
  assign resp_offset[OFFW:0] = {1'b0, udev_req_dstaddr_r[OFFW-1:0]};
  assign resp_size[2:0]      = udev_req_cmd_r[UMI_SIZE_MSB:UMI_SIZE_LSB];
  assign rdata_shift[RW-1:0] = apb_prdata[RW-1:0] >> {resp_offset, 3'b000};
  assign rdata_mask[RW-1:0]  = ~({RW{1'b1}} << (8 << resp_size));

  // ERR: DEVERR on apb_pslverr; an error response has no data: DEVERR,
  // or NETERR outside the group
  always @(posedge apb_pclk)
    if (capture_resp) begin
      rdata_r <= rdata_shift[RW-1:0] & rdata_mask[RW-1:0];
      err_r   <= {apb_pslverr, 1'b0};
    end
    else if (err_start) begin
      rdata_r <= {RW{1'b0}};
      err_r   <= group_match ? 2'b10 : 2'b11;
    end

  // an atomic is answered with RESP_RD, as an executed atomic is
  assign op_read_resp = (udev_req_cmd_r[UMI_OPCODE_MSB:UMI_OPCODE_LSB] == UMI_REQ_READ) |
                        (udev_req_cmd_r[UMI_OPCODE_MSB:UMI_OPCODE_LSB] == UMI_REQ_ATOMIC);

  assign udev_resp_cmd[UMI_OPCODE_MSB:UMI_OPCODE_LSB] = op_read_resp ? UMI_RESP_READ : UMI_RESP_WRITE;
  assign udev_resp_cmd[UMI_EX_BIT:UMI_SIZE_LSB]       = udev_req_cmd_r[UMI_EX_BIT:UMI_SIZE_LSB];
  assign udev_resp_cmd[UMI_USER_MSB:UMI_USER_LSB]     = err_r[1:0];
  assign udev_resp_cmd[UMI_HOSTID_MSB:UMI_HOSTID_LSB] = udev_req_cmd_r[UMI_HOSTID_MSB:UMI_HOSTID_LSB];

  assign udev_resp_dstaddr[AW-1:0] = udev_req_srcaddr_r[AW-1:0];
  assign udev_resp_srcaddr[AW-1:0] = udev_req_dstaddr_r[AW-1:0];
  assign udev_resp_data[DW-1:0]    = {{(DW-RW){1'b0}}, rdata_r[RW-1:0]};

endmodule
