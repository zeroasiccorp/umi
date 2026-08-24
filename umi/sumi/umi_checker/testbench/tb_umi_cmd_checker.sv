/*******************************************************************************
 * Self-test for umi_cmd_checker in SIMULATION (no formal tools).
 *
 * The testbench drives one SUMI channel directly -- the checker is a
 * passive observer, so no DUT is needed to demonstrate it. Two runs:
 *
 *   clean (default) : legal beats -- write, read, read-response with
 *                     data, atomic, RESP_LINK, REQ_ERROR -- each with
 *                     legal alignment and capacity.
 *                     Expect: "TB PASS", exit 0, no UMI-CMD text.
 *   +inject         : one beat with the reserved opcode 0x19 (a CMD-1
 *                     violation).
 *                     Expect: one UMI-CMD CMD-1 error, nonzero exit.
 *
 * The verdict is self-checking: the tb reads the checker's per-rule
 * dec_*_ok verdict wires hierarchically and compares them against its
 * own expectation for every beat; any mismatch prints "TB FAIL" and
 * ends in $fatal. Exit codes gate pass/fail, but the exit code alone
 * cannot distinguish a working checker from a broken one: an inject
 * run whose checker missed the beat also exits nonzero, through the
 * $fatal mismatch path. The caller must check the output text -- a
 * working inject run prints the UMI-CMD $error line and no "TB FAIL"
 * line; a missed detection prints "TB FAIL" before the nonzero exit.
 *
 * No message printed by this testbench repeats the checker's error text.
 * If it did, the caller's search for that text would match the
 * testbench's own output and the run would pass with the checker silent.
 *
 * Run (Icarus, from this directory):
 *   iverilog -g2012 -I ../../include -o tb_umi_cmd_checker.vvp \
 *            tb_umi_cmd_checker.sv ../rtl/umi_cmd_checker.sv
 *   vvp tb_umi_cmd_checker.vvp             # expect: TB PASS, exit 0
 *   vvp tb_umi_cmd_checker.vvp +inject     # expect: CMD-1 error, exit 1
 ******************************************************************************/

`timescale 1ns / 1ps
`default_nettype none

module tb_umi_cmd_checker;

    localparam CW = 32;
    localparam AW = 64;
    localparam DW = 64;

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

    umi_cmd_checker #(
        .CW (CW), .AW (AW), .DW (DW)
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

    // the checker's own per-rule verdicts, observed hierarchically
    // (CMD6 is parameter-gated off in this instance and not sampled)
    wire beat_ok = chk.dec_cmd1_ok  & chk.dec_cmd2_ok
                 & chk.dec_cmd4a_ok & chk.dec_cmd4b_ok
                 & chk.dec_cmd10_ok & chk.dec_cmd11_ok
                 & chk.dec_cmd12_ok & chk.dec_cmd15_ok
                 & chk.dec_cmd16_ok;

    // drive one beat and require the checker's verdict to match
    task drive_beat(input [CW-1:0] t_cmd,
                    input [AW-1:0] t_da,
                    input [AW-1:0] t_sa,
                    input [DW-1:0] t_data,
                    input          t_legal);
        begin
            valid   = 1'b1;
            ready   = 1'b1;
            cmd     = t_cmd;
            dstaddr = t_da;
            srcaddr = t_sa;
            data    = t_data;
            @(negedge clk);   // the posedge in between samples the beat
            if (beat_ok !== t_legal) begin
                tb_errors = tb_errors + 1;
                $display("TB FAIL: cmd=%h expected %s, checker says %s",
                         t_cmd, t_legal ? "legal" : "ILLEGAL",
                         (beat_ok === 1'b1) ? "legal" : "ILLEGAL");
            end
        end
    endtask

    initial begin
        if ($test$plusargs("inject"))
            inject = 1'b1;

        // reset: no beats offered, nothing may fire
        repeat (2) @(negedge clk);
        nreset = 1'b1;
        @(negedge clk);

        // REQ_WR SIZE=2 LEN=1 (8 bytes: exactly one DW=64 beat), EOM
        drive_beat(32'h0040_0143,
                   64'h0000_0000_1000_0100,
                   64'h0000_0010_0000_1004,
                   64'hDEAD_BEEF_CAFE_F00D, 1'b1);

        // REQ_RD SIZE=1 LEN=0 (no data relevance on a read request)
        drive_beat(32'h0000_0021,
                   64'h0000_0000_1000_0002,
                   64'h0000_0010_0000_1006,
                   64'h0, 1'b1);

        // RESP_RD SIZE=3 LEN=0 with ERR=OK carrying data (SA is
        // undefined on responses -- deliberately unaligned here)
        drive_beat(32'h0000_0062,
                   64'h0000_0000_1000_0108,
                   64'hFFFF_FFFF_FFFF_FFFF,
                   64'h0123_4567_89AB_CDEF, 1'b1);

        // REQ_ATOMIC ADD SIZE=2 (ATYPE rides the LEN field)
        drive_beat(32'h0000_0049,
                   64'h0000_0000_1000_0200,
                   64'h0000_0010_0000_1008,
                   64'h0000_0000_0000_0001, 1'b1);

        // RESP_LINK: CMD-only, no DA/SA/DATA obligations
        drive_beat(32'h0000_000E,
                   64'hAAAA_AAAA_AAAA_AAAA,
                   64'h5555_5555_5555_5555,
                   64'h0, 1'b1);

        // REQ_ERROR: full-byte special, SIZE field 0 by encoding
        drive_beat(32'h0000_000F,
                   64'h0000_0000_1000_0300,
                   64'h0000_0010_0000_100C,
                   64'h0, 1'b1);

        // the injected violation: reserved opcode hole 0x19
        if (inject)
            drive_beat(32'h0000_0019,
                       64'h0000_0000_1000_0400,
                       64'h0000_0010_0000_1010,
                       64'h0, 1'b0);

        // idle down
        valid = 1'b0;
        ready = 1'b0;
        repeat (2) @(negedge clk);

        if (tb_errors != 0) begin
            $display("TB FAIL: %0d mismatch(es) between tb and checker", tb_errors);
            $fatal(0, "tb/checker mismatch");
        end
        if (!inject) begin
            $display("TB PASS: legal sequence, checker silent");
            $finish;
        end
        $display("TB DONE: inject run complete (the checker error above is the expected result)");
        $fatal(0, "expected-violation run: nonzero exit by design");
    end

endmodule

`default_nettype wire
