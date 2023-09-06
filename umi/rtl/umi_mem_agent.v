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
    parameter RAMDEPTH = 512
    )
   (// global ebrick controls (from clink0/ebrick_regs/bus)
    input           clk,    // clock signals
    input           nreset, // async active low reset
    // Device port (per clink)
    input           udev_req_valid,
    input [CW-1:0]  udev_req_cmd,
    input [AW-1:0]  udev_req_dstaddr,
    input [AW-1:0]  udev_req_srcaddr,
    input [DW-1:0]  udev_req_data,
    output          udev_req_ready,
    output          udev_resp_valid,
    output [CW-1:0] udev_resp_cmd,
    output [AW-1:0] udev_resp_dstaddr,
    output [AW-1:0] udev_resp_srcaddr,
    output [DW-1:0] udev_resp_data,
    input           udev_resp_ready
    /*AUTOINPUT*/
    ///*AUTOOUTPUT*/
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
   reg [AW-1:0]         loc_rdaddr;
   wire [11:0]          loc_lenp1;
   wire [11:0]          loc_bytes;

   wire [DW-1:0]        loc_rddata;
   wire [DW-1:0]        mem_rddata;

   //##################################################################
   //# UMI ENDPOINT (Pipelined Request/Response)
   //##################################################################

   /*umi_endpoint AUTO_TEMPLATE (
    );
    */

   umi_endpoint #(.CW(CW),
                  .AW(AW),
                  .DW(DW),
                  .REG(0))
   umi_endpoint(.loc_ready      (1'b1),
                /*AUTOINST*/
                // Outputs
                .udev_req_ready (udev_req_ready),
                .udev_resp_valid(udev_resp_valid),
                .udev_resp_cmd  (udev_resp_cmd[CW-1:0]),
                .udev_resp_dstaddr(udev_resp_dstaddr[AW-1:0]),
                .udev_resp_srcaddr(udev_resp_srcaddr[AW-1:0]),
                .udev_resp_data (udev_resp_data[DW-1:0]),
                .loc_addr       (loc_addr[AW-1:0]),
                .loc_write      (loc_write),
                .loc_read       (loc_read),
                .loc_opcode     (loc_opcode[7:0]),
                .loc_size       (loc_size[2:0]),
                .loc_len        (loc_len[7:0]),
                .loc_wrdata     (loc_wrdata[DW-1:0]),
                // Inputs
                .nreset         (nreset),
                .clk            (clk),
                .udev_req_valid (udev_req_valid),
                .udev_req_cmd   (udev_req_cmd[CW-1:0]),
                .udev_req_dstaddr(udev_req_dstaddr[AW-1:0]),
                .udev_req_srcaddr(udev_req_srcaddr[AW-1:0]),
                .udev_req_data  (udev_req_data[DW-1:0]),
                .udev_resp_ready(udev_resp_ready),
                .loc_rddata     (loc_rddata[DW-1:0]));

   // Add support for partial writes - for now only 8B aligned addr
   assign loc_lenp1[11:0] = {4'h0,loc_len[7:0]} + 1'b1;
   assign loc_bytes[11:0] = loc_lenp1[11:0] << loc_size[2:0];

   reg [DW-1:0] wmask;
   integer i;

   always @(*)
     for (i=0;i<DW/8;i=i+1) begin
        if ((i >= loc_addr[$clog2(DW/8)-1:0]) & (i < (loc_addr[$clog2(DW/8)-1:0] + loc_bytes)))
          wmask[i*8+:8] = 8'hFF;
        else
          wmask[i*8+:8] = 8'h00;
     end

   la_spram #(.DW    (DW),               // Memory width
              .AW    ($clog2(RAMDEPTH)), // Address width (derived)
              .TYPE  ("DEFAULT"),        // Pass through variable for hard macro
              .CTRLW (128),              // Width of asic ctrl interface
              .TESTW (128)               // Width of asic test interface
              )
   la_spram_i(// Outputs
              .dout             (mem_rddata[DW-1:0]),
              // Inputs
              .clk              (clk),
              .ce               (1'b1),
              .we               (loc_write),
              .wmask            (wmask[DW-1:0]),
              .addr             (loc_addr[$clog2(DW/8)+:$clog2(RAMDEPTH)]),
              .din              (loc_wrdata[DW-1:0]<<(8*loc_addr[$clog2(DW/8)-1:0])),
              .vss              (1'b0),
              .vdd              (1'b1),
              .vddio            (1'b1),
              .ctrl             ('h0),
              .test             ('h0));

   always @(posedge clk or negedge nreset)
     if (~nreset)
       loc_rdaddr <= 'h0;
     else
       loc_rdaddr <= loc_addr;

   assign loc_rddata = mem_rddata >> (8*loc_rdaddr[$clog2(DW/8)-1:0]);

endmodule // ebrick_core
// Local Variables:
// verilog-library-directories:("./" "../umi/rtl" "../../submodules/lambdalib/ramlib/rtl/")
// End:
