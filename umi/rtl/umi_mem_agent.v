/******************************************************************************
 * Function:  UMI memory agent
 * Author:    Amir Volk
 * Copyright: (c) 2023 Zero ASIC. All rights reserved.
 *
 * License: This file contains confidential and proprietary information of
 * Zero ASIC. This file may only be used in accordance with the terms and
 * conditions of a signed license agreement with Zero ASIC. All other use,
 * reproduction, or distribution of this software is strictly prohibited.
 *
 * This block is implementing a simple memory array for use in simulation
 *
 * Limitation - transaction cannot cross the DW boundary (need to be split at the request side)
 *
 ****************************************************************************/

module umi_mem_agent
  #(parameter DW = 256,           // umi packet width
    parameter AW = 64,            // address width
    parameter CW = 32,            // command width
    parameter RAMDEPTH = 512,
    parameter CTRLW = 8,
    parameter SRAMTYPE = "DEFAULT"
    )
   (// global ebrick controls (from clink0/ebrick_regs/bus)
    input             clk,    // clock signals
    input             nreset, // async active low reset
    input [CTRLW-1:0] sram_ctrl, // Control signal for SRAM
    // Device port (per clink)
    input             udev_req_valid,
    input [CW-1:0]    udev_req_cmd,
    input [AW-1:0]    udev_req_dstaddr,
    input [AW-1:0]    udev_req_srcaddr,
    input [DW-1:0]    udev_req_data,
    output            udev_req_ready,
    output            udev_resp_valid,
    output [CW-1:0]   udev_resp_cmd,
    output [AW-1:0]   udev_resp_dstaddr,
    output [AW-1:0]   udev_resp_srcaddr,
    output [DW-1:0]   udev_resp_data,
    input             udev_resp_ready
    /*AUTOINPUT*/
    ///*AUTOOUTPUT*/
    );

   //##################################################################
   //# UMI FIFO FLEX (acting as a transaction splitter)
   //##################################################################

    wire            ff2ep_req_valid;
    wire [CW-1:0]   ff2ep_req_cmd;
    wire [AW-1:0]   ff2ep_req_dstaddr;
    wire [AW-1:0]   ff2ep_req_srcaddr;
    wire [DW-1:0]   ff2ep_req_data;
    wire            ff2ep_req_ready;

    umi_fifo_flex #(
        .ASYNC  (0),
        .SPLIT  (1),
        .DEPTH  (0),
        .CW     (CW),
        .AW     (AW),
        .IDW    (DW),
        .ODW    (DW))
    umi_fifo_flex_ (
        .bypass             (1'b1),
        .chaosmode          (1'b0),
        .fifo_full          (),
        .fifo_empty         (),

        .umi_in_clk         (clk),
        .umi_in_nreset      (nreset),
        .umi_in_valid       (udev_req_valid),
        .umi_in_cmd         (udev_req_cmd),
        .umi_in_dstaddr     (udev_req_dstaddr),
        .umi_in_srcaddr     (udev_req_srcaddr),
        .umi_in_data        (udev_req_data),
        .umi_in_ready       (udev_req_ready),

        .umi_out_clk        (clk),
        .umi_out_nreset     (nreset),
        .umi_out_valid      (ff2ep_req_valid),
        .umi_out_cmd        (ff2ep_req_cmd),
        .umi_out_dstaddr    (ff2ep_req_dstaddr),
        .umi_out_srcaddr    (ff2ep_req_srcaddr),
        .umi_out_data       (ff2ep_req_data),
        .umi_out_ready      (ff2ep_req_ready),

        .vdd                (),
        .vss                ()
    );

   /*AUTOREG*/

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [AW-1:0]        loc_addr;
   wire [7:0]           loc_len;
   wire [7:0]           loc_opcode;
   wire                 loc_read;
   wire [2:0]           loc_size;
   wire [DW-1:0]        loc_wrdata;
   wire                 loc_write;
   // End of automatics
   wire [11:0]          loc_lenp1;
   wire [11:0]          loc_bytes;

   wire                 loc_atomic;
   wire [7:0]           loc_atype;
   wire [DW-1:0]        loc_rddata;
   wire                 loc_ready;

   //##################################################################
   //# UMI ENDPOINT (Pipelined Request/Response)
   //##################################################################

   /*umi_endpoint AUTO_TEMPLATE (
    .udev_req_\(.*\)      (ff2ep_req_\1[]),
    );
    */

   umi_endpoint #(.CW(CW),
                  .AW(AW),
                  .DW(DW),
                  .REG(0))
   umi_endpoint(.loc_ready      (loc_ready),
                /*AUTOINST*/
                // Outputs
                .udev_req_ready (ff2ep_req_ready),
                .udev_resp_valid(udev_resp_valid),
                .udev_resp_cmd  (udev_resp_cmd[CW-1:0]),
                .udev_resp_dstaddr(udev_resp_dstaddr[AW-1:0]),
                .udev_resp_srcaddr(udev_resp_srcaddr[AW-1:0]),
                .udev_resp_data (udev_resp_data[DW-1:0]),
                .loc_addr       (loc_addr[AW-1:0]),
                .loc_write      (loc_write),
                .loc_read       (loc_read),
                .loc_atomic     (loc_atomic),
                .loc_opcode     (loc_opcode[7:0]),
                .loc_size       (loc_size[2:0]),
                .loc_len        (loc_len[7:0]),
                .loc_atype      (loc_atype[7:0]),
                .loc_wrdata     (loc_wrdata[DW-1:0]),
                // Inputs
                .nreset         (nreset),
                .clk            (clk),
                .udev_req_valid (ff2ep_req_valid),
                .udev_req_cmd   (ff2ep_req_cmd[CW-1:0]),
                .udev_req_dstaddr(ff2ep_req_dstaddr[AW-1:0]),
                .udev_req_srcaddr(ff2ep_req_srcaddr[AW-1:0]),
                .udev_req_data  (ff2ep_req_data[DW-1:0]),
                .udev_resp_ready(udev_resp_ready),
                .loc_rddata     (loc_rddata[DW-1:0]));

   // Add support for partial writes - for now only 8B aligned addr
   // These are 12 bits wide - it works because the max data a SUMI
   // packet can transfer is 1024 bits/128 bytes.
   assign loc_lenp1[11:0] = {4'h0,loc_len[7:0]} + 1'b1;
   assign loc_bytes[11:0] = loc_lenp1[11:0] << loc_size[2:0];

   reg [DW-1:0] wmask;
   integer i;

   always @(*)
     for (i=0;i<DW/8;i=i+1) begin
        if ((i >= loc_addr[$clog2(DW/8)-1:0]) &
            (i < ({{32-$clog2(DW/8){1'b0}},loc_addr[$clog2(DW/8)-1:0]} + {20'h0,loc_bytes})))
          wmask[i*8+:8] = 8'hFF;
        else
          wmask[i*8+:8] = 8'h00;
     end

   reg  [AW-1:0]    loc_addr_r;
   reg              loc_write_r;
   reg              loc_read_r;
   reg              loc_atomic_r;
   reg  [7:0]       loc_atype_r;
   reg  [DW-1:0]    loc_wrdata_r;
   reg  [DW-1:0]    wmask_r;

   reg  [DW-1:0]    loc_wrdata_atomic;


   wire [DW-1:0]    mem_rddata;
   wire             mem_we;
   wire [DW-1:0]    mem_wmask;
   wire [AW-1:0]    mem_addr;
   wire [DW-1:0]    mem_wrdata;

   wire [DW-1:0]    mem_rddata_atomic;
   reg  [31:0]      postatomic_shift;

   // Deassert ready to get additional cycle to write data
   assign loc_ready = ~loc_atomic_r;

   always @(posedge clk or negedge nreset) begin
     if (~nreset) begin
       loc_addr_r       <= 'b0;
       loc_write_r      <= 'b0;
       loc_read_r       <= 'b0;
       loc_atomic_r     <= 'b0;
       loc_atype_r      <= 'b0;
       loc_wrdata_r     <= 'b0;
       wmask_r          <= 'b0;
       postatomic_shift <= 'b0;
     end
     else begin
       loc_addr_r       <= loc_addr;
       loc_write_r      <= loc_write;
       loc_read_r       <= loc_read;
       loc_atomic_r     <= loc_atomic;
       loc_atype_r      <= loc_atype;
       loc_wrdata_r     <= loc_wrdata<<(DW - ({20'h0,loc_bytes}<<3));
       wmask_r          <= wmask;
       postatomic_shift <= DW -
                           (({{32-$clog2(DW/8){1'b0}},loc_addr[$clog2(DW/8)-1:0]} +
                           {20'h0,loc_bytes})<<3);
     end
   end

   assign mem_rddata_atomic = mem_rddata<<postatomic_shift;

   always @(*) begin
     if (loc_atype_r == 8'h00)
       loc_wrdata_atomic = loc_wrdata_r + mem_rddata_atomic;
     else if (loc_atype_r == 8'h01)
       loc_wrdata_atomic = loc_wrdata_r & mem_rddata_atomic;
     else if (loc_atype_r == 8'h02)
       loc_wrdata_atomic = loc_wrdata_r | mem_rddata_atomic;
     else if (loc_atype_r == 8'h03)
       loc_wrdata_atomic = loc_wrdata_r ^ mem_rddata_atomic;
     else if (loc_atype_r == 8'h04)
       loc_wrdata_atomic = $signed(loc_wrdata_r) > $signed(mem_rddata_atomic) ?
                           loc_wrdata_r : mem_rddata_atomic;
     else if (loc_atype_r == 8'h05)
       loc_wrdata_atomic = $signed(loc_wrdata_r) > $signed(mem_rddata_atomic) ?
                           mem_rddata_atomic : loc_wrdata_r;
     else if (loc_atype_r == 8'h06)
       loc_wrdata_atomic = $unsigned(loc_wrdata_r) > $unsigned(mem_rddata_atomic) ?
                           loc_wrdata_r : mem_rddata_atomic;
     else if (loc_atype_r == 8'h07)
       loc_wrdata_atomic = $unsigned(loc_wrdata_r) > $unsigned(mem_rddata_atomic) ?
                           mem_rddata_atomic : loc_wrdata_r;
     else if (loc_atype_r == 8'h08)
       loc_wrdata_atomic = loc_wrdata_r;
     else
       loc_wrdata_atomic = loc_wrdata_r;
   end

   assign mem_we = loc_write | loc_atomic_r;
   assign mem_addr = loc_atomic_r ? loc_addr_r : loc_addr;
   assign mem_wmask = loc_atomic_r ? wmask_r : wmask;
   assign mem_wrdata = loc_atomic_r ?
                       (loc_wrdata_atomic[DW-1:0]>>postatomic_shift) :
                       (loc_wrdata[DW-1:0]<<(8*loc_addr[$clog2(DW/8)-1:0]));

   la_spram #(.DW    (DW),               // Memory width
              .AW    ($clog2(RAMDEPTH)), // Address width (derived)
              .TYPE  (SRAMTYPE),         // Pass through variable for hard macro
              .CTRLW (CTRLW),            // Width of asic ctrl interface
              .TESTW (128)               // Width of asic test interface
              )
   la_spram_i(// Outputs
              .dout             (mem_rddata[DW-1:0]),
              // Inputs
              .clk              (clk),
              .ce               (1'b1),
              .we               (mem_we),
              .wmask            (mem_wmask[DW-1:0]),
              .addr             (mem_addr[$clog2(DW/8)+:$clog2(RAMDEPTH)]),
              .din              (mem_wrdata),
              .vss              (1'b0),
              .vdd              (1'b1),
              .vddio            (1'b1),
              .ctrl             (sram_ctrl),
              .test             ('h0));

   assign loc_rddata = mem_rddata >> (8*loc_addr_r[$clog2(DW/8)-1:0]);

endmodule // ebrick_core
// Local Variables:
// verilog-library-directories:("./" "../umi/rtl" "../../submodules/lambdalib/ramlib/rtl/")
// End:
