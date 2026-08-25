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
 * - Proves umi_regif answers a register request with the right kind of
 *   response and keeps the SUMI handshake on the response channel --
 *   and shows where that second claim stops holding.
 *
 * THE TWO ARMS ARE DIFFERENT CIRCUITS. umi_regif builds its request
 * ready two ways (umi_regif.v:117-121):
 *
 *   SAFE=0   udev_req_ready = reg_ready & (udev_resp_ready | ~udev_resp_valid)
 *   SAFE=1   udev_req_ready = reg_ready & udev_req_safe_ready
 *
 * The SAFE=0 form refuses a new request unless the response channel is
 * free or is being drained this cycle, so a response is never replaced
 * before it is taken. That arm is proven here: the response channel
 * satisfies README.md section 4.2 rules 2 and 3.
 *
 * The SAFE=1 form deliberately breaks the combinational path from
 * udev_resp_ready back to udev_req_ready -- the block header explains
 * why, it is there to keep integrators out of combinational loops --
 * and replaces it with a one-cycle stall register
 * (umi_regif.v:107-113). That register does not know whether the
 * previous response was accepted. So a second request can be taken
 * while the first response is still standing, and the response payload
 * is then overwritten under an offer nobody has accepted.
 *
 * This harness does not assert that away and does not paper over it.
 * The SAFE=0 arm carries the handshake proof. SAFE=1 gets two rows: a
 * hazard row that reaches the overwrite and produces the trace
 * (c_regif_overwrite), and a fault row that leaves the accounting law
 * in and requires it to FAIL on a_regif_outstanding. The second is
 * there so the finding cannot quietly go away: if a later change makes
 * SAFE=1 hold the law, that row goes green and the lane reports it.
 *
 * SAFE defaults to 1 (umi_regif.v:43), so the hazard row is the
 * configuration an integrator gets without asking.
 *
 * WHAT IS PROVEN, both arms unless noted:
 *   RULE2_valid_hold / RULE3_*_stable   the response channel
 *                     (SAFE=0 only -- see above)
 *   a_regif_kind      a read is answered RESP_READ and a write
 *                     RESP_WRITE, per README 3.4.11 and 3.4.12
 *   a_regif_outstanding  the block holds at most one answer, and holds
 *                     one exactly while VALID is high. This is the
 *                     accounting law, and the one SAFE=1 breaks
 *   a_regif_no_invent a posted write raises no response at all
 *                     (README 3.4.4)
 *
 * The register-side outputs (reg_write, reg_read, reg_addr, reg_wdata)
 * are single assigns off the request word, and asserting each against
 * its own expression would be the code read back, so they are not
 * asserted. What is asserted is the part that is not a restatement:
 * a_regif_no_invent, which says a posted write leaves the response side
 * quiet, and a_regif_outstanding, an accounting law over time.
 *
 * Outside these laws: the register file behind the interface, error
 * propagation from reg_err, and the group-address decode.
 *
 * ROWS (tests/sumi/test_formal_sc.py):
 *   regif:prove            SAFE=0, all laws, unbounded
 *   regif:cover            witnesses: expect all reached
 *   regif:hazard           SAFE=1, response checker and the accounting
 *                          law both lifted; the overwrite is witnessed
 *                          by c_regif_overwrite
 *   regif:fault_safe       SAFE=1 with the accounting law LEFT IN --
 *                          must FAIL on a_regif_outstanding. The
 *                          shipped default configuration is the fault
 *                          here; nothing is injected. This row is what
 *                          stops the finding regressing silently
 *   regif:fault_valid      must FAIL, chk_resp.RULE2_valid_hold
 *   regif:fault_kind       must FAIL, a_regif_kind_wr (the xor
 *                          swaps the two response opcodes, so either
 *                          half of the kind law can catch it)
 *   regif:fault_posted     must FAIL, a_regif_no_invent
 *
 ******************************************************************************/

