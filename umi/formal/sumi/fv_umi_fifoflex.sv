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
 * - Proves umi_fifoflex neither invents nor loses payload while it
 *   changes the width of a UMI stream, and keeps the SUMI handshake on
 *   both faces while doing it.
 *
 * WHAT A WIDTH CONVERTER CAN GET WRONG. Every other carriage proof in
 * this directory tracks a beat: the beat that went in is the beat that
 * comes out. That question does not survive a width change -- one beat
 * in is not one beat out, so there is no beat to track. What is
 * conserved is BYTES, and that is what these rows count:
 *
 *   a_flex_conserve  bytes delivered never exceed bytes accepted, so
 *                    nothing is invented
 *   a_flex_bounded   bytes accepted and not yet delivered stay within
 *                    the storage the block actually has, so nothing
 *                    silently piles up
 *
 * Bytes come from the command word the specification defines them in:
 * (LEN+1) << SIZE, per README 3.3.2 and 3.3.3, computed the same way on
 * both faces from CW fields alone. Nothing in the DUT is copied to do
 * it.
 *
 * BOUNDED, AND NOT BY ACCIDENT. These are bmc rows. A conservation law
 * written over running counters is not inductive: the counters wrap, so
 * the step case may start with delivered already ahead of accepted and
 * the induction fails while the base case passes. The exact in-flight
 * figure would close it, but it lives in latch_bytes and the packet
 * latch (umi_fifoflex.v:271-287), neither of which is a port. Bounded
 * is the honest answer here and the rows say so.
 *
 * THE BLOCK'S OWN LIMITS, ASSUMED RATHER THAN TRIPPED OVER. The header
 * of umi_fifoflex records two things it does not handle, and a harness
 * that ignored them would be reporting the block for doing what it
 * says it does:
 *   - SIZE larger than the output width is out of scope, because the
 *     block does not manipulate SIZE (umi_fifoflex.v:25). m_flex_size
 *     keeps SIZE within the narrower of the two faces.
 *   - a beat is only merged when the merged result does not cross the
 *     output boundary (umi_fifoflex.v:26-27). m_flex_cap keeps each
 *     input beat inside one input word, which is the condition the
 *     block is built for.
 * Both are stated here so a reader can see the shape of the claim
 * rather than infer it.
 *
 * WHAT HOLDS, AND WHAT DOES NOT. The block is three circuits behind one
 * port list (umi_fifoflex.v:263, :410, :462), and they do not all keep
 * the law:
 *
 *   SPLIT=0, IDW == ODW   conservation holds. This is fifoflex:bmc.
 *   IDW  < ODW  (merge)   conservation holds with the splitter on.
 *                         This is fifoflex:bmc_merge.
 *   SPLIT=1               conservation FAILS. fifoflex:fault_split
 *                         requires it to, with nothing injected: the
 *                         block delivers more bytes than it was given,
 *                         because one latched packet is offered and
 *                         accepted more than once. umi_memagent
 *                         instantiates umi_fifoflex with SPLIT=1
 *                         (umi_memagent.v:63-70), so this is the arm in
 *                         use, not a corner nobody builds.
 *
 * THE LENGTH ARITHMETIC IS UNSIGNED. Separately from the above, the
 * split arm computes a beat length as
 *
 *     ((ODW/8 - byte_offset) >> SIZE) - 1        (umi_fifoflex.v:429-431)
 *
 * with no guard on the subtraction. An address whose offset leaves
 * fewer than one SIZE-sized word inside the output word makes the shift
 * yield zero, and the minus one wraps to 255 -- a beat announcing 256
 * words. Such an address is not aligned, so README 3.3.1 already rules
 * it out and m_flex_align assumes it away on the proving rows; the
 * hazard row withdraws that assumption and c_flex_lenblow reaches the
 * wrap. Written down because the guard is one comparison and the
 * failure is silent.
 *
 * Outside these laws: which bytes come out in which order (the byte
 * count does not see a permutation), the async arm (ASYNC=0
 * throughout -- see fv_umi_fifo for why a synchroniser needs a delay
 * model before it means anything), and progress.
 *
 * ROWS (tests/test_formal_sc.py):
 *   fifoflex:bmc          SPLIT=0, IDW == ODW, bounded
 *   fifoflex:bmc_merge    IDW  < ODW, bounded
 *   fifoflex:cover        witnesses: expect all reached
 *   fifoflex:hazard       alignment withdrawn; c_flex_lenblow reaches
 *                         the unsigned wrap in the length arithmetic
 *   fifoflex:fault_valid  must FAIL, chk_out.RULE2_valid_hold
 *   fifoflex:fault_invent must FAIL, a_flex_conserve (injected)
 *   fifoflex:fault_split  must FAIL, a_flex_conserve -- SPLIT=1, and
 *                         nothing is injected
 *
 ******************************************************************************/

