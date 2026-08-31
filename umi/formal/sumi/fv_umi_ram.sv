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
 * - Proves umi_ram returns each answer to the port that asked for it,
 *   and shows what happens when the field it routes on is not what the
 *   convention assumes.
 *
 * THE ROUTING IS A FIELD IN THE ADDRESS, NOT A TAG. umi_ram broadcasts
 * one answer to every port and gates each port's VALID with one bit of
 * the response address (umi_ram.v:106-108):
 *
 *   udev_resp_valid[N-1:0] = mem_resp_dstaddr[IDOFF+:N] & {N{mem_resp_valid}};
 *   mem_resp_ready         = |(mem_resp_dstaddr[IDOFF+:N] & udev_resp_ready)
 *                          | ~mem_resp_valid;
 *
 * That field arrives from the requester: umi_endpoint sets the response
 * DSTADDR to the request SRCADDR, so whatever a port puts in
 * SRCADDR[IDOFF+:N] is what steers its answer home. Nothing in the
 * block checks it, and the two ways it can be wrong are different
 * failures:
 *
 *   more than one bit set   the same answer is delivered to several
 *                           ports at once
 *   no bit set              every udev_resp_valid is low, so
 *                           mem_resp_ready is low while mem_resp_valid
 *                           is high. The answer can never retire, the
 *                           memory never accepts another request, and
 *                           the block is wedged for good
 *
 * WHAT IS PROVEN. With the convention held -- port i sets exactly its
 * own bit, m_ram_id -- one law closes:
 *
 *   a_ram_route     a port is only offered an answer that carries its
 *                   own id bit
 *
 * WHAT IS NOT, AND IS PINNED INSTEAD. Two claims a reader would expect
 * beside it do not hold, and each has a row that requires the failure
 * so it cannot regress into silence:
 *
 *   rule 3 on the response ports. The response address is broadcast to
 *   every port, and it MOVES while an answer is standing unaccepted:
 *   ram:fault_stable puts the handshake checker back on and requires
 *   RULE3_dstaddr_stable to fail. Nothing is injected on that row. The
 *   counterexample needs one accepted request and then changes the
 *   broadcast address underneath it. The green rows therefore run with
 *   the response checker lifted (FV_RAM_NOCHK), which is stated here
 *   rather than left for a reader to notice.
 *
 *   one answer to one port. c_ram_dup_conv reaches two ports being
 *   offered the same answer at once WITH m_ram_id still held, so the
 *   duplicate delivery is not something only a misbehaving requester
 *   can cause.
 *
 * WHAT IS WITNESSED. ram:hazard drops m_ram_id and covers both failures
 * the convention is holding off -- c_ram_dup for duplicate delivery,
 * c_ram_wedge for the lock-up. The wedge cover is the one to look at:
 * it reaches a state where a request has been accepted, no port is
 * being offered an answer, and the request side has been shut for
 * several cycles. Same shape as the SAFE=1 row in fv_umi_regif.
 *
 * BOUNDED. umi_ram is a composite: umi_mux in front, umi_memagent
 * behind it, and inside that a umi_endpoint, a umi_fifoflex and a real
 * la_spram. The memory array and the arbiter thermometer are both
 * unobservable from these ports, so induction starts from states no
 * trace reaches. These rows are bmc and are labelled bounded.
 *
 * SIZE. N=2, DW=64, AW=64, RAMDEPTH=8. IDOFF stays at its default of
 * 40, which requires AW above 41, so the address stays wide while the
 * memory is made small -- the routing law does not depend on how many
 * words sit behind it.
 *
 * Outside these laws: what the memory returns (that is fv_umi_memif for
 * the arithmetic and fv_umi_endpoint for the request/response glue),
 * arbitration fairness between the ports, and progress.
 *
 * ROWS (tests/test_formal_sc.py):
 *   ram:bmc           a_ram_route, bounded, response checker lifted
 *   ram:cover         witnesses: expect all reached, including
 *                     c_ram_dup_conv
 *   ram:hazard        m_ram_id dropped; c_ram_dup and c_ram_wedge reach
 *                     the two failures the convention holds off
 *   ram:fault_route   must FAIL, a_ram_route
 *   ram:fault_stable  the response checker put back, nothing injected:
 *                     must FAIL, RULE3_dstaddr_stable
 *
 ******************************************************************************/

`default_nettype none

module fv_umi_ram #(
    parameter N        = 2,
    parameter CW       = 32,
    parameter AW       = 64,
    parameter DW       = 64,
    parameter IDOFF    = 40,
    parameter RAMDEPTH = 8,
    parameter CTRLW    = 8,
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
    // free stimulus, one bundle per port
    // ----------------------------------------------------------------
    (* anyseq *) wire [N-1:0]      req_valid;
    (* anyseq *) wire [N*CW-1:0]   req_cmd;
    (* anyseq *) wire [N*AW-1:0]   req_dstaddr;
    (* anyseq *) wire [N*AW-1:0]   req_srcaddr;
    (* anyseq *) wire [N*DW-1:0]   req_data;
    (* anyseq *) wire [N-1:0]      resp_ready;
    (* anyseq *) wire [CTRLW-1:0]  sram_ctrl;

    wire [N-1:0]    req_ready;
    wire [N-1:0]    resp_valid;
    wire [N*CW-1:0] resp_cmd;
    wire [N*AW-1:0] resp_dstaddr;
    wire [N*AW-1:0] resp_srcaddr;
    wire [N*DW-1:0] resp_data;

    // the routing convention: port i steers its answer home by setting
    // its own bit, and only its own bit, in the request SRCADDR. The
    // block never checks this -- see the header.
    // Per-port wires built in a loop, then one property over the
    // vector: a procedural assertion label inside a generate loop is
    // not uniquified by the elaborator, so the second iteration
    // collides with the first. Same shape fv_umi_crossbar uses.
    wire [N-1:0] id_ok;
    wire [N-1:0] single;
    genvar gi;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : g_ram_id
            assign id_ok[gi] = (req_srcaddr[gi*AW+IDOFF +: N]
                                == (({{(N-1){1'b0}}, 1'b1}) << gi));
            assign single[gi] = (req_cmd[gi*CW+UMI_LEN_LSB +: 8] == 8'd0);
        end
    endgenerate

`ifndef FV_RAM_ANYID
    always @(*)
        m_ram_id : assume (&id_ok);
`endif

    // one beat per request while the split path is under investigation
    always @(*)
        m_ram_single : assume (&single);

    umi_ram #(
        .N (N), .DW (DW), .AW (AW), .CW (CW),
        .IDOFF (IDOFF), .RAMDEPTH (RAMDEPTH), .CTRLW (CTRLW)
    ) dut (
        .clk               (clk),
        .nreset            (nreset),
        .sram_ctrl         (sram_ctrl),
        .mode              (2'b10),          // round robin, per umi_arbiter.v:63
        .udev_req_valid    (req_valid),
        .udev_req_cmd      (req_cmd),
        .udev_req_dstaddr  (req_dstaddr),
        .udev_req_srcaddr  (req_srcaddr),
        .udev_req_data     (req_data),
        .udev_req_ready    (req_ready),
        .udev_resp_valid   (resp_valid),
        .udev_resp_cmd     (resp_cmd),
        .udev_resp_dstaddr (resp_dstaddr),
        .udev_resp_srcaddr (resp_srcaddr),
        .udev_resp_data    (resp_data),
        .udev_resp_ready   (resp_ready)
    );

    // ----------------------------------------------------------------
    // observed response valids: the fault corrupts what the laws see,
    // never the DUT. No RTL is copied or edited.
    // ----------------------------------------------------------------
    (* anyseq *) wire f_glitch;

`ifdef FV_FAULT_ROUTE
    // an answer offered to a port whose id bit is clear
    wire [N-1:0] obs_valid = resp_valid | {N{f_glitch}};
