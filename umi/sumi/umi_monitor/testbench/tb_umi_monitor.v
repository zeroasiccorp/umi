/*******************************************************************************
 * Testbench: tb_umi_monitor
 *
 * Drives a sequence of UMI transactions through umi_monitor and verifies
 * that the beat output pulses correctly and the simulation display
 * prints the expected opcode names.
 *
 ******************************************************************************/

`timescale 1ns / 1ps

module tb_umi_monitor;

`include "umi_messages.vh"

   localparam CW = 32;
   localparam AW = 64;
   localparam DW = 128;

   //##################################
   // Clock and Reset
   //##################################

   reg clk;
   reg nreset;

   initial begin
      clk = 1'b0;
      forever #0.5 clk = ~clk;
   end

   //##################################
   // UMI bus signals
   //##################################

   reg              valid;
   reg              ready;
   reg [CW-1:0]     cmd;
   reg [AW-1:0]     dstaddr;
   reg [AW-1:0]     srcaddr;
   reg [DW-1:0]     data;
   wire             beat;

   //##################################
   // DUT
   //##################################

   umi_monitor #(.CW(CW),
              .AW(AW),
              .DW(DW))
   dut (.clk     (clk),
        .nreset  (nreset),
        .valid   (valid),
        .ready   (ready),
        .cmd     (cmd),
        .dstaddr (dstaddr),
        .srcaddr (srcaddr),
        .data    (data),
        .beat    (beat));

   //##################################
   // Beat counter
   //##################################

   integer beat_count;

   always @(posedge clk)
     if (beat)
       beat_count <= beat_count + 1;

   //##################################
   // Helper task
   //##################################

   task drive_transaction;
      input [4:0]    opcode;
      input [AW-1:0] dst;
      input [AW-1:0] src;
      input [DW-1:0] d;
      input          rdy;
      begin
         @(posedge clk);
         valid   <= 1'b1;
         ready   <= rdy;
         cmd     <= {27'b0, opcode};
         dstaddr <= dst;
         srcaddr <= src;
         data    <= d;
         @(posedge clk);
         valid   <= 1'b0;
         ready   <= 1'b0;
         cmd     <= {CW{1'b0}};
         dstaddr <= {AW{1'b0}};
         srcaddr <= {AW{1'b0}};
         data    <= {DW{1'b0}};
      end
   endtask

   //##################################
   // Test sequence
   //##################################

   integer errors;

   initial begin
      $timeformat(-9, 0, "ns", 0);
      $dumpfile("tb_umi_monitor.vcd");
      $dumpvars(0, tb_umi_monitor);

      // Init
      valid   = 1'b0;
      ready   = 1'b0;
      cmd     = {CW{1'b0}};
      dstaddr = {AW{1'b0}};
      srcaddr = {AW{1'b0}};
      data    = {DW{1'b0}};
      errors     = 0;
      beat_count = 0;

      // Reset
      nreset = 1'b0;
      repeat (4) @(posedge clk);
      nreset = 1'b1;
      repeat (2) @(posedge clk);

      $display("===========================================");
      $display("  tb_umi_monitor test sequence");
      $display("===========================================");

      // Test 1: REQ_WRITE with valid+ready (beat should fire)
      $display("");
      $display("TEST 1: REQ_WRITE with handshake");
      drive_transaction(
         UMI_REQ_WRITE,
         64'h0000_0000_4100_0000,
         64'h0000_0000_5000_0000,
         128'hDEAD_BEEF_CAFE_BABE_1234_5678_ABCD_EF01,
         1'b1
      );
      @(posedge clk);

      // Test 2: REQ_READ with valid+ready
      $display("");
      $display("TEST 2: REQ_READ with handshake");
      drive_transaction(
         UMI_REQ_READ,
         64'h0000_0000_4100_0100,
         64'h0000_0000_5000_0000,
         128'h0,
         1'b1
      );
      @(posedge clk);

      // Test 3: RESP_READ with valid+ready
      $display("");
      $display("TEST 3: RESP_READ with handshake");
      drive_transaction(
         UMI_RESP_READ,
         64'h0000_0000_5000_0000,
         64'h0000_0000_4100_0100,
         128'hCAFE_BABE_DEAD_BEEF_0000_0000_0000_0000,
         1'b1
      );
      @(posedge clk);

      // Test 4: REQ_POSTED with valid+ready
      $display("");
      $display("TEST 4: REQ_POSTED with handshake");
      drive_transaction(
         UMI_REQ_POSTED,
         64'h0000_0000_3000_0000,
         64'h0000_0000_5000_0000,
         128'h0000_0000_0000_0000_0000_0000_0000_0001,
         1'b1
      );
      @(posedge clk);

      // Test 5: RESP_WRITE with valid+ready
      $display("");
      $display("TEST 5: RESP_WRITE with handshake");
      drive_transaction(
         UMI_RESP_WRITE,
         64'h0000_0000_5000_0000,
         64'h0000_0000_4100_0000,
         128'h0,
         1'b1
      );
      @(posedge clk);

      // Test 6: valid without ready (no beat, no display)
      $display("");
      $display("TEST 6: REQ_WRITE valid but ready=0 (should be silent)");
      drive_transaction(
         UMI_REQ_WRITE,
         64'h0000_0000_4200_0000,
         64'h0000_0000_5000_0000,
         128'hAAAA_BBBB_CCCC_DDDD_EEEE_FFFF_0000_1111,
         1'b0
      );
      @(posedge clk);

      // Test 7: ready without valid (no beat, no display)
      $display("");
      $display("TEST 7: ready=1 but valid=0 (should be silent)");
      @(posedge clk);
      valid <= 1'b0;
      ready <= 1'b1;
      @(posedge clk);
      ready <= 1'b0;
      @(posedge clk);

      // Verify beat count before reset test clears it
      repeat (2) @(posedge clk);

      $display("");
      $display("===========================================");
      if (beat_count == 5) begin
         $display("  PASSED: beat_count=%0d (expected 5)", beat_count);
      end else begin
         $display("  FAILED: beat_count=%0d (expected 5)", beat_count);
         errors = errors + 1;
      end
      $display("===========================================");

      // Test 8: beat during reset (should be silent)
      $display("TEST 8: handshake during reset (should be silent)");
      nreset = 1'b0;
      @(posedge clk);
      drive_transaction(
         UMI_REQ_WRITE,
         64'h0000_0000_4100_0000,
         64'h0000_0000_5000_0000,
         128'h1111_2222_3333_4444_5555_6666_7777_8888,
         1'b1
      );
      nreset = 1'b1;
      repeat (2) @(posedge clk);

      if (errors > 0)
        $display("FAIL: %0d errors", errors);
      else
        $display("PASS");

      $finish;
   end

endmodule
