module umi_mem #(
    parameter AW = 16,
    parameter DW = 64
) (
    input clk,
    input nreset,

	input rx0_umi_valid,
	input [255:0] rx0_umi_packet,
	output rx0_umi_ready,

	output tx0_umi_valid,
	output [255:0] tx0_umi_packet,
	input tx0_umi_ready
);

    wire [AW-1:0] addr;
    wire write;
    wire read;
    wire [DW-1:0] write_data;
    wire [DW-1:0] read_data;
    wire tx_ready_passthru;

    reg [DW-1:0] mem[1 << (AW - $clog2(DW))];

    umi_endpoint #(
        .AW(AW),
        .DW(DW)
    ) endpoint(
        .clk(clk),
        .nreset(nreset),

        .umi_in_valid(rx0_umi_valid),
        .umi_in_packet(rx0_umi_packet),
        .umi_out_ready(rx0_umi_ready),

        .umi_out_valid(tx0_umi_valid),
        .umi_out_packet(tx0_umi_packet),
        .umi_in_ready(tx_ready_passthru),

        .addr(addr),
        .write(write),
        .read(read),
        .write_data(write_data),
        .read_data(read_data)
    );

    // Truncate address - mem only supports DW-aligned accesses.
    wire [AW-1-$clog2(DW):0] mem_addr;
    assign mem_addr = addr[AW-1:$clog2(DW)];
    assign tx_ready_passthru = tx0_umi_ready;

    always @(posedge clk) begin
        if (write) begin
            mem[mem_addr] <= write_data;
        end
    end

    assign read_data = mem[mem_addr];

endmodule
