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
 *
 * ----
 *
 * Documentation:
 *
 * Passive UMI bus monitor. Taps a UMI bus without driving any signals.
 *
 * Synthesis: produces a 1-cycle 'beat' pulse on every valid+ready
 * handshake. Can be used for transaction counters, performance
 * monitors, or activity indicators.
 *
 * Simulation: on negedge clock, displays the full transaction
 * (opcode name, addresses, data) whenever a handshake occurs.
 * Acts as a built-in protocol analyzer for debug.
 *
 ******************************************************************************/

module umi_monitor
  #(parameter            CW = 32,
    parameter            AW = 64,
    parameter            DW = 128,
    parameter            TIMEOUT = 100, // simulation only
    parameter            VERBOSE = 0,   // set to 1 always enable tracing
    parameter [12*8-1:0] NAME = "umi")  // short label for display (12 chars)
   (// UMI bus tap
    input          valid,
    input          ready,
    input [CW-1:0] cmd,
    input [AW-1:0] dstaddr,
    input [AW-1:0] srcaddr,
    input [DW-1:0] data,
    // clk, reset only used for simulation display
    input          clk,
    input          nreset,
    // beat output
    output         beat
    );

   //##########################################
   // A transaction has happened
   //##########################################

`include "umi_messages.vh"

   assign beat = valid & ready;

   //##########################################
   // Simulation only monitoring
   //##########################################

`ifdef SIMULATION

   // compile time enable of verbose tracing
 `ifdef VERBOSE
   localparam VERBOSE_SWITCH = 1;
 `else
   localparam VERBOSE_SWITCH = 0;
 `endif

   // sane printing
   initial $timeformat(-9, 2, "ns", 0);

   // Pad NAME with leading spaces for aligned display
   reg [12*8-1:0] name_padded;
   integer ni;
   initial begin
      name_padded = "            "; // 12 spaces
      for (ni = 0; ni < 12; ni = ni + 1)
        if (NAME[ni*8+:8] != 0)
          name_padded[ni*8+:8] = NAME[ni*8+:8];
   end

   wire [4:0] opcode;

   assign opcode = cmd[4:0];

   // Stall timeout: valid high but ready low for TIMEOUT cycles
   integer stall_count;
   always @(posedge clk or negedge nreset)
     if (!nreset)
       stall_count <= 0;
     else if (valid & ~ready)
       stall_count <= stall_count + 1;
     else
       stall_count <= 0;

   always @(posedge clk) begin
      if (nreset & (stall_count == TIMEOUT)) begin
         $display("%10t %s WARNING: UMI_TIMEOUT: valid=%b ready=%b dst=0x%h src=0x%h cmd=0x%h (%0d cycles) (%m)",
                  $realtime, name_padded, valid, ready, dstaddr, srcaddr, cmd, stall_count);
      end
   end

   if (VERBOSE | VERBOSE_SWITCH) begin
      // Transaction display on handshake
      always @(negedge clk) begin
         if (nreset & beat) begin
            case (opcode)
              UMI_REQ_READ:    $display("%10t    %s    UMI_REQ_READ:    dst=0x%h src=0x%h data=0x%h (%m)", $realtime, name_padded, dstaddr, srcaddr, data);
              UMI_REQ_WRITE:   $display("%10t    %s    UMI_REQ_WRITE:   dst=0x%h src=0x%h data=0x%h (%m)", $realtime, name_padded, dstaddr, srcaddr, data);
              UMI_REQ_POSTED:  $display("%10t    %s    UMI_REQ_POSTED:  dst=0x%h src=0x%h data=0x%h (%m)", $realtime, name_padded, dstaddr, srcaddr, data);
              UMI_RESP_READ:   $display("%10t    %s    UMI_RESP_READ:   dst=0x%h src=0x%h data=0x%h (%m)", $realtime, name_padded, dstaddr, srcaddr, data);
              UMI_RESP_WRITE:  $display("%10t    %s    UMI_RESP_WRITE:  dst=0x%h src=0x%h data=0x%h (%m)", $realtime, name_padded, dstaddr, srcaddr, data);
              UMI_REQ_ATOMIC:  $display("%10t    %s    UMI_REQ_ATOMIC:  dst=0x%h src=0x%h data=0x%h (%m)", $realtime, name_padded, dstaddr, srcaddr, data);
              UMI_REQ_RDMA:    $display("%10t    %s    UMI_REQ_RDMA:    dst=0x%h src=0x%h data=0x%h (%m)", $realtime, name_padded, dstaddr, srcaddr, data);
              UMI_REQ_USER0:   $display("%10t    %s    UMI_REQ_USER0:   dst=0x%h src=0x%h data=0x%h (%m)", $realtime, name_padded, dstaddr, srcaddr, data);
              UMI_REQ_ERROR:   $display("%10t    %s    UMI_REQ_ERROR:   dst=0x%h src=0x%h data=0x%h (%m)", $realtime, name_padded, dstaddr, srcaddr, data);
              UMI_REQ_LINK:    $display("%10t    %s    UMI_REQ_LINK:    dst=0x%h src=0x%h data=0x%h (%m)", $realtime, name_padded, dstaddr, srcaddr, data);
              default:         $display("%10t    %s    UMI_OPCODE=0x%h: dst=0x%h src=0x%h data=0x%h (%m)", $realtime, name_padded, opcode, dstaddr, srcaddr, data);
            endcase
         end
      end
   end
`endif

endmodule