`default_nettype none

module fv_umi_fifoflex #(
    parameter CW    = 32,
    parameter AW    = 64,
    parameter IDW   = 64,
    parameter ODW   = 64,
    parameter DEPTH = 2,
    parameter SPLIT = 1,
    parameter [5:0] RULE_EN = 6'h3F
) (
    input wire clk
);

`include "umi_messages.vh"

    // the narrower face decides how much one beat may carry
    localparam MINDW  = (IDW < ODW) ? IDW : ODW;
    localparam MINSZ  = $clog2(MINDW/8);      // largest in-range SIZE
    localparam INCAP  = IDW / 8;              // bytes in one input word
    localparam BW     = 12;                   // byte counters, modulo 4096

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
    (* anyseq *) wire           in_valid;
    (* anyseq *) wire [CW-1:0]  in_cmd;
    (* anyseq *) wire [AW-1:0]  in_dstaddr;
    (* anyseq *) wire [AW-1:0]  in_srcaddr;
    (* anyseq *) wire [IDW-1:0] in_data;
    (* anyseq *) wire           out_ready;

    wire           in_ready;
    wire           out_valid;
    wire [CW-1:0]  out_cmd;
    wire [AW-1:0]  out_dstaddr;
    wire [AW-1:0]  out_srcaddr;
    wire [ODW-1:0] out_data;
    wire           fifo_full;
    wire           fifo_empty;

    umi_fifoflex #(
        .ASYNC (0), .SPLIT (SPLIT), .DEPTH (DEPTH),
        .CW (CW), .AW (AW), .IDW (IDW), .ODW (ODW)
    ) dut (
        .bypass          (1'b0),
        .chaosmode       (1'b0),
        .fifo_full       (fifo_full),
        .fifo_empty      (fifo_empty),
        .umi_in_clk      (clk),
        .umi_in_nreset   (nreset),
        .umi_in_valid    (in_valid),
        .umi_in_cmd      (in_cmd),
        .umi_in_dstaddr  (in_dstaddr),
        .umi_in_srcaddr  (in_srcaddr),
        .umi_in_data     (in_data),
        .umi_in_ready    (in_ready),
        .umi_out_clk     (clk),
        .umi_out_nreset  (nreset),
        .umi_out_valid   (out_valid),
        .umi_out_cmd     (out_cmd),
        .umi_out_dstaddr (out_dstaddr),
        .umi_out_srcaddr (out_srcaddr),
        .umi_out_data    (out_data),
        .umi_out_ready   (out_ready),
        .vdd             (1'b1),
        .vss             (1'b0)
    );

    // ----------------------------------------------------------------
    // bytes, from the command word the specification defines them in
    // ----------------------------------------------------------------
    wire [7:0] in_len   = in_cmd[UMI_LEN_MSB:UMI_LEN_LSB];
    wire [2:0] in_size  = in_cmd[UMI_SIZE_MSB:UMI_SIZE_LSB];
    wire [7:0] out_len  = out_cmd[UMI_LEN_MSB:UMI_LEN_LSB];
    wire [2:0] out_size = out_cmd[UMI_SIZE_MSB:UMI_SIZE_LSB];

    wire [BW-1:0] in_bytes  = ({{(BW-8){1'b0}}, in_len}  + {{(BW-1){1'b0}}, 1'b1})
                              << in_size;
    wire [BW-1:0] out_bytes = ({{(BW-8){1'b0}}, out_len} + {{(BW-1){1'b0}}, 1'b1})
                              << out_size;

    // the block's own stated limits: SIZE inside the narrower face, and
    // one input beat inside one input word. See THE BLOCK'S OWN LIMITS.
    // DA aligned to SIZE, README 3.3.1 -- the same rule
    // umi_cmd_checker enforces as CMD4_da_aligned
    wire [AW-1:0] align_mask = ({{(AW-1){1'b0}}, 1'b1} << in_size)
                             - {{(AW-1){1'b0}}, 1'b1};

    always @(*) begin
        m_flex_size : assume (in_size <= MINSZ[2:0]);
        m_flex_cap  : assume (in_bytes <= INCAP[BW-1:0]);
        m_flex_some : assume (in_bytes != {BW{1'b0}});
`ifndef FV_FLEX_NOALIGN
        m_flex_align : assume ((in_dstaddr & align_mask) == {AW{1'b0}});
`endif
    end

    // ----------------------------------------------------------------
    // observed output: the faults corrupt what the laws see, never the
    // DUT. No RTL is copied or edited.
    // ----------------------------------------------------------------
    (* anyseq *) wire f_glitch;

`ifdef FV_FAULT_VALID
    wire obs_valid = out_valid & ~f_glitch;
`else
    wire obs_valid = out_valid;
`endif

`ifdef FV_FAULT_INVENT
    // one extra byte claimed on every delivered beat
    wire [BW-1:0] obs_bytes = out_bytes + {{(BW-1){1'b0}}, 1'b1};
`else
    wire [BW-1:0] obs_bytes = out_bytes;
`endif

    // ----------------------------------------------------------------
    // the handshake, both faces of one rule list
    // ----------------------------------------------------------------
    umi_handshake_checker #(
        .CW (CW), .AW (AW), .DW (IDW),
        .ASSUME (1),                      // environment: assume legal input
        .RULE_EN (RULE_EN)
    ) env_in (
        .clk     (clk),
        .nreset  (nreset),
        .valid   (in_valid),
        .ready   (in_ready),
        .cmd     (in_cmd),
        .dstaddr (in_dstaddr),
        .srcaddr (in_srcaddr),
        .data    (in_data)
    );

    umi_handshake_checker #(
        .CW (CW), .AW (AW), .DW (ODW),
        .ASSUME (0),                      // requirement: assert legal output
        .RULE_EN (RULE_EN)
    ) chk_out (
        .clk     (clk),
        .nreset  (nreset),
        .valid   (obs_valid),
        .ready   (out_ready),
        .cmd     (out_cmd),
        .dstaddr (out_dstaddr),
        .srcaddr (out_srcaddr),
        .data    (out_data)
    );

    // ----------------------------------------------------------------
    // byte accounting
    // ----------------------------------------------------------------
    wire insert = in_valid  & in_ready;
    wire remove = obs_valid & out_ready;

    reg [BW-1:0] taken;
    reg [BW-1:0] given;
    always @(posedge clk or negedge nreset)
        if (!nreset) begin
            taken <= {BW{1'b0}};
            given <= {BW{1'b0}};
        end else begin
            if (insert)
                taken <= taken + in_bytes;
            if (remove)
                given <= given + obs_bytes;
        end

    // what the block can be holding: the packet latch plus the fifo,
    // each at most one input word wide
    localparam [BW-1:0] HOLD = (DEPTH + 2) * INCAP;

`ifndef FV_FLEX_NOALIGN
    always @(posedge clk)
        if (f_past_exists & nreset & past_nreset) begin
            a_flex_conserve : assert (given <= taken);
            a_flex_bounded  : assert ((taken - given) <= HOLD);
        end
`endif

    // ----------------------------------------------------------------
    // witnesses
    // ----------------------------------------------------------------
`ifdef FORMAL
    always @(posedge clk)
        if (f_past_exists & nreset & past_nreset) begin
            c_flex_in    : cover (insert);
            c_flex_out   : cover (remove);
            c_flex_wait  : cover (obs_valid & ~out_ready);
            c_flex_bp    : cover (~in_ready);
            // payload really does cross, so the laws are not passing on
            // an idle link
            c_flex_move  : cover (given != {BW{1'b0}});
            // and a conversion really happens: a delivered beat that
            // does not carry the same byte count as the one taken
            c_flex_convert : cover (remove & (obs_bytes != in_bytes));
        end

 `ifdef FV_FLEX_NOALIGN
    // Alignment withdrawn. The split arm computes the beat length as
    //   ((ODW/8 - byte_offset) >> SIZE) - 1        (umi_fifoflex.v:429-431)
    // and that subtraction is unsigned. An address whose offset leaves
    // fewer than one SIZE-word inside the output word makes the shift
    // yield zero, so the minus one wraps to 255 and the block emits a
    // beat claiming 256 words. c_flex_lenblow reaches it.
    always @(posedge clk)
        if (f_past_exists & nreset & past_nreset)
            c_flex_lenblow : cover (remove & (obs_bytes > INCAP[BW-1:0]));
 `endif
`endif

endmodule

`default_nettype wire
