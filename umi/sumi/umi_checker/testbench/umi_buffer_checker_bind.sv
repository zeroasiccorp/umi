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
 * Worked example: attaching umi_handshake_checker to a shipped design
 * block with `bind`, so the design is checked without being edited.
 *
 * The target is umi_buffer. Adding this file to a simulation compile
 * puts one checker instance inside EVERY umi_buffer instance in the
 * elaborated design, one per SUMI channel:
 *
 *   u_umi_hs_in    watches the input channel, so it asserts against
 *                  whatever drives the buffer (the producer upstream).
 *   u_umi_hs_out   watches the output channel, so it asserts against
 *                  umi_buffer itself.
 *
 * Both instances take ASSUME=0, which is the assert face: the checker
 * reports a rule break as a simulation error. ASSUME=1 turns the same
 * properties into assumptions and is for formal harnesses only, where
 * it constrains free stimulus; it has no meaning in simulation, where
 * nothing is free. See the parameter notes in the checker header.
 *
 * umi_buffer carries a SUMI packet as one DW-wide payload rather than
 * as four named ports, so the bind slices the payload back into the
 * checker's CMD/DSTADDR/SRCADDR/DATA ports. The packing order below,
 * MSB first, is the one tb_umi_buffer_bind.sv and umi/formal/sumi/
 * fv_umi_buffer.sv both use. A block whose ports are already named
 * umi_*_cmd, umi_*_dstaddr and so on needs no slicing: connect the
 * ports straight across.
 *
 * All names in a bind port connection resolve in the TARGET's scope, so
 * clk, nreset, in_valid, out_data and the DW parameter below are
 * umi_buffer's own. Retargeting this file at another block is a matter
 * of renaming those, not of restructuring anything.
 *
 * SIMULATION ONLY. yosys has dropped bind directives without reporting
 * it, so a property reached through a bind must never be the only thing
 * standing behind a formal claim. The formal proofs in umi/formal/
 * instantiate the checkers directly in the harness for that reason, and
 * the umi_buffer handshake proof lives in umi/formal/sumi/
 * fv_umi_buffer.sv, not here.
 ******************************************************************************/

`default_nettype none

// SUMI field widths for the packed payload umi_buffer carries. The
// checker's own DW is what is left after the command and the two
// addresses have been taken off the top.
localparam int UMI_BIND_CW = 32;
localparam int UMI_BIND_AW = 64;

// Input channel: the producer feeding this buffer must obey README 4.2.
bind umi_buffer umi_handshake_checker #(
    .CW          (UMI_BIND_CW),
    .AW          (UMI_BIND_AW),
    .DW          (DW - UMI_BIND_CW - 2*UMI_BIND_AW),
    .ASSUME      (0),
    .CHECK_RESET (1)
) u_umi_hs_in (
    .clk     (clk),
    .nreset  (nreset),
    .valid   (in_valid),
    .ready   (in_ready),
    .cmd     (in_data[DW-1 -: UMI_BIND_CW]),
    .dstaddr (in_data[DW-UMI_BIND_CW-1 -: UMI_BIND_AW]),
    .srcaddr (in_data[DW-UMI_BIND_CW-UMI_BIND_AW-1 -: UMI_BIND_AW]),
    .data    (in_data[DW-UMI_BIND_CW-2*UMI_BIND_AW-1 : 0])
);

// Output channel: the buffer itself must obey README 4.2.
bind umi_buffer umi_handshake_checker #(
    .CW          (UMI_BIND_CW),
    .AW          (UMI_BIND_AW),
    .DW          (DW - UMI_BIND_CW - 2*UMI_BIND_AW),
    .ASSUME      (0),
    .CHECK_RESET (1)
) u_umi_hs_out (
    .clk     (clk),
    .nreset  (nreset),
    .valid   (out_valid),
    .ready   (out_ready),
    .cmd     (out_data[DW-1 -: UMI_BIND_CW]),
    .dstaddr (out_data[DW-UMI_BIND_CW-1 -: UMI_BIND_AW]),
    .srcaddr (out_data[DW-UMI_BIND_CW-UMI_BIND_AW-1 -: UMI_BIND_AW]),
    .data    (out_data[DW-UMI_BIND_CW-2*UMI_BIND_AW-1 : 0])
);

`default_nettype wire
