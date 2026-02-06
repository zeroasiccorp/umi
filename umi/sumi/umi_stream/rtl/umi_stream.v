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
 ******************************************************************************
 *
 * This module converts between UMI memory mapped transactions and streaming
 * transactions dynamically via the devicemode signal
 *
 * When configured as a device, posted writes go through a fifo unmodified
 * from the umi domain to the streaming domain. Write requests have acks
 * sent back immediately, ie the write to the fifo indicates completion.
 * Read requests pull data from the fifo whenever not empty.
 *
 * When configure as a non-device full duplex channel, only posted writes
 * are allowed.
 *
 ******************************************************************************/

module umi_stream
  #(parameter AW = 64,        // UMI data width
    parameter CW = 32,        // UMI command width
    parameter DW = 256,       // UMI data width
    parameter S2MM_DEPTH = 4, // S2MM FIFO depth
    parameter MM2S_DEPTH = 4  // MM2S FIFO depth
    )
   (// operating mode
    input           devicemode, // 1 = device endpoint, 0=full duplex link
    // S2MM addresses (from external controller)
    input [AW-1:0]  s2mm_dstaddr,
    input [AW-1:0]  s2mm_srcaddr,
    input [CW-1:0]  s2mm_cmd,
    // UMI memory mapped interface
    input           umi_nreset,
    input           umi_clk,
    input           umi_in_valid,
    input [CW-1:0]  umi_in_cmd,
    input [AW-1:0]  umi_in_dstaddr,
    input [AW-1:0]  umi_in_srcaddr,
    input [DW-1:0]  umi_in_data,
    output          umi_in_ready,
    output          umi_out_valid,
    output [CW-1:0] umi_out_cmd,
    output [AW-1:0] umi_out_dstaddr,
    output [AW-1:0] umi_out_srcaddr,
    output [DW-1:0] umi_out_data,
    input           umi_out_ready,
    // USI streaming interface
    input           usi_clk,
    input           usi_nreset,
    output          usi_out_valid,
    output          usi_out_last,
    output [DW-1:0] usi_out_data,
    input           usi_out_ready,
    input           usi_in_valid,
    input           usi_in_last,
    input [DW-1:0]  usi_in_data,
    output          usi_in_ready
    );

