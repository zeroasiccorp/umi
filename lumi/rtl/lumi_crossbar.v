/*******************************************************************************
 * Copyright 2023 Zero ASIC Corporation
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
 * - LUMI register access crossbar
 *
 * 1. Note asymmetry, only host can initiate register access
 * 2. Pipelined interface avoids lockup/complexity.
 *
 * ## HOST/CONTROLLER SIDE
 *
 * REQUEST   | CORE PHY REGS
 * ----------|----------------
 * CORE(H)   |  --   Y    Y
 * PHY(D)    |       --
 * REGS(D)   |            --
 *
 * ## CHIPLET SIDE
 *
 * REQUEST   | CORE PHY REGS
 * ----------|----------------
 * CORE(D)   |  --
 * PHY(H)    |  Y    --   Y
 * REGS(D)   |            --
 *
 * CROSSBAR INPUT -- > OUTPUT PATH ENABLE MASK (REQUEST)
 *
 * [0] = core requesting core
 * [1] = phy requesting core
 * [2] = regs requesting core
 *
 * [3] = core requesting phy
 * [4] = phy requesting phy
 * [5] = regs requesting phy
 *
 * [6] = core requesting regs
 * [7] = phy requesting regs
 * [8] = regs requesting regs
 *
 *
 ******************************************************************************/
module lumi_crossbar
  #(parameter TARGET = "DEFAULT", // target
    parameter RW = 256,           // umi packet width
    parameter CW = 32,            // umi packet width
    parameter AW = 64,            // address width
    parameter IDOFFSET = 40,      // chipid offset
    parameter GRPOFFSET = 24,     // group address offset
    parameter GRPAW = 8,          // group address width
    parameter GRPID = 0           // group id for clink
    )
   (// clink clock and reset
    input           nreset,     // async active low reset
    input           clk,        // common clink clock
    input           devicemode, // 1=host, 0=device
    // Core
    input           core_in_valid,
    input [CW-1:0]  core_in_cmd,
    input [AW-1:0]  core_in_dstaddr,
    input [AW-1:0]  core_in_srcaddr,
    input [RW-1:0]  core_in_data,
    output          core_in_ready,
    output          core_out_valid,
    output [CW-1:0] core_out_cmd,
    output [AW-1:0] core_out_dstaddr,
    output [AW-1:0] core_out_srcaddr,
    output [RW-1:0] core_out_data,
    input           core_out_ready,
    // Phy I/O
    input           phy_in_valid,
    input [CW-1:0]  phy_in_cmd,
    input [AW-1:0]  phy_in_dstaddr,
    input [AW-1:0]  phy_in_srcaddr,
    input [RW-1:0]  phy_in_data,
    output          phy_in_ready,
    output          phy_out_valid,
    output [CW-1:0] phy_out_cmd,
    output [AW-1:0] phy_out_dstaddr,
    output [AW-1:0] phy_out_srcaddr,
    output [RW-1:0] phy_out_data,
    input           phy_out_ready,
    // Local registers
    input           regs_in_valid,
    input [CW-1:0]  regs_in_cmd,
    input [AW-1:0]  regs_in_dstaddr,
    input [AW-1:0]  regs_in_srcaddr,
    input [RW-1:0]  regs_in_data,
    output          regs_in_ready,
    output          regs_out_valid,
    output [CW-1:0] regs_out_cmd,
    output [AW-1:0] regs_out_dstaddr,
    output [AW-1:0] regs_out_srcaddr,
    output [RW-1:0] regs_out_data,
    input           regs_out_ready
    );

`include "lumi_regmap.vh"
   localparam DW = RW;

   //local wires
   wire [8:0] enable;
   wire [8:0] request;
   wire       core2reg;
   wire       phy2reg;

   //###########################################
   //# Creating input-->output enable (see help)
   //###########################################

   assign enable[8:0] = devicemode ? 9'b010_101_010 : 9'b001_001_110;

   // The device and host have different GRPIDs assigned
   // UMI packet must have the correct return to send address

   assign core2reg = (core_in_dstaddr[GRPOFFSET+:GRPAW] == GRPID[GRPAW-1:0]);
   assign phy2reg  = (phy_in_dstaddr[GRPOFFSET+:GRPAW]  == GRPID[GRPAW-1:0]);

   // Core decode (request/response)
   assign request[0] = 1'b0;                                   // core
   assign request[3] = ~core2reg & core_in_valid;              // phy
   assign request[6] = core2reg & core_in_valid & ~devicemode; // regs

   // Phy decode (request/response)
   assign request[1] = ~phy2reg & phy_in_valid;                // core
   assign request[4] = 1'b0;                                   // phy
   assign request[7] = phy2reg  & phy_in_valid & devicemode;   // regs

   // Register decode (response only)
   assign request[2] = regs_in_valid & ~devicemode;            // core
   assign request[5] = regs_in_valid &  devicemode;            // phy
   assign request[8] = 1'b0;                                   // regs

   //######################################
   // CROSSBAR (3x3)
   //######################################

   umi_crossbar #(.TARGET(TARGET),
                  .DW(DW),
                  .CW(CW),
                  .AW(AW),
                  .N(3))
   umi_crossbar (// Outputs
                 .umi_in_ready     ({regs_in_ready,
                                     phy_in_ready,
                                     core_in_ready}),
                 .umi_out_valid    ({regs_out_valid,
                                     phy_out_valid,
                                     core_out_valid}),
                 .umi_out_cmd      ({regs_out_cmd[CW-1:0],
                                     phy_out_cmd[CW-1:0],
                                     core_out_cmd[CW-1:0]}),
                 .umi_out_dstaddr ({regs_out_dstaddr[AW-1:0],
                                    phy_out_dstaddr[AW-1:0],
                                    core_out_dstaddr[AW-1:0]}),
                 .umi_out_srcaddr ({regs_out_srcaddr[AW-1:0],
                                    phy_out_srcaddr[AW-1:0],
                                    core_out_srcaddr[AW-1:0]}),
                 .umi_out_data  ({regs_out_data[DW-1:0],
                                  phy_out_data[DW-1:0],
                                  core_out_data[DW-1:0]}),
                 // Inputs
                 .clk             (clk),
                 .nreset          (nreset),
                 .mode            (2'b00),// TODO: fix?
                 .mask            (~enable[8:0]),
                 .umi_in_request  (request[8:0]),
                 .umi_in_cmd      ({regs_in_cmd[CW-1:0],
                                    phy_in_cmd[CW-1:0],
                                    core_in_cmd[CW-1:0]}),
                 .umi_in_dstaddr ({regs_in_dstaddr[AW-1:0],
                                   phy_in_dstaddr[AW-1:0],
                                   core_in_dstaddr[AW-1:0]}),
                 .umi_in_srcaddr ({regs_in_srcaddr[AW-1:0],
                                   phy_in_srcaddr[AW-1:0],
                                   core_in_srcaddr[AW-1:0]}),
                 .umi_in_data  ({regs_in_data[DW-1:0],
                                 phy_in_data[DW-1:0],
                                 core_in_data[DW-1:0]}),
                 .umi_out_ready   ({regs_out_ready,
                                    phy_out_ready,
                                    core_out_ready}));


endmodule // clink_crossbar
// Local Variables:
// verilog-library-directories:("." "../../../umi/umi/rtl/")
// End:
