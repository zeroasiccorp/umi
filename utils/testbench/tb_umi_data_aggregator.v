`timescale 1ns / 1ps
`default_nettype wire

module tb_umi_data_aggregator #(
    parameter TARGET     = "DEFAULT",   // pass through variable for hard macro
    parameter TIMEOUT    = 5000,        // timeout value (cycles)
    parameter PERIOD_CLK = 10           // clock period
)
();

    // Local parameters
    localparam STIMDEPTH = 1024;
    localparam TCW       = 8;
    localparam CW        = 32;          // UMI width
    localparam AW        = 64;          // UMI width
    localparam DW        = 512;

    // Clock
    reg             clk;

    always
        #(PERIOD_CLK/2) clk = ~clk;

    // SIM Ctrl signals
    reg             nreset;
    reg [128*8-1:0] memhfile;
    reg             load;
    reg             go;
    integer         r;

    // Reset initialization
    initial begin
        #(1)
        nreset   = 1'b0;
        clk      = 1'b0;
        load     = 1'b0;
        go       = 1'b0;
        #(PERIOD_CLK * 10)
        nreset   = 1'b1;
        #(PERIOD_CLK * 10)
        go       = 1'b1;
    end // initial begin

    // control block
    initial begin
        r = $value$plusargs("MEMHFILE=%s", memhfile);
        $readmemh(memhfile, umi_stimulus.ram);
        $timeformat(-9, 0, " ns", 20);
        $dumpfile("waveform.vcd");
        $dumpvars();
        #(TIMEOUT)
        $finish;
    end

    // DUT signals
    wire            umi_stim2dut_valid;
    wire [CW-1:0]   umi_stim2dut_cmd;
    wire [AW-1:0]   umi_stim2dut_dstaddr;
    wire [AW-1:0]   umi_stim2dut_srcaddr;
    wire [DW-1:0]   umi_stim2dut_data;
    wire            umi_stim2dut_ready;

    wire            umi_dut2check_valid;
    wire [CW-1:0]   umi_dut2check_cmd;
    wire [AW-1:0]   umi_dut2check_dstaddr;
    wire [AW-1:0]   umi_dut2check_srcaddr;
    wire [DW-1:0]   umi_dut2check_data;
    reg             umi_dut2check_ready;

    always @(posedge clk) begin
        if(~nreset)
            umi_dut2check_ready <= 1'b0;
        else
            umi_dut2check_ready <= ~umi_dut2check_ready;
    end

    umi_data_aggregator #(
        .CW         (CW),
        .AW         (AW),
        .DW         (DW)
    ) dut (
        .clk                (clk),
        .nreset             (nreset),

        .umi_in_valid       (umi_stim2dut_valid),
        .umi_in_cmd         (umi_stim2dut_cmd),
        .umi_in_dstaddr     (umi_stim2dut_dstaddr),
        .umi_in_srcaddr     (umi_stim2dut_srcaddr),
        .umi_in_data        (umi_stim2dut_data),
        .umi_in_ready       (umi_stim2dut_ready),

        .umi_out_valid      (umi_dut2check_valid),
        .umi_out_cmd        (umi_dut2check_cmd),
        .umi_out_dstaddr    (umi_dut2check_dstaddr),
        .umi_out_srcaddr    (umi_dut2check_srcaddr),
        .umi_out_data       (umi_dut2check_data),
        .umi_out_ready      (umi_dut2check_ready)
    );

   umi_stimulus #(
       .DEPTH   (STIMDEPTH),
       .TARGET  (TARGET),
       .CW      (CW),
       .AW      (AW),
       .DW      (DW),
       .TCW     (TCW)
   ) umi_stimulus (
        // Inputs
        .nreset         (nreset),
        .load           (load),
        .go             (go),
        .ext_clk        (clk),
        .ext_valid      (1'b0),
        .ext_packet     ({(DW+AW+AW+CW+TCW){1'b0}}),
        .dut_clk        (clk),
        .dut_ready      (umi_stim2dut_ready),

        // Outputs
        .stim_valid     (umi_stim2dut_valid),
        .stim_cmd       (umi_stim2dut_cmd[CW-1:0]),
        .stim_dstaddr   (umi_stim2dut_dstaddr[AW-1:0]),
        .stim_srcaddr   (umi_stim2dut_srcaddr[AW-1:0]),
        .stim_data      (umi_stim2dut_data[DW-1:0]),
        .stim_done      (umi_stim2dut_done)
   );

endmodule