`default_nettype none

module fv_umi_regif #(
    parameter RW   = 32,
    parameter RAW  = 32,
    parameter SAFE = 0,
    parameter CW   = 32,
    parameter AW   = 64,
    parameter DW   = 64,
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
    (* anyseq *) wire [RW-1:0] reg_rdata;
    (* anyseq *) wire [1:0]    reg_err;
    (* anyseq *) wire          reg_ready;

    wire          req_ready;
    wire          resp_valid;
    wire [CW-1:0] resp_cmd;
    wire [AW-1:0] resp_dstaddr;
    wire [AW-1:0] resp_srcaddr;
    wire [DW-1:0] resp_data;
    wire          reg_write;
    wire          reg_read;
    wire [RAW-1:0] reg_addr;
    wire [RW-1:0] reg_wdata;
    wire [1:0]    reg_prot;

    umi_regif #(
        .RW (RW), .RAW (RAW), .SAFE (SAFE),
        .CW (CW), .AW (AW), .DW (DW)
    ) dut (
        .clk             (clk),
        .nreset          (nreset),
        .udev_req_valid  (req_valid),
        .udev_req_cmd    (req_cmd),
        .udev_req_dstaddr(req_dstaddr),
        .udev_req_srcaddr(req_srcaddr),
        .udev_req_data   (req_data),
        .udev_req_ready  (req_ready),
        .udev_resp_valid (resp_valid),
        .udev_resp_cmd   (resp_cmd),
        .udev_resp_dstaddr(resp_dstaddr),
        .udev_resp_srcaddr(resp_srcaddr),
        .udev_resp_data  (resp_data),
        .udev_resp_ready (resp_ready),
        .reg_write       (reg_write),
        .reg_read        (reg_read),
        .reg_addr        (reg_addr),
        .reg_wdata       (reg_wdata),
        .reg_prot        (reg_prot),
        .reg_rdata       (reg_rdata),
        .reg_err         (reg_err),
        .reg_ready       (reg_ready)
    );

    // ----------------------------------------------------------------
    // the request the device is answering
    // ----------------------------------------------------------------
    wire beat        = req_valid & req_ready;
    wire cmd_read    = (req_cmd[4:0] == UMI_REQ_READ);
    wire cmd_write   = (req_cmd[4:0] == UMI_REQ_WRITE);
    wire cmd_posted  = (req_cmd[4:0] == UMI_REQ_POSTED);
    wire responds    = cmd_read | cmd_write;

    // ----------------------------------------------------------------
    // observed response: the faults corrupt what the laws see, never
    // the DUT. No RTL is copied or edited.
    // ----------------------------------------------------------------
    (* anyseq *) wire f_glitch;

`ifdef FV_FAULT_VALID
    wire obs_valid = resp_valid & ~f_glitch;
`elsif FV_FAULT_POSTED
    // a posted write answered anyway
    reg posted_q;
    always @(posedge clk or negedge nreset)
        if (!nreset)
            posted_q <= 1'b0;
        else
            posted_q <= beat & cmd_posted & f_glitch;
    wire obs_valid = resp_valid | posted_q;
`else
    wire obs_valid = resp_valid;
