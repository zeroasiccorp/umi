
// FULL OPCODES

localparam WRITE_POSTED    = 8'h01;
localparam WRITE_RESPONSE  = 8'h03;
localparam WRITE_SIGNAL    = 8'h05;
localparam WRITE_STREAM    = 8'h07;
localparam WRITE_ACK       = 8'h09;
localparam WRITE_MULTICAST = 8'h0B;

localparam INVALID         = 8'h00;
localparam READ_REQUEST    = 8'h02;
localparam ATOMIC_ADD      = 8'h04;
localparam ATOMIC_AND      = 8'h14;
localparam ATOMIC_OR       = 8'h24;
localparam ATOMIC_XOR      = 8'h34;
localparam ATOMIC_MAX      = 8'h44;
localparam ATOMIC_MIN      = 8'h54;
localparam ATOMIC_MAXU     = 8'h64;
localparam ATOMIC_MINU     = 8'h74;
localparam ATOMIC_SWAP     = 8'h84;

// GROUPS
localparam ATOMIC          = 4'h4;
