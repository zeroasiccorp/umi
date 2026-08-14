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
 * Runs the bind example in umi_buffer_checker_bind.sv, which attaches a
 * umi_handshake_checker to each SUMI channel of umi_buffer.
 *
 * The buffer is configured as a skid buffer (MODE=1) and carries one
 * SUMI packet packed {CMD, DSTADDR, SRCADDR, DATA}, MSB first. The
 * sequence offers a beat with the consumer stalled, which fills the
 * buffer and drops in_ready -- the incomplete offer that README 4.2
 * rules 2 and 3 govern -- then drains it. Two runs:
 *
 *   clean (default) : the offer is held stable across the stall, and
 *                     the buffer holds its own output stable in turn.
 *                     Expect: "EXAMPLE PASS", exit 0, no assertion.
 *   +inject         : CMD is changed while the offer is stalled, a
 *                     rule 3 break on the channel THIS TESTBENCH drives.
 *                     Expect: RULE3_cmd_stable reported against
 *                     u_umi_hs_in, and no "EXAMPLE PASS".
 *
 * The inject run is the negative control for the whole example. A clean
 * run alone cannot tell a checker that is silent from one that is not
 * there: comment the two bind directives out and this same +inject run
 * prints "EXAMPLE PASS" and exits zero, with the planted violation
 * unreported. Seeing the bound instance named in the failure is the
 * evidence that the bind survived elaboration and was evaluated.
 *
 * The violation is deliberately planted on the input channel, which the
 * testbench owns. umi_buffer only captures a beat on an accepted cycle,
 * so the corrupted command is never taken in and the output channel
 * stays legal -- u_umi_hs_out is silent in both runs.
 *
 * Run (Verilator, from this directory). Icarus cannot run this example:
 * it does not support bind.
 *   verilator --binary --assert --timing -o tb tb_umi_buffer_bind.sv \
 *             umi_buffer_checker_bind.sv ../rtl/umi_handshake_checker.sv \
 *             ../../umi_buffer/rtl/umi_buffer.v
 *   ./obj_dir/tb                # expect: EXAMPLE PASS, exit 0
 *   ./obj_dir/tb +inject        # expect: RULE3_cmd_stable, exit 1
 ******************************************************************************/

`timescale 1ns / 1ps
`default_nettype none

module tb_umi_buffer_bind;

    localparam CW = 32;
    localparam AW = 64;
    localparam DW = 64;
    localparam PW = CW + AW + AW + DW;   // packed SUMI packet

    reg           clk = 1'b0;
    reg           nreset = 1'b0;

    reg           in_valid = 1'b0;
    reg [CW-1:0]  in_cmd = '0;
    reg [AW-1:0]  in_dstaddr = '0;
    reg [AW-1:0]  in_srcaddr = '0;
    reg [DW-1:0]  in_data = '0;
    wire          in_ready;

    wire          out_valid;
    wire [PW-1:0] out_packet;
    reg           out_ready = 1'b0;

    reg inject = 1'b0;

    always #5 clk = ~clk;

    // the design under test, exactly as shipped. The checkers are not
    // instantiated here: umi_buffer_checker_bind.sv puts them inside.
    umi_buffer #(
        .DW   (PW),
        .MODE (1)
    ) dut (
        .clk       (clk),
        .nreset    (nreset),
        .in_valid  (in_valid),
        .in_data   ({in_cmd, in_dstaddr, in_srcaddr, in_data}),
        .in_ready  (in_ready),
        .out_valid (out_valid),
        .out_data  (out_packet),
        .out_ready (out_ready)
    );

    initial begin
        if ($test$plusargs("inject"))
            inject = 1'b1;

        // reset (both bound checkers: VALID must stay low here)
        repeat (2) @(negedge clk);
        nreset = 1'b1;
        @(negedge clk);

        // offer a beat with the consumer stalled
        in_valid   = 1'b1;
        in_cmd     = 32'h0000_0621;
        in_dstaddr = 64'h0000_0000_1234_5678;
        in_srcaddr = 64'h0000_1100_0000_0000;
        in_data    = 64'hDEAD_BEEF_CAFE_F00D;
        out_ready  = 1'b0;

        // let the skid buffer fill until it stops accepting
        while (in_ready !== 1'b0)
            @(negedge clk);

        // one more edge, so the checker has recorded the stalled offer
        // it will compare the next beat against
        @(negedge clk);

        // mid-stall: the injected violation changes CMD while waiting
        if (inject)
            in_cmd = 32'h0000_0721;
        @(negedge clk);

        // the consumer wakes up and drains the buffer
        out_ready = 1'b1;
        repeat (4) @(negedge clk);

        // stop offering, then let the last beats leave
        in_valid = 1'b0;
        repeat (4) @(negedge clk);

        $display("EXAMPLE PASS: umi_buffer and its driver kept README 4.2, bound checkers silent");
        $finish;
    end

endmodule

`default_nettype wire
