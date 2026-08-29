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
 * - Proves umi_address_remap rewrites the destination address and
 *   disturbs nothing else, and that a packet already addressed to this
 *   chip is passed through untouched.
 *
 * WHAT THE BLOCK IS. A combinational SUMI channel that may rewrite
 * DSTADDR on the way past. Three outcomes, in priority order
 * (umi_address_remap.v:121-125): a packet whose ID field already
 * matches chipid is left alone; otherwise a packet inside
 * [set_dstaddress_low, set_dstaddress_high] gets the offset added; and
 * otherwise the ID field is replaced from the remap table.
 *
 * WHAT IS PROVEN:
 *   RULE2_valid_hold / RULE3_*_stable  the output channel keeps the
 *                     README 4.2 handshake, with the input constrained
 *                     legal by the same checker in its ASSUME face
 *   a_remap_local     a packet whose ID field already equals chipid
 *                     leaves with its DSTADDR untouched. This is the
 *                     block's central guarantee: local traffic is not
 *                     re-routed
 *   a_remap_carry     the other four SUMI wires -- VALID, CMD, SRCADDR
 *                     and DATA -- and the READY going back are the same
 *                     on both faces. Only DSTADDR may move
 *
 * NOT ASSERTED. Which of the offset and the remap table wins, and what
 * the remap table produces, are the ternary and the case statement read
 * back. What is asserted is the part that is not a restatement: that
 * local traffic is exempt, and that nothing but DSTADDR is touched.
 *
 * THE CONFIGURATION PINS MUST HOLD STILL. chipid, the remap table and
 * the three set_dstaddress_* pins are (* anyconst *) here. That is not
 * a convenience: DSTADDR is a combinational function of them, so an
 * integrator that moves any of them while a beat is standing unaccepted
 * moves the payload under a standing VALID, which is a README 4.2 rule
 * 3 violation at this block's own output. The hazard row withdraws the
 * constraint and reaches the violation; the block header does not
 * mention the condition, and this harness does.
 *
 * SCOPE. Purely combinational, so induction closes immediately and the
 * value of prove mode is the quantifier over every input word.
 *
 * NMAPS IS FIXED AT 8. The remap case statement enumerates eight table
 * entries by hand and the RTL says so -- "FIXME: Parameterize this"
 * (umi_address_remap.v:85) -- so the block does not elaborate below
 * that. The harness runs the default rather than sweeping a parameter
 * the block does not honour.
 *
 * ROWS (tests/test_formal_sc.py):
 *   remap:prove          both laws and the handshake, unbounded
 *   remap:cover          witnesses: expect all reached
 *   remap:hazard         configuration pins free: expect the witness
 *   remap:fault_local    must FAIL, a_remap_local
 *   remap:fault_carry    must FAIL, a_remap_carry
 *   remap:fault_cfg      must FAIL, RULE3_dstaddr_stable. Nothing
 *                        injected -- the configuration pins move
 *
 ******************************************************************************/

`default_nettype none

module fv_umi_address_remap #(
    parameter CW    = 32,
    parameter AW    = 64,
    parameter DW    = 64,
    parameter IDW   = 16,
    parameter IDSB  = 40,
    parameter NMAPS = 8
) (
    input wire clk
);

    // ----------------------------------------------------------------
    // reset: free, but asserted at time zero
    // ----------------------------------------------------------------
    (* anyseq *) wire nreset;
    reg f_past_exists = 1'b0;
    always @(posedge clk)
        f_past_exists <= 1'b1;
    always @(*)
        if (!f_past_exists)
            assume (!nreset);

    // ----------------------------------------------------------------
    // configuration. Held still unless the hazard row says otherwise.
    // ----------------------------------------------------------------
`ifdef FV_REMAP_FREECFG
    (* anyseq *)  wire [IDW-1:0]       chipid;
    (* anyseq *)  wire [IDW*NMAPS-1:0] old_row_col_address, new_row_col_address;
    (* anyseq *)  wire [AW-1:0]        set_low, set_high, set_offset;
