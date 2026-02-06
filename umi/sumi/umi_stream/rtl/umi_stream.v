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
 * transactions. The module can be configured as a host or device during
 * elaboration by setting the HOST parameter.
 *
 * When configured as a device, posted writes go through a fifo unmodified
 * from the umi domain to the streaming domain. Write requests have acks
 * sent back immediately, ie the write to the fifo indicates completion.
 * Read requests pull data from the fifo whenever not empty. An apb
 * accessible register keeps track of the fifo empty status allowing for
 * polling the register before attempting a read.
 *
 * When configure as a device, reads are done from the s2mm fifo.
 * When configure as a non-device full duplex channel, reads are illegal.
 *
 ******************************************************************************/

module umi_stream
  #(parameter AW = 64,  // UMI data width
    parameter CW = 32,  // UMI command width
    parameter DW = 256, // UMI data width
    parameter RW = 32,  // APB register width
    parameter RAW = 32, // APB address width
    parameter DEPTH = 4 // FIFO depth
    )
   (// operating mode
    input           devicemode, // 1 = device endpoint, 0=full duplex link
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
    // S2MM control interface
    input [AW-1:0]  s2mm_dstaddr,
    input [AW-1:0]  s2mm_srcaddr,
    input [CW-1:0]  s2mm_cmd,
    // USI streaming interface
    input           usi_clk,
    input           usi_nreset,
    output          usi_out_valid,
    output          usi_out_last,
    output [DW-1:0] usi_out_data,
    input           usi_out_ready,
    input           usi_in_valid,
    input           usi_in_last,
    output [DW-1:0] usi_in_data,
    output          usi_in_ready
    );

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

   // synced apb interface
   wire [7:0]          sys_addr;
   wire [3:0]          sys_word_addr;
   wire                sys_read;
   wire                sys_write;
   wire [RW-1:0]       sys_wdata;
   reg [RW-1:0]        sys_rdata;

   //###################################################
   // Memory Mapped to Stream (MM2S)
   //###################################################

   assign mm2s_fifo_read = ~mm2s_fifo_empty & usi_out_ready;


   assign usi_out_valid = ~mm2s_fifo_empty;
   assign usi_out_data  = mm2s_fifo_dout[DW-1:0];
   assign usi_out_last  = mm2s_fifo_dout[DW];

   la_asyncfifo #(.DW(DW+1),
                  .DEPTH(DEPTH))
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

   assign umi_out_valid = ~s2mm_fifo_empty;
   assign umi_out_data  = s2mm_fifo_dout[DW-1:0];
   assign umi_out_last  = s2mm_fifo_dout[DW];

   la_asyncfifo #(.DW(DW+1),
                  .DEPTH(DEPTH))
   ififo_s2mm  (// write side
                .wr_clk         (umi_clk),
                .wr_nreset      (umi_nreset),
                .wr_full        (s2mm_fifo_full),
                .wr_almost_full (s2mm_fifo_almost_full),
                .wr_din         (s2mm_fifo_din[DW:0]),
                .wr_en          (s2mm_fifo_write),
                .wr_chaosmode   (1'b0),
                // read side
                .rd_clk         (usi_clk),
                .rd_nreset      (usi_nreset),
                .rd_dout        (s2mm_fifo_dout[DW:0]),
                .rd_empty       (s2mm_fifo_empty),
                .rd_en          (s2mm_fifo_read),
                // misc
                .vss            (vss),
                .vdd            (vdd),
                .ctrl           (1'b0),
                .test           (1'b0));


endmodule