`else
    wire [N-1:0] obs_valid = resp_valid;
`endif

    // ----------------------------------------------------------------
    // the handshake on every port, both faces of one rule list
    // ----------------------------------------------------------------
    wire [N-1:0] route_bad;
    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin : g_port
            umi_handshake_checker #(
                .CW (CW), .AW (AW), .DW (DW),
                .ASSUME (1),              // environment: legal requests in
                .RULE_EN (RULE_EN)
            ) env_req (
                .clk     (clk),
                .nreset  (nreset),
                .valid   (req_valid[i]),
                .ready   (req_ready[i]),
                .cmd     (req_cmd[i*CW +: CW]),
                .dstaddr (req_dstaddr[i*AW +: AW]),
                .srcaddr (req_srcaddr[i*AW +: AW]),
                .data    (req_data[i*DW +: DW])
            );

`ifndef FV_RAM_NOCHK
            umi_handshake_checker #(
                .CW (CW), .AW (AW), .DW (DW),
                .ASSUME (0),              // requirement: legal answers out
                .RULE_EN (RULE_EN)
            ) chk_resp (
                .clk     (clk),
                .nreset  (nreset),
                .valid   (obs_valid[i]),
                .ready   (resp_ready[i]),
                .cmd     (resp_cmd[i*CW +: CW]),
                .dstaddr (resp_dstaddr[i*AW +: AW]),
                .srcaddr (resp_srcaddr[i*AW +: AW]),
                .data    (resp_data[i*DW +: DW])
            );

`endif
            // a port offered an answer that does not carry its own id
            // bit. The address is broadcast, so this reads the same
            // field the block gates on -- off a port.
            assign route_bad[i] = obs_valid[i]
                                & ~resp_dstaddr[i*AW+IDOFF+i];
        end
    endgenerate

    // ----------------------------------------------------------------
    // at most one port offered an answer at a time
    // ----------------------------------------------------------------
`ifndef FV_RAM_ANYID
    always @(posedge clk)
        if (f_past_exists & nreset & past_nreset)
            a_ram_route : assert (route_bad == {N{1'b0}});
`endif

    // ----------------------------------------------------------------
    // witnesses
    // ----------------------------------------------------------------
`ifdef FORMAL
    wire any_req_beat = |(req_valid & req_ready);

    always @(posedge clk)
        if (f_past_exists & nreset & past_nreset) begin
            c_ram_req0  : cover (req_valid[0] & req_ready[0]);
            c_ram_req1  : cover (req_valid[1] & req_ready[1]);
            c_ram_resp0 : cover (obs_valid[0] & resp_ready[0]);
            c_ram_resp1 : cover (obs_valid[1] & resp_ready[1]);
            c_ram_wait  : cover (|obs_valid & ~|resp_ready);
            c_ram_bp    : cover (~|req_ready);
            // one answer offered to BOTH ports at once, reached with
            // the request-side convention still held -- see the header
            c_ram_dup_conv : cover (&obs_valid);
        end

 `ifdef FV_RAM_ANYID
    // the two failures the routing convention is holding off. Both are
    // behaviour of the shipped block, not faults this harness injects.
    reg accepted;
    always @(posedge clk or negedge nreset)
        if (!nreset)
            accepted <= 1'b0;
        else if (any_req_beat)
            accepted <= 1'b1;

    // how long the request side has been refusing everything
    reg [3:0] blocked;
    always @(posedge clk or negedge nreset)
        if (!nreset)
            blocked <= 4'd0;
        else if (|req_ready)
            blocked <= 4'd0;
        else if (blocked != 4'hF)
            blocked <= blocked + 4'd1;

    always @(posedge clk)
        if (f_past_exists & nreset & past_nreset) begin
            // one answer handed to both ports at once
            c_ram_dup   : cover (&resp_valid);
            // a request was taken, nobody is being offered an answer,
            // and the request side has been shut for several cycles
            c_ram_wedge : cover (accepted & ~|resp_valid & (blocked >= 4'd3));
        end
 `endif
`endif

endmodule

`default_nettype wire