`else
    (* anyconst *) wire [IDW-1:0]       chipid;
    (* anyconst *) wire [IDW*NMAPS-1:0] old_row_col_address, new_row_col_address;
    (* anyconst *) wire [AW-1:0]        set_low, set_high, set_offset;
`endif

    // ----------------------------------------------------------------
    // free stimulus
    // ----------------------------------------------------------------
    (* anyseq *) wire          in_valid;
    (* anyseq *) wire [CW-1:0] in_cmd;
    (* anyseq *) wire [AW-1:0] in_dstaddr;
    (* anyseq *) wire [AW-1:0] in_srcaddr;
    (* anyseq *) wire [DW-1:0] in_data;
    (* anyseq *) wire          out_ready;

    wire          in_ready;
    wire          out_valid;
    wire [CW-1:0] out_cmd;
    wire [AW-1:0] out_dstaddr;
    wire [AW-1:0] out_srcaddr;
    wire [DW-1:0] out_data;

    umi_address_remap #(
        .CW (CW), .AW (AW), .DW (DW), .IDW (IDW),
        .IDSB (IDSB), .NMAPS (NMAPS)
    ) dut (
        .chipid                (chipid),
        .old_row_col_address   (old_row_col_address),
        .new_row_col_address   (new_row_col_address),
        .set_dstaddress_low    (set_low),
        .set_dstaddress_high   (set_high),
        .set_dstaddress_offset (set_offset),
        .umi_in_valid   (in_valid),
        .umi_in_cmd     (in_cmd),
        .umi_in_dstaddr (in_dstaddr),
        .umi_in_srcaddr (in_srcaddr),
        .umi_in_data    (in_data),
        .umi_in_ready   (in_ready),
        .umi_out_valid  (out_valid),
        .umi_out_cmd    (out_cmd),
        .umi_out_dstaddr(out_dstaddr),
        .umi_out_srcaddr(out_srcaddr),
        .umi_out_data   (out_data),
        .umi_out_ready  (out_ready)
    );

    // ----------------------------------------------------------------
    // the input face is constrained legal by the rule list the output
    // face is judged by
    // ----------------------------------------------------------------
    umi_handshake_checker #(
        .CW (CW), .AW (AW), .DW (DW), .ASSUME (1)
    ) env_in (
        .clk (clk), .nreset (nreset),
        .valid (in_valid), .ready (in_ready),
        .cmd (in_cmd), .dstaddr (in_dstaddr),
        .srcaddr (in_srcaddr), .data (in_data)
    );

    // ----------------------------------------------------------------
    // faults corrupt what the laws see, never the DUT
    // ----------------------------------------------------------------
    (* anyseq *) wire f_glitch;

`ifdef FV_FAULT_LOCAL
    // a local packet whose address moves anyway
    wire [AW-1:0] obs_dstaddr = out_dstaddr ^ {{(AW-1){1'b0}}, f_glitch};
`else
    wire [AW-1:0] obs_dstaddr = out_dstaddr;
`endif

`ifdef FV_FAULT_CARRY
    // a payload wire that does not survive the pass-through
    wire [DW-1:0] obs_data = out_data ^ {{(DW-1){1'b0}}, f_glitch};
`else
    wire [DW-1:0] obs_data = out_data;
`endif

    umi_handshake_checker #(
        .CW (CW), .AW (AW), .DW (DW), .ASSUME (0)
    ) chk_out (
        .clk (clk), .nreset (nreset),
        .valid (out_valid), .ready (out_ready),
        .cmd (out_cmd), .dstaddr (obs_dstaddr),
        .srcaddr (out_srcaddr), .data (obs_data)
    );

    // ----------------------------------------------------------------
    // the two laws
    // ----------------------------------------------------------------
    wire local_packet = (in_dstaddr[(IDSB+IDW-1):IDSB] == chipid);

    always @(*) begin
        // a packet already addressed to this chip is not re-routed
        a_remap_local : assert (!local_packet || (obs_dstaddr == in_dstaddr));
        // and nothing but DSTADDR crosses changed
        a_remap_carry : assert ((out_valid == in_valid)
                                && (in_ready == out_ready)
                                && (out_cmd == in_cmd)
                                && (out_srcaddr == in_srcaddr)
                                && (obs_data == in_data));
    end

    // ----------------------------------------------------------------
    // witnesses
    // ----------------------------------------------------------------
`ifdef FORMAL
    always @(*) begin
        c_remap_local  : cover (in_valid & local_packet);
        c_remap_moved  : cover (in_valid & ~local_packet
                                & (obs_dstaddr != in_dstaddr));
        c_remap_offset : cover (in_valid & ~local_packet
                                & (in_dstaddr >= set_low)
                                & (in_dstaddr <= set_high));
        c_remap_beat   : cover (in_valid & out_ready
                                & (in_data != {DW{1'b0}}));
        c_remap_stall  : cover (in_valid & ~out_ready);
    end
`endif

endmodule

`default_nettype wire
