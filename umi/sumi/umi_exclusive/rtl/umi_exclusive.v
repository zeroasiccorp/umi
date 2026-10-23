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
 * - Exclusive access reservation monitor (README 3.3.8), used by a device
 *   to implement the exclusive read / exclusive write sequence.
 * - One reservation per HOSTID (32 entries). An exclusive read from one
 *   host never clears the reservation of another host.
 * - A reservation holds the device address and SIZE of the exclusive
 *   read. An exclusive write succeeds (ex_ok=1) only if the host holds a
 *   valid reservation with the same address and SIZE.
 * - An accepted exclusive write always clears the reservation of its host.
 * - The reserved region is the device row (granule) holding the address:
 *   addr[AW-1:GW], with 2^GW bytes per row. A write to a row clears every
 *   reservation in that row, from any host.
 * - The instantiating device must report every memory write on wr_valid,
 *   including atomics and successful exclusive writes.
 *
 ******************************************************************************/

module umi_exclusive
  #(parameter AW = 14,  // device address width (bytes)
    parameter GW = 5    // log2 of the reservation granule size (bytes)
    )
   (// ctrls
    input          clk,
    input          nreset,
    // exclusive request
    input          ex_valid,  // exclusive request accepted
    input          ex_write,  // 1=exclusive write, 0=exclusive read
    input [4:0]    ex_hostid, // requesting host
    input [AW-1:0] ex_addr,   // request address
    input [2:0]    ex_size,   // request size
    output         ex_ok,     // reservation valid and matching (write)
    // memory write monitor
    input          wr_valid,  // memory write
    input [AW-1:GW] wr_addr   // memory write address (granule)
    );

   // local state
   reg [31:0]      res_valid;
   reg [AW-1:0]    res_addr[0:31];
   reg [2:0]       res_size[0:31];

   integer         i;

   //###################################################
   // Exclusive write check
   //###################################################

   assign ex_ok = res_valid[ex_hostid] &
                  (res_addr[ex_hostid] == ex_addr[AW-1:0]) &
                  (res_size[ex_hostid] == ex_size[2:0]);

   //###################################################
   // Reservation table
   //###################################################

   // an exclusive read sets the reservation of its host, an exclusive
   // write clears it, a memory write clears all reservations in its row
   always @(posedge clk or negedge nreset)
     if (!nreset)
       res_valid[31:0] <= 32'b0;
     else
       for (i=0;i<32;i=i+1)
         if (ex_valid & (ex_hostid[4:0] == i[4:0]))
           res_valid[i] <= ~ex_write;
         else if (wr_valid & (res_addr[i][AW-1:GW] == wr_addr[AW-1:GW]))
           res_valid[i] <= 1'b0;

   always @(posedge clk)
     if (ex_valid & ~ex_write)
       begin
          res_addr[ex_hostid] <= ex_addr[AW-1:0];
          res_size[ex_hostid] <= ex_size[2:0];
       end

endmodule // umi_exclusive
