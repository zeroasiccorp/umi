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
 * Passive protocol checker for the SUMI ready/valid handshake
 * (README section 4.2). Attach one instance per SUMI channel; it
 * drives nothing and never interferes with the design.
 *
 * README 4.2 defines six rules. This module enforces the two that are
 * runtime obligations of the transmitter, witnesses two more, and
 * documents the remaining two, which are structural:
 *
 *   Rule 1 (a transaction occurs when READY and VALID are both
 *          asserted on a rising clock edge) is a definition. The
 *          RULE1_* cover properties witness that transactions,
 *          stalls, and stall-then-complete sequences are all
 *          reachable, so a formal proof of the other rules can not
 *          pass vacuously.
 *   Rule 2 (once VALID is asserted, it must not be de-asserted until
 *          a transaction completes) -> RULE2_valid_hold.
 *   Rule 3 (while VALID is asserted, the packet fields CMD, DSTADDR,
 *          SRCADDR, DATA must remain stable until the transaction
 *          completes) -> RULE3_cmd_stable / RULE3_dstaddr_stable /
 *          RULE3_srcaddr_stable / RULE3_data_stable.
 *   Rule 4 (READY may be de-asserted before a transaction completes)
 *          is a permission for the receiver, not an obligation: there
 *          is nothing to assert. The RULE1_stall cover witnesses that
 *          the surrounding environment actually exercises it.
 *   Rules 5/6 (VALID must not depend on READY; READY may depend on
 *          VALID but not combinationally) constrain the DESIGN
 *          STRUCTURE, not the waveform: a legal trace can be produced
 *          by an illegal circuit. They can not be checked by a bound
 *          monitor and are out of scope here.
 *
 * ASSUME parameter: the same properties can face two directions.
 *   ASSUME=0 (default): assert the rules. Use on any channel the
 *            design under test drives (its outputs) -- in simulation
 *            or formal.
 *   ASSUME=1: assume the rules. Formal-only: use on free inputs of a
 *            formal harness so the solver only explores legal
 *            stimulus. This is the standard assume/guarantee split;
 *            the same file is both the requirement and the
 *            environment, so the two can never drift apart.
 *
 * CHECK_RESET parameter: README 4.2 says nothing about reset. Every
 * block in this repository holds VALID low while nreset is asserted,
 * and the checker's history must be grounded somewhere, so RESET_
 * valid_low (VALID low during reset) is enforced by default. Set
 * CHECK_RESET=0 if a design legitimately asserts VALID during reset.
 *
 * Implementation notes:
 *  - Written in the portable synthesizable-plus-assertions subset:
 *    named immediate assertions inside always blocks, no $past, no
 *    sequences, no bind, no packages. The same file works under
 *    yosys/SymbiYosys (read_verilog -formal), Verilator (--assert),
 *    and slang lint. Cover statements are formal-only (`ifdef FORMAL,
 *    which SymbiYosys defines automatically).
 *  - Each assert is paired with an `ifndef FORMAL $error twin: yosys's
 *    frontend does not parse the assert-else form, and the twin's !==
 *    comparison also catches X propagating into a rule in 4-state
 *    simulation, which a plain boolean assert would wave through.
 *  - History is kept in explicit shadow registers rather than $past
 *    so the file also runs under simulators without $past support.
 ******************************************************************************/

`default_nettype none

module umi_handshake_checker #(
    parameter CW = 32,          // command width
    parameter AW = 64,          // address width
    parameter DW = 256,         // data width
    parameter ASSUME = 0,       // 0: assert the rules, 1: assume them (formal env)
    parameter CHECK_RESET = 1   // 1: also require VALID low during reset
) (
    input wire          clk,
    input wire          nreset,
    input wire          valid,
    input wire          ready,
    input wire [CW-1:0] cmd,
    input wire [AW-1:0] dstaddr,
    input wire [AW-1:0] srcaddr,
    input wire [DW-1:0] data
);

    // #################################################################
    // # History (shadow registers)
    // #################################################################

    // one full clock has elapsed: nothing can be checked at time zero
    reg          past_exists;
    // last cycle was an incomplete offer: valid, not accepted, not in reset
    reg          past_stalled;
    reg [CW-1:0] past_cmd;
    reg [AW-1:0] past_dstaddr;
    reg [AW-1:0] past_srcaddr;
    reg [DW-1:0] past_data;

    initial begin
        past_exists  = 1'b0;
        past_stalled = 1'b0;
    end

    always @(posedge clk) begin
        past_exists  <= 1'b1;
        past_stalled <= nreset & valid & ~ready;
        past_cmd     <= cmd;
        past_dstaddr <= dstaddr;
        past_srcaddr <= srcaddr;
        past_data    <= data;
    end

    // #################################################################
    // # The rules (one generate arm per direction)
    // #################################################################

    generate
        if (ASSUME == 0) begin : g_assert

            always @(posedge clk) begin
                if (past_exists & nreset & past_stalled) begin
                    RULE2_valid_hold : assert (valid);
`ifndef FORMAL
                    if ((valid) !== 1'b1)
                        $error("UMI-HS RULE2 %m: VALID de-asserted before the transaction completed (README 4.2 rule 2)");
`endif
                    RULE3_cmd_stable : assert (cmd == past_cmd);
`ifndef FORMAL
                    if ((cmd == past_cmd) !== 1'b1)
                        $error("UMI-HS RULE3 %m: CMD changed while VALID was waiting for READY (README 4.2 rule 3)");
`endif
                    RULE3_dstaddr_stable : assert (dstaddr == past_dstaddr);
`ifndef FORMAL
                    if ((dstaddr == past_dstaddr) !== 1'b1)
                        $error("UMI-HS RULE3 %m: DSTADDR changed while VALID was waiting for READY (README 4.2 rule 3)");
`endif
                    RULE3_srcaddr_stable : assert (srcaddr == past_srcaddr);
`ifndef FORMAL
                    if ((srcaddr == past_srcaddr) !== 1'b1)
                        $error("UMI-HS RULE3 %m: SRCADDR changed while VALID was waiting for READY (README 4.2 rule 3)");
`endif
                    RULE3_data_stable : assert (data == past_data);
`ifndef FORMAL
                    if ((data == past_data) !== 1'b1)
                        $error("UMI-HS RULE3 %m: DATA changed while VALID was waiting for READY (README 4.2 rule 3)");
`endif
                end
                if (CHECK_RESET != 0) begin
                    if (past_exists & ~nreset) begin
                        RESET_valid_low : assert (~valid);
`ifndef FORMAL
                        if ((~valid) !== 1'b1)
                            $error("UMI-HS RESET %m: VALID asserted while nreset is active (repo convention, not README 4.2)");
`endif
                    end
                end
            end

        end else begin : g_assume
`ifdef FORMAL
            always @(posedge clk) begin
                if (past_exists & nreset & past_stalled) begin
                    RULE2_valid_hold : assume (valid);
                    RULE3_cmd_stable : assume (cmd == past_cmd);
                    RULE3_dstaddr_stable : assume (dstaddr == past_dstaddr);
                    RULE3_srcaddr_stable : assume (srcaddr == past_srcaddr);
                    RULE3_data_stable : assume (data == past_data);
                end
                if (CHECK_RESET != 0) begin
                    if (past_exists & ~nreset)
                        RESET_valid_low : assume (~valid);
                end
            end
`endif
        end
    endgenerate

    // #################################################################
    // # Vacuity witnesses (formal-only)
    // #################################################################
    // A handshake proof over an environment that never stalls, or
    // never completes a transaction, proves nothing. These covers
    // fail loudly (unreached) if the harness is over-constrained.

`ifdef FORMAL
    always @(posedge clk) begin
        if (past_exists & nreset) begin
            RULE1_transaction : cover (valid & ready);
            RULE1_stall : cover (valid & ~ready);
            RULE1_stall_then_complete : cover (past_stalled & valid & ready);
        end
    end
`endif

endmodule

`default_nettype wire
