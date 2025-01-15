`default_nettype none

module testbench(
`ifdef VERILATOR
    input clk
`endif
);

`include "umi_messages.vh"
`include "switchboard.vh"

    // fixed
    localparam DW       = 128;
    localparam CW       = 32;
    localparam AW       = 64;
    localparam IOW      = 64;

    // standard
    localparam PERIOD_CLK   = 10;
    localparam RST_CYCLES   = 16;

`ifndef VERILATOR
    // Generate clock for non verilator sim tools
    reg clk;

    initial
        clk  = 1'b0;
    always #(PERIOD_CLK/2) clk = ~clk;
`endif

    // Reset control
    reg [RST_CYCLES:0]      nreset_vec;
    wire                    nreset;
    wire                    initdone;

    assign nreset = nreset_vec[RST_CYCLES-1];
    assign initdone = nreset_vec[RST_CYCLES];

    initial
        nreset_vec = 'b1;
    always @(negedge clk) nreset_vec <= {nreset_vec[RST_CYCLES-1:0], 1'b1};

    // Initialize UMI
    integer valid_mode, ready_mode;

    initial begin
        /* verilator lint_off IGNOREDRETURN */
        if (!$value$plusargs("valid_mode=%d", valid_mode)) begin
            valid_mode = 2;  // default if not provided as a plusarg
        end

        if (!$value$plusargs("ready_mode=%d", ready_mode)) begin
            ready_mode = 2;  // default if not provided as a plusarg
        end
        /* verilator lint_on IGNOREDRETURN */
    end

    wire            umi_req_in_valid;
    wire [CW-1:0]   umi_req_in_cmd;
    wire [AW-1:0]   umi_req_in_dstaddr;
    wire [AW-1:0]   umi_req_in_srcaddr;
    wire [DW-1:0]   umi_req_in_data;
    wire            umi_req_in_ready;

    wire            umi_req_out_valid;
    wire [CW-1:0]   umi_req_out_cmd;
    wire [AW-1:0]   umi_req_out_dstaddr;
    wire [AW-1:0]   umi_req_out_srcaddr;
    wire [DW-1:0]   umi_req_out_data;
    wire            umi_req_out_ready;

    wire            umi_resp_in_valid;
    wire [CW-1:0]   umi_resp_in_cmd;
    wire [AW-1:0]   umi_resp_in_dstaddr;
    wire [AW-1:0]   umi_resp_in_srcaddr;
    wire [DW-1:0]   umi_resp_in_data;
    wire            umi_resp_in_ready;

    wire            umi_resp_out_valid;
    wire [CW-1:0]   umi_resp_out_cmd;
    wire [AW-1:0]   umi_resp_out_dstaddr;
    wire [AW-1:0]   umi_resp_out_srcaddr;
    wire [DW-1:0]   umi_resp_out_data;
    wire            umi_resp_out_ready;

    // phy interface
    wire [IOW-1:0]  phy_txdata;
    wire            phy_txvld;
    wire            phy_txrdy;
    wire            ioclk;
    wire            ionreset;

    assign ioclk = clk;
    assign ionreset = nreset;

    // Req Umi Agent
    queue_to_umi_sim #(
        .VALID_MODE_DEFAULT(2),
        .DW(DW)
    ) umi_req_in_i (
        .clk        (clk),

        .valid      (umi_req_in_valid),
        .cmd        (umi_req_in_cmd[CW-1:0]),
        .dstaddr    (umi_req_in_dstaddr[AW-1:0]),
        .srcaddr    (umi_req_in_srcaddr[AW-1:0]),
        .data       (umi_req_in_data[DW-1:0]),
        .ready      (umi_req_in_ready & initdone)
    );

    umi_to_queue_sim #(
        .READY_MODE_DEFAULT(2),
        .DW(DW)
    ) umi_req_out_i (
        .clk        (clk),

        .valid      (umi_req_out_valid & initdone),
        .cmd        (umi_req_out_cmd[CW-1:0]),
        .dstaddr    (umi_req_out_dstaddr[AW-1:0]),
        .srcaddr    (umi_req_out_srcaddr[AW-1:0]),
        .data       (umi_req_out_data[DW-1:0]),
        .ready      (umi_req_out_ready)
    );

    initial begin
        `ifndef VERILATOR
            #1;
        `endif
        umi_req_in_i.init("umi_req_in.q");
        umi_req_in_i.set_valid_mode(valid_mode);

        umi_req_out_i.init("umi_req_out.q");
        umi_req_out_i.set_ready_mode(ready_mode);
    end

    // Resp Umi Agent
    queue_to_umi_sim #(
        .VALID_MODE_DEFAULT(2),
        .DW(DW)
    ) umi_resp_in_i (
        .clk        (clk),

        .valid      (umi_resp_in_valid),
        .cmd        (umi_resp_in_cmd[CW-1:0]),
        .dstaddr    (umi_resp_in_dstaddr[AW-1:0]),
        .srcaddr    (umi_resp_in_srcaddr[AW-1:0]),
        .data       (umi_resp_in_data[DW-1:0]),
        .ready      (umi_resp_in_ready & initdone)
    );

    umi_to_queue_sim #(
        .READY_MODE_DEFAULT(2),
        .DW(DW)
    ) umi_resp_out_i (
        .clk        (clk),

        .valid      (umi_resp_out_valid & initdone),
        .cmd        (umi_resp_out_cmd[CW-1:0]),
        .dstaddr    (umi_resp_out_dstaddr[AW-1:0]),
        .srcaddr    (umi_resp_out_srcaddr[AW-1:0]),
        .data       (umi_resp_out_data[DW-1:0]),
        .ready      (umi_resp_out_ready)
    );

    initial begin
        `ifndef VERILATOR
            #1;
        `endif
        umi_resp_in_i.init("umi_resp_in.q");
        umi_resp_in_i.set_valid_mode(valid_mode);

        umi_resp_out_i.init("umi_resp_out.q");
        umi_resp_out_i.set_ready_mode(ready_mode);
    end

    //#############################################################
    //# DUT
    //#############################################################

    lumi_tx_ready #(
        .IOW        (IOW),
        .DW         (DW),
        .CW         (CW),
        .AW         (AW)
    ) dut_tx (
        .clk                        (clk),
        .nreset                     (nreset),
        .csr_en                     (initdone),
        .csr_iowidth                ($clog2(IOW/8)),
        .vss                        (),
        .vdd                        (),

        .umi_req_in_valid           (umi_req_in_valid & initdone),
        .umi_req_in_cmd             (umi_req_in_cmd[CW-1:0]),
        .umi_req_in_dstaddr         (umi_req_in_dstaddr[AW-1:0]),
        .umi_req_in_srcaddr         (umi_req_in_srcaddr[AW-1:0]),
        .umi_req_in_data            (umi_req_in_data[DW-1:0]),
        .umi_req_in_ready           (umi_req_in_ready),

        .umi_resp_in_valid          (umi_resp_in_valid & initdone),
        .umi_resp_in_cmd            (umi_resp_in_cmd[CW-1:0]),
        .umi_resp_in_dstaddr        (umi_resp_in_dstaddr[AW-1:0]),
        .umi_resp_in_srcaddr        (umi_resp_in_srcaddr[AW-1:0]),
        .umi_resp_in_data           (umi_resp_in_data[DW-1:0]),
        .umi_resp_in_ready          (umi_resp_in_ready),

        .phy_txdata                 (phy_txdata),
        .phy_txvld                  (phy_txvld),
        .phy_txrdy                  (phy_txrdy),
        .ioclk                      (ioclk),
        .ionreset                   (ionreset)
    );

    lumi_rx_ready #(
        .IOW        (IOW),
        .DW         (DW),
        .CW         (CW),
        .AW         (AW)
    ) dut_rx (
        .clk                    (clk),
        .nreset                 (nreset),
        .csr_en                 (initdone),
        .csr_iowidth            ($clog2(IOW/8)),
        .vss                    (),
        .vdd                    (),

        .ioclk                  (ioclk),
        .ionreset               (ionreset),
        .phy_rxdata             (phy_txdata),
        .phy_rxvld              (phy_txvld),
        .phy_rxrdy              (phy_txrdy),

        .umi_resp_out_cmd       (umi_resp_out_cmd),
        .umi_resp_out_dstaddr   (umi_resp_out_dstaddr),
        .umi_resp_out_srcaddr   (umi_resp_out_srcaddr),
        .umi_resp_out_data      (umi_resp_out_data),
        .umi_resp_out_valid     (umi_resp_out_valid),
        .umi_resp_out_ready     (umi_resp_out_ready & initdone),

        .umi_req_out_cmd        (umi_req_out_cmd),
        .umi_req_out_dstaddr    (umi_req_out_dstaddr),
        .umi_req_out_srcaddr    (umi_req_out_srcaddr),
        .umi_req_out_data       (umi_req_out_data),
        .umi_req_out_valid      (umi_req_out_valid),
        .umi_req_out_ready      (umi_req_out_ready & initdone)
    );

    // waveform dump
    `SB_SETUP_PROBES

    // auto-stop
    auto_stop_sim auto_stop_sim_i (.clk(clk));

endmodule

`default_nettype wire
