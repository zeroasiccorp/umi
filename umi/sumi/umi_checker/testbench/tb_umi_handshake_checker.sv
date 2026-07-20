/*******************************************************************************
 * Self-test for umi_handshake_checker in SIMULATION (no formal tools).
 *
 * The testbench drives one SUMI channel directly -- the checker is a
 * passive observer, so no DUT is needed to demonstrate it. Two runs:
 *
 *   clean (default) : a legal sequence -- reset, a stalled offer held
 *                     stable, completion, a back-to-back beat.
 *                     Expect: "TB PASS", exit 0.
 *   +inject         : same sequence, but CMD is changed in the middle
 *                     of the stall (a rule 3 violation).
 *                     Expect: one UMI-HS RULE3 error, nonzero exit.
 *
 * Run (Verilator):
 *   verilator --binary --assert --timing -o tb tb_umi_handshake_checker.sv \
 *             ../rtl/umi_handshake_checker.sv && ./obj_dir/tb
 *   ./obj_dir/tb +inject     # must report the RULE3 violation
 ******************************************************************************/

`timescale 1ns / 1ps
`default_nettype none

module tb_umi_handshake_checker;

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

    always #5 clk = ~clk;

    umi_handshake_checker #(
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

    initial begin
        if ($test$plusargs("inject"))
            inject = 1'b1;

        // reset (checker: VALID must stay low here)
        repeat (2) @(negedge clk);
        nreset = 1'b1;
        @(negedge clk);

        // offer a beat into backpressure: hold everything (rules 2+3)
        valid   = 1'b1;
        cmd     = 32'h0000_0621;      // an arbitrary, held command
        dstaddr = 64'h0000_0000_1234_5678;
        srcaddr = 64'h0000_1100_0000_0000;
        data    = 64'hDEAD_BEEF_CAFE_F00D;
        ready   = 1'b0;
        @(negedge clk);

        // mid-stall: the injected violation changes CMD while waiting
        if (inject)
            cmd = 32'h0000_0721;
        @(negedge clk);

        // the receiver wakes up; the transaction completes (rule 1)
        ready = 1'b1;
        @(negedge clk);

        // back-to-back second beat, accepted immediately
        cmd  = 32'h0000_0631;
        data = 64'h0123_4567_89AB_CDEF;
        @(negedge clk);

        // idle down
        valid = 1'b0;
        ready = 1'b0;
        repeat (2) @(negedge clk);

        if (!inject)
            $display("TB PASS: legal sequence, checker silent");
        else
            $display("TB DONE: inject run complete (a RULE3 error above is the expected result)");
        $finish;
    end

endmodule

`default_nettype wire
