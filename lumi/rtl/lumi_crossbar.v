/*******************************************************************************
 * Function:  LUMI REGISTER CROSSBAR
 * Author:    Amir Volk
 * Copyright: 2023 Zero ASIC Corporation. All rights reserved.
 *
 * License: This file contains confidential and proprietary information of
 * Zero ASIC. This file may only be used in accordance with the terms and
 * conditions of a signed license agreement with Zero ASIC. All other use,
 * reproduction, or distribution of this software is strictly prohibited.
 *
 * Documentation:
 *
 * 1. Note assymetry, only host can initiate register access
 * 2. Pipelined interface avoids lockup/complexity.
 *
 * ## HOST/CONTROLLER SIDE
 *
 * REQUEST   | CORE SERIAL REGS
 * ----------|------------------
 * CORE(H)   |  --   Y     Y
 * SERIAL(D) |       --
 * REGS(D)   |             --
 *
 * RESPONSE  | CORE SERIAL REGS
 * ----------|------------------
 * CORE(H)   |  --
 * SERIAL(D) |  Y     --
 * REGS(D)   |  Y     Y     --
 *
 * ## CHIPLET SIDE
 *
 * REQUEST   | CORE SERIAL REGS
 * ----------|------------------
 * CORE(D)   |  --
 * SERIAL(H) |  Y    --    Y
 * REGS(D)   |             --
 *
 * RESPONSE  | CORE SERIAL REGS
 * ----------|------------------
 * CORE(D)   |  --   Y
 * SERIAL(D) |       --
 * REGS(D)   |       Y      --
 *
 * CROSSBAR INPUT -- > OUTPUT PATH ENABLE MASK (REQUEST)
 *
 * [0] = core requesting core
 * [1] = serial requesting core
 * [2] = regs requesting core
 *
 * [3] = core requesting serial
 * [4] = serial requesting serial
 * [5] = regs requesting serial
 *
 * [6] = core requesting regs
 * [7] = serial requesting regs
 * [8] = regs requesting regs
 *
 *
 ******************************************************************************/
module lumi_crossbar
  #(parameter TARGET = "DEFAULT", // target
    parameter DW = 256,           // umi packet width
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
    input [DW-1:0]  core_in_data,
    output          core_in_ready,
    output          core_out_valid,
    output [CW-1:0] core_out_cmd,
    output [AW-1:0] core_out_dstaddr,
    output [AW-1:0] core_out_srcaddr,
    output [DW-1:0] core_out_data,
    input           core_out_ready,
    // Serial I/O
    input           serial_in_valid,
    input [CW-1:0]  serial_in_cmd,
    input [AW-1:0]  serial_in_dstaddr,
    input [AW-1:0]  serial_in_srcaddr,
    input [DW-1:0]  serial_in_data,
    output          serial_in_ready,
    output          serial_out_valid,
    output [CW-1:0] serial_out_cmd,
    output [AW-1:0] serial_out_dstaddr,
    output [AW-1:0] serial_out_srcaddr,
    output [DW-1:0] serial_out_data,
    input           serial_out_ready,
    // Local registers
    input           regs_in_valid,
    input [CW-1:0]  regs_in_cmd,
    input [AW-1:0]  regs_in_dstaddr,
    input [AW-1:0]  regs_in_srcaddr,
    input [DW-1:0]  regs_in_data,
    output          regs_in_ready,
    output          regs_out_valid,
    output [CW-1:0] regs_out_cmd,
    output [AW-1:0] regs_out_dstaddr,
    output [AW-1:0] regs_out_srcaddr,
    output [DW-1:0] regs_out_data,
    input           regs_out_ready
    );

`include "clink_regmap.vh"

   //local wires
   wire [8:0] enable;
   wire [8:0] request;
   wire       core2reg;
   wire       serial2reg;

   //###########################################
   //# Creating input-->output enable (see help)
   //###########################################

   assign enable[8:0] = devicemode ? 9'b010_101_010 : 9'b001_101_110;

   // The device and host have different GRPIDs assigned
   // UMI packet must have the correct return to send address

   assign core2reg   = (core_in_dstaddr[GRPOFFSET+:GRPAW]   == GRPID[GRPAW-1:0]);
   assign serial2reg = (serial_in_dstaddr[GRPOFFSET+:GRPAW] == GRPID[GRPAW-1:0]);

   // Core decode (request/response)
   assign request[0] = 1'b0;                                      // core
   assign request[3] = ~core2reg & core_in_valid;                 // serial
   assign request[6] = core2reg & core_in_valid & ~devicemode;    // regs

   // Serial decode (request/response)
   assign request[1] = ~serial2reg & serial_in_valid;             // core
   assign request[4] = 1'b0;                                      // serial
   assign request[7] = serial2reg  & serial_in_valid & devicemode;// regs

   // Register decode (response only)
   assign request[2] = regs_in_valid & ~devicemode;               // core
   assign request[5] = regs_in_valid &  devicemode;               // serial
   assign request[8] = 1'b0;                                      // regs

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
                                     serial_in_ready,
                                     core_in_ready}),
                 .umi_out_valid    ({regs_out_valid,
                                     serial_out_valid,
                                     core_out_valid}),
                 .umi_out_cmd      ({regs_out_cmd[CW-1:0],
                                     serial_out_cmd[CW-1:0],
                                     core_out_cmd[CW-1:0]}),
                 .umi_out_dstaddr ({regs_out_dstaddr[AW-1:0],
                                    serial_out_dstaddr[AW-1:0],
                                    core_out_dstaddr[AW-1:0]}),
                 .umi_out_srcaddr ({regs_out_srcaddr[AW-1:0],
                                    serial_out_srcaddr[AW-1:0],
                                    core_out_srcaddr[AW-1:0]}),
                 .umi_out_data  ({regs_out_data[DW-1:0],
                                  serial_out_data[DW-1:0],
                                  core_out_data[DW-1:0]}),
                 // Inputs
                 .clk             (clk),
                 .nreset          (nreset),
                 .mode            (2'b00),// TODO: fix?
                 .mask            (~enable[8:0]),
                 .umi_in_request  (request[8:0]),
                 .umi_in_cmd      ({regs_in_cmd[CW-1:0],
                                    serial_in_cmd[CW-1:0],
                                    core_in_cmd[CW-1:0]}),
                 .umi_in_dstaddr ({regs_in_dstaddr[AW-1:0],
                                   serial_in_dstaddr[AW-1:0],
                                   core_in_dstaddr[AW-1:0]}),
                 .umi_in_srcaddr ({regs_in_srcaddr[AW-1:0],
                                   serial_in_srcaddr[AW-1:0],
                                   core_in_srcaddr[AW-1:0]}),
                 .umi_in_data  ({regs_in_data[DW-1:0],
                                 serial_in_data[DW-1:0],
                                 core_in_data[DW-1:0]}),
                 .umi_out_ready   ({regs_out_ready,
                                    serial_out_ready,
                                    core_out_ready}));


endmodule // clink_crossbar
// Local Variables:
// verilog-library-directories:("." "../../../umi/umi/rtl/")
// End:
