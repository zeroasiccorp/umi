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
 * - Proves umi_endpoint turns a UMI request into the right local memory
 *   operation, answers it with the right response, and keeps the SUMI
 *   handshake on the response channel while doing so.
 *
 * THE LAWS.
 *   RULE2_valid_hold / RULE3_*_stable  the response channel, with the
 *                     request channel constrained legal by the same
 *                     checker in its ASSUME face
 *   a_ep_mem_onehot0  loc_read, loc_write and loc_atomic never overlap:
 *                     one request drives at most one kind of memory
 *                     operation
 *   a_ep_kind         a read or an atomic is answered RESP_READ, a
 *                     write RESP_WRITE (README 3.4.11, 3.4.12, and the
 *                     RESP_READ-for-atomics rule in 3.4.6)
 *   a_ep_da           the response goes back to the requester: response
 *                     DSTADDR is the SRCADDR of the request that caused
 *                     it (README 3.3.1)
 *   a_ep_sa           and its SRCADDR is that request's DSTADDR
 *   a_ep_outstanding  (REG=0, unbounded) the answers owed are exactly
 *                     what VALID advertises. This is also what enforces
 *                     README 3.4.4: a posted write is not a question,
 *                     so answering one pushes delivered past asked, the
 *                     difference wraps, and the law catches it
 *   a_ep_capacity     (REG=1, bounded) that arm holds two answers and
 *                     only one is a port, so it states capacity, with
 *                     a_ep_backed adding that a standing answer is
 *                     always backed by a request
 *
 * WHAT THE HARNESS READS, AND FROM WHERE. Everything above is taken off
 * ports. The request beat is udev_req_valid & udev_req_ready, both
 * ports. The kind of request is decoded from udev_req_cmd[4:0] against
 * the localparams in umi_messages.vh -- that is the specification's own
 * encoding, not a copy of the block's decoder, and fv_umi_decode
 * already proves umi_decode agrees with it across the legal opcode set.
 * The request is assumed to carry a legal opcode (m_ep_legal) for the
 * same reason fv_umi_decode assumes it: outside that set the four-bit
 * compares inside umi_decode alias, and this harness is not the place
 * that question is asked.
 *
 * WHY THERE IS NO OVERWRITE HERE. umi_regif has a configuration that
 * takes a second request while the first answer still stands
 * (see fv_umi_regif). umi_endpoint cannot: request_stall
 * (umi_endpoint.v:286-288) folds udev_resp_ready back into
 * udev_req_ready, so a standing unaccepted answer stops the request
 * side outright. The accounting laws are what say so, on both arms --
 * nothing is ever answered that was not asked, and nothing asked is
 * dropped to make room.
 *
 * A cycle-local "a posted write leaves the response side quiet" law was
 * written first and removed. It is wrong on REG=1 -- an answer already
 * in the pipeline stage can surface a cycle after a posted beat, with
 * nothing amiss -- and on REG=0 it says nothing the accounting law does
 * not already say. Two reasons to drop it, and neither is visible
 * without running it.
 *
 * The register-side outputs that are single assigns off the request
 * word -- loc_addr, loc_wrdata -- are not asserted against their own
 * expressions, which would be the code read back. What is asserted
 * about the memory side is the part that is not a restatement:
 * a_ep_mem_onehot0.
 *
 * Outside these laws: the memory behind loc_*, error propagation, the
 * atomic arithmetic (that is fv_umi_memif), and multi-beat requests --
 * the harness holds LEN at zero, so every request here is one beat.
 *
 * ROWS (tests/sumi/test_formal_sc.py):
 *   endpoint:prove         REG=0, all laws, unbounded
 *   endpoint:bmc_reg       REG=1, BOUNDED -- the second answer sits in
 *                          a pipeline stage no port shows, so the exact
 *                          count is not expressible and a bare bound on
 *                          wrapping counters does not close by induction
 *   endpoint:cover         witnesses: expect all reached
 *   endpoint:fault_valid   must FAIL, chk_resp.RULE2_valid_hold
 *   endpoint:fault_kind    must FAIL, a_ep_kind_wr (the xor swaps
 *                          the two response opcodes, so either half
 *                          of the kind law can catch it)
 *   endpoint:fault_da      must FAIL, a_ep_da
 *   endpoint:fault_posted  must FAIL, a_ep_outstanding -- a posted
 *                          write given a reply
 *   endpoint:fault_cap     REG=1 with the REG=0 accounting law forced
 *                          on -- must FAIL, a_ep_outstanding. Nothing
 *                          is injected: the two arms really do hold
 *                          different numbers of answers, and this row
 *                          keeps that written down
 *
 ******************************************************************************/

`default_nettype none

module fv_umi_endpoint #(
    parameter REG = 0,
    parameter CW  = 32,
    parameter AW  = 64,
    parameter DW  = 64,
    parameter [5:0] RULE_EN = 6'h3F
) (
    input wire clk
);

`include "umi_messages.vh"

    // ----------------------------------------------------------------
    // reset: free, but asserted at time zero (grounds all history)
    // ----------------------------------------------------------------
    (* anyseq *) wire nreset;
    reg f_past_exists = 1'b0;
    always @(posedge clk)
        f_past_exists <= 1'b1;
    always @(*)
        if (!f_past_exists)
            assume (!nreset);

    reg past_nreset = 1'b0;
    always @(posedge clk)
        past_nreset <= nreset;

    // ----------------------------------------------------------------
    // free stimulus
    // ----------------------------------------------------------------
    (* anyseq *) wire          req_valid;
    (* anyseq *) wire [CW-1:0] req_cmd;
    (* anyseq *) wire [AW-1:0] req_dstaddr;
    (* anyseq *) wire [AW-1:0] req_srcaddr;
    (* anyseq *) wire [DW-1:0] req_data;
    (* anyseq *) wire          resp_ready;
    (* anyseq *) wire [DW-1:0] loc_rddata;
    (* anyseq *) wire          loc_ready;

    wire          req_ready;
    wire          resp_valid;
    wire [CW-1:0] resp_cmd;
    wire [AW-1:0] resp_dstaddr;
    wire [AW-1:0] resp_srcaddr;
    wire [DW-1:0] resp_data;
    wire [AW-1:0] loc_addr;
    wire          loc_write;
    wire          loc_read;
    wire          loc_atomic;
    wire [7:0]    loc_opcode;
    wire [2:0]    loc_size;
    wire [7:0]    loc_len;
    wire [7:0]    loc_atype;
    wire [DW-1:0] loc_wrdata;

    // ----------------------------------------------------------------
    // the request, decoded from the specification's own encoding
    // ----------------------------------------------------------------
    wire [4:0] req_opcode = req_cmd[4:0];
    wire cmd_read   = (req_opcode == UMI_REQ_READ);
    wire cmd_write  = (req_opcode == UMI_REQ_WRITE);
    wire cmd_posted = (req_opcode == UMI_REQ_POSTED);
    wire cmd_atomic = (req_opcode == UMI_REQ_ATOMIC);

    // the five request kinds this block acts on, plus INVALID so the
    // quiet case is explored. Outside the legal set umi_decode's
    // four-bit compares alias, which is fv_umi_decode's question.
    wire req_legal = cmd_read | cmd_write | cmd_posted | cmd_atomic
                   | (req_cmd[7:0] == UMI_INVALID);

    always @(*) begin
        m_ep_legal : assume (req_legal);
        // one beat per request: multi-beat framing is the transaction
        // checker's subject, not this block's
        m_ep_single : assume (req_cmd[UMI_LEN_MSB:UMI_LEN_LSB] == 8'd0);
    end

    umi_endpoint #(
        .REG (REG), .CW (CW), .AW (AW), .DW (DW)
    ) dut (
        .nreset           (nreset),
        .clk              (clk),
        .udev_req_valid   (req_valid),
        .udev_req_cmd     (req_cmd),
        .udev_req_dstaddr (req_dstaddr),
        .udev_req_srcaddr (req_srcaddr),
        .udev_req_data    (req_data),
        .udev_req_ready   (req_ready),
        .udev_resp_valid  (resp_valid),
        .udev_resp_cmd    (resp_cmd),
        .udev_resp_dstaddr(resp_dstaddr),
        .udev_resp_srcaddr(resp_srcaddr),
        .udev_resp_data   (resp_data),
        .udev_resp_ready  (resp_ready),
        .loc_addr         (loc_addr),
        .loc_write        (loc_write),
        .loc_read         (loc_read),
        .loc_atomic       (loc_atomic),
        .loc_opcode       (loc_opcode),
        .loc_size         (loc_size),
        .loc_len          (loc_len),
        .loc_atype        (loc_atype),
        .loc_wrdata       (loc_wrdata),
        .loc_rddata       (loc_rddata),
        .loc_ready        (loc_ready)
    );

    // ----------------------------------------------------------------
    // observed response: the faults corrupt what the laws see, never
    // the DUT. No RTL is copied or edited.
    // ----------------------------------------------------------------
    (* anyseq *) wire f_glitch;

    // Two separate observation paths, so a fault can reach only the law
    // it is aimed at. obs_valid is what the handshake checker sees;
    // acct_valid is what the accounting and the field laws see. Sharing
    // one wire made the VALID fault convict a_ep_sa -- the dropped
    // beats put the answer counter out of step, so the tracked answer
    // pointed at the wrong response long before rule 2 was reached.
`ifdef FV_FAULT_VALID
    wire obs_valid = resp_valid & ~f_glitch;
`else
    wire obs_valid = resp_valid;
`endif

`ifdef FV_FAULT_POSTED
    // a posted write answered anyway
    reg posted_q;
    always @(posedge clk or negedge nreset)
        if (!nreset)
            posted_q <= 1'b0;
        else
            posted_q <= req_valid & req_ready & cmd_posted & f_glitch;
    wire acct_valid = resp_valid | posted_q;
`else
    wire acct_valid = resp_valid;
`endif

`ifdef FV_FAULT_KIND
    // RESP_READ 0x02 and RESP_WRITE 0x04 differ by 0x06, so one
    // constant xor swaps them. Constant on purpose -- a per-cycle flip
    // would move the payload under a standing offer and convict rule 3
    // before reaching the law this row is aimed at.
    wire [CW-1:0] obs_cmd = resp_cmd ^ {{(CW-5){1'b0}}, 5'b00110};
`else
    wire [CW-1:0] obs_cmd = resp_cmd;
`endif

`ifdef FV_FAULT_DA
    // the answer sent somewhere other than back to the requester
    wire [AW-1:0] obs_dstaddr = ~resp_dstaddr;
`else
    wire [AW-1:0] obs_dstaddr = resp_dstaddr;
`endif

    // ----------------------------------------------------------------
    // the two channels
    // ----------------------------------------------------------------
    umi_handshake_checker #(
        .CW (CW), .AW (AW), .DW (DW),
        .ASSUME (1),                      // environment: assume legal input
        .RULE_EN (RULE_EN)
    ) env_req (
        .clk     (clk),
        .nreset  (nreset),
        .valid   (req_valid),
        .ready   (req_ready),
        .cmd     (req_cmd),
        .dstaddr (req_dstaddr),
        .srcaddr (req_srcaddr),
        .data    (req_data)
    );

    umi_handshake_checker #(
        .CW (CW), .AW (AW), .DW (DW),
        .ASSUME (0),                      // requirement: assert legal output
        .RULE_EN (RULE_EN)
    ) chk_resp (
        .clk     (clk),
        .nreset  (nreset),
        .valid   (obs_valid),
        .ready   (resp_ready),
        .cmd     (obs_cmd),
        .dstaddr (obs_dstaddr),
        .srcaddr (resp_srcaddr),
        .data    (resp_data)
    );

    // ----------------------------------------------------------------
    // the request being answered
    // ----------------------------------------------------------------
    wire beat     = req_valid & req_ready;
    wire responds = cmd_read | cmd_write | cmd_atomic;

    // Requests that call for an answer, and answers delivered, both
    // numbered. A single "most recent request" shadow is NOT enough
    // here: the REG=1 arm holds two answers at once, so the newest
    // request does not describe the answer currently being offered.
    // One arbitrary number is tracked instead -- the solver picks it,
    // so proving the tracked answer proves every answer -- which is
    // depth-independent and covers both arms with one set of laws.
    localparam KW = 5;
    localparam CAPACITY = 1 + REG;   // response slots on this arm
    reg [KW-1:0] asked;
    reg [KW-1:0] answered;
    always @(posedge clk or negedge nreset)
        if (!nreset) begin
            asked    <= {KW{1'b0}};
            answered <= {KW{1'b0}};
        end else begin
            if (beat & responds)
                asked <= asked + {{(KW-1){1'b0}}, 1'b1};
            if (acct_valid & resp_ready)
                answered <= answered + {{(KW-1){1'b0}}, 1'b1};
        end

    wire [KW-1:0] outstanding = asked - answered;

    (* anyconst *) wire [KW-1:0] fv_answer;
    reg          exp_read;
    reg          exp_write;
    reg [AW-1:0] exp_da;
    reg [AW-1:0] exp_sa;
    always @(posedge clk)
        if (beat & responds & (asked == fv_answer)) begin
            // an atomic is answered as a read (README 3.4.6)
            exp_read  <= cmd_read | cmd_atomic;
            exp_write <= cmd_write;
            exp_da    <= req_srcaddr;   // back to the requester
            exp_sa    <= req_dstaddr;
        end

    // the answer now being offered carries number `answered`
    wire tracked = (answered == fv_answer);

    // ----------------------------------------------------------------
    // the laws
    // ----------------------------------------------------------------
    always @(*) begin
        // one request, at most one kind of memory operation
        a_ep_mem_onehot0 : assert (({2'b0, loc_read}
                                  + {2'b0, loc_write}
                                  + {2'b0, loc_atomic}) <= 3'd1);
    end

    always @(posedge clk)
        if (f_past_exists & nreset & past_nreset) begin
            if (acct_valid & tracked & exp_read)
                a_ep_kind : assert (obs_cmd[4:0] == UMI_RESP_READ);
            if (acct_valid & tracked & exp_write & ~exp_read)
                a_ep_kind_wr : assert (obs_cmd[4:0] == UMI_RESP_WRITE);
            if (acct_valid & tracked) begin
                a_ep_da : assert (obs_dstaddr == exp_da);
                a_ep_sa : assert (resp_srcaddr == exp_sa);
            end
        end

    // How many answers the block may hold at once, and it is not the
    // same number on both arms. REG=0 has one response slot, so the
    // count is exactly what VALID advertises. REG=1 adds a pipeline
    // stage (umi_endpoint.v:290-307) and can hold two -- one in the
    // stage, one behind it -- and only the outer one is a port, so the
    // exact form is not expressible there and the law states capacity
    // instead. This was not predicted: the exact law was written for
    // both arms and REG=1 failed its base case with a real two-deep
    // trace.
`ifdef FV_EP_EXACT
    // the REG=0 law forced on regardless of arm: on REG=1 it must fail,
    // and the row that requires it to is what stops the two arms
    // quietly becoming one
    always @(posedge clk)
        if (f_past_exists & nreset & past_nreset)
            a_ep_outstanding : assert (outstanding
                                       == {{(KW-1){1'b0}}, acct_valid});
`else
    generate
        if (REG == 0) begin : g_ep_exact
            // One response slot, and it is a port, so the count can be
            // pinned exactly -- which is also what makes it inductive.
            // An answer nobody asked for (a posted write given a reply)
            // pushes delivered past asked, the difference wraps, and
            // this catches it.
            always @(posedge clk)
                if (f_past_exists & nreset & past_nreset)
                    a_ep_outstanding : assert (outstanding
                                               == {{(KW-1){1'b0}},
                                                   acct_valid});
        end else begin : g_ep_pipe
            // REG=1 holds two answers -- one in the pipeline stage, one
            // behind it -- and only the outer one is a port. The exact
            // count is therefore not expressible here, and a bare bound
            // on wrapping counters is not inductive: the step case may
            // start from any pair of counter values. So this arm is
            // BOUNDED, and its row says so.
            always @(posedge clk)
                if (f_past_exists & nreset & past_nreset) begin
                    a_ep_capacity : assert (outstanding
                                            <= CAPACITY[KW-1:0]);
                    a_ep_backed   : assert (~acct_valid
                                            || (outstanding != {KW{1'b0}}));
                end
        end
    endgenerate
`endif

    // ----------------------------------------------------------------
    // witnesses
    // ----------------------------------------------------------------
`ifdef FORMAL
    always @(posedge clk)
        if (f_past_exists & nreset & past_nreset) begin
            c_ep_read    : cover (acct_valid & tracked & exp_read);
            c_ep_write   : cover (acct_valid & tracked & exp_write
                                  & ~exp_read);
            // the tracked answer really is delivered, so the field laws
            // are not passing on an answer that never came
            c_ep_deliver : cover (acct_valid & resp_ready & tracked);
            c_ep_xfer    : cover (obs_valid & resp_ready);
            c_ep_wait    : cover (obs_valid & ~resp_ready);
            c_ep_bp      : cover (~req_ready);
            c_ep_memrd   : cover (loc_read);
            c_ep_memwr   : cover (loc_write);
            c_ep_atomic  : cover (loc_atomic);
            // a posted write really does reach memory without an answer
            c_ep_posted  : cover (beat & cmd_posted & loc_write);
        end
`endif

endmodule

`default_nettype wire
