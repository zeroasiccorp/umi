/*******************************************************************************
 * Self-test for umi_frame_checker in SIMULATION (no formal tools).
 *
 * The testbench drives one SUMI REQUEST channel -- the checker is a
 * passive observer of a single channel, so no DUT is needed to
 * demonstrate it, and a request channel is the case umi_txn_checker
 * leaves unasserted. It plays a single-beat message (which has no
 * intra-message framing and must therefore be ignored) followed by a
 * three-beat REQ_WR message split word-per-beat. Two runs:
 *
 *   clean (default) : the three beats repeat SIZE, opcode, QOS, PROT and
 *                     EOF, and walk DA and SA forward by the eight bytes
 *                     each beat carries. Expect: "TB PASS", exit 0, no
 *                     checker output at all.
 *   +inject         : the same message, but the CLOSING beat carries
 *                     SIZE=2 where the message opened at SIZE=3 -- the
 *                     mid-message SIZE mutation, a FRAME_size_stable
 *                     violation. Expect: one "UMI-FRAME size" error.
 *
 * The mutation is placed on the closing beat on purpose. The running
 * address a beat is judged against is derived from the PREVIOUS beat, so
 * changing SIZE last cannot disturb the address laws, and the byte total
 * only shrinks. Exactly one rule fires, which is what makes the run
 * evidence about that rule rather than about the checker in general.
 *
 * The testbench carries its own reading of README 4.1.1 -- an
 * independent running-address, field-stability and byte-ceiling model,
 * advanced beat by beat -- and every beat declares whether it is meant
 * to be legal. If the model and the declaration disagree the run prints
 * "TB FAIL" and ends in $fatal. That is what stops an injected beat from
 * silently being legal after all: without it, a mutation that turns out
 * not to violate anything would leave the checker correctly silent and
 * the run would look like a missed detection.
 *
 * Exit codes gate pass/fail, but the exit code alone cannot distinguish
 * a working checker from a broken one: the inject run ends in $fatal by
 * design, and a run whose checker missed the beat exits nonzero the same
 * way. The caller must ALSO check the output text -- a working inject
 * run prints the checker's own "UMI-FRAME size" line and no "TB FAIL"
 * line. No message printed by this testbench repeats that text, so the
 * text in the log can only have come from the checker.
 *
 * Run (Icarus, from this directory):
 *   iverilog -g2012 -I ../../include -o tb_umi_frame_checker.vvp \
 *            tb_umi_frame_checker.sv ../rtl/umi_frame_checker.sv
 *   vvp tb_umi_frame_checker.vvp             # expect: TB PASS, exit 0
 *   vvp tb_umi_frame_checker.vvp +inject     # expect: size error, exit 1
 ******************************************************************************/

`timescale 1ns / 1ps
`default_nettype none

module tb_umi_frame_checker;

    localparam CW = 32;
    localparam AW = 64;
    localparam DW = 64;   // 8 bytes/beat: SIZE=3 gives exactly one word/beat

    localparam [31:0] MAX_MSG_BYTES = 32768;

    // command words, REQ_WR (5'h03) with LEN=0, QOS=0, PROT=0, EOF=0.
    // SIZE is bits [7:5] and EOM is bit 22.
    localparam [CW-1:0] CMD_OPEN     = 32'h0000_0063;  // SIZE=3, EOM=0
    localparam [CW-1:0] CMD_CLOSE    = 32'h0040_0063;  // SIZE=3, EOM=1
    localparam [CW-1:0] CMD_CLOSE_S2 = 32'h0040_0043;  // SIZE=2, EOM=1

    reg           clk = 1'b0;
    reg           nreset = 1'b0;
    reg           valid = 1'b0;
    reg           ready = 1'b0;
    reg [CW-1:0]  cmd = '0;
    reg [AW-1:0]  dstaddr = '0;
    reg [AW-1:0]  srcaddr = '0;
    reg [DW-1:0]  data = '0;

    reg inject = 1'b0;
    integer tb_errors = 0;

    always #5 clk = ~clk;

    umi_frame_checker #(
        .CW (CW), .AW (AW), .DW (DW), .MAX_MSG_BYTES (MAX_MSG_BYTES)
    ) chk (
        .clk     (clk),
        .nreset  (nreset),
        .valid   (valid),
        .ready   (ready),
        .cmd     (cmd),
        .dstaddr (dstaddr),
        .srcaddr (srcaddr),
        .data    (data)
    );

    // ----------------------------------------------------------------
    // the testbench's own model of README 4.1.1, advanced independently
    // ----------------------------------------------------------------
    reg           mdl_open = 1'b0;
    reg [CW-1:0]  mdl_first = '0;
    reg [AW-1:0]  mdl_next_da = '0;
    reg [AW-1:0]  mdl_next_sa = '0;
    reg [31:0]    mdl_acc = 32'd0;

    // drive one beat and require the model's verdict to match t_legal
    task drive_beat(input [CW-1:0] t_cmd,
                    input [AW-1:0] t_da,
                    input [AW-1:0] t_sa,
                    input [DW-1:0] t_data,
                    input          t_legal);
        reg [2:0]    t_size;
        reg [7:0]    t_len;
        reg [31:0]   t_bytes;
        reg [AW-1:0] t_bytes_aw;
        reg          beat_ok;
        begin
            // entered at a negedge: the checker's shadow registers still
            // hold the values its NEXT posedge will judge this beat by
            valid   = 1'b1;
            ready   = 1'b1;
            cmd     = t_cmd;
            dstaddr = t_da;
            srcaddr = t_sa;
            data    = t_data;

            t_size     = t_cmd[7:5];
            t_len      = t_cmd[15:8];
            t_bytes    = ({24'd0, t_len} + 32'd1) << t_size;   // README 3.3.2/3.3.3
            t_bytes_aw = {{(AW-32){1'b0}}, t_bytes};

            // a beat that opens a message is unconstrained; a continuation
            // must repeat the fields and land on the running address
            beat_ok = ~mdl_open ? 1'b1
                    : ((t_size        == mdl_first[7:5])
                    &  (t_cmd[4:0]    == mdl_first[4:0])
                    &  (t_cmd[19:16]  == mdl_first[19:16])
                    &  (t_cmd[21:20]  == mdl_first[21:20])
                    &  (t_cmd[23]     == mdl_first[23])
                    &  (t_da          == mdl_next_da)
                    &  (t_sa          == mdl_next_sa)
                    &  ((mdl_acc + t_bytes) <= MAX_MSG_BYTES));

            if (beat_ok !== t_legal) begin
                tb_errors = tb_errors + 1;
                $display("TB FAIL: beat verdict mismatch: cmd=%h da=%h sa=%h (%s beat) model says %s, expected %s",
                         t_cmd, t_da, t_sa, mdl_open ? "cont" : "opening",
                         beat_ok ? "legal" : "ILLEGAL",
                         t_legal ? "legal" : "ILLEGAL");
            end

            @(posedge clk);        // checker samples the beat and judges it

            // advance the model the way the checker advances its shadow:
            // first_cmd is captured from the beat that OPENS a message
            if (!mdl_open)
                mdl_first = t_cmd;
            mdl_open    = ~t_cmd[22];
            mdl_next_da = t_da + t_bytes_aw;
            mdl_next_sa = t_sa + t_bytes_aw;
            mdl_acc     = t_cmd[22] ? 32'd0 : (mdl_acc + t_bytes);

            @(negedge clk);
            valid = 1'b0;
            ready = 1'b0;
        end
    endtask

    initial begin
        if ($test$plusargs("inject"))
            inject = 1'b1;

        // reset: no beats offered
        repeat (2) @(negedge clk);
        nreset = 1'b1;
        @(negedge clk);

        // a message carried in ONE beat: no intra-message framing exists,
        // so nothing here may be judged however the fields fall
        drive_beat(CMD_CLOSE,
                   64'h0000_0000_0000_3000,
                   64'h0000_0000_0000_4000,
                   64'hA5A5_A5A5_A5A5_A5A5, 1'b1);

        // a three-beat message, 8 bytes per beat, opening at SIZE=3
        drive_beat(CMD_OPEN,
                   64'h0000_0000_0000_2000,
                   64'h0000_0000_0000_1000,
                   64'h0011_2233_4455_6677, 1'b1);

        // continuation: DA and SA have both advanced by 8
        drive_beat(CMD_OPEN,
                   64'h0000_0000_0000_2008,
                   64'h0000_0000_0000_1008,
                   64'h8899_AABB_CCDD_EEFF, 1'b1);

        // closing continuation. +inject sends SIZE=2 on a message that
        // opened at SIZE=3; the addresses still follow from the previous
        // beat, so the size rule is the only one that can fire.
        drive_beat(inject ? CMD_CLOSE_S2 : CMD_CLOSE,
                   64'h0000_0000_0000_2010,
                   64'h0000_0000_0000_1010,
                   64'h0F1E_2D3C_4B5A_6978,
                   inject ? 1'b0 : 1'b1);

        // idle down
        valid = 1'b0;
        ready = 1'b0;
        repeat (2) @(negedge clk);

        if (tb_errors != 0) begin
            $display("TB FAIL: %0d verdict mismatch(es) between tb and model", tb_errors);
            $fatal(0, "tb/model mismatch");
        end
        if (!inject) begin
            $display("TB PASS: legal three-beat request message, checker silent");
            $finish;
        end
        $display("TB DONE: inject run complete (the framing error above is the expected result)");
        $fatal(0, "expected-violation run: nonzero exit by design");
    end

endmodule

`default_nettype wire
