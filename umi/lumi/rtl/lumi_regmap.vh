/*******************************************************************************
 * Copyright 2023 Zero ASIC Corporation
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
 * - LUMI Register Map
 *
 ******************************************************************************/

// registers (addr[7:0]), 32bit aligned
localparam LUMI_CTRL              = 8'h00; // device configuration
localparam LUMI_STATUS            = 8'h04; // device status
localparam LUMI_TXMODE            = 8'h10; // tx operating mode
localparam LUMI_RXMODE            = 8'h14; // rx operating mode
localparam LUMI_CRDTINIT          = 8'h20; // Credit init value
localparam LUMI_CRDTINTRVL        = 8'h24; // Credit update interval
localparam LUMI_REQCRDTSTALLCYC   = 8'h30; // Cycle count of outstanding request transaction and credits are not available
localparam LUMI_RESPCRDTSTALLCYC  = 8'h34; // Cycle count of outstanding response transaction and credits are not available
localparam LUMI_REQCRDTACTIVECYC  = 8'h38; // Cycle count of outstanding request transaction and credits are available
localparam LUMI_RESPCRDTACTIVECYC = 8'h3C; // Cycle count of outstanding response transaction and credits are available
