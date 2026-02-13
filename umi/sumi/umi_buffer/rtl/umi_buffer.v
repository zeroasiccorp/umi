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
 * - Valid/ready (AXIS rules) data buffer with configurable mode
 * - MODE 0: Combinational bypass (zero latency, no backpressure handling)
 * - MODE 1: Full skid buffer with registered valid/ready and 3-state FSM
 *   (EMPTY, BUSY, FULL) for pipelined backpressure handling
 *
 ******************************************************************************/

module umi_buffer #(
  parameter DW = 32,
  /* MODE == 0: Bypass mode
   * MODE == 1: FULL SKID BUFF */
  parameter MODE = 1
) (
  input clk,
  input nreset,

  // Input stream interface
  input           in_valid,
  input [DW-1:0]  in_data,
  output          in_ready,

  // Output stream interface
  output          out_valid,
  output [DW-1:0] out_data,
  input           out_ready
);

  localparam [1:0] EMPTY  = 2'b00,
                   BUSY   = 2'b01,
                   FULL   = 2'b10;

  //####################################
  // Registers
  //####################################

  reg [DW-1:0] data_st0;
  reg [DW-1:0] data_st1;
  reg [1:0] state;

  reg in_rdy;
  reg out_vld;

  //####################################
  // Wires
  //####################################
  wire data_st0_en;
  wire data_st1_en;
  wire use_skid;

  wire insert;
  wire remove;

  wire load;
  wire flow;
  wire flush;
  wire fill;

  reg [1:0] next_state;

  if (MODE == 0) begin

    // Bypass buffer
    assign out_valid = in_valid;
    assign out_data = in_data;
    assign in_ready = out_ready;

  end else if (MODE == 1) begin

    /* AXIS Valid/Ready signaling rules compliant
     * pipelined SKID buffer implementation. */

    // SKID data register
    always @(posedge clk)
      if (data_st0_en)
        data_st0 <= in_data;

    // Primary data register
    always @(posedge clk)
      if (data_st1_en)
        data_st1 <= use_skid ? data_st0 : in_data;

    assign out_data = data_st1;

    // Registered input ready signal
    always @(posedge clk or negedge nreset)
      if (~nreset)
        in_rdy <= 1'b0;
      else
        in_rdy <= (next_state != FULL);

    assign in_ready = in_rdy;

    // Registered output valid signal
    always @(posedge clk or negedge nreset)
      if (~nreset)
        out_vld <= 1'b0;
      else
        out_vld <= (next_state != EMPTY);

    assign out_valid = out_vld;

    //##################################
    // SKID buffer data path CTRL logic
    //##################################
    assign insert = in_valid & in_ready;
    assign remove = out_valid & out_ready;

    assign load = (state == EMPTY) & insert;
    assign flow = (state == BUSY) & insert & remove;
    assign flush = (state == FULL) & ~insert & remove;
    assign fill = (state == BUSY) & insert & ~remove;

    assign data_st1_en = load | flow | flush;
    assign data_st0_en = fill;
    assign use_skid = flush;

    always @(*) begin
      case (state)
        EMPTY:
          next_state = insert ? BUSY : EMPTY;
        BUSY:
          if (insert & ~remove)
            next_state = FULL;
          else if (~insert & remove)
            next_state = EMPTY;
          else
            next_state = BUSY;
        FULL:
          next_state = remove ? BUSY : FULL;
        default:
          next_state = EMPTY;
      endcase
    end

    always @(posedge clk or negedge nreset)
      if (~nreset)
        state <= EMPTY;
      else
        state <= next_state;

  end

endmodule