`include "umi_messages.vh"

   // Power supplies
   supply0 vss;
   supply1 vdd;

   // M2SS signals
   wire                mm2s_fifo_full;
   wire                mm2s_fifo_almost_full;
   wire                mm2s_fifo_empty;
   wire                mm2s_fifo_write;
   wire                mm2s_fifo_read;
   wire [DW:0]         mm2s_fifo_din;
   wire [DW:0]         mm2s_fifo_dout;

   // S2MM signals
   wire                s2mm_fifo_full;
   wire                s2mm_fifo_almost_full;
   wire                s2mm_fifo_empty;
   wire                s2mm_fifo_write;
   wire                s2mm_fifo_read;
   wire [DW:0]         s2mm_fifo_din;
   wire [DW:0]         s2mm_fifo_dout;

   // Command decode signals (direct decode from umi_in_cmd)
   wire                cmd_read;
   wire                cmd_write;
   wire                cmd_write_posted;

   // Transaction control signals
   wire                umi_resp;
   wire                request_stall;
   wire                resp_vld_out;

   // Response packet signals
   wire [CW-1:0]       resp_cmd;

   // Response pipeline registers (following umi_endpoint pattern)
   reg                 resp_vld_r;
   reg                 resp_vld_keep;
   reg [CW-1:0]        resp_cmd_r;
   reg [AW-1:0]        resp_dstaddr_r;
   reg [AW-1:0]        resp_srcaddr_r;
   reg [DW-1:0]        resp_data_r;
   reg [DW-1:0]        resp_data_keep;
   wire [DW-1:0]       resp_data_out;

   //###################################################
   // UMI Command Decode (direct decode using umi_messages.vh)
   //###################################################

   assign cmd_read         = (umi_in_cmd[4:0] == UMI_REQ_READ);
   assign cmd_write        = (umi_in_cmd[4:0] == UMI_REQ_WRITE);
   assign cmd_write_posted = (umi_in_cmd[4:0] == UMI_REQ_POSTED);

   //###################################################
   // UMI Transaction Decode
   //###################################################

   // Stall when there's a pending response and consumer not ready
   assign resp_vld_out = resp_vld_r | resp_vld_keep;
   assign request_stall = resp_vld_out & ~umi_out_ready;

   // Ready to accept new UMI transactions (device mode only for response-generating ops)
   // Posted writes: only needs FIFO not full (works in both modes)
   // Write with ack: need FIFO not full AND no stall (device mode only)
   // Read: need s2mm not empty AND no stall (device mode only)
   assign umi_in_ready = (cmd_write_posted & ~mm2s_fifo_full) |
                         (cmd_write & devicemode & ~mm2s_fifo_full & ~request_stall) |
                         (cmd_read & devicemode & ~s2mm_fifo_empty & ~request_stall);

   // Transaction accepted that generates a response (device mode only)
   // Write with ack (cmd_write) generates response, posted write does NOT
   // Read generates response
   assign umi_resp = umi_in_valid & umi_in_ready & devicemode &
                     (cmd_write | cmd_read);

   //###################################################
   // MM2S FIFO Write Control
   //###################################################

   // Write to mm2s fifo on any write transaction (posted or with ack)
   assign mm2s_fifo_write = umi_in_valid & umi_in_ready &
                            (cmd_write | cmd_write_posted);

   assign mm2s_fifo_din[DW-1:0] = umi_in_data[DW-1:0];

   assign mm2s_fifo_din[DW] = umi_in_cmd[UMI_EOM_BIT];

   //###################################################
   // S2MM FIFO Read Control (for read responses)
   //###################################################

   // In device mode: read when servicing a read request
   // In non-device mode, auto drain when umi_out is ready
   assign s2mm_fifo_read = devicemode ? (umi_in_valid & umi_in_ready & cmd_read):
                                        (~s2mm_fifo_empty & umi_out_ready);

   //###################################################
   // Response Generation
   //###################################################

   assign resp_cmd[4:0]   = cmd_read ? UMI_RESP_READ : UMI_RESP_WRITE;
   assign resp_cmd[31:5]  = umi_in_cmd[31:5];

   // Response valid register
   always @(posedge umi_clk or negedge umi_nreset)
     if (!umi_nreset)
       resp_vld_r <= 1'b0;
     else
       resp_vld_r <= umi_resp;

   // Response (capture when response is generated)
   always @(posedge umi_clk or negedge umi_nreset)
     if (!umi_nreset)
       begin
          resp_cmd_r[CW-1:0]     <= {CW{1'b0}};
          resp_dstaddr_r[AW-1:0] <= {AW{1'b0}};
          resp_srcaddr_r[AW-1:0] <= {AW{1'b0}};
       end
     else if (umi_resp)
       begin
          resp_cmd_r[CW-1:0]     <= resp_cmd[CW-1:0];
          resp_dstaddr_r[AW-1:0] <= umi_in_srcaddr[AW-1:0];
          resp_srcaddr_r[AW-1:0] <= {AW{1'b0}};
       end

   // Data storage in case ready is low
   always @(posedge umi_clk or negedge umi_nreset)
     if (!umi_nreset)
       resp_data_keep[DW-1:0] <= {DW{1'b0}};
     else if (resp_vld_r)
       resp_data_keep[DW-1:0] <= resp_data_r[DW-1:0];

   // Response data register (for reads, capture from s2mm fifo)
   always @(posedge umi_clk or negedge umi_nreset)
     if (!umi_nreset)
       resp_data_r[DW-1:0] <= {DW{1'b0}};
     else if (umi_resp)
       resp_data_r[DW-1:0] <= cmd_read ? s2mm_fifo_dout[DW-1:0] :
                                         {DW{1'b0}};

   // Valid keep - holds response when consumer not ready
   always @(posedge umi_clk or negedge umi_nreset)
     if (!umi_nreset)
       resp_vld_keep <= 1'b0;
     else if (resp_vld_r & ~umi_out_ready)
       resp_vld_keep <= 1'b1;
     else if (umi_out_ready)
       resp_vld_keep <= 1'b0;

   // Output data mux
   assign resp_data_out[DW-1:0] = resp_vld_r ? resp_data_r[DW-1:0] :
                                               resp_data_keep[DW-1:0];

   //###################################################
   // UMI Output Mux
   //###################################################

   assign umi_out_valid   = devicemode ? resp_vld_out   : ~s2mm_fifo_empty;
   assign umi_out_cmd     = devicemode ? resp_cmd_r     : s2mm_cmd;
   assign umi_out_dstaddr = devicemode ? resp_dstaddr_r : s2mm_dstaddr;
   assign umi_out_srcaddr = devicemode ? resp_srcaddr_r : s2mm_srcaddr;
   assign umi_out_data    = devicemode ? resp_data_out  : s2mm_fifo_dout[DW-1:0];

   //###################################################
   // Memory Mapped to Stream (MM2S)
   //###################################################

   assign mm2s_fifo_read = ~mm2s_fifo_empty & usi_out_ready;
   assign usi_out_valid  = ~mm2s_fifo_empty;
   assign usi_out_data   = mm2s_fifo_dout[DW-1:0];
   assign usi_out_last   = mm2s_fifo_dout[DW];

   la_asyncfifo #(.DW(DW+1),
                  .DEPTH(MM2S_DEPTH))
   ififo_mm2s (// write side
               .wr_clk         (umi_clk),
               .wr_nreset      (umi_nreset),
               .wr_full        (mm2s_fifo_full),
               .wr_almost_full (mm2s_fifo_almost_full),
               .wr_din         (mm2s_fifo_din[DW:0]),
               .wr_en          (mm2s_fifo_write),
               .wr_chaosmode   (1'b0),
               // read side
               .rd_clk         (usi_clk),
               .rd_nreset      (usi_nreset),
               .rd_dout        (mm2s_fifo_dout[DW:0]),
               .rd_empty       (mm2s_fifo_empty),
               .rd_en          (mm2s_fifo_read),
               // misc
               .vss            (vss),
               .vdd            (vdd),
               .ctrl           (1'b0),
               .test           (1'b0));

   //######################################################
   // Stream to Memory Mapped (S2MM)
   //######################################################

   assign s2mm_fifo_write       = usi_in_valid & ~s2mm_fifo_full;
   assign s2mm_fifo_din[DW-1:0] = usi_in_data[DW-1:0];
   assign s2mm_fifo_din[DW]     = usi_in_last;
   assign usi_in_ready          = ~s2mm_fifo_full;

   la_asyncfifo #(.DW(DW+1),
                  .DEPTH(S2MM_DEPTH))
   ififo_s2mm  (// write side (stream domain)
                .wr_clk         (usi_clk),
                .wr_nreset      (usi_nreset),
                .wr_full        (s2mm_fifo_full),
                .wr_almost_full (s2mm_fifo_almost_full),
                .wr_din         (s2mm_fifo_din[DW:0]),
                .wr_en          (s2mm_fifo_write),
                .wr_chaosmode   (1'b0),
                // read side (umi domain)
                .rd_clk         (umi_clk),
                .rd_nreset      (umi_nreset),
                .rd_dout        (s2mm_fifo_dout[DW:0]),
                .rd_empty       (s2mm_fifo_empty),
                .rd_en          (s2mm_fifo_read),
                // misc
                .vss            (vss),
                .vdd            (vdd),
                .ctrl           (1'b0),
                .test           (1'b0));

endmodule
