# Ebrick Address Remap

## Functionality
This module remaps UMI transactions across different memory regions. The current address map dictates that the memory region attached to each CLINK/UMI is 1 TiB. Hence, the address bits [39:0] of a UMI transaction are used to address regions within a UMI device attached to a CLINK port. Bits [55:40] are ID bits used to identify the appropriate CLINK/UMI device on the efabric and to route transactions to it. Bits [63:56] are reserved.

The module performs 2 functions. It allows remapping UMI transactions going to a UMI device to be redirected to a different device and it allows addresses within a certain range to be offsetted by a base address.

In order to accomplish the remapping, it accepts NMAPS input mappings from one device address to another. In the mapping, the bits being remapped are denoted by old_row_col_address and the bits being mapped to are denoted by new_row_col_address. The ID bits of dstaddr of an incoming transaction on the input UMI port are compared to the NMAPS different old_row_col_address and if a match is found, bits [55:40] of the dstaddr are replaced by the corresponding new_row_col_address.

The offset is accomplished by comparing bits [39:0] of the dstaddr of an incoming UMI packet to a lower and upper bound. If the dstaddr lies within the bounds (inclusive), then an offset is subtracted from the bits [39:0] of the incoming UMI packet before it is sent out. Currently, only a single offset is permitted.

## Limitations
Any transactions to local devices (within the ebrick issuing the transaction) that use the current devices chipid in bits [55:40] are maintained as is even if a mapping exists. There exist two ways for a device to access its own local memory region, bits [55:40] can be set to the devices own chipid or they can be set to 0. To be clear, transactions to local memory regions that set bits [55:40] to 0 can still be remapped. Only local transactions that use chipid in bits [55:40] cannot be remapped. This allows the host to maintain access to critical local infrastructure including the memory that contains the various address mappings.

## For software developers
The primary intention of the remap feature is to allow a host to access main memory that exists at a different CLINK/UMI region. Current software for RISCV hosts tends to boot from address such as 0x8000_0000. The software would need to be rewritten in order to work with the ebrick/efabric address map. This module allows a developer to remap and offset an outgoing transaction and thus boot from a device that might not be a part of the local memory region. After boot is complete, it is expected that the developer will reverse the remapping.
