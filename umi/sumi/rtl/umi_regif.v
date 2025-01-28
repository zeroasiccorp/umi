/******************************************************************************
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
 * Documentation:
 *
 * - The module translates a UMI request into a simple register interface.
 * - Reads requests consume two cycles.
 * - Read data must return on same cycle immediately (no pipeline)
 * - Only read/writes/posted <= DW is supported.
 * - No atomics support
 * - This module can check if the incoming access is within the designated
 *   address range by setting the GRPOFFSET, GRPAW, and GRPID parameter.
 *   The address range [GRPOFFSET+:GRPAW] is checked against GRPID for a
 *   match. To disable the check, set the GRPAW to 0.
 *
 * Demo:
 *
 * >> iverilog umi_regif.v -DTB_UMI_REGIF -y . -I.
 * >> ./a.out
 *
 *****************************************************************************/

module umi_regif
  #(parameter RW = 32,        // register width
    parameter GRPOFFSET = 24, // group address offset
    parameter GRPAW = 0,      // group address width
    parameter GRPID = 0,      // group ID
    parameter SAFE = 1,       // 1: no combinatorial path, low performance
    // umi standard parameters
    parameter CW = 32,        // command width
    parameter AW = 64,        // address width
    parameter DW = 64         // data width
    )
   (// clk, reset
    input               clk,       //clk
    input               nreset,    //async active low reset
    // UMI transaction
    input               udev_req_valid,
    input [CW-1:0]      udev_req_cmd,
    input [AW-1:0]      udev_req_dstaddr,
    input [AW-1:0]      udev_req_srcaddr,
    input [DW-1:0]      udev_req_data,
    output              udev_req_ready,
    output reg          udev_resp_valid,
    output reg [CW-1:0] udev_resp_cmd,
    output reg [AW-1:0] udev_resp_dstaddr,
    output reg [AW-1:0] udev_resp_srcaddr,
    output reg [DW-1:0] udev_resp_data,
    input               udev_resp_ready,
    // single-port register interface
    output              reg_write, // write enable
    output              reg_read,  // read request
    output [AW-1:0]     reg_addr,  // address
    output [RW-1:0]     reg_wdata, // write data
    output [1:0]        reg_prot,  // protection
    input [RW-1:0]      reg_rdata, // read data
    input [1:0]         reg_err,   // device error
    input               reg_ready  // device is ready
    );

`include "umi_messages.vh"

   // local state
   reg udev_req_safe_ready;


   // local wires
   wire [CW-1:0] resp_cmd;
   wire          cmd_read;
   wire          cmd_write;
   wire          cmd_posted;
   wire          cmd_atomic;
   wire          match;
   wire          beat;

   //######################################
   // UMI Request
   //######################################

   generate
     if (GRPAW != 0)
       assign match = (udev_req_dstaddr[GRPOFFSET+:GRPAW] == GRPID[GRPAW-1:0]);
     else
       assign match = 1'b1;
   endgenerate

   assign cmd_read = (udev_req_cmd[4:0]==UMI_REQ_READ);
   assign cmd_write = (udev_req_cmd[4:0]==UMI_REQ_WRITE);
   assign cmd_posted = (udev_req_cmd[4:0]==UMI_REQ_POSTED);
   assign cmd_atomic = (udev_req_cmd[4:0]==UMI_REQ_ATOMIC);

    // single cycle stall on every ready
   always @ (posedge clk or negedge nreset)
     if(!nreset)
       udev_req_safe_ready <= 1'b0;
     else if (udev_req_valid & udev_req_ready)
       udev_req_safe_ready <= 1'b0;
     else
       udev_req_safe_ready <= 1'b1;

   // The unsafe combinatorial path from resp_ready-->req_ready has the
   // potential of causing cominatiro loops in designs if the that are
   if(SAFE)
     assign udev_req_ready = reg_ready & udev_req_safe_ready;
   else
     assign udev_req_ready = reg_ready & (udev_resp_ready|~udev_resp_valid);

   // request accepted
   assign beat = udev_req_valid & udev_req_ready;

   //######################################
   // Register Interface
   //######################################

   assign reg_write = (cmd_write | cmd_posted) & beat;
   assign reg_read = cmd_read & beat;
   assign reg_addr[AW-1:0] = udev_req_dstaddr[AW-1:0];
   assign reg_wdata[RW-1:0] = udev_req_data[RW-1:0];
   assign reg_prot[1:0] = udev_req_cmd[21:20];

   //######################################
   // UMI Response
   //######################################

   //1. Set on incoming valid read
   //2. Keep high as long as incoming read is set
   //3. If no incoming read and output is ready, clear
   always @(posedge clk or negedge nreset)
     if (!nreset)
       udev_resp_valid <= 1'b0;
     else if (beat & (cmd_write | cmd_read))
       udev_resp_valid <= 1'b1;
     else if (udev_resp_valid & udev_resp_ready)
       udev_resp_valid <= 1'b0;

   // read/write responses
   assign resp_cmd[4:0] = (cmd_read)  ? UMI_RESP_READ :
                          (cmd_write) ? UMI_RESP_WRITE :
                                        5'b0;

   assign resp_cmd[24:5] = udev_req_cmd[24:5];
   assign resp_cmd[26:25] = reg_err[1:0];
   assign resp_cmd[31:27] = udev_req_cmd[31:27];

   // sample data on read/write
   always @ (posedge clk)
     if (beat & (cmd_write | cmd_read))
       begin
          udev_resp_cmd[CW-1:0]     <= resp_cmd;
          udev_resp_dstaddr[AW-1:0] <= udev_req_srcaddr;
          udev_resp_srcaddr[AW-1:0] <= udev_req_dstaddr;
          udev_resp_data[DW-1:0]    <= {{(DW-RW){1'b0}},
                                        reg_rdata[RW-1:0]};
       end

endmodule

//#####################################################################
// DEMO TESTBENCH
//#####################################################################

`ifdef TB_UMI_REGIF

module tb();
 `include "umi_messages.vh"

   parameter integer RW = 32;
   parameter integer DW = 64;
   parameter integer AW = 64;
   parameter integer CW = 32;
   parameter integer CTRLW = 8;
   parameter integer REGS = 512;
   parameter integer PERIOD = 2;
   parameter integer TIMEOUT = PERIOD * 100;

   //######################################
   // TEST
   //######################################

   // stimulus signals
   reg             nreset;
   reg             clk;
   reg             sel_read;

   wire [CW-1:0]   udev_req_cmd;
   reg [DW-1:0]    udev_req_data;
   reg [AW-1:0]    udev_req_dstaddr;
   reg [AW-1:0]    udev_req_srcaddr;
   reg             udev_req_valid;
   reg             udev_resp_ready;

   // control block
   initial
     begin
        $timeformat(-9, 0, " ns", 20);
        $dumpfile("dump.vcd");
        $dumpvars();
        #(TIMEOUT)
        $finish;
     end

   // reset init
   initial
     begin
        #(1)
        nreset = 'b0;
        clk = 'b0;
        #(PERIOD * 10)
        nreset = 1'b1;
     end

   // clock
   always
     #(PERIOD/2) clk = ~clk;

   // legal valid generator
   always @(posedge clk or negedge nreset)
     if(~nreset)
       begin
          udev_req_valid  <= 1'b0;
       end
     else if(~udev_req_valid | (udev_req_valid & udev_req_ready))
       begin
          udev_req_valid <= $random;
       end

   // pushback
   always @(posedge clk)
     udev_resp_ready <= $random;

   // write/read generator
   always @(posedge clk or negedge nreset)
     if(~nreset)
       begin
          udev_req_data <='b0;
          udev_req_dstaddr <='b0;
          udev_req_srcaddr <='b0;
          sel_read <='b0;
       end
     else if(udev_req_valid & udev_req_ready)
       begin
          sel_read <= ~sel_read;
          udev_req_data    <= sel_read ? udev_req_data + 'h4 : udev_req_data;
          udev_req_dstaddr <= sel_read ? udev_req_dstaddr + 'h4 : udev_req_dstaddr;
          udev_req_srcaddr <= sel_read ? udev_req_srcaddr + 'h4 : udev_req_srcaddr;
       end

   // flip-flopping write-read pattern
   assign udev_req_cmd = sel_read ? {24'b0, 3'b011, UMI_REQ_READ}:
                                    {24'b0, 3'b011, UMI_REQ_WRITE};

   // reverse lookup
   reg [127:0] 	  ascii;
    always @*
      begin
         ascii = "unknown";
         if (udev_resp_cmd[4:0]==UMI_RESP_READ)   ascii = "UMI_RESP_READ";
         if (udev_resp_cmd[4:0]==UMI_RESP_WRITE)  ascii = "UMI_RESP_WRITE";
      end

   // capture responses
   always @ (posedge clk)
     if (udev_resp_valid & udev_resp_ready)
       $display("(response) addr=%h, data=%h, cmd=%s",
                udev_resp_srcaddr, udev_resp_data, ascii);

   //######################################
   // DUT
   //######################################

   wire [RW-1:0]       reg_rdata;
   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [AW-1:0]        reg_addr;
   wire [1:0]           reg_prot;
   wire                 reg_read;
   wire [RW-1:0]        reg_wdata;
   wire                 reg_write;
   wire                 udev_req_ready;
   wire [CW-1:0]        udev_resp_cmd;
   wire [DW-1:0]        udev_resp_data;
   wire [AW-1:0]        udev_resp_dstaddr;
   wire [AW-1:0]        udev_resp_srcaddr;
   wire                 udev_resp_valid;
   // End of automatics
   umi_regif #(.AW(AW),
               .DW(DW),
               .RW(CW))
   umi_regif (.reg_ready        (1'b1),
              .reg_err(2'b0),
              /*AUTOINST*/
              // Outputs
              .udev_req_ready   (udev_req_ready),
              .udev_resp_valid  (udev_resp_valid),
              .udev_resp_cmd    (udev_resp_cmd[CW-1:0]),
              .udev_resp_dstaddr(udev_resp_dstaddr[AW-1:0]),
              .udev_resp_srcaddr(udev_resp_srcaddr[AW-1:0]),
              .udev_resp_data   (udev_resp_data[DW-1:0]),
              .reg_write        (reg_write),
              .reg_read         (reg_read),
              .reg_addr         (reg_addr[AW-1:0]),
              .reg_wdata        (reg_wdata[RW-1:0]),
              .reg_prot         (reg_prot[1:0]),
              // Inputs
              .clk              (clk),
              .nreset           (nreset),
              .udev_req_valid   (udev_req_valid),
              .udev_req_cmd     (udev_req_cmd[CW-1:0]),
              .udev_req_dstaddr (udev_req_dstaddr[AW-1:0]),
              .udev_req_srcaddr (udev_req_srcaddr[AW-1:0]),
              .udev_req_data    (udev_req_data[DW-1:0]),
              .udev_resp_ready  (udev_resp_ready),
              .reg_rdata        (reg_rdata[RW-1:0]));

   //######################################
   // MEMORY
   //######################################

   reg     [RW-1:0] regs[REGS-1:0];

   always @(posedge clk)
     if(reg_write)
       regs[reg_addr[2+:$clog2(REGS)]] <= reg_wdata[RW-1:0];

   assign reg_rdata[RW-1:0] = regs[reg_addr[2+:$clog2(REGS)]];

endmodule

`endif
