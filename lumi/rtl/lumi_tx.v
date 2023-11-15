/******************************************************************************
 * Function:  Link UMI (LUMI) transmit
 * Author:    Amir Volk
 *
 * Copyright (c) 2023 Zero ASIC Corporation. All rights reserved.
 * This code is licensed under Apache License 2.0 (see LICENSE for details)
 *
 * Version history:
 * Version 1 - convert from CLINK to LUMI
 *****************************************************************************/
module lumi_tx
  #(parameter TARGET = "DEFAULT", // implementation target
    // for development only (fixed )
    parameter IOW = 64,           // Lumi rx/tx width (SDR only, DDR is handled in the phy)
    parameter DW = 128,           // umi data width
    parameter CW = 32,            // umi data width
    parameter AW = 64             // address width
    )
   (// ctrl signls
    input             clk,         // clock for driving output data
    input             nreset,      // clk synced async active low reset
    input             csr_en,      // 1=enable outputs
    input             csr_crdt_en, // 1=enable sending updates
    input [7:0]       csr_iowidth, // bus width
    input             vss,         // common ground
    input             vdd,         // core supply
    // Request (read/write)
    input             umi_req_in_valid,
    input [CW-1:0]    umi_req_in_cmd,
    input [AW-1:0]    umi_req_in_dstaddr,
    input [AW-1:0]    umi_req_in_srcaddr,
    input [DW-1:0]    umi_req_in_data,
    output            umi_req_in_ready,
    // Response (write)
    input             umi_resp_in_valid,
    input [CW-1:0]    umi_resp_in_cmd,
    input [AW-1:0]    umi_resp_in_dstaddr,
    input [AW-1:0]    umi_resp_in_srcaddr,
    input [DW-1:0]    umi_resp_in_data,
    output            umi_resp_in_ready,
    // phy interface
    output [IOW-1:0]  phy_txdata,  // Tx data to the phy
    output            phy_txvld,   // valid signal to the phy
    input             ioclk,
    input             ionreset,
    // Credit interface
    output reg [31:0] csr_crdt_status,
    input [15:0]      csr_crdt_intrvl,
    input [15:0]      rmt_crdt_req,
    input [15:0]      rmt_crdt_resp,
    input [15:0]      loc_crdt_req,
    input [15:0]      loc_crdt_resp
    );

   // local state
   reg [(DW+AW+AW+CW)-1:0]   shiftreg;
   reg [(DW+AW+AW+CW)-1:0]   shiftreg_odd;
   wire [DW+AW+AW+CW-1:0]    shiftreg_in;
   wire [DW+AW+AW+CW-1:0]    shiftreg_in_new;
   reg [(DW+AW+AW+CW)/8-1:0] valid;
   reg [(DW+AW+AW+CW)/8-1:0] valid_start_value_req;
   reg [(DW+AW+AW+CW)/8-1:0] valid_start_value_resp;
   wire [(DW+AW+AW+CW)/8-1:0] valid_start_value;

   // local wires
   wire [CW-1:0]             umi_out_cmd;
   wire [CW-1:0]             umi_muxed_cmd;
   wire [AW-1:0]             umi_out_dstaddr;
   wire [AW-1:0]             umi_out_srcaddr;
   wire [DW-1:0]             umi_out_data;
   wire                      umi_out_valid;
   wire                      umi_in_ready;

   wire                      umi_req_in_gated;
   wire                      umi_resp_in_gated;

   wire [10:0]               iowidth;
   wire                      phy_txrdy;
   wire                      phy_fifo_empty;
   wire                      phy_fifo_wr;
   wire                      phy_fifo_full;
   wire                      ionreset_sync;

   // Amir - byterate is used later as shifterd 3 bits to the left so needs 3 more bits than the "pure" value
   wire [$clog2(DW+AW+AW+CW)-1:0] byterate;
   //   wire [$clog2(DW/8)-1:0] byterate;
   wire [(DW+AW+AW+CW)/8-1:0]     bytemask;
   wire [(DW+AW+AW+CW)/8-1:0]     valid_next;

   wire [1:0]                     rxready;
   wire                           umi_req_ready;
   wire                           umi_resp_ready;
   wire                           lumi_txrdy;

   wire                           sample_packet;

   wire                           req_cmd_only;
   wire                           req_no_data;

   wire                           resp_cmd_only;
   wire                           resp_no_data;

   reg [15:0]                     tx_crdt_req;
   reg [15:0]                     tx_crdt_resp;
   reg [2:0]                      shift_reg_type;
   wire [11:0]                    cmd_resp_lenp1;
   wire [11:0]                    cmd_req_lenp1;
   wire [11:0]                    cmd_resp_bytes;
   wire [11:0]                    cmd_req_bytes;
   reg [11:0]                     req_packet_bytes;
   reg [11:0]                     resp_packet_bytes;
   wire [11:0]                    req_packet_lines;
   wire [11:0]                    resp_packet_lines;
   wire [11:0]                    req_packet_mod;
   wire [11:0]                    resp_packet_mod;
   wire [15:0]                    req_crdt_need;
   wire [15:0]                    resp_crdt_need;
   wire [15:0]                    req_crdt_avail;
   wire [15:0]                    resp_crdt_avail;
   reg [15:0]                     crdt_updt_cntr;
   reg [1:0]                      crdt_updt_send;

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [7:0]           cmd_req_len;
   wire [2:0]           cmd_req_size;
   wire [7:0]           cmd_resp_len;
   wire [2:0]           cmd_resp_size;
   wire                 req_cmd_atomic;
   wire                 req_cmd_error;
   wire                 req_cmd_future0;
   wire                 req_cmd_future0_resp;
   wire                 req_cmd_future1_resp;
   wire                 req_cmd_invalid;
   wire                 req_cmd_link;
   wire                 req_cmd_link_resp;
   wire                 req_cmd_rdma;
   wire                 req_cmd_read;
   wire                 req_cmd_read_resp;
   wire                 req_cmd_request;
   wire                 req_cmd_response;
   wire                 req_cmd_user0;
   wire                 req_cmd_user0_resp;
   wire                 req_cmd_user1_resp;
   wire                 req_cmd_write;
   wire                 req_cmd_write_posted;
   wire                 req_cmd_write_resp;
   wire                 resp_cmd_atomic;
   wire                 resp_cmd_error;
   wire                 resp_cmd_future0;
   wire                 resp_cmd_future0_resp;
   wire                 resp_cmd_future1_resp;
   wire                 resp_cmd_invalid;
   wire                 resp_cmd_link;
   wire                 resp_cmd_link_resp;
   wire                 resp_cmd_rdma;
   wire                 resp_cmd_read;
   wire                 resp_cmd_read_resp;
   wire                 resp_cmd_request;
   wire                 resp_cmd_response;
   wire                 resp_cmd_user0;
   wire                 resp_cmd_user0_resp;
   wire                 resp_cmd_user1_resp;
   wire                 resp_cmd_write;
   wire                 resp_cmd_write_posted;
   wire                 resp_cmd_write_resp;
   // End of automatics

   //########################################
   //# Credit management
   //########################################
   // credit counters store the number of transmitted bytes in units of CLINK width

   always @(posedge clk or negedge nreset)
     if (~nreset)
       begin
          tx_crdt_req[15:0]  <= 'h0;
          tx_crdt_resp[15:0] <= 'h0;
       end
     else
       if (phy_fifo_wr & phy_txrdy)
         begin
            tx_crdt_resp[15:0] <= tx_crdt_resp[15:0] + {15'h0,shift_reg_type[1]};
            tx_crdt_req[15:0]  <= tx_crdt_req[15:0]  + {15'h0,shift_reg_type[0]};
         end

   // Credit status - count cycles of no-credit

   always @(posedge clk or negedge nreset)
     if (~nreset)
       csr_crdt_status[31:0] <= 'h0;
     else
       begin
          csr_crdt_status[15:0]  <= csr_crdt_status[15:0]  + {15'h0000,(umi_req_in_valid   & phy_txrdy & ~rxready[0])};
          csr_crdt_status[31:16] <= csr_crdt_status[31:16] + {15'h0000,(umi_resp_in_valid  & phy_txrdy & ~rxready[1])};
       end

   //########################################
   //# Credit message generation for the remote side
   //########################################
   // credit counters are stored in the rxphy block and sent periodically

   always @(posedge clk or negedge nreset)
     if (~nreset)
       crdt_updt_cntr <= 'h0;
     else
       if (csr_crdt_en)
         crdt_updt_cntr <= (crdt_updt_cntr == csr_crdt_intrvl) ?
                           'h0:
                           crdt_updt_cntr + 1;

   // Credit update send:
   // - set when counter reaches 0
   // - clear when both updates are sent
   always @(posedge clk or negedge nreset)
     if (~nreset)
       crdt_updt_send <= 2'b00;
     else
       if (crdt_updt_cntr == csr_crdt_intrvl)
         crdt_updt_send <= 2'b01;
       else
         crdt_updt_send <= (|crdt_updt_send) & sample_packet ?
                           (crdt_updt_send << 1) :
                           crdt_updt_send;

   //########################################
   //# UMI Transmit Arbiter
   //########################################

   // Mux together response and request over one data channel
   // the mux assumes one hot select (valid so need to prioritize the resp)
   /*umi_mux AUTO_TEMPLATE(
    .umi_out_ready     (lumi_txrdy & ~(|crdt_updt_send)),
    .umi_out_valid     (),
    .umi_in_ready      ({umi_req_ready,umi_resp_ready}),
    .umi_in_valid      ({umi_req_in_gated & ~umi_resp_in_gated ,umi_resp_in_gated}),
    .umi_in_cmd        ({umi_req_in_cmd,umi_resp_in_cmd}),
    .umi_in_\(.*\)addr ({umi_req_in_\1addr,umi_resp_in_\1addr}),
    .umi_in_data       ({umi_req_in_data,umi_resp_in_data}),
    );*/

   umi_mux #(.DW(DW),
             .CW(CW),
             .AW(AW),
             .N(2))
   umi_mux(/*AUTOINST*/
           // Outputs
           .umi_in_ready        ({umi_req_ready,umi_resp_ready}), // Templated
           .umi_out_valid       (),                      // Templated
           .umi_out_cmd         (umi_out_cmd[CW-1:0]),
           .umi_out_dstaddr     (umi_out_dstaddr[AW-1:0]),
           .umi_out_srcaddr     (umi_out_srcaddr[AW-1:0]),
           .umi_out_data        (umi_out_data[DW-1:0]),
           // Inputs
           .umi_in_valid        ({umi_req_in_gated & ~umi_resp_in_gated ,umi_resp_in_gated}), // Templated
           .umi_in_cmd          ({umi_req_in_cmd,umi_resp_in_cmd}), // Templated
           .umi_in_dstaddr      ({umi_req_in_dstaddr,umi_resp_in_dstaddr}), // Templated
           .umi_in_srcaddr      ({umi_req_in_srcaddr,umi_resp_in_srcaddr}), // Templated
           .umi_in_data         ({umi_req_in_data,umi_resp_in_data}), // Templated
           .umi_out_ready       (lumi_txrdy & ~(|crdt_updt_send))); // Templated

   // Muxing the umi_mux output with sending credit updates
   // Change the order to send resp credits first so in case both are pending
   // response will get credits first
   assign umi_muxed_cmd = crdt_updt_send[1] ?
                          {loc_crdt_req[15:0],4'h0,4'h2,8'h2F}  :
                          crdt_updt_send[0] ?
                          {loc_crdt_resp[15:0],4'h1,4'h2,8'h2F} :
                          umi_out_cmd;

   // response takes precedence over request
   // Ready to the UMI input is set upon packet acception for transmission (lumi_txrdy)
   // credit update is highest priority so it blocks both ready signals
   // Add phy_txrdy to allow for backpressure (local) from the phy
   assign umi_req_in_gated  = umi_req_in_valid  & phy_txrdy & rxready[0] & ~(|crdt_updt_send);
   assign umi_resp_in_gated = umi_resp_in_valid & phy_txrdy & rxready[1] & ~(|crdt_updt_send);

   assign lumi_txrdy        = ((~|valid[(DW+AW+AW+CW)/8-1:0]) | (~|valid_next[(DW+AW+AW+CW)/8-1:0]));
   assign umi_req_in_ready  = umi_req_ready  & umi_req_in_gated & ~umi_resp_in_gated;
   assign umi_resp_in_ready = umi_resp_ready & umi_resp_in_gated;

   //########################################
   // Credit based FC:
   //########################################

   // Ready to transmit is provided when the number of available credits is sufficient for the packet size

   /*umi_unpack AUTO_TEMPLATE(
    .cmd_len    (cmd_@"(substring vl-cell-name 11)"_len[]),
    .cmd_size   (cmd_@"(substring vl-cell-name 11)"_size[]),
    .cmd.*      (),
    .packet_cmd (umi_@"(substring vl-cell-name 11)"_in_cmd[]),
    );*/

   umi_unpack #(.CW(CW))
   umi_unpack_req(/*AUTOINST*/
                  // Outputs
                  .cmd_opcode           (),                      // Templated
                  .cmd_size             (cmd_req_size[2:0]),     // Templated
                  .cmd_len              (cmd_req_len[7:0]),      // Templated
                  .cmd_atype            (),                      // Templated
                  .cmd_qos              (),                      // Templated
                  .cmd_prot             (),                      // Templated
                  .cmd_eom              (),                      // Templated
                  .cmd_eof              (),                      // Templated
                  .cmd_ex               (),                      // Templated
                  .cmd_user             (),                      // Templated
                  .cmd_user_extended    (),                      // Templated
                  .cmd_err              (),                      // Templated
                  .cmd_hostid           (),                      // Templated
                  // Inputs
                  .packet_cmd           (umi_req_in_cmd[CW-1:0])); // Templated

   umi_unpack #(.CW(CW))
   umi_unpack_resp(/*AUTOINST*/
                   // Outputs
                   .cmd_opcode          (),                      // Templated
                   .cmd_size            (cmd_resp_size[2:0]),    // Templated
                   .cmd_len             (cmd_resp_len[7:0]),     // Templated
                   .cmd_atype           (),                      // Templated
                   .cmd_qos             (),                      // Templated
                   .cmd_prot            (),                      // Templated
                   .cmd_eom             (),                      // Templated
                   .cmd_eof             (),                      // Templated
                   .cmd_ex              (),                      // Templated
                   .cmd_user            (),                      // Templated
                   .cmd_user_extended   (),                      // Templated
                   .cmd_err             (),                      // Templated
                   .cmd_hostid          (),                      // Templated
                   // Inputs
                   .packet_cmd          (umi_resp_in_cmd[CW-1:0])); // Templated


   assign cmd_resp_lenp1[11:0] = {4'h0,cmd_resp_len[7:0]} + 1'b1;
   assign cmd_req_lenp1[11:0]  = {4'h0,cmd_req_len[7:0]}  + 1'b1;

   assign cmd_resp_bytes[11:0] = cmd_resp_lenp1[11:0] << cmd_resp_size[2:0];
   assign cmd_req_bytes[11:0]  = cmd_req_lenp1[11:0] << cmd_req_size[2:0];

   // Find how many lines of credit are needed
   assign req_packet_lines[11:0]  = req_packet_bytes[11:0]  >> csr_iowidth[7:0];
   assign resp_packet_lines[11:0] = resp_packet_bytes[11:0] >> csr_iowidth[7:0];

   // The above calculation is doing round down so need to see if an extra line is needed
   assign req_packet_mod[11:0]  = ~(req_packet_lines[11:0]  << csr_iowidth[7:0]) & req_packet_bytes[11:0];
   assign resp_packet_mod[11:0] = ~(resp_packet_lines[11:0] << csr_iowidth[7:0]) & resp_packet_bytes[11:0];

   assign req_crdt_need[15:0]  = {4'h0,req_packet_lines[11:0]}  + {15'h0,(|req_packet_mod[11:0])};
   assign resp_crdt_need[15:0] = {4'h0,resp_packet_lines[11:0]} + {15'h0,(|resp_packet_mod[11:0])};

   // The last part account for a credit being consumed this cycle
   assign req_crdt_avail[15:0]  = (rmt_crdt_req[15:0]  - tx_crdt_req[15:0] - {15'h0,phy_fifo_wr & phy_txrdy & shift_reg_type[0]});
   assign resp_crdt_avail[15:0] = (rmt_crdt_resp[15:0] - tx_crdt_resp[15:0]- {15'h0,phy_fifo_wr & phy_txrdy & shift_reg_type[1]});

   assign rxready[0] = req_crdt_avail[15:0]  >= req_crdt_need[15:0];
   assign rxready[1] = resp_crdt_avail[15:0] >= resp_crdt_need[15:0];

   assign phy_fifo_wr = |valid[(DW+AW+AW+CW)/8-1:0];

   //########################################
   //# CTRL MODES
   //########################################
   // shift left size is the width of the operand so need to reserve space for shifts
   assign iowidth[10:0] = 11'h1 << csr_iowidth[7:0];

   // Bytes transferred per cycle
   assign byterate[$clog2(DW+AW+AW+CW)-1:0] = {{($clog2(DW+AW+AW+CW)-8){1'b0}},iowidth[7:0]};

   //########################################
   //# FLOW CONTROL - currently not affected by CLINK RX ready.
   // No point in fixing since we will move to credit based FC.
   //########################################

   // sample input controls to avoid timing issues

   always @ (posedge clk or negedge nreset)
     if(~nreset)
       valid[(DW+AW+AW+CW)/8-1:0] <= 'b0;
     else if (sample_packet)
       valid[(DW+AW+AW+CW)/8-1:0] <= valid_start_value[(DW+AW+AW+CW)/8-1:0];
     else if (phy_txrdy)
       valid[(DW+AW+AW+CW)/8-1:0] <= valid_next[(DW+AW+AW+CW)/8-1:0];

   assign valid_next[(DW+AW+AW+CW)/8-1:0] = valid[(DW+AW+AW+CW)/8-1:0] << byterate[$clog2(DW+AW+AW+CW)-1:0];

   //########################################
   //# DATA SHIFT REGISTER
   //########################################

   assign sample_packet = lumi_txrdy & csr_en & phy_txrdy & ((|crdt_updt_send) |
                                                             umi_resp_in_gated |
                                                             umi_req_in_gated  );

   //########################################
   // UMI bandwidth optimization - send only what is needed
   //########################################

   // First step - decode the packet
   // Need to do separately for request and response since the decode affects the credit calc

   /*umi_decode AUTO_TEMPLATE(
    .command       (umi_@"(substring vl-cell-name 11)"_in_cmd[]),
    .cmd_atomic_.* (),
    .cmd_\(.*\)    (@"(substring vl-cell-name 11)"_cmd_\1[]),
    );*/

   umi_decode #(.CW(CW))
   umi_decode_req (/*AUTOINST*/
                   // Outputs
                   .cmd_invalid         (req_cmd_invalid),       // Templated
                   .cmd_request         (req_cmd_request),       // Templated
                   .cmd_response        (req_cmd_response),      // Templated
                   .cmd_read            (req_cmd_read),          // Templated
                   .cmd_write           (req_cmd_write),         // Templated
                   .cmd_write_posted    (req_cmd_write_posted),  // Templated
                   .cmd_rdma            (req_cmd_rdma),          // Templated
                   .cmd_atomic          (req_cmd_atomic),        // Templated
                   .cmd_user0           (req_cmd_user0),         // Templated
                   .cmd_future0         (req_cmd_future0),       // Templated
                   .cmd_error           (req_cmd_error),         // Templated
                   .cmd_link            (req_cmd_link),          // Templated
                   .cmd_read_resp       (req_cmd_read_resp),     // Templated
                   .cmd_write_resp      (req_cmd_write_resp),    // Templated
                   .cmd_user0_resp      (req_cmd_user0_resp),    // Templated
                   .cmd_user1_resp      (req_cmd_user1_resp),    // Templated
                   .cmd_future0_resp    (req_cmd_future0_resp),  // Templated
                   .cmd_future1_resp    (req_cmd_future1_resp),  // Templated
                   .cmd_link_resp       (req_cmd_link_resp),     // Templated
                   .cmd_atomic_add      (),                      // Templated
                   .cmd_atomic_and      (),                      // Templated
                   .cmd_atomic_or       (),                      // Templated
                   .cmd_atomic_xor      (),                      // Templated
                   .cmd_atomic_max      (),                      // Templated
                   .cmd_atomic_min      (),                      // Templated
                   .cmd_atomic_maxu     (),                      // Templated
                   .cmd_atomic_minu     (),                      // Templated
                   .cmd_atomic_swap     (),                      // Templated
                   // Inputs
                   .command             (umi_req_in_cmd[CW-1:0])); // Templated

   umi_decode #(.CW(CW))
   umi_decode_resp (/*AUTOINST*/
                    // Outputs
                    .cmd_invalid        (resp_cmd_invalid),      // Templated
                    .cmd_request        (resp_cmd_request),      // Templated
                    .cmd_response       (resp_cmd_response),     // Templated
                    .cmd_read           (resp_cmd_read),         // Templated
                    .cmd_write          (resp_cmd_write),        // Templated
                    .cmd_write_posted   (resp_cmd_write_posted), // Templated
                    .cmd_rdma           (resp_cmd_rdma),         // Templated
                    .cmd_atomic         (resp_cmd_atomic),       // Templated
                    .cmd_user0          (resp_cmd_user0),        // Templated
                    .cmd_future0        (resp_cmd_future0),      // Templated
                    .cmd_error          (resp_cmd_error),        // Templated
                    .cmd_link           (resp_cmd_link),         // Templated
                    .cmd_read_resp      (resp_cmd_read_resp),    // Templated
                    .cmd_write_resp     (resp_cmd_write_resp),   // Templated
                    .cmd_user0_resp     (resp_cmd_user0_resp),   // Templated
                    .cmd_user1_resp     (resp_cmd_user1_resp),   // Templated
                    .cmd_future0_resp   (resp_cmd_future0_resp), // Templated
                    .cmd_future1_resp   (resp_cmd_future1_resp), // Templated
                    .cmd_link_resp      (resp_cmd_link_resp),    // Templated
                    .cmd_atomic_add     (),                      // Templated
                    .cmd_atomic_and     (),                      // Templated
                    .cmd_atomic_or      (),                      // Templated
                    .cmd_atomic_xor     (),                      // Templated
                    .cmd_atomic_max     (),                      // Templated
                    .cmd_atomic_min     (),                      // Templated
                    .cmd_atomic_maxu    (),                      // Templated
                    .cmd_atomic_minu    (),                      // Templated
                    .cmd_atomic_swap    (),                      // Templated
                    // Inputs
                    .command            (umi_resp_in_cmd[CW-1:0])); // Templated

   // Second step - push all to the right, this is only needed when you skip a field
   assign shiftreg_in_new = {umi_out_data,umi_out_srcaddr,umi_out_dstaddr,umi_muxed_cmd};

   // Third step - only send the required number of bits
   // TODO - do not send SA for responses
   assign req_cmd_only  = req_cmd_invalid    |
                          req_cmd_link       |
                          req_cmd_link_resp  ;
   assign req_no_data   = req_cmd_read       |
                          req_cmd_rdma       |
                          req_cmd_error      |
                          req_cmd_write_resp |
                          req_cmd_user0      |
                          req_cmd_future0    ;

   assign resp_cmd_only = resp_cmd_invalid    |
                          req_cmd_link        |
                          req_cmd_link_resp   ;
   assign resp_no_data  = resp_cmd_read       |
                          resp_cmd_rdma       |
                          resp_cmd_error      |
                          resp_cmd_write_resp |
                          resp_cmd_user0      |
                          resp_cmd_future0    ;

   always @(*)
     case ({req_cmd_only,req_no_data})
       2'b10:
         begin
            valid_start_value_req = {{CW/8{1'b1}},{(DW+AW+AW)/8{1'b0}}};
            req_packet_bytes[11:0] = CW/8;
         end
       2'b01:
         begin
            valid_start_value_req = {{(AW+AW+CW)/8{1'b1}},{DW/8{1'b0}}};
            req_packet_bytes[11:0] = (AW+AW+CW)/8;
         end
       default:
         begin
            valid_start_value_req = {{(AW+AW+CW)/8{1'b1}},~({DW/8{1'b1}}>>cmd_req_bytes[11:0])};
            req_packet_bytes[11:0] = (AW+AW+CW)/8 + cmd_req_bytes[11:0];
         end
     endcase

   always @(*)
     case ({resp_cmd_only,resp_no_data})
       2'b10:
         begin
            valid_start_value_resp = {{CW/8{1'b1}},{(DW+AW+AW)/8{1'b0}}};
            resp_packet_bytes[11:0] = CW/8;
         end
       2'b01:
         begin
            valid_start_value_resp = {{(AW+AW+CW)/8{1'b1}},{DW/8{1'b0}}};
            resp_packet_bytes[11:0] = (AW+AW+CW)/8;
         end
       default:
         begin
            valid_start_value_resp = {{(AW+AW+CW)/8{1'b1}},~({DW/8{1'b1}}>>cmd_resp_bytes[11:0])};
            resp_packet_bytes[11:0] = (AW+AW+CW)/8 + cmd_resp_bytes[11:0];
         end
     endcase

   assign valid_start_value = lumi_txrdy & csr_en & (|crdt_updt_send) ?
                              {{CW/8{1'b1}},{(DW+AW+AW)/8{1'b0}}}     :
                              lumi_txrdy & umi_resp_in_gated          ?
                              valid_start_value_resp                  :
                              valid_start_value_req;

   // TX is done as lsb first
   // adding indication to the packet type in the shift register for crdt management
   always @ (posedge clk or negedge nreset)
     if (~nreset)
       begin
          shiftreg[(DW+AW+AW+CW)-1:0] <= 'b0;
          shift_reg_type[2:0] <= 3'b000;
       end
     else if (sample_packet)
       begin
          shiftreg[(DW+AW+AW+CW)-1:0] <= shiftreg_in_new[(DW+AW+AW+CW)-1:0];
          shift_reg_type[2] <=  (|crdt_updt_send);
          shift_reg_type[1] <= ~(|crdt_updt_send) & umi_resp_in_gated;
          shift_reg_type[0] <= ~(|crdt_updt_send) & ~umi_resp_in_gated & umi_req_in_gated;
       end
     else if (phy_txrdy)
       shiftreg[(DW+AW+AW+CW)-1:0] <= shiftreg_in[(DW+AW+AW+CW)-1:0];

   assign shiftreg_in[(DW+AW+AW+CW)-1:0] = shiftreg[(DW+AW+AW+CW)-1:0] >>
                                           (byterate[$clog2(DW+AW+AW+CW)-1:0] <<3);

   //########################################
   //# Output data - no need for masking or by anymore
   //########################################
   assign phy_txrdy = ~phy_fifo_full;

   la_asyncfifo #(.DW(IOW),          // Memory width
                  .DEPTH(8),         // FIFO depth
                  .NS(1),            // Number of power supplies
                  .CHAOS(0),         // generates random full logic when set
                  .CTRLW(1),         // width of asic ctrl interface
                  .TESTW(1),         // width of asic test interface
                  .TYPE("DEFAULT"))  // Pass through variable for hard macro
   req_fifo_i(// Outputs
              .wr_full          (phy_fifo_full),
              .rd_dout          (phy_txdata[IOW-1:0]),
              .rd_empty         (phy_fifo_empty),
              // Inputs
              .rd_clk           (ioclk),
              .rd_nreset        (ionreset),
              .wr_clk           (clk),
              .wr_nreset        (nreset),
              .vss              (1'b0),
              .vdd              (1'b1),
              .wr_chaosmode     (1'b0),
              .ctrl             (1'b0),
              .test             (1'b0),
              .wr_en            (phy_fifo_wr),
              .wr_din           (shiftreg[IOW-1:0]),
              .rd_en            (1'b1));

   la_rsync la_rsync(.clk(ioclk),
                     .nrst_in(ionreset),
                     .nrst_out(ionreset_sync));

   assign phy_txvld = ~phy_fifo_empty & ionreset_sync;

endmodule
// Local Variables:
// verilog-library-directories:("." "../../umi/rtl/" "../submodules/lambdalib/stdlib/rtl")
// End:
