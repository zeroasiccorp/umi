/*******************************************************************************
 * Function:  UMI NxN Crossbar
 * Author:    Andreas Olofsson
 * License:   (c) 2023 Zero ASIC Corporation
 *
 * Documentation:
 *
 * The crossbar is pipelined and non-blocking, allowing for any-to-any
 * simulataneous input to output connections.
 *
 * The input request vector is a concatenated vectors of inputs
 * requesting outputs ports per the order below.
 *
 * [0]     = input 0   requesting output 0
 * [1]     = input 1   requesting output 0
 * [2]     = input 2   requesting output 0
 * [N-1]   = input N-1 requesting output 0
 * [N]     = input 0   requesting output 1
 * [N+1]   = input 1   requesting output 1
 * [N+2]   = input 2   requesting output 1
 * [2*N-1] = input N-1 requesting output 1
 * ...
 *
 * Input to output paths are enabled through the [NxN] wide 'mask' input,
 * which follows ordering of the input valid convention shown above.
 *
 ******************************************************************************/
module umi_crossbar
  #(parameter TARGET = "DEFAULT", // implementation target
    parameter DW = 256,           // UMI width
    parameter CW = 32,
    parameter AW = 64,
    parameter N = 2               // Total UMI ports
    )
   (// controls
    input             clk,
    input             nreset,
    input [1:0]       mode, // arbiter mode (0=fixed)
    input [N*N-1:0]   mask, // arbiter mode (0=fixed)
    // Incoming UMI
    input [N*N-1:0]   umi_in_request,
    input [N*CW-1:0]  umi_in_cmd,
    input [N*AW-1:0]  umi_in_dstaddr,
    input [N*AW-1:0]  umi_in_srcaddr,
    input [N*DW-1:0]  umi_in_data,
    output [N-1:0]    umi_in_ready,
    // Outgoing UMI
    output [N-1:0]    umi_out_valid,
    output [N*CW-1:0] umi_out_cmd,
    output [N*AW-1:0] umi_out_dstaddr,
    output [N*AW-1:0] umi_out_srcaddr,
    output [N*DW-1:0] umi_out_data,
    input [N-1:0]     umi_out_ready
    );

   wire [N*N-1:0]    grants;
   reg [N-1:0]       umi_ready;
   wire              ready_gated;
   wire [N*N-1:0]    umi_out_sel;
   genvar            i;

   //##############################
   // Arbiters for all outputs
   //##############################

   for (i=0;i<N;i=i+1)
     begin
        umi_arbiter #(.TARGET(TARGET),
                      .N(N))
        umi_arbiter (// Outputs
                     .grants   (grants[N*i+:N]),
                     // Inputs
                     .clk      (clk),
                     .nreset   (nreset),
                     .mode     (mode[1:0]),
                     .mask     (mask[N*i+:N]),
                     .requests (umi_in_request[N*i+:N]));

        assign umi_out_valid[i] = |grants[N*i+:N];
     end // for (i=0;i<N;i=i+1)

   // masking final select to help synthesis pruning
   // TODO: check in syn if this is strictly needed

   assign umi_out_sel[N*N-1:0] = grants[N*N-1:0] & ~mask[N*N-1:0];

   //##############################
   // Ready
   //##############################

   // Amir - The ready should be taking into account the incoming ready from
   // the target of the transaction.
   // Therefore you need to replicate umi_out_ready bits and not as a bus and
   // it can only be done inside the loop.
   integer j,k;
   always @(*)
     begin
        umi_ready[N-1:0] = {N{1'b1}};
        for (j=0;j<N;j=j+1)
          for (k=0;k<N;k=k+1)
            umi_ready[j] = umi_ready[j] & ~(umi_in_request[j+N*k] &
                                            (~grants[j+N*k] | ~umi_out_ready[k]));
     end

   la_rsync la_rsync(.nrst_out          (ready_gated),
                     .clk               (clk),
                     .nrst_in           (nreset));

   assign umi_in_ready[N-1:0] = {N{ready_gated}} & umi_ready[N-1:0];

   //##############################
   // Mux on all outputs
   //##############################

   for(i=0;i<N;i=i+1)
     begin: ivmux
        la_vmux #(.N(N),
                  .W(DW))
        la_data_vmux(// Outputs
                     .out (umi_out_data[i*DW+:DW]),
                     // Inputs
                     .sel (umi_out_sel[i*N+:N]),
                     .in  (umi_in_data[N*DW-1:0]));

        la_vmux #(.N(N),
                  .W(AW))
        la_src_vmux(// Outputs
                    .out (umi_out_srcaddr[i*AW+:AW]),
                    // Inputs
                    .sel (umi_out_sel[i*N+:N]),
                    .in  (umi_in_srcaddr[N*AW-1:0]));

        la_vmux #(.N(N),
                  .W(AW))
        la_dst_vmux(// Outputs
                    .out (umi_out_dstaddr[i*AW+:AW]),
                    // Inputs
                    .sel (umi_out_sel[i*N+:N]),
                    .in  (umi_in_dstaddr[N*AW-1:0]));

        la_vmux #(.N(N),
                  .W(CW))
        la_cmd_vmux(// Outputs
                    .out (umi_out_cmd[i*CW+:CW]),
                    // Inputs
                    .sel (umi_out_sel[i*N+:N]),
                    .in  (umi_in_cmd[N*CW-1:0]));
     end

endmodule // umi_crossbar
