/*******************************************************************************
 * Self-test for umi_txn_checker in SIMULATION (no formal tools).
 *
 * The testbench drives BOTH channels of one point-to-point SUMI link --
 * the checker is a passive observer of a request/response pair, so no DUT
 * is needed to demonstrate it. It plays one whole transaction: a
 * multi-word READ request, then that request's framed multi-beat response
 * split word-per-beat with EOM only on the closing beat. Two runs:
 *
 *   clean (default) : REQ_RD (SIZE=3, LEN=1 -> 16 bytes, EOM) followed by
 *                     a two-beat RESP_RD: beat1 (first, 8 bytes, EOM=0,
 *                     DA = request SA) then beat2 (continuation, 8 bytes,
 *                     EOM=1, DA = request SA + 8 = the continuation law).
 *                     Expect: "TB PASS", exit 0, no UMI-TXN text.
 *   +inject         : the same transaction, but the CONTINUATION beat's
 *                     DSTADDR is corrupted (breaks the ADDR_i running
 *                     address law -- a TXN_da_cont violation).
 *                     Expect: one UMI-TXN da_cont error, nonzero exit.
 *
 * The verdict is self-checking: for every response beat the tb
 * reconstructs the checker's OWN address verdict from the shadow state the
 * checker publishes on its f_* observation ports (f_first selects the
 * reference -- the first beat checks DA == request SA held in f_e0's DA
 * field, a continuation checks DA == f_next_da, the running address) and
 * compares it against the tb's independent legal/illegal expectation for
 * that beat. Any mismatch prints "TB FAIL" and ends in $fatal.
 *
 * Exit codes gate pass/fail, but the exit code alone cannot distinguish a
 * working checker from a broken one: an inject run whose checker missed
 * the beat also exits nonzero, through the $fatal mismatch path. The
 * caller must ALSO check the output text -- a working inject run prints
 * the UMI-TXN da_cont $error line and no "TB FAIL" line; a missed
 * detection prints "TB FAIL" before the nonzero exit.
 *
 * Run (Icarus, from this directory):
 *   iverilog -g2012 -I ../../include -o tb_umi_txn_checker.vvp \
 *            tb_umi_txn_checker.sv ../rtl/umi_txn_checker.sv
 *   vvp tb_umi_txn_checker.vvp             # expect: TB PASS, exit 0
 *   vvp tb_umi_txn_checker.vvp +inject     # expect: da_cont error, exit 1
 ******************************************************************************/

`timescale 1ns / 1ps
`default_nettype none

module tb_umi_txn_checker;

    localparam CW = 32;
    localparam AW = 64;
    localparam DW = 64;   // 8 bytes/beat: SIZE=3 gives exactly one word/beat

    reg           clk = 1'b0;
    reg           nreset = 1'b0;

    // request channel (observed to learn what responses are owed)
    reg           req_valid = 1'b0;
    reg           req_ready = 1'b0;
    reg [CW-1:0]  req_cmd = '0;
    reg [AW-1:0]  req_dstaddr = '0;
    reg [AW-1:0]  req_srcaddr = '0;
    reg [DW-1:0]  req_data = '0;

    // response channel (checked)
    reg           resp_valid = 1'b0;
    reg           resp_ready = 1'b0;
    reg [CW-1:0]  resp_cmd = '0;
    reg [AW-1:0]  resp_dstaddr = '0;
    reg [AW-1:0]  resp_srcaddr = '0;
    reg [DW-1:0]  resp_data = '0;

    reg inject = 1'b0;
    integer tb_errors = 0;

    always #5 clk = ~clk;

    // the checker's shadow state, taken from its observation PORTS
    wire              tap_first;
    wire [AW-1:0]     tap_next_da;
    wire [AW+43:0]    tap_e0;

    umi_txn_checker #(
        .CW (CW), .AW (AW), .DW (DW)
    ) chk (
        .clk          (clk),
        .nreset       (nreset),
        .req_valid    (req_valid),
        .req_ready    (req_ready),
        .req_cmd      (req_cmd),
        .req_dstaddr  (req_dstaddr),
        .req_srcaddr  (req_srcaddr),
        .req_data     (req_data),
        .resp_valid   (resp_valid),
        .resp_ready   (resp_ready),
        .resp_cmd     (resp_cmd),
        .resp_dstaddr (resp_dstaddr),
        .resp_srcaddr (resp_srcaddr),
        .resp_data    (resp_data),
        // shadow-state observation ports; the three the verdict
        // reconstruction below needs are brought out, the rest are left
        // unconnected as the checker's header prescribes
        .f_occ        (),
        .f_got        (),
        .f_first      (tap_first),
        .f_next_da    (tap_next_da),
        .f_last_cmd   (),
        .f_e0         (tap_e0),
        .f_e1         ()
    );

    // The DA law reference for a response beat is the DA of the oldest
    // tracker entry on the first beat, or f_next_da (the running address)
    // on a continuation. f_e0 packs, from the LSB, {bytes[15:0],
    // da[AW-1:0], hostid[4:0], ex, prot[1:0], qos[3:0], len[7:0],
    // size[2:0], ropc[4:0]}, which puts DA at bit 28.
    wire [AW-1:0] tap_e0_da = tap_e0[AW+27:28];

    // drive one request beat (host->device); pushes a response obligation
    task drive_req(input [CW-1:0] t_cmd,
                   input [AW-1:0] t_da,
                   input [AW-1:0] t_sa,
                   input [DW-1:0] t_data);
        begin
            // entered at a negedge
            req_valid   = 1'b1;
            req_ready   = 1'b1;
            req_cmd     = t_cmd;
            req_dstaddr = t_da;
            req_srcaddr = t_sa;
            req_data    = t_data;
            resp_valid  = 1'b0;
            resp_ready  = 1'b0;
            @(posedge clk);        // the request is sampled / enqueued here
            @(negedge clk);
            req_valid   = 1'b0;
            req_ready   = 1'b0;
        end
    endtask

    // drive one response beat (device->host) and require the checker's own
    // address verdict to match the tb's expectation for this beat
    task drive_resp(input [CW-1:0] t_cmd,
                    input [AW-1:0] t_da,
                    input [AW-1:0] t_sa,
                    input [DW-1:0] t_data,
                    input          t_legal);
        reg [AW-1:0] ref_da;
        reg          beat_ok;
        begin
            // entered at a negedge: the checker's shadow registers still
            // hold the values its NEXT posedge assertion will read
            resp_valid   = 1'b1;
            resp_ready   = 1'b1;
            resp_cmd     = t_cmd;
            resp_dstaddr = t_da;
            resp_srcaddr = t_sa;
            resp_data    = t_data;
            req_valid    = 1'b0;
            req_ready    = 1'b0;
            // reconstruct exactly what the checker's DA rule will decide
            ref_da  = tap_first ? tap_e0_da : tap_next_da;
            beat_ok = (t_da === ref_da);
            if (beat_ok !== t_legal) begin
                tb_errors = tb_errors + 1;
                $display("TB FAIL: response DA verdict mismatch: da=%h ref=%h (%s beat) checker says %s, expected %s",
                         t_da, ref_da, tap_first ? "first" : "cont",
                         beat_ok ? "legal" : "ILLEGAL",
                         t_legal ? "legal" : "ILLEGAL");
            end
            @(posedge clk);        // checker samples the beat and asserts
            @(negedge clk);
            resp_valid   = 1'b0;
            resp_ready   = 1'b0;
        end
    endtask

    initial begin
        if ($test$plusargs("inject"))
            inject = 1'b1;

        // reset: no beats offered, nothing may fire
        repeat (2) @(negedge clk);
        nreset = 1'b1;
        @(negedge clk);

        // REQ_RD SIZE=3 (8 B/word), LEN=1 (2 words = 16 B), EOM. The
        // request SA (0x1000) is the DA the first response beat must copy
        // (README 3.3.1). DA/DATA of a request are not L2 obligations.
        drive_req(32'h0040_0161,
                  64'h0000_0000_2000_0000,
                  64'h0000_0000_0000_1000,
                  64'h0);

        // RESP_RD beat 1 (FIRST): SIZE=3 LEN=0 (8 B), EOM=0 (message not
        // yet closed), DA = request SA = 0x1000.
        drive_resp(32'h0000_0062,
                   64'h0000_0000_0000_1000,
                   64'hFFFF_FFFF_FFFF_FFFF,   // response SA undefined (waived)
                   64'h0123_4567_89AB_CDEF, 1'b1);

        // RESP_RD beat 2 (CONTINUATION, closes): SIZE=3 LEN=0 (8 B),
        // EOM=1, DA = 0x1000 + 8 = 0x1008 (the ADDR_i continuation law).
        // +inject corrupts this DA, breaking the continuation address.
        drive_resp(32'h0040_0062,
                   inject ? 64'hDEAD_BEEF_0000_0000 : 64'h0000_0000_0000_1008,
                   64'hFFFF_FFFF_FFFF_FFFF,
                   64'hFEDC_BA98_7654_3210,
                   inject ? 1'b0 : 1'b1);

        // idle down
        req_valid  = 1'b0;
        req_ready  = 1'b0;
        resp_valid = 1'b0;
        resp_ready = 1'b0;
        repeat (2) @(negedge clk);

        if (tb_errors != 0) begin
            $display("TB FAIL: %0d verdict mismatch(es) between tb and checker", tb_errors);
            $fatal(0, "tb/checker mismatch");
        end
        if (!inject) begin
            $display("TB PASS: legal request/response transaction, checker silent");
            $finish;
        end
        $display("TB DONE: inject run complete (the UMI-TXN da_cont error above is the expected result)");
        $fatal(0, "expected-violation run: nonzero exit by design");
    end

endmodule

`default_nettype wire
