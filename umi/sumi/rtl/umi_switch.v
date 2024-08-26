/*******************************************************************************
 * Copyright 2024 Zero ASIC Corporation
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
 * - Pipelined non-blocking swith with M outputs and N inputs
 *
 * - The order and masking is as follows
 *
 * [0]     = input 0   requesting output 0
 * [1]     = input 1   requesting output 0
 * [2]     = input 2   requesting output 0
 * [N-1]   = input N-1 requesting output 0
 *
 * [N]     = input 0   requesting output 1
 * [N+1]   = input 1   requesting output 1
 * [N+2]   = input 2   requesting output 1
 * [2*N-1] = input N-1 requesting output 1
 *
 * Testing:
 *
 * >> iverilog umi_switch.v -DTB_UMI_SWITCH -y . -y $LAMBDALIB/vectorlib/rtl
 * >> ./a.out
 *
 ******************************************************************************/

module umi_switch
  #(
    parameter           N = 4,    // number of input ports
    parameter           M = 4,    // number of outputs ports
    parameter [M*N-1:0] MASK = 0, // static disable of input to output path
    parameter           DW = 128, // umi data width
    parameter           CW = 32,  // umi command width
    parameter           AW = 64   // umi adress width
    )
   (// controls
    input              clk,
    input              nreset,
    input [1:0]        arbmode, // arbiter mode (0=fixed)
    input [N*M-1:0]    arbmask, // dynamic input  mask (1=disable)
    // Incoming UMI
    input [N*M-1:0]    umi_in_valid,
    input [N*CW-1:0]   umi_in_cmd,
    input [N*AW-1:0]   umi_in_dstaddr,
    input [N*AW-1:0]   umi_in_srcaddr,
    input [N*DW-1:0]   umi_in_data,
    output reg [N-1:0] umi_in_ready,
    // Outgoing UMI
    output [M-1:0]     umi_out_valid,
    output [M*CW-1:0]  umi_out_cmd,
    output [M*AW-1:0]  umi_out_dstaddr,
    output [M*AW-1:0]  umi_out_srcaddr,
    output [M*DW-1:0]  umi_out_data,
    input [M-1:0]      umi_out_ready
    );

   genvar i,j;

   wire [M*N-1:0]   umi_ready;
   wire [N*M-1:0]   umi_valid;

   //#######################################################
   // Output Ports
   //#######################################################

   // disable loopback
   for (i=0;i<M;i=i+1)
     for (j=0;j<N;j=j+1)
       if(MASK[i*N+j])
         assign umi_valid[i*N+j] = 1'b0;
       else
         assign umi_valid[i*N+j] = umi_in_valid[i*N+j];

   // instantiate M output ports
   for (i=0;i<M;i=i+1)
     begin: port
        umi_port #(.N(N),
                   .DW(DW),
                   .CW(CW),
                   .AW(AW))
        i0 (// Outputs
             .umi_in_ready          (umi_ready[i*N+:N]),
             .umi_out_valid         (umi_out_valid[i]),
             .umi_out_cmd           (umi_out_cmd[i*CW+:CW]),
             .umi_out_dstaddr       (umi_out_dstaddr[i*AW+:AW]),
             .umi_out_srcaddr       (umi_out_srcaddr[i*AW+:AW]),
             .umi_out_data          (umi_out_data[i*DW+:DW]),
             // Inputs
             .clk                   (clk),
             .nreset                (nreset),
             .arbmode               (arbmode[1:0]),
             .arbmask               (arbmask[i*N+:N]),
             .umi_in_valid          (umi_valid[i*N+:N]),
             .umi_in_cmd            (umi_in_cmd[N*CW-1:0]),
             .umi_in_dstaddr        (umi_in_dstaddr[N*AW-1:0]),
             .umi_in_srcaddr        (umi_in_srcaddr[N*AW-1:0]),
             .umi_in_data           (umi_in_data[N*DW-1:0]),
             .umi_out_ready         (umi_out_ready[i]));
     end

   //#########################################
   // Merge ready signals from all ports
   //##########################################

   integer n,m;
   always @(*)
     begin
        umi_in_ready[N-1:0] = {N{1'b1}};
        for (n=0;n<N;n=n+1)
          for (m=0;m<M;m=m+1)
            umi_in_ready[n] = umi_in_ready[n] & umi_ready[n+N*m];
     end

endmodule

//#####################################################################
// A SIMPLE TESTBENCH
//#####################################################################

`ifdef TB_UMI_SWITCH
module tb();

   // sim params
   parameter PERIOD = 2;
   parameter TIMEOUT = PERIOD  * 50;

   // dut params
   parameter CW = 32;
   parameter AW = 64;
   parameter DW = 128;
   parameter M = 4;
   parameter N  = 4;
   parameter MASK = 16'h8421; // disable loopback

   // control block
   initial
     begin
        $timeformat(-9, 0, " ns", 20);
        $dumpfile("dump.vcd");
        $dumpvars(0, tb);
        #(TIMEOUT)
        $finish;
     end

   // test program
   initial
     begin
        #(1)
        clk = 'b0;
        nreset = 'b0;
        umi_out_ready = {(N){1'b1}};
        umi_in_valid = {(N*M){1'b1}};
        umi_in_cmd = 'b0;
        umi_in_dstaddr = 'b0;
        umi_in_srcaddr = 'b0;
        umi_in_data = 'b0;
        #(PERIOD * 10)
        nreset = 1'b1;
     end

   // clk
   always
     #(PERIOD/2) clk = ~clk;

   /*AUTOREGINPUT*/
   // Beginning of automatic reg inputs (for undeclared instantiated-module inputs)
   reg [N*M-1:0]        arbmask;
   reg [1:0]            arbmode;
   reg                  clk;
   reg                  nreset;
   reg [N*CW-1:0]       umi_in_cmd;
   reg [N*DW-1:0]       umi_in_data;
   reg [N*AW-1:0]       umi_in_dstaddr;
   reg [N*AW-1:0]       umi_in_srcaddr;
   reg [N*M-1:0]        umi_in_valid;
   reg [M-1:0]          umi_out_ready;
   // End of automatics

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [N-1:0]         umi_in_ready;
   wire [M*CW-1:0]      umi_out_cmd;
   wire [M*DW-1:0]      umi_out_data;
   wire [M*AW-1:0]      umi_out_dstaddr;
   wire [M*AW-1:0]      umi_out_srcaddr;
   wire [M-1:0]         umi_out_valid;
   // End of automatics

   umi_switch #(/*AUTOINSTPARAM*/
                // Parameters
                .N                      (N),
                .M                      (M),
                .MASK                   (MASK[M*N-1:0]),
                .DW                     (DW),
                .CW                     (CW),
                .AW                     (AW))
   umi_switch(/*AUTOINST*/
              // Outputs
              .umi_in_ready             (umi_in_ready[N-1:0]),
              .umi_out_valid            (umi_out_valid[M-1:0]),
              .umi_out_cmd              (umi_out_cmd[M*CW-1:0]),
              .umi_out_dstaddr          (umi_out_dstaddr[M*AW-1:0]),
              .umi_out_srcaddr          (umi_out_srcaddr[M*AW-1:0]),
              .umi_out_data             (umi_out_data[M*DW-1:0]),
              // Inputs
              .clk                      (clk),
              .nreset                   (nreset),
              .arbmode                  (arbmode[1:0]),
              .arbmask                  (arbmask[N*M-1:0]),
              .umi_in_valid             (umi_in_valid[N*M-1:0]),
              .umi_in_cmd               (umi_in_cmd[N*CW-1:0]),
              .umi_in_dstaddr           (umi_in_dstaddr[N*AW-1:0]),
              .umi_in_srcaddr           (umi_in_srcaddr[N*AW-1:0]),
              .umi_in_data              (umi_in_data[N*DW-1:0]),
              .umi_out_ready            (umi_out_ready[M-1:0]));

endmodule
`endif
