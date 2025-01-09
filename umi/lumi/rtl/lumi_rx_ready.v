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
 * - LUMI Receiver
 * - Converts PHY side interface to SUMI (cmd, addr, data)
 *
 ******************************************************************************/

module lumi_rx_ready
  #(parameter TARGET = "DEFAULT",                         // implementation target
    // for development only (fixed )
    parameter IOW = 64,                                   // clink rx/tx width
    parameter DW = 256,                                   // umi data width
    parameter CW = 32,                                    // umi data width
    parameter AW = 64                                     // address width
    )
   (// local control
    input             clk,                // clock for sampling input data
    input             nreset,             // async active low reset
    input             csr_en,             // 1=enable outputs
    input [7:0]       csr_iowidth,        // pad bus width
    input             vss,                // common ground
    input             vdd,                // core supply
    // pad signals
    input             ioclk,              // clock for sampling input data
    input             ionreset,           // async active low reset
    input [IOW-1:0]   phy_rxdata,
    input             phy_rxvld,
    output            phy_rxrdy,
    // Write/Response
    output [CW-1:0]   umi_resp_out_cmd,
    output [AW-1:0]   umi_resp_out_dstaddr,
    output [AW-1:0]   umi_resp_out_srcaddr,
    output [DW-1:0]   umi_resp_out_data,  // link data pads
    output            umi_resp_out_valid, // valid for fifo
    input             umi_resp_out_ready, // flow control from fifo
    // Read/Request
    output [CW-1:0]   umi_req_out_cmd,
    output [AW-1:0]   umi_req_out_dstaddr,
    output [AW-1:0]   umi_req_out_srcaddr,
    output [DW-1:0]   umi_req_out_data,   // link data pads
    output            umi_req_out_valid,  // valid for fifo
    input             umi_req_out_ready   // flow control from fifo
    );

    // local state
    reg [$clog2((AW+AW+CW))-1:0]        sopptr_metadata;
    reg [$clog2(DW+IOW)-1:0]            sopptr_data;
    wire [$clog2(DW+IOW)-1:0]           sopptr_data_in;
    wire [$clog2(DW+IOW)-1:0]           sopptr_data_out;
    wire [$clog2(DW+IOW)-1:0]           sopptr_data_init;
    wire [$clog2(DW+IOW)-1:0]           sopptr_data_next;
    reg [$clog2((DW+AW+AW+CW))-1:0]     rxbytes_raw;
    wire [$clog2((DW+AW+AW+CW))-1:0]    full_hdr_size;
    wire [$clog2((AW+AW+CW))-1:0]       rxbytes_metadata_to_rcv;
    wire [$clog2(DW)-1:0]               rxbytes_data_to_rcv;
    reg [$clog2((AW+AW+CW))-1:0]        rxbytes_keep_metadata;
    reg [$clog2(DW)-1:0]                rxbytes_keep_data;
    reg                                 rxvalid;
    wire [1:0]                          rxtype;
    reg [1:0]                           rxtype_next;

    // local wires
    // Amir - byterate is used later as shifterd 3 bits to the left so needs 3 more bits than the "pure" value
    wire [13:0]                         byterate;
    wire [IOW-1:0]                      bitmask;
    wire [10:0]                         iowidth;
    reg [IOW-1:0]                       rxdata;
    reg [7:0]                           rxdata_d;

    wire                                rx_cmd_only;
    wire                                rx_no_data;
    wire [11:0]                         rxcmd_lenp1;
    wire [11:0]                         rxcmd_bytes;

    wire [15:0]                         rxhdr;
    wire                                rxhdr_sample;

    wire                                rxcmd_error;
    wire                                rxcmd_future0;
    wire                                rxcmd_future0_resp;
    wire                                rxcmd_future1_resp;
    wire                                rxcmd_invalid;
    wire [7:0]                          rxcmd_len;
    wire                                rxcmd_link;
    wire                                rxcmd_link_resp;
    wire                                rxcmd_rdma;
    wire                                rxcmd_read;
    wire                                rxcmd_read_resp;
    wire                                rxcmd_request;
    wire                                rxcmd_response;
    wire [2:0]                          rxcmd_size;
    wire                                rxcmd_user0;
    wire                                rxcmd_user0_resp;
    wire                                rxcmd_user1_resp;
    wire                                rxcmd_write;
    wire                                rxcmd_write_posted;
    wire                                rxcmd_write_resp;

    reg  [1:0]                          first_sample;
    wire [1:0]                          first_sample_next;

    wire [(CW+AW+AW)-1:0]               masked_metadata;
    reg  [CW-1:0]                       cmd_metadata;
    reg  [AW-1:0]                       dstaddr_metadata;
    reg  [AW-1:0]                       srcaddr_metadata;
    wire [IOW-1:0]                      masked_rxdata;

    wire                                metadata_beats_rem;
    wire                                last_metadata_beat_rem;
    wire                                all_metadata_received;

    wire [DW+IOW-1:0]                   umi_data_in;
    wire [DW+IOW-1:0]                   umi_data_next;
    reg  [DW+IOW-1:0]                   umi_data;

    wire                                umi_out_valid;
    wire                                umi_out_ready;
    wire                                umi_out_commit;

    //########################################
    //# interface width calculation
    //########################################
    assign iowidth[10:0] = 11'h1 << csr_iowidth[7:0];

    // bytes per clock cycle
    // Updating to 128b DW
    assign byterate = {3'b0,iowidth[10:0]};
    assign bitmask = ({{(IOW-1){1'b0}}, 1'b1} << (byterate << 3)) - 1;

    assign first_sample_next = first_sample | {umi_out_commit, (phy_rxrdy & !phy_rxvld)};

    always @ (posedge ioclk or negedge ionreset)
        if (~ionreset)
            first_sample <= 2'b11;
        else if (phy_rxrdy & phy_rxvld)
            first_sample <= 2'b00;
        else
            first_sample <= first_sample_next;

    //########################################
    //# Input Sampling
    //########################################

    // Detect valid signal
    always @ (posedge ioclk or negedge ionreset)
        if (~ionreset)
            rxvalid  <= 1'b0;
        else
            rxvalid  <= phy_rxvld & phy_rxrdy & csr_en;

    // rising edge data sample
    always @ (posedge ioclk)
        rxdata[IOW-1:0] <= phy_rxdata[IOW-1:0];

    always @ (posedge ioclk or negedge ionreset)
        if (~ionreset)
            rxdata_d[7:0] <= 'h0;
        else if (rxvalid)
            rxdata_d[7:0] <= rxdata[7:0];

    //########################################
    //# Input data tracking
    //########################################
    //
    // Input data is now separate before and after the input fifo
    // As a result need to understand data size and track (to generate SOP)

    // Handle 1B i/f width
    assign rxhdr[15:0] = (sopptr_metadata == 'h0) & (csr_iowidth == 8'h0) ? {8'h0,rxdata[7:0]}       : // dummy width of 4B
                         (sopptr_metadata == 'h1) & (csr_iowidth == 8'h0) ? {rxdata[7:0],rxdata_d[7:0]} :
                         rxdata[15:0];

    /*umi_unpack AUTO_TEMPLATE(
     .cmd_len    (rxcmd_len[]),
     .cmd_size   (rxcmd_size[]),
     .cmd.*      (),
     .packet_cmd ({{CW-16{1'b0}},rxhdr[15:0]}),
     );*/

    umi_unpack #(.CW(CW))
    rxdata_unpack(/*AUTOINST*/
                  // Outputs
                  .cmd_opcode            (),                      // Templated
                  .cmd_size              (rxcmd_size[2:0]),       // Templated
                  .cmd_len               (rxcmd_len[7:0]),        // Templated
                  .cmd_atype             (),                      // Templated
                  .cmd_qos               (),                      // Templated
                  .cmd_prot              (),                      // Templated
                  .cmd_eom               (),                      // Templated
                  .cmd_eof               (),                      // Templated
                  .cmd_ex                (),                      // Templated
                  .cmd_user              (),                      // Templated
                  .cmd_user_extended     (),                      // Templated
                  .cmd_err               (),                      // Templated
                  .cmd_hostid            (),                      // Templated
                  // Inputs
                  .packet_cmd            ({{CW-16{1'b0}},rxhdr[15:0]})); // Templated

    /*umi_decode AUTO_TEMPLATE(
     .command      ({{CW-16{1'b0}},rxhdr[15:0]}),
     .cmd_atomic.* (),
     .cmd_\(.*\)   (rxcmd_\1[]),
     );*/

    umi_decode #(.CW(CW))
    rxdata_decode (/*AUTOINST*/
                   // Outputs
                   .cmd_invalid          (rxcmd_invalid),         // Templated
                   .cmd_request          (rxcmd_request),         // Templated
                   .cmd_response         (rxcmd_response),        // Templated
                   .cmd_read             (rxcmd_read),            // Templated
                   .cmd_write            (rxcmd_write),           // Templated
                   .cmd_write_posted     (rxcmd_write_posted),    // Templated
                   .cmd_rdma             (rxcmd_rdma),            // Templated
                   .cmd_atomic           (),                      // Templated
                   .cmd_user0            (rxcmd_user0),           // Templated
                   .cmd_future0          (rxcmd_future0),         // Templated
                   .cmd_error            (rxcmd_error),           // Templated
                   .cmd_link             (rxcmd_link),            // Templated
                   .cmd_read_resp        (rxcmd_read_resp),       // Templated
                   .cmd_write_resp       (rxcmd_write_resp),      // Templated
                   .cmd_user0_resp       (rxcmd_user0_resp),      // Templated
                   .cmd_user1_resp       (rxcmd_user1_resp),      // Templated
                   .cmd_future0_resp     (rxcmd_future0_resp),    // Templated
                   .cmd_future1_resp     (rxcmd_future1_resp),    // Templated
                   .cmd_link_resp        (rxcmd_link_resp),       // Templated
                   .cmd_atomic_add       (),                      // Templated
                   .cmd_atomic_and       (),                      // Templated
                   .cmd_atomic_or        (),                      // Templated
                   .cmd_atomic_xor       (),                      // Templated
                   .cmd_atomic_max       (),                      // Templated
                   .cmd_atomic_min       (),                      // Templated
                   .cmd_atomic_maxu      (),                      // Templated
                   .cmd_atomic_minu      (),                      // Templated
                   .cmd_atomic_swap      (),                      // Templated
                   // Inputs
                   .command              ({{CW-16{1'b0}},rxhdr[15:0]})); // Templated

    // Second step - decode what format will be received
    assign rx_cmd_only  = rxcmd_invalid    |
                          rxcmd_link       |
                          rxcmd_link_resp  ;
    assign rx_no_data   = rxcmd_read       |
                          rxcmd_rdma       |
                          rxcmd_error      |
                          rxcmd_write_resp |
                          rxcmd_user0      |
                          rxcmd_future0    ;

    assign rxcmd_lenp1[11:0] = {4'h0,rxcmd_len[7:0]} + 1'b1;
    assign rxcmd_bytes[11:0] = rx_no_data ?
                               'b0 :
                               (rxcmd_lenp1[11:0] << rxcmd_size[2:0]);

    always @(posedge ioclk or negedge ionreset)
        if (~ionreset)
            rxtype_next <= 2'b00;
        else if (rxhdr_sample & rxvalid)
            rxtype_next <= {rxcmd_response, rxcmd_request};

    assign rxtype = (rxhdr_sample & rxvalid) ? {rxcmd_response, rxcmd_request} : rxtype_next;

    assign full_hdr_size = (CW+AW+AW)/8;

    always @(*)
        case ({rx_cmd_only,rx_no_data})
            2'b10: rxbytes_raw = (CW)/8;
            2'b01: rxbytes_raw = full_hdr_size;
            default: rxbytes_raw = full_hdr_size;
        endcase

    // support for 1B IOW (#bytes unknown in first cycle)
    assign rxhdr_sample = (sopptr_metadata == 'h0) |
                          (sopptr_metadata == 'h1) & (csr_iowidth == 8'h0);

    always @ (posedge ioclk or negedge ionreset) begin
        if (~ionreset) begin
            rxbytes_keep_metadata <= 'h1;
            rxbytes_keep_data <= 'h1;
        end
        else if (rxhdr_sample & rxvalid) begin
            rxbytes_keep_metadata <= rxbytes_raw;
            rxbytes_keep_data <= rxcmd_bytes[$clog2(DW)-1:0];
        end
    end

    assign rxbytes_metadata_to_rcv = rxhdr_sample & rxvalid ?
                                     rxbytes_raw :
                                     rxbytes_keep_metadata;

    assign rxbytes_data_to_rcv = rxhdr_sample & rxvalid ?
                                 rxcmd_bytes[$clog2(DW)-1:0] :
                                 rxbytes_keep_data;

    // Valid register holds one bit per byte to transfer
    always @ (posedge ioclk or negedge ionreset)
        if (~ionreset)
            sopptr_metadata <= 'b0;
        else if (&first_sample_next)
            sopptr_metadata <= 'b0;
        else if (rxvalid & metadata_beats_rem)
            sopptr_metadata <= sopptr_metadata + byterate;

    assign masked_rxdata = rxdata & bitmask;
    assign masked_metadata = {srcaddr_metadata, dstaddr_metadata, cmd_metadata} |
                             masked_rxdata << (sopptr_metadata << 3);

    always @ (posedge ioclk or negedge ionreset) begin
        if (~ionreset) begin
            cmd_metadata <= 'b0;
            dstaddr_metadata <= 'b0;
            srcaddr_metadata <= 'b0;
        end
        else if (&first_sample_next) begin
            cmd_metadata <= 'b0;
            dstaddr_metadata <= 'b0;
            srcaddr_metadata <= 'b0;
        end
        else if (rxvalid & metadata_beats_rem) begin
            cmd_metadata <= masked_metadata[0+:CW];
            dstaddr_metadata <= masked_metadata[CW+:AW];
            srcaddr_metadata <= masked_metadata[(CW+AW)+:AW];
        end
        else if (umi_out_commit) begin
            dstaddr_metadata <= dstaddr_metadata + rxbytes_data_to_rcv;
            srcaddr_metadata <= srcaddr_metadata + rxbytes_data_to_rcv;
        end
    end

    assign metadata_beats_rem = (sopptr_metadata < rxbytes_metadata_to_rcv);
    assign last_metadata_beat_rem = metadata_beats_rem &
                                    ((sopptr_metadata + byterate) >= rxbytes_metadata_to_rcv);
    assign all_metadata_received = (sopptr_metadata >= rxbytes_metadata_to_rcv);
    assign umi_out_commit = umi_out_valid & umi_out_ready;

    // Account for data that is bundled with metadata in the first beat
    assign sopptr_data_init = sopptr_metadata + byterate - rxbytes_metadata_to_rcv;
    // Amount of input data qualified with valid
    assign sopptr_data_in = byterate & {14{rxvalid}};
    // Amount of output data qualified with valid
    assign sopptr_data_out = umi_out_commit ?
                             ((sopptr_data > (DW/8)) ?
                             (DW/8) :
                             sopptr_data) :
                             'b0;
    // Amount of data
    assign sopptr_data_next = sopptr_data + sopptr_data_in - sopptr_data_out;

    always @ (posedge ioclk or negedge ionreset)
        if (~ionreset)
            sopptr_data <= 'b0;
        else if (&first_sample_next)
            sopptr_data <= 'b0;
        else if (rxvalid & last_metadata_beat_rem)
            sopptr_data <= sopptr_data_init;
        else if (all_metadata_received)
            sopptr_data <= sopptr_data_next;

    // Qualify masked data with valid and left shift to the correct position
    assign umi_data_in = ({{DW{1'b0}}, masked_rxdata} << ((sopptr_data-sopptr_data_out) << 3)) &
                         {(DW+IOW){rxvalid}};

    // Determine next data by right shifting for output and ORing with input data
    assign umi_data_next = (umi_data >> (sopptr_data_out << 3)) | umi_data_in;

    always @ (posedge ioclk or negedge ionreset)
        if (~ionreset)
            umi_data <= 'b0;
        else if (&first_sample_next)
            umi_data <= 'b0;
        else if (rxvalid & last_metadata_beat_rem)
            umi_data <= masked_rxdata >> ((byterate - sopptr_data_init) << 3);
        else if (all_metadata_received)
            umi_data <= umi_data_next;

    assign umi_out_valid = all_metadata_received &
                           (sopptr_data >= rxbytes_data_to_rcv) &
                           !(&first_sample);

    assign umi_out_ready = (rxtype[0] & umi_req_out_ready) |
                           (rxtype[1] & umi_resp_out_ready);

    assign umi_req_out_cmd      = cmd_metadata;
    assign umi_req_out_dstaddr  = dstaddr_metadata;
    assign umi_req_out_srcaddr  = srcaddr_metadata;
    assign umi_req_out_data     = umi_data[DW-1:0];
    assign umi_req_out_valid    = umi_out_valid & rxtype[0];

    assign umi_resp_out_cmd     = cmd_metadata;
    assign umi_resp_out_dstaddr = dstaddr_metadata;
    assign umi_resp_out_srcaddr = srcaddr_metadata;
    assign umi_resp_out_data    = umi_data[DW-1:0];
    assign umi_resp_out_valid   = umi_out_valid & rxtype[1];

    assign phy_rxrdy = (&first_sample) |
                       metadata_beats_rem |
                       (sopptr_data < rxbytes_data_to_rcv) |
                       ((sopptr_data >= rxbytes_data_to_rcv) & umi_out_commit);

endmodule
// Local Variables:
// verilog-library-directories:("." "../../umi/rtl/")
// End:
