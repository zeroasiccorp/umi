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
  #(parameter CW = 32,
    parameter AW = 64,
    parameter DW = 128,
    parameter TIMEOUT = 100) // simulation only
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

`include "umi_messages.vh"

   assign beat = valid & ready;

`ifdef SIMULATION

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
         $display("WARNING: UMI_TIMEOUT: valid=%b ready=%b dst=0x%h src=0x%h cmd=0x%h (%0d wait cycles, %0t, %m)",
                  valid, ready, dstaddr, srcaddr, cmd, stall_count, $realtime);
      end
   end

   // Transaction display on handshake
   always @(negedge clk) begin
      if (nreset & beat) begin
         case (opcode)
           UMI_REQ_READ:    $display("UMI_REQ_READ:    dst=0x%h src=0x%h data=0x%h (%0t, %m)", dstaddr, srcaddr, data, $realtime);
           UMI_REQ_WRITE:   $display("UMI_REQ_WRITE:   dst=0x%h src=0x%h data=0x%h (%0t, %m)", dstaddr, srcaddr, data, $realtime);
           UMI_REQ_POSTED:  $display("UMI_REQ_POSTED:  dst=0x%h src=0x%h data=0x%h (%0t, %m)", dstaddr, srcaddr, data, $realtime);
           UMI_RESP_READ:   $display("UMI_RESP_READ:   dst=0x%h src=0x%h data=0x%h (%0t, %m)", dstaddr, srcaddr, data, $realtime);
           UMI_RESP_WRITE:  $display("UMI_RESP_WRITE:  dst=0x%h src=0x%h data=0x%h (%0t, %m)", dstaddr, srcaddr, data, $realtime);
           UMI_REQ_ATOMIC:  $display("UMI_REQ_ATOMIC:  dst=0x%h src=0x%h data=0x%h (%0t, %m)", dstaddr, srcaddr, data, $realtime);
           UMI_REQ_RDMA:    $display("UMI_REQ_RDMA:    dst=0x%h src=0x%h data=0x%h (%0t, %m)", dstaddr, srcaddr, data, $realtime);
           UMI_REQ_USER0:   $display("UMI_REQ_USER0:   dst=0x%h src=0x%h data=0x%h (%0t, %m)", dstaddr, srcaddr, data, $realtime);
           UMI_REQ_ERROR:   $display("UMI_REQ_ERROR:   dst=0x%h src=0x%h data=0x%h (%0t, %m)", dstaddr, srcaddr, data, $realtime);
           UMI_REQ_LINK:    $display("UMI_REQ_LINK:    dst=0x%h src=0x%h data=0x%h (%0t, %m)", dstaddr, srcaddr, data, $realtime);
           default:         $display("UMI_OPCODE=0x%h: dst=0x%h src=0x%h data=0x%h (%0t, %m)", opcode, dstaddr, srcaddr, data, $realtime);
         endcase
      end
   end
`endif

endmodule
