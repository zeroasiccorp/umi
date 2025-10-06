/*******************************************************************************
 * Copyright 2020 Zero ASIC Corporation
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
 * ##Documentation##
 *
 * - Asynchronous UMI FIFO
 * - Separate read and write clocks
 *
 ******************************************************************************/

module umi_fifo
  #(parameter TARGET      = "DEFAULT", // implementation target
    parameter DEPTH       = 4,         // FIFO depth
    parameter ALMOSTFULL  = 0,         // Almost full threshold
    parameter AW          = 64,        // UMI width
    parameter CW          = 32,        // UMI width
    parameter DW          = 256        // UMI width
    )
   (// control/status signals
    input           bypass, // bypass FIFO
    input           chaosmode, // enable "random" fifo pushback
    output          fifo_full,
    output          fifo_almost_full,
    output          fifo_empty,
    // Input
    input           umi_in_clk,
    input           umi_in_nreset,
    input           umi_in_valid,//per byte valid signal
    input [CW-1:0]  umi_in_cmd,
    input [AW-1:0]  umi_in_dstaddr,
    input [AW-1:0]  umi_in_srcaddr,
    input [DW-1:0]  umi_in_data,
    output          umi_in_ready,
    // Output
    input           umi_out_clk,
    input           umi_out_nreset,
    output          umi_out_valid,
    output [CW-1:0] umi_out_cmd,
    output [AW-1:0] umi_out_dstaddr,
    output [AW-1:0] umi_out_srcaddr,
    output [DW-1:0] umi_out_data,
    input           umi_out_ready,
    // Supplies
    input           vdd,
    input           vss
    );

   // local state
   reg              fifo_out_valid;
   reg [DW-1:0]     fifo_out_data;

   // local wires
   wire             umi_out_beat;
   wire             fifo_read;
   wire             fifo_write;
   wire [DW+AW+AW+CW-1:0] fifo_dout;
   wire             fifo_in_ready;

   //#################################
   // UMI Control Logic
   //#################################

   // Read FIFO when ready (blocked inside fifo when empty)
   assign fifo_read = ~fifo_empty & umi_out_ready;

   // Write fifo when high (blocked inside fifo when full)
   assign fifo_write = ~fifo_full & umi_in_valid;

   // FIFO pushback
   assign fifo_in_ready = ~fifo_full;

   //#################################
   // Standard Dual Clock FIFO
   //#################################

   la_asyncfifo  #(.DW(CW+AW+AW+DW),
                   .DEPTH(DEPTH),
                   .ALMOSTFULL(ALMOSTFULL))
   fifo  (// Outputs
          .wr_full        (fifo_full),
          .wr_almost_full (fifo_almost_full),
          .rd_dout        (fifo_dout[DW+AW+AW+CW-1:0]),
          .rd_empty       (fifo_empty),
          // Inputs
          .wr_clk         (umi_in_clk),
          .wr_nreset      (umi_in_nreset),
          .wr_din         ({umi_in_data[DW-1:0],umi_in_srcaddr[AW-1:0],umi_in_dstaddr[AW-1:0],umi_in_cmd[CW-1:0]}),
          .wr_en          (umi_in_valid),
          .wr_chaosmode   (chaosmode),
          .rd_clk         (umi_out_clk),
          .rd_nreset      (umi_out_nreset),
          .rd_en          (fifo_read),
          .vss            (vss),
          .vdd            (vdd),
          .ctrl           (1'b0),
          .test           (1'b0));

   //#################################
   // FIFO Bypass
   //#################################

   assign umi_out_cmd[CW-1:0]     = bypass ? umi_in_cmd[CW-1:0]     : fifo_dout[CW-1:0];
   assign umi_out_dstaddr[AW-1:0] = bypass ? umi_in_dstaddr[AW-1:0] : fifo_dout[CW+:AW];
   assign umi_out_srcaddr[AW-1:0] = bypass ? umi_in_srcaddr[AW-1:0] : fifo_dout[CW+AW+:AW];
   assign umi_out_data[DW-1:0]    = bypass ? umi_in_data[DW-1:0]    : fifo_dout[CW+AW+AW+:DW];
   assign umi_out_valid           = bypass ? umi_in_valid           : ~fifo_empty;
   assign umi_in_ready            = bypass ? umi_out_ready          : fifo_in_ready;

   // debug signals
   assign umi_out_beat = umi_out_valid & umi_out_ready;

endmodule // clink_fifo
// Local Variables:
// verilog-library-directories:(".")
// End:
