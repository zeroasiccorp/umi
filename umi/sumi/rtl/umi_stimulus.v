/**************************************************************************
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
 * - This module drives out valid UMI host transactions from memory,
 *   incrementing the memory read address and sending a UMI
 *   transaction whnile 'go' is held high.
 *
 * - The local memory has one host transaction per memory address,
 *   with the following format:
 *   {data, srcaddr, dstaddr, cmd, ctrl}
 *
 * - The data, srcaddr, dstaddr, cmd, ctrl widths are parametrized
 *   via DW,AW,CW.
 *
 * - Bit[0] of the ctrl field indicates a valid transaction. Bits
 *   [7:1] user bits driven out to to the interface
 *
 * - Memory read address loops to zero when it reaches the end of
 *   the memory.
 *
 * - The FILENAME is loaded into memory if non-empty
 *
 * - The APB access port can be used by an external host to
 *   to read/write from memory.
 *
 * - The memory access priority is:
 *   - apb (highest)
 *   - response
 *   - request (lowest)
 *
 * Demo:
 *
 * >> iverilog umi_stimulus.v -DTB_UMI_STIMULUS -y . -I.
 * >> ./a.out +hexfile="./test0.memh"
 *
 *************************************************************************/

module umi_stimulus
  #(parameter DW = 256,           // umi data width
    parameter AW = 64,            // umi addr width
    parameter CW = 32,            // umi ctrl width
    parameter TCW = 8,            // test ctrl width
    parameter DEPTH = 128 ,       // memory depth
    parameter RAW = 32,           // apb address width
    parameter ARGNAME = "hexfile" // $plusargs name (optional)
    )
   (
    // control
    input               nreset,      // async active low reset
    input               clk,         // clk
    input               go,          // drive stimulus
    input
    // apb load interface (optional)
    input [AW-1:0]      apb_paddr,   // address bus
    input               apb_penable, // goes high for cycle 2:n of transfer
    input               apb_pwrite,  // 1=write, 0=read
    input [RW-1:0]      apb_pwdata,  // write data (8, 16, 32b)
    input [3:0]         apb_pstrb,   // (optional) write strobe byte lanes
    input [2:0]         apb_pprot,   // (optional) level of access
    input               apb_psel,    // select signal for each device
    output              apb_pready,  // "wait" signal asserted by device
    output reg [RW-1:0] apb_prdata   // read data (8, 16, 32b)
    // umi host interface
    output              uhost_req_valid,
    output [CW-1:0]     uhost_req_cmd,
    output [AW-1:0]     uhost_req_dstaddr,
    output [AW-1:0]     uhost_req_srcaddr,
    output [DW-1:0]     uhost_req_data,
    input               uhost_req_ready,
    input               uhost_resp_valid,
    input [CW-1:0]      uhost_resp_cmd,
    input [AW-1:0]      uhost_resp_dstaddr,
    input [AW-1:0]      uhost_resp_srcaddr,
    input [DW-1:0]      uhost_resp_data,
    output              uhost_resp_ready
    );

   // memory parameters
   localparam MAW = $clog2(DEPTH); // Memory address width
   localparam MW = DW+2*AW+CW+TCW;

   reg [8*16-1:0] memhfile;

   //#################################
   // Initialize RAM
   //#################################

   initial
     if($value$plusargs($sformatf("%s=%%s", ARGNAME), memhfile))
       $readmemh(memhfile, la_spram.memory.ram);

   //#################################
   // Access Arbiter
   //#################################

   assign mem_ce = apb_penable | uhost_req_valid | uhost_resp_valid;

   assign mem_we = apb_penable      ? apb_pwrite :
                   uhost_resp_valid ? 1'b1       :
                                      1'b0;


   assign mem_din[MW-1:0] = apb_penable ? MW'b0 : // TODO: implement



   assign apb_pready = 1'b1;
   assign uhost_resp_ready = ~apb_penable;
   assign request_ready = uhost_req_ready &
                          ~(uhost_resp_valid | apb_penable);


   //#################################
   // Generator Statemachine
   //#################################




   //#################################
   // RAM
   //#################################

   la_spram #(.DW    (MW),      // Memory width
              .AW    (MAW))     // Address width (derived)
   la_spram(// Outputs
       .dout             (mem_rddata[DW-1:0]),
       // Inputs
       .clk              (clk),
       .ce               (mem_ce),
       .we               (mem_we),
       .wmask            (MW'b1),
       .addr             (mem_addr[$clog2(DW/8)+:$clog2(RAMDEPTH)]),
       .din              (mem_wrdata),
       .vss              (1'b0),
       .vdd              (1'b1),
       .vddio            (1'b1),
       .ctrl             (sram_ctrl),
       .test             (128'h0));

endmodule
// Local Variables:
// verilog-library-directories:("./" "../../../../lambdalib/lambdalib/ramlib/rtl/")
// End:

//#####################################################################
// A SIMPLE TESTBENCH
//#####################################################################

`ifdef TB_UMI_STIMULUS

module tb();

   parameter integer RW = 32;
   parameter integer DW = 64;
   parameter integer AW = 64;
   parameter integer CW = 32;
   parameter integer CTRLW = 8;
   parameter integer REGS = 512;
   parameter integer PERIOD = 2;
   parameter integer TIMEOUT = PERIOD * 100;

   //######################################
   // TEST HARNESS
   //######################################

   // waveform dump
   initial
     begin
        $timeformat(-9, 0, " ns", 20);
        $dumpfile("dump.vcd");
        $dumpvars();
        #(TIMEOUT)
        $finish;
     end

   // reset init
   reg             nreset;
   reg             clk;
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




   //######################################
   // DUT
   //######################################


   /* umi_stimulus AUTO_TEMPLATE(
    .uhost_req_\(.*\) (uhost_req_\1[]),
    .\(.*\)           (@"(if (equal vl-dir \\"output\\")  \\"\\" (concat vl-width \\"'b0\\") )"),
    );*/

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [CW-1:0]        uhost_req_cmd;
   wire [DW-1:0]        uhost_req_data;
   wire [AW-1:0]        uhost_req_dstaddr;
   wire [AW-1:0]        uhost_req_srcaddr;
   wire                 uhost_req_valid;
   // End of automatics
   umi_stimulus #(.AW(AW),
                  .DW(DW),
                  .RW(CW))
   stim (/*AUTOINST*/
         // Outputs
         .apb_pready            (),                      // Templated
         .apb_prdata            (),                      // Templated
         .uhost_req_valid       (uhost_req_valid),       // Templated
         .uhost_req_cmd         (uhost_req_cmd[CW-1:0]), // Templated
         .uhost_req_dstaddr     (uhost_req_dstaddr[AW-1:0]), // Templated
         .uhost_req_srcaddr     (uhost_req_srcaddr[AW-1:0]), // Templated
         .uhost_req_data        (uhost_req_data[DW-1:0]), // Templated
         .uhost_resp_ready      (),                      // Templated
         // Inputs
         .nreset                (1'b0),                  // Templated
         .clk                   (1'b0),                  // Templated
         .go                    (1'b0),                  // Templated
         .apb_paddr             (AW'b0),                 // Templated
         .apb_penable           (1'b0),                  // Templated
         .apb_pwrite            (1'b0),                  // Templated
         .apb_pwdata            (RW'b0),                 // Templated
         .apb_pstrb             (4'b0),                  // Templated
         .apb_pprot             (3'b0),                  // Templated
         .apb_psel              (1'b0),                  // Templated
         .uhost_req_ready       (uhost_req_ready),       // Templated
         .uhost_resp_valid      (1'b0),                  // Templated
         .uhost_resp_cmd        (CW'b0),                 // Templated
         .uhost_resp_dstaddr    (AW'b0),                 // Templated
         .uhost_resp_srcaddr    (AW'b0),                 // Templated
         .uhost_resp_data       (DW'b0));                // Templated

endmodule

`endif
