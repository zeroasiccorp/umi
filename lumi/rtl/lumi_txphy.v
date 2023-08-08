/******************************************************************************
 * Function: CLINK Transmitter IO
 * Author:   Andreas Olofsson
 * License:  (c) 2020 Zero ASIC Corporation
 *
 * Version history:
 * Version 1 - change from packet UMI to exploded
 *****************************************************************************/
module clink_txphy
  #(parameter TARGET = "DEFAULT", // implementation target
    // for development only (fixed )
    parameter IOW = 64,           // clink rx/tx width
    parameter DW = 128,           // umi data width
    parameter CW = 32,            // umi data width
    parameter AW = 64             // address width
    )
   (// ctrl signls
    input             ioclk,           // clock for driving output data
    input             ionreset,        // ioclk synced async active low reset
    input             devicemode,      // 1=host, 0=device
    input [1:0]       chipdir,         // chiplet direction
    input             csr_en,          // 1=enable outputs
    input             csr_crdt_en,     // 1=enable sending updates
    input [1:0]       csr_chipletmode, // 00=110um,01=45um,10=10um,11=1um
    input             csr_ddrmode,     // 1 = ddr, 0 = sdr
    input [7:0]       csr_iowidth,     // bus width
    input [3:0]       csr_eccmode,     // eccmode
    input [1:0]       csr_arbmode,     // phy arbiter mode
    input             csr_bpio,        // bypass txio logic
    input             vss,             // common ground
    input             vdd,             // core supply
    input             vddio,           // io voltage
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
    // pad signals
    output [IOW-1:0]  io_txdata,       // link data to pads
    output [3:0]      io_txctrl,       // link ctrl (valid) to pads
    input [3:0]       io_txstatus,     // flow control from pads
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

   wire [DW+AW+AW+CW-1:0]    shiftreg_in;
   wire [DW+AW+AW+CW-1:0]    shiftreg_in_new;

   wire [7:0]                fixedwidth;
   wire [10:0]               iowidth;

   // Amir - byterate is used later as shifterd 3 bits to the left so needs 3 more bits than the "pure" value
   wire [$clog2(DW+AW+AW+CW)-1:0] byterate;
   //   wire [$clog2(DW/8)-1:0] byterate;
   wire [(DW+AW+AW+CW)/8-1:0]     bytemask;
   wire [IOW-1:0]                 bitmask;
   wire [(DW+AW+AW+CW)-1:0]       txdata_odd;
   wire [IOW-1:0]                 txdata_ddr;
   wire [IOW-1:0]                 txdata;
   wire [IOW-1:0]                 txdata_masked;
   wire [(DW+AW+AW+CW)/8-1:0]     valid_next;

   wire                           txfec;
   wire                           txaux;
   wire [1:0]                     rxready;
   wire                           umi_req_ready;
   wire                           umi_resp_ready;
   wire                           txphy_ready;

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
   reg [15:0]                     crdt_updt_cntr;
   reg [1:0]                      crdt_updt_send;

   /*AUTOWIRE*/
   // Beginning of automatic wires (for undeclared instantiated-module outputs)
   wire [7:0]           cmd_req_len;
   wire [2:0]           cmd_req_size;
   wire [7:0]           cmd_resp_len;
   wire [2:0]           cmd_resp_size;
   wire                 req_cmd_atomic;
   wire                 req_cmd_atomic_add;
   wire                 req_cmd_atomic_and;
   wire                 req_cmd_atomic_max;
   wire                 req_cmd_atomic_maxu;
   wire                 req_cmd_atomic_min;
   wire                 req_cmd_atomic_minu;
   wire                 req_cmd_atomic_or;
   wire                 req_cmd_atomic_swap;
   wire                 req_cmd_atomic_xor;
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
   wire                 resp_cmd_atomic_add;
   wire                 resp_cmd_atomic_and;
   wire                 resp_cmd_atomic_max;
   wire                 resp_cmd_atomic_maxu;
   wire                 resp_cmd_atomic_min;
   wire                 resp_cmd_atomic_minu;
   wire                 resp_cmd_atomic_or;
   wire                 resp_cmd_atomic_swap;
   wire                 resp_cmd_atomic_xor;
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

   always @(posedge ioclk or negedge ionreset)
     if (~ionreset)
       begin
          tx_crdt_req[15:0]  <= 'h0;
          tx_crdt_resp[15:0] <= 'h0;
       end
     else
       if (io_txctrl[0])
         begin
            tx_crdt_resp[15:0] <= tx_crdt_resp[15:0] + {15'h0,shift_reg_type[1]};
            tx_crdt_req[15:0]  <= tx_crdt_req[15:0]  + {15'h0,shift_reg_type[0]};
         end

   // Credit status - count cycles of no-credit

   always @(posedge ioclk or negedge ionreset)
     if (~ionreset)
       csr_crdt_status[31:0] <= 'h0;
     else
       begin
          csr_crdt_status[15:0]  <= csr_crdt_status[15:0]  + {15'h0000,(umi_req_in_valid   & ~rxready[0])};
          csr_crdt_status[31:16] <= csr_crdt_status[31:16] + {15'h0000,(umi_resp_in_valid  & ~rxready[1])};
       end

   //########################################
   //# Credit message generation for the remote side
   //########################################
   // credit counters are stored in the rxphy block and sent periodically

   always @(posedge ioclk or negedge ionreset)
     if (~ionreset)
       crdt_updt_cntr <= 'h0;
     else
       if (csr_crdt_en)
         crdt_updt_cntr <= (crdt_updt_cntr == csr_crdt_intrvl) ?
                           'h0:
                           crdt_updt_cntr + 1;

   // Credit update send:
   // - set when counter reaches 0
   // - clear when both updates are sent
   always @(posedge ioclk or negedge ionreset)
     if (~ionreset)
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
    .umi_out_ready     (txphy_ready & ~(|crdt_updt_send)),
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
           .umi_out_ready       (txphy_ready & ~(|crdt_updt_send))); // Templated

   // Muxing the umi_mux output with sending credit updates
   // Change the order to send resp credits first so in case both are pending
   // response will get credits first
   assign umi_muxed_cmd = crdt_updt_send[1] ?
                          {loc_crdt_req[15:0],4'h0,4'h2,8'h2F}  :
                          crdt_updt_send[0] ?
                          {loc_crdt_resp[15:0],4'h1,4'h2,8'h2F} :
                          umi_out_cmd;

   // response takes precedence over request
   // Ready to the UMI input is set upon packet acception for tranmission (txphy_ready)
   // credit update is highest priority so it blocks both ready signals
   assign umi_req_in_gated  = umi_req_in_valid  & rxready[0] & ~(|crdt_updt_send);
   assign umi_resp_in_gated = umi_resp_in_valid & rxready[1] & ~(|crdt_updt_send);

   assign txphy_ready       = ((~|valid[(DW+AW+AW+CW)/8-1:0]) | (~|valid_next[(DW+AW+AW+CW)/8-1:0]));
   assign umi_req_in_ready  = umi_req_ready  & umi_req_in_gated & ~umi_resp_in_gated;
   assign umi_resp_in_ready = umi_resp_ready & umi_resp_in_gated;

   //########################################
   //# IO Signal assignment
   //########################################

   //TODO:
   assign txfec = 1'b0;
   assign txaux = 1'b0;

   //########################################
   // Credit based FC:
   //########################################

   // assign rxready[1:0]   = io_txstatus[1:0];

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

   assign rxready[0] = (rmt_crdt_req[15:0]  - tx_crdt_req[15:0])  >= ({4'h0,req_packet_bytes[11:0]}  >> (byterate[7:0] >> 1));
   assign rxready[1] = (rmt_crdt_resp[15:0] - tx_crdt_resp[15:0]) >= ({4'h0,resp_packet_bytes[11:0]} >> (byterate[7:0] >> 1));

   assign io_txctrl[0] = |valid[(DW+AW+AW+CW)/8-1:0];
   assign io_txctrl[1] = ioclk; // TODO: add ioclk at some point
   assign io_txctrl[2] = txfec; //forward error correction
   assign io_txctrl[3] = txaux; //redundant data bit

   //########################################
   //# CTRL MODES
   //########################################

   // Chiplet standardized widths
   // Amir - fix 8B and 32B mode to the right values
   // TODO - 2D mode should be 1B and not 2B
   assign fixedwidth[7:0] = (csr_chipletmode[1:0] == 2'h0) ? 'h2  : //2B - 2D mode
			    (csr_chipletmode[1:0] == 2'h1) ? 'h8  : //8B - 3D mode
			    (csr_chipletmode[1:0] == 2'h2) ? 'h20 : //32B - efabric
		                                             'h8;   //8B

   // Selecting between hardcoded iowidth and csr iowidth
   assign iowidth[7:0] = |csr_iowidth[7:0] ? csr_iowidth[7:0] :
			 fixedwidth[7:0];

   // shift left size is the width of the operand so need to reserve space for shifts
   assign iowidth[10:8] = 3'b000;

   // Bytes transferred per cycle
   // TODO - this will need to change based on DW
   assign byterate[$clog2(DW+AW+AW+CW)-1:0] = iowidth[8:0] << csr_ddrmode;

   // Enabling IO pins - TODO?
   assign bitmask[IOW-1:0] = ~({(IOW){1'b1}} << (iowidth<<3));

   //########################################
   //# FLOW CONTROL - currently not affected by CLINK RX ready.
   // No point in fixing since we will move to credit based FC.
   //########################################

   // sample input controls to avoid timing issues

   always @ (posedge ioclk or negedge ionreset)
     if(~ionreset)
       valid[(DW+AW+AW+CW)/8-1:0] <= 'b0;
     else if (sample_packet)
       valid[(DW+AW+AW+CW)/8-1:0] <= valid_start_value[(DW+AW+AW+CW)/8-1:0];
     else
       valid[(DW+AW+AW+CW)/8-1:0] <= valid_next[(DW+AW+AW+CW)/8-1:0];

   assign valid_next[(DW+AW+AW+CW)/8-1:0] = valid[(DW+AW+AW+CW)/8-1:0] << byterate[$clog2(DW+AW+AW+CW)-1:0];

   //########################################
   //# DATA SHIFT REGISTER
   //########################################

   assign sample_packet = txphy_ready & csr_en & ((|crdt_updt_send) |
                                                  umi_resp_in_gated |
			                          umi_req_in_gated  );

   //########################################
   // UMI bandwidth optimization - send only what is needed
   //########################################

   // First step - decode the packet
   // Need to do separately for request and response since the decode affects the credit calc

   /*umi_decode AUTO_TEMPLATE(
    .command    (umi_@"(substring vl-cell-name 11)"_in_cmd[]),
    .cmd_\(.*\) (@"(substring vl-cell-name 11)"_cmd_\1[]),
    );*/

   umi_decode #(.CW(CW))
   umi_decode_req (//.command             (umi_muxed_cmd[CW-1:0]),
                   /*AUTOINST*/
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
                   .cmd_atomic_add      (req_cmd_atomic_add),    // Templated
                   .cmd_atomic_and      (req_cmd_atomic_and),    // Templated
                   .cmd_atomic_or       (req_cmd_atomic_or),     // Templated
                   .cmd_atomic_xor      (req_cmd_atomic_xor),    // Templated
                   .cmd_atomic_max      (req_cmd_atomic_max),    // Templated
                   .cmd_atomic_min      (req_cmd_atomic_min),    // Templated
                   .cmd_atomic_maxu     (req_cmd_atomic_maxu),   // Templated
                   .cmd_atomic_minu     (req_cmd_atomic_minu),   // Templated
                   .cmd_atomic_swap     (req_cmd_atomic_swap),   // Templated
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
                    .cmd_atomic_add     (resp_cmd_atomic_add),   // Templated
                    .cmd_atomic_and     (resp_cmd_atomic_and),   // Templated
                    .cmd_atomic_or      (resp_cmd_atomic_or),    // Templated
                    .cmd_atomic_xor     (resp_cmd_atomic_xor),   // Templated
                    .cmd_atomic_max     (resp_cmd_atomic_max),   // Templated
                    .cmd_atomic_min     (resp_cmd_atomic_min),   // Templated
                    .cmd_atomic_maxu    (resp_cmd_atomic_maxu),  // Templated
                    .cmd_atomic_minu    (resp_cmd_atomic_minu),  // Templated
                    .cmd_atomic_swap    (resp_cmd_atomic_swap),  // Templated
                    // Inputs
                    .command            (umi_resp_in_cmd[CW-1:0])); // Templated

   // Second step - push all to the right, this is only needed when you skip a field
   assign shiftreg_in_new = {umi_out_data,umi_out_srcaddr,umi_out_dstaddr,umi_muxed_cmd};

   // Third step - only send the required number of bits
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

   assign valid_start_value = txphy_ready & csr_en & (|crdt_updt_send) ?
                              {{CW/8{1'b1}},{(DW+AW+AW)/8{1'b0}}}      :
                              txphy_ready & umi_resp_in_gated          ?
                              valid_start_value_resp                   :
                              valid_start_value_req;

   // TX is done as lsb first
   // adding indication to the packet type in the shift register for crdt management
   always @ (posedge ioclk or negedge ionreset)
     if (~ionreset)
       begin
          shiftreg[(DW+AW+AW+CW)-1:0] <= 'b0;
          shift_reg_type[2:0] <= 3'b000;
       end
     else if (sample_packet)
       begin
          shiftreg[(DW+AW+AW+CW)-1:0] <= shiftreg_in_new[(DW+AW+AW+CW)-1:0];
          shift_reg_type[2] <=  (req_cmd_link | resp_cmd_link_resp);
          shift_reg_type[1] <= ~(req_cmd_link | resp_cmd_link_resp) & umi_resp_in_gated;
          shift_reg_type[0] <= ~(req_cmd_link | resp_cmd_link_resp) & ~umi_resp_in_gated & umi_req_in_gated;
       end
     else
       shiftreg[(DW+AW+AW+CW)-1:0] <= shiftreg_in[(DW+AW+AW+CW)-1:0];

   assign shiftreg_in[(DW+AW+AW+CW)-1:0] = shiftreg[(DW+AW+AW+CW)-1:0] >>
				           (byterate[$clog2(DW+AW+AW+CW)-1:0] <<3);

   //########################################
   //# DDR DATA
   //########################################

   // data to launch on negedge of ioclk
   // NOTE: limited byterates supported for DDR
   assign txdata_odd[IOW-1:0] = //(byterate=='h2) ? shiftreg[8+:8]}:
			        (byterate=='h4)  ? {{(IOW-16){1'b0}},shiftreg[16+:16]}:
//			        (byterate=='h8)  ? shiftreg[32+:32]:
//			        (byterate=='h10) ? {{(IOW-64){1'b0}},shiftreg[64+:64]}:
                     	                           shiftreg[IOW+:IOW]; //syntax for lint
   /*
    always @ (negedge ioclk)
    shiftreg_odd[(DW+AW+AW+CW)-1:0] <= txdata_odd[(DW+AW+AW+CW)-1:0];

    assign txdata_ddr[IOW-1:0] = ioclk ? shiftreg[(DW+AW+AW+CW)-IOW-1:0] :
    shiftreg_odd[(DW+AW+AW+CW)-IOW-1:0];
    */

   //########################################
   //# Output data selector
   //########################################

   // Selecting between SDR and DDR modeds
   //
   //

   //assign txdata[IOW-1:0] = csr_ddrmode ? txdata_ddr[IOW-1:0] :
   //		                          shiftreg[IOW-1:0];

   assign txdata[IOW-1:0] = shiftreg[IOW-1:0];

   // Keeeping data clean
   assign txdata_masked[IOW-1:0] = txdata[IOW-1:0] &
				   bitmask[IOW-1:0];

   // Bypass mode
   assign io_txdata[IOW-1:0] = csr_bpio  ?
                               umi_out_data[IOW-1:0] :
                               txdata_masked[IOW-1:0];


endmodule // clink_txphy
// Local Variables:
// verilog-library-directories:("." "../../submodules/umi/umi/rtl/")
// End:
