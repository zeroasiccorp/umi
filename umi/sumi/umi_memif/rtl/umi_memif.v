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
 ******************************************************************************/

module umi_memif
  #(parameter DW = 256, // umi packet width
    parameter AW = 64,  // umi address width
    parameter MAW = 32  // ram address width
    )
   (// ctrls
    input            clk,
    input            nreset,
    // umi interface
    input            umi_read,   // memory read
    input            umi_write,  // memory write
    input            umi_atomic, // read-modify-write
    input [2:0]      umi_size,   // 1 --> DW/8 byte
    input [7:0]      umi_len,    // total transfers = LEN + 1
    input [7:0]      umi_atype,  // atomic type
    input [AW-1:0]   umi_addr,   // size aligned address
    input [DW-1:0]   umi_wrdata,
    output [DW-1:0]  umi_rddata,
    output           umi_ready,
    // mem interface
    output           mem_ce,
    output           mem_we,
    output [MAW-1:0] mem_addr,
    output [DW-1:0]  mem_wrmask,
    output [DW-1:0]  mem_wrdata,
    input [DW-1:0]   mem_rddata
    );

   // local state
   reg  [AW-1:0]    umi_addr_r;
   reg              umi_write_r;
   reg              umi_read_r;
   reg              umi_atomic_r;
   reg [7:0]        umi_atype_r;
   reg [DW-1:0]     umi_wrdata_r;
   reg [DW-1:0]     wmask_r;
   reg [31:0]       postatomic_shift; // fixed 32b value

   // local wires
   reg [DW-1:0]     wmask;
   reg [DW-1:0]     umi_wrdata_atomic;
   wire [DW-1:0]    mem_rddata_atomic;
   wire [11:0]      umi_lenp1;
   wire [11:0]      umi_bytes;

   // vars
   integer          i;

   //##################################################
   // Read alignment
   //##################################################

   assign umi_rddata = mem_rddata >> (8*umi_addr_r[$clog2(DW/8)-1:0]);

   //##################################################
   // Write Mask
   //##################################################
   // TODO: Add support for partial writes - for now only 8B aligned addr
   // These are 12 bits wide - it works because the max data a SUMI
   // packet can transfer is 1024 bits/128 bytes.

   assign umi_lenp1[11:0] = {4'h0,umi_len[7:0]} + 1'b1;
   assign umi_bytes[11:0] = umi_lenp1[11:0] << umi_size[2:0];


   always @(*)
     for (i=0;i<DW/8;i=i+1) begin
        if ((i >= umi_addr[$clog2(DW/8)-1:0]) &
            (i < ({{32-$clog2(DW/8){1'b0}},umi_addr[$clog2(DW/8)-1:0]} + {20'h0,umi_bytes})))
          wmask[i*8+:8] = 8'hFF;
        else
          wmask[i*8+:8] = 8'h00;
     end

   //##########################################
   // Handling Atomics
   //##########################################

   // Deassert ready to get additional cycle to write data
   assign umi_ready = ~umi_atomic_r;

   always @(posedge clk or negedge nreset) begin
     if (~nreset) begin
       umi_addr_r       <= 'b0;
       umi_write_r      <= 'b0;
       umi_read_r       <= 'b0;
       umi_atomic_r     <= 'b0;
       umi_atype_r      <= 'b0;
       umi_wrdata_r     <= 'b0;
       wmask_r          <= 'b0;
       postatomic_shift <= 'b0;
     end
     else begin
       umi_addr_r       <= umi_addr;
       umi_write_r      <= umi_write;
       umi_read_r       <= umi_read;
       umi_atomic_r     <= umi_atomic;
       umi_atype_r      <= umi_atype;
       umi_wrdata_r     <= umi_wrdata<<(DW - ({20'h0,umi_bytes}<<3));
       wmask_r          <= wmask;
       postatomic_shift <= DW -(({{32-$clog2(DW/8){1'b0}},umi_addr[$clog2(DW/8)-1:0]} +
                                 {20'h0,umi_bytes})<<3);
     end
   end

   assign mem_rddata_atomic = (mem_rddata & wmask_r) << postatomic_shift;

   always @(*) begin
      case (umi_atype_r)
        8'h00: umi_wrdata_atomic = umi_wrdata_r + mem_rddata_atomic;
        8'h01: umi_wrdata_atomic = umi_wrdata_r & mem_rddata_atomic;
        8'h02: umi_wrdata_atomic = umi_wrdata_r | mem_rddata_atomic;
        8'h03: umi_wrdata_atomic = umi_wrdata_r ^ mem_rddata_atomic;
        8'h04: umi_wrdata_atomic = ($signed(umi_wrdata_r) > $signed(mem_rddata_atomic)) ?
                                   umi_wrdata_r : mem_rddata_atomic;
        8'h05: umi_wrdata_atomic = ($signed(umi_wrdata_r) > $signed(mem_rddata_atomic)) ?
                                   mem_rddata_atomic : umi_wrdata_r;
        8'h06: umi_wrdata_atomic = ($unsigned(umi_wrdata_r) > $unsigned(mem_rddata_atomic)) ?
                                   umi_wrdata_r : mem_rddata_atomic;
        8'h07: umi_wrdata_atomic = ($unsigned(umi_wrdata_r) > $unsigned(mem_rddata_atomic)) ?
                                   mem_rddata_atomic : umi_wrdata_r;
        8'h08: umi_wrdata_atomic = umi_wrdata_r;
        default: umi_wrdata_atomic = umi_wrdata_r;
      endcase
   end

   //##########################################
   // simple memory interface
   //##########################################

   assign mem_ce     = 1'b1; // TODO: this should work... umi_write | umi_read;

   assign mem_we     = umi_write | umi_atomic_r;

   assign mem_addr   = umi_atomic_r ? umi_addr_r : umi_addr;

   assign mem_wrmask = umi_atomic_r ? wmask_r : wmask;

   assign mem_wrdata = umi_atomic_r ?
                       (umi_wrdata_atomic[DW-1:0]>>postatomic_shift) :
                       (umi_wrdata[DW-1:0]<<(8*umi_addr[$clog2(DW/8)-1:0]));



endmodule
