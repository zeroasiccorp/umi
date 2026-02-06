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
 * Testbench for umi_stream module
 * Tests both device mode and non-device (full duplex) mode
 *
 ******************************************************************************/

`timescale 1ns/1ps

module tb_umi_stream;

   // Parameters
   parameter AW = 64;
   parameter CW = 32;
   parameter DW = 64;
   parameter RW = 32;
   parameter RAW = 32;
   parameter DEPTH = 4;

   // UMI command opcodes (from umi_messages.vh)
   localparam UMI_REQ_READ   = 5'h01;
   localparam UMI_REQ_WRITE  = 5'h03;
   localparam UMI_REQ_POSTED = 5'h05;
   localparam UMI_RESP_READ  = 5'h02;
   localparam UMI_RESP_WRITE = 5'h04;

   // UMI command bit positions
   localparam UMI_EOM_BIT = 22;

   // Clock periods (ns)
   parameter UMI_CLK_PERIOD = 10;
   parameter USI_CLK_PERIOD = 12;

   // Test control
   reg         devicemode;
   reg         umi_nreset;
   reg         umi_clk;
   reg         usi_nreset;
   reg         usi_clk;

   // UMI input interface
   reg         umi_in_valid;
   reg [CW-1:0] umi_in_cmd;
   reg [AW-1:0] umi_in_dstaddr;
   reg [AW-1:0] umi_in_srcaddr;
   reg [DW-1:0] umi_in_data;
   wire        umi_in_ready;

   // UMI output interface
   wire        umi_out_valid;
   wire [CW-1:0] umi_out_cmd;
   wire [AW-1:0] umi_out_dstaddr;
   wire [AW-1:0] umi_out_srcaddr;
   wire [DW-1:0] umi_out_data;
   reg         umi_out_ready;

   // S2MM control interface (for non-device mode)
   reg [AW-1:0] s2mm_dstaddr;
   reg [AW-1:0] s2mm_srcaddr;
   reg [CW-1:0] s2mm_cmd;

   // USI streaming output interface
   wire        usi_out_valid;
   wire        usi_out_last;
   wire [DW-1:0] usi_out_data;
   reg         usi_out_ready;

   // USI streaming input interface
   reg         usi_in_valid;
   reg         usi_in_last;
   reg [DW-1:0] usi_in_data;
   wire        usi_in_ready;

   // Test tracking
   integer     errors;
   integer     test_num;

   //###################################################
   // DUT Instantiation
   //###################################################

   umi_stream #(
      .AW(AW),
      .CW(CW),
      .DW(DW),
      .RW(RW),
      .RAW(RAW),
      .DEPTH(DEPTH)
   ) dut (
      // Operating mode
      .devicemode     (devicemode),
      // UMI interface
      .umi_nreset     (umi_nreset),
      .umi_clk        (umi_clk),
      .umi_in_valid   (umi_in_valid),
      .umi_in_cmd     (umi_in_cmd),
      .umi_in_dstaddr (umi_in_dstaddr),
      .umi_in_srcaddr (umi_in_srcaddr),
      .umi_in_data    (umi_in_data),
      .umi_in_ready   (umi_in_ready),
      .umi_out_valid  (umi_out_valid),
      .umi_out_cmd    (umi_out_cmd),
      .umi_out_dstaddr(umi_out_dstaddr),
      .umi_out_srcaddr(umi_out_srcaddr),
      .umi_out_data   (umi_out_data),
      .umi_out_ready  (umi_out_ready),
      // S2MM control
      .s2mm_dstaddr   (s2mm_dstaddr),
      .s2mm_srcaddr   (s2mm_srcaddr),
      .s2mm_cmd       (s2mm_cmd),
      // USI interface
      .usi_clk        (usi_clk),
      .usi_nreset     (usi_nreset),
      .usi_out_valid  (usi_out_valid),
      .usi_out_last   (usi_out_last),
      .usi_out_data   (usi_out_data),
      .usi_out_ready  (usi_out_ready),
      .usi_in_valid   (usi_in_valid),
      .usi_in_last    (usi_in_last),
      .usi_in_data    (usi_in_data),
      .usi_in_ready   (usi_in_ready)
   );

   //###################################################
   // Clock Generation
   //###################################################

   initial begin
      umi_clk = 1'b0;
      forever #(UMI_CLK_PERIOD/2) umi_clk = ~umi_clk;
   end

   initial begin
      usi_clk = 1'b0;
      forever #(USI_CLK_PERIOD/2) usi_clk = ~usi_clk;
   end

   //###################################################
   // VCD Dump
   //###################################################

   initial begin
      $dumpfile("tb_umi_stream.vcd");
      $dumpvars(0, tb_umi_stream);
   end

   //###################################################
   // Test Tasks
   //###################################################

   // Initialize all signals
   task init_signals;
      begin
         devicemode = 1'b1;
         umi_nreset = 1'b0;
         usi_nreset = 1'b0;
         umi_in_valid = 1'b0;
         umi_in_cmd = {CW{1'b0}};
         umi_in_dstaddr = {AW{1'b0}};
         umi_in_srcaddr = {AW{1'b0}};
         umi_in_data = {DW{1'b0}};
         umi_out_ready = 1'b1;
         s2mm_dstaddr = {AW{1'b0}};
         s2mm_srcaddr = {AW{1'b0}};
         s2mm_cmd = {CW{1'b0}};
         usi_out_ready = 1'b1;
         usi_in_valid = 1'b0;
         usi_in_last = 1'b0;
         usi_in_data = {DW{1'b0}};
         errors = 0;
         test_num = 0;
      end
   endtask

   // Apply reset
   task apply_reset;
      begin
         umi_nreset = 1'b0;
         usi_nreset = 1'b0;
         repeat (10) @(posedge umi_clk);
         umi_nreset = 1'b1;
         usi_nreset = 1'b1;
         repeat (5) @(posedge umi_clk);
      end
   endtask

   // Build UMI command
   function [CW-1:0] build_umi_cmd;
      input [4:0] opcode;
      input [2:0] size;
      input [7:0] len;
      input       eom;
      begin
         build_umi_cmd = {CW{1'b0}};
         build_umi_cmd[4:0] = opcode;
         build_umi_cmd[7:5] = size;
         build_umi_cmd[15:8] = len;
         build_umi_cmd[UMI_EOM_BIT] = eom;
      end
   endfunction

   // Send UMI write transaction (posted or with ack)
   task send_umi_write;
      input        posted;
      input [AW-1:0] dstaddr;
      input [AW-1:0] srcaddr;
      input [DW-1:0] data;
      input        eom;
      begin
         umi_in_valid = 1'b1;
         umi_in_cmd = build_umi_cmd(posted ? UMI_REQ_POSTED : UMI_REQ_WRITE, 3'd3, 8'd0, eom);
         umi_in_dstaddr = dstaddr;
         umi_in_srcaddr = srcaddr;
         umi_in_data = data;
         @(posedge umi_clk);
         while (!umi_in_ready) @(posedge umi_clk);
         @(posedge umi_clk);
         umi_in_valid = 1'b0;
      end
   endtask

   // Send UMI read request
   task send_umi_read;
      input [AW-1:0] dstaddr;
      input [AW-1:0] srcaddr;
      integer wait_count;
      begin
         umi_in_valid = 1'b1;
         umi_in_cmd = build_umi_cmd(UMI_REQ_READ, 3'd3, 8'd0, 1'b1);
         umi_in_dstaddr = dstaddr;
         umi_in_srcaddr = srcaddr;
         umi_in_data = {DW{1'b0}};
         wait_count = 0;
         @(posedge umi_clk);
         while (!umi_in_ready) begin
            @(posedge umi_clk);
            wait_count = wait_count + 1;
            if (wait_count == 10)
               $display("DEBUG read: s2mm_empty=%b request_stall=%b devicemode=%b cmd_read=%b resp_vld_out=%b",
                        dut.s2mm_fifo_empty, dut.request_stall, devicemode, dut.cmd_read, dut.resp_vld_out);
            if (wait_count > 50) begin
               $display("ERROR: Timeout in send_umi_read, umi_in_ready stuck low");
               umi_in_valid = 1'b0;
               disable send_umi_read;
            end
         end
         @(posedge umi_clk);
         umi_in_valid = 1'b0;
      end
   endtask

   // Wait for and check UMI response
   task wait_umi_response;
      input [4:0]   expected_opcode;
      input [DW-1:0] expected_data;
      integer       timeout;
      begin
         timeout = 0;
         while (!umi_out_valid && timeout < 100) begin
            @(posedge umi_clk);
            timeout = timeout + 1;
         end
         if (timeout >= 100) begin
            $display("ERROR: Timeout waiting for UMI response");
            errors = errors + 1;
         end else begin
            if (umi_out_cmd[4:0] !== expected_opcode) begin
               $display("ERROR: Expected opcode %h, got %h", expected_opcode, umi_out_cmd[4:0]);
               errors = errors + 1;
            end
            if (expected_data !== {DW{1'bx}} && umi_out_data !== expected_data) begin
               $display("ERROR: Expected data %h, got %h", expected_data, umi_out_data);
               errors = errors + 1;
            end
            @(posedge umi_clk);
         end
      end
   endtask

   // Send streaming data to S2MM FIFO (from stream side)
   task send_usi_data;
      input [DW-1:0] data;
      input         last;
      integer wait_count;
      begin
         usi_in_valid = 1'b1;
         usi_in_data = data;
         usi_in_last = last;
         wait_count = 0;
         @(posedge usi_clk);
         while (!usi_in_ready) begin
            @(posedge usi_clk);
            wait_count = wait_count + 1;
            if (wait_count == 10)
               $display("DEBUG send_usi: s2mm_full=%b usi_in_ready=%b", dut.s2mm_fifo_full, usi_in_ready);
            if (wait_count > 50) begin
               $display("ERROR: Timeout in send_usi_data, s2mm FIFO full?");
               usi_in_valid = 1'b0;
               disable send_usi_data;
            end
         end
         @(posedge usi_clk);
         usi_in_valid = 1'b0;
         usi_in_last = 1'b0;
      end
   endtask

   // Wait for and check streaming output from MM2S
   task wait_usi_data;
      input [DW-1:0] expected_data;
      input         expected_last;
      integer       timeout;
      begin
         timeout = 0;
         while (!usi_out_valid && timeout < 100) begin
            @(posedge usi_clk);
            timeout = timeout + 1;
         end
         if (timeout >= 100) begin
            $display("ERROR: Timeout waiting for USI data");
            errors = errors + 1;
         end else begin
            if (usi_out_data !== expected_data) begin
               $display("ERROR: Expected USI data %h, got %h", expected_data, usi_out_data);
               errors = errors + 1;
            end
            if (usi_out_last !== expected_last) begin
               $display("ERROR: Expected USI last %b, got %b", expected_last, usi_out_last);
               errors = errors + 1;
            end
            @(posedge usi_clk);
         end
      end
   endtask

   //###################################################
   // Main Test Sequence
   //###################################################

   initial begin
      $display("========================================");
      $display("Starting umi_stream testbench");
      $display("========================================");

      init_signals();
      apply_reset();

      //--------------------------------------------
      // Test 1: Device Mode - Posted Write to Stream
      //--------------------------------------------
      test_num = 1;
      $display("\nTest %0d: Device Mode - Posted Write", test_num);

      devicemode = 1'b1;

      send_umi_write(1'b1, 64'h1000, 64'h2000, 64'hDEADBEEF_CAFEBABE, 1'b1);
      wait_usi_data(64'hDEADBEEF_CAFEBABE, 1'b1);

      if (errors == 0) $display("Test %0d PASSED", test_num);
      else $display("Test %0d FAILED", test_num);

      repeat (20) @(posedge umi_clk);

      //--------------------------------------------
      // Test 2: Device Mode - Write with Ack
      //--------------------------------------------
      test_num = 2;
      errors = 0;
      $display("\nTest %0d: Device Mode - Write with Ack", test_num);

      send_umi_write(1'b0, 64'h3000, 64'h4000, 64'h12345678_AABBCCDD, 1'b0);
      wait_umi_response(UMI_RESP_WRITE, {DW{1'bx}});
      wait_usi_data(64'h12345678_AABBCCDD, 1'b0);

      if (errors == 0) $display("Test %0d PASSED", test_num);
      else $display("Test %0d FAILED", test_num);

      repeat (20) @(posedge umi_clk);

      //--------------------------------------------
      // Test 3: Device Mode - Read from S2MM FIFO
      //--------------------------------------------
      test_num = 3;
      errors = 0;
      $display("\nTest %0d: Device Mode - Read Request", test_num);

      // Push data into S2MM FIFO from streaming side
      send_usi_data(64'hFEEDFACE_BEEFCAFE, 1'b1);
      repeat (20) @(posedge umi_clk);

      // Send read request - will read the data we just pushed
      send_umi_read(64'h5000, 64'h6000);
      wait_umi_response(UMI_RESP_READ, 64'hFEEDFACE_BEEFCAFE);

      if (errors == 0) $display("Test %0d PASSED", test_num);
      else $display("Test %0d FAILED", test_num);

      repeat (20) @(posedge umi_clk);

      //--------------------------------------------
      // Test 4: Device Mode - Multiple Posted Writes
      //--------------------------------------------
      test_num = 4;
      errors = 0;
      $display("\nTest %0d: Device Mode - Multiple Posted Writes", test_num);

      send_umi_write(1'b1, 64'h7000, 64'h8000, 64'h1111111111111111, 1'b0);
      wait_usi_data(64'h1111111111111111, 1'b0);

      send_umi_write(1'b1, 64'h7008, 64'h8000, 64'h2222222222222222, 1'b0);
      wait_usi_data(64'h2222222222222222, 1'b0);

      send_umi_write(1'b1, 64'h7010, 64'h8000, 64'h3333333333333333, 1'b1);
      wait_usi_data(64'h3333333333333333, 1'b1);

      if (errors == 0) $display("Test %0d PASSED", test_num);
      else $display("Test %0d FAILED", test_num);

      repeat (20) @(posedge umi_clk);

      //--------------------------------------------
      // Test 5: Non-Device Mode (Full Duplex)
      //--------------------------------------------
      test_num = 5;
      errors = 0;
      $display("\nTest %0d: Non-Device Mode - Stream to UMI", test_num);

      // Switch to non-device mode
      devicemode = 1'b0;
      repeat (10) @(posedge umi_clk);

      // Setup S2MM control signals for pass-through
      s2mm_cmd = build_umi_cmd(UMI_RESP_READ, 3'd3, 8'd0, 1'b1);
      s2mm_dstaddr = 64'hAAAA_0000;
      s2mm_srcaddr = 64'hBBBB_0000;

      // Send streaming data - should appear on UMI output
      send_usi_data(64'hDDDDDDDD_EEEEEEEE, 1'b1);

      // Wait for data on UMI output
      while (!umi_out_valid) @(posedge umi_clk);

      if (umi_out_data !== 64'hDDDDDDDD_EEEEEEEE) begin
         $display("ERROR: Expected data %h, got %h", 64'hDDDDDDDD_EEEEEEEE, umi_out_data);
         errors = errors + 1;
      end
      if (umi_out_dstaddr !== 64'hAAAA_0000) begin
         $display("ERROR: Expected dstaddr %h, got %h", 64'hAAAA_0000, umi_out_dstaddr);
         errors = errors + 1;
      end
      @(posedge umi_clk);

      if (errors == 0) $display("Test %0d PASSED", test_num);
      else $display("Test %0d FAILED", test_num);

      repeat (20) @(posedge umi_clk);

      //--------------------------------------------
      // Test 6: Non-Device Mode - UMI Write to Stream
      //--------------------------------------------
      test_num = 6;
      errors = 0;
      $display("\nTest %0d: Non-Device Mode - UMI Write to Stream", test_num);

      // Posted writes should still go to stream in non-device mode
      send_umi_write(1'b1, 64'h9000, 64'hA000, 64'hFFFFFFFF_00000000, 1'b1);
      wait_usi_data(64'hFFFFFFFF_00000000, 1'b1);

      if (errors == 0) $display("Test %0d PASSED", test_num);
      else $display("Test %0d FAILED", test_num);

      repeat (20) @(posedge umi_clk);

      //--------------------------------------------
      // Test Summary
      //--------------------------------------------
      $display("\n========================================");
      $display("All tests completed");
      $display("========================================\n");

      $finish;
   end

   //###################################################
   // Timeout watchdog
   //###################################################

   initial begin
      #200000;
      $display("ERROR: Simulation timeout!");
      $finish;
   end

endmodule