`endif

`ifdef FV_FAULT_KIND
    // The two response opcodes exchanged: RESP_READ 0x02 and RESP_WRITE
    // 0x04 differ by 0x06, so one constant xor swaps them. Constant on
    // purpose -- a per-cycle flip would move the payload under a
    // standing offer and convict rule 3 before ever reaching the law
    // this row is aimed at.
    wire [CW-1:0] obs_cmd = resp_cmd ^ {{(CW-5){1'b0}}, 5'b00110};
`else
    wire [CW-1:0] obs_cmd = resp_cmd;
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

`ifndef FV_REGIF_NOCHK
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
        .dstaddr (resp_dstaddr),
        .srcaddr (resp_srcaddr),
        .data    (resp_data)
    );
`endif

    // ----------------------------------------------------------------
    // answering the right question
    // ----------------------------------------------------------------
    reg was_read;
    reg was_write;
    always @(posedge clk or negedge nreset)
        if (!nreset) begin
            was_read  <= 1'b0;
            was_write <= 1'b0;
        end else if (beat & responds) begin
            was_read  <= cmd_read;
            was_write <= cmd_write;
        end

    // accounting: an answer for every question, never one more
    localparam KW = 5;
    reg [KW-1:0] asked;
    reg [KW-1:0] answered;
    always @(posedge clk or negedge nreset)
        if (!nreset) begin
            asked    <= {KW{1'b0}};
            answered <= {KW{1'b0}};
        end else begin
            if (beat & responds)
                asked <= asked + {{(KW-1){1'b0}}, 1'b1};
            if (resp_valid & resp_ready)
                answered <= answered + {{(KW-1){1'b0}}, 1'b1};
        end

    // Outstanding answers, and the law that makes the accounting
    // inductive. "answered never exceeds asked" is true but NOT
    // inductive -- the counters wrap, so the step case may start from
    // answered ahead of asked and the induction fails while the base
    // case passes. The exact form below closes: the block holds at most
    // one answer, and it is holding one exactly while VALID is high.
    // In SAFE=1 this is also the law the overwrite breaks -- a second
    // request is taken while the first answer still stands, so the
    // count goes to two while VALID says one.
    wire [KW-1:0] outstanding = asked - answered;

    always @(posedge clk)
        if (f_past_exists & nreset & past_nreset) begin
            // a read is answered RESP_READ, a write RESP_WRITE
            if (obs_valid & was_read)
                a_regif_kind : assert (obs_cmd[4:0] == UMI_RESP_READ);
            if (obs_valid & was_write & !was_read)
                a_regif_kind_wr : assert (obs_cmd[4:0] == UMI_RESP_WRITE);
`ifndef FV_REGIF_HAZARD
            a_regif_outstanding : assert (outstanding
                                          == {{(KW-1){1'b0}}, resp_valid});
`endif
        end

    // the posted-write law, stated where it can be seen: after a beat
    // that carried a posted write and nothing else is outstanding, the
    // response channel must stay quiet
    reg posted_only;
    always @(posedge clk or negedge nreset)
        if (!nreset)
            posted_only <= 1'b0;
        else
            posted_only <= beat & cmd_posted & ~resp_valid;

    always @(posedge clk)
        if (f_past_exists & nreset & past_nreset & posted_only)
            a_regif_no_invent : assert (~obs_valid);

    // ----------------------------------------------------------------
    // witnesses
    // ----------------------------------------------------------------
`ifdef FORMAL
    always @(posedge clk)
        if (f_past_exists & nreset & past_nreset) begin
            c_regif_read   : cover (obs_valid & was_read);
            c_regif_write  : cover (obs_valid & was_write & !was_read);
            c_regif_xfer   : cover (obs_valid & resp_ready);
            c_regif_wait   : cover (obs_valid & ~resp_ready);
            c_regif_posted : cover (beat & cmd_posted);
            c_regif_bp     : cover (~req_ready);
        end

 `ifdef FV_REGIF_HAZARD
    // SAFE=1 only: the response payload replaced while the previous
    // answer is still standing unaccepted. Reaching this is the whole
    // point of the row -- it is the trace an integrator needs.
    reg        rv_q;
    reg        rr_q;
    reg [AW-1:0] rsa_q;
    always @(posedge clk) begin
        rv_q  <= resp_valid;
        rr_q  <= resp_ready;
        rsa_q <= resp_srcaddr;
    end

    always @(posedge clk)
        if (f_past_exists & nreset & past_nreset)
            c_regif_overwrite : cover (rv_q & ~rr_q & resp_valid
                                       & (resp_srcaddr != rsa_q));
 `endif
`endif

endmodule

`default_nettype wire
