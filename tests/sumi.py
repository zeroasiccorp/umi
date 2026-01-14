from enum import IntEnum
from typing import Optional
import dataclasses
import copy

from bit_utils import BitField, BitVector
from vrd_transaction import VRDTransaction


class SumiCmdType(IntEnum):
    # Invalid transaction indicator (cmd[7:0])
    UMI_INVALID = 0x00

    # Requests (host -> device) (cmd[7:0])
    UMI_REQ_READ = 0x01     # read/load
    UMI_REQ_WRITE = 0x03    # write/store with ack
    UMI_REQ_POSTED = 0x05   # posted write
    UMI_REQ_RDMA = 0x07     # remote DMA command
    UMI_REQ_ATOMIC = 0x09   # alias for all atomics
    UMI_REQ_USER0 = 0x0B    # reserved for user
    UMI_REQ_FUTURE0 = 0x0D  # reserved fur future use
    UMI_REQ_ERROR = 0x0F    # reserved for error message
    UMI_REQ_LINK = 0x2F     # reserved for link ctrl

    # Response (device -> host) (cmd[7:0])
    UMI_RESP_READ = 0x02        # response to read request
    UMI_RESP_WRITE = 0x04       # response (ack) from write request
    UMI_RESP_USER0 = 0x06       # signal write without ack
    UMI_RESP_USER1 = 0x08       # reserved for user
    UMI_RESP_FUTURE0 = 0x0A     # reserved for future use
    UMI_RESP_FUTURE1 = 0x0C     # reserved for future use
    UMI_RESP_LINK = 0x0E        # reserved for link ctrl

    @classmethod
    def supports_streaming(cls, value):
        return value in [
            SumiCmdType.UMI_REQ_WRITE,
            SumiCmdType.UMI_REQ_POSTED,
            SumiCmdType.UMI_RESP_READ
        ]


@dataclasses.dataclass
class SumiCmd(BitVector):

    cmd_type: BitField = dataclasses.field(default_factory=lambda: BitField(value=0, width=5, offset=0))
    size: BitField = dataclasses.field(default_factory=lambda: BitField(value=0, width=3, offset=5))
    len: BitField = dataclasses.field(default_factory=lambda: BitField(value=0, width=8, offset=8))
    eom: BitField = dataclasses.field(default_factory=lambda: BitField(value=0, width=1, offset=22))

    def __repr__(self):
        return f"Sumi CMD ({super().__repr__()})"


class SumiTransaction:

    def __init__(
        self,
        cmd: SumiCmd,
        da: Optional[int],
        sa: Optional[int],
        data: Optional[bytes],
        addr_width: int = 64
    ):
        self.cmd = copy.deepcopy(cmd)
        self.da = BitField(value=da, width=addr_width, offset=0)
        self.sa = BitField(value=sa, width=addr_width, offset=0)
        self.data = data
        self._addr_width = addr_width

    def header_to_bytes(self) -> bytes:
        return (bytes(self.cmd)
                + int.to_bytes(int(self.da), length=self._addr_width//8, byteorder='little')
                + int.to_bytes(int(self.sa), length=self._addr_width//8, byteorder='little'))

    def to_lumi(self, lumi_size, inc_header=True, override_last=None):
        raw = self.data[:(int(self.cmd.len)+1 << int(self.cmd.size))]
        if inc_header:
            raw = self.header_to_bytes() + raw
        # Break raw into LUMI bus sized chunks
        chunks = [raw[i:i+lumi_size] for i in range(0, len(raw), lumi_size)]
        # Zero pad last chunk
        chunks[-1] = chunks[-1] + bytes([0] * (lumi_size - len(chunks[-1])))
        vrd_transactions = []
        for i, chunk in enumerate(chunks):
            # Set last true for the last chunk
            last = (i == len(chunks)-1)
            # Allow user to override last (useful for simulating streaming mode)
            if last and (override_last is not None):
                last = override_last
            # Convert data to a valid ready transaction type
            vrd_transactions.append(VRDTransaction(
                data=chunk,
                last=last
            ))
        return vrd_transactions

    def trunc_and_pad_zeros(self):
        data_len = ((int(self.cmd.len)+1) << int(self.cmd.size))
        self.data = bytes([0] * (len(self.data) - data_len)) + self.data[:data_len]

    def __eq__(self, other):
        if isinstance(other, SumiTransaction):
            # For all command types CMD's must match
            if int(self.cmd) == int(other.cmd):
                # For RESP_WRITE only compare header fields DA
                if int(self.cmd.cmd_type) == SumiCmdType.UMI_RESP_WRITE:
                    return int(self.da) == int(other.da)
                else:
                    return (self.header_to_bytes() + self.data) == (other.header_to_bytes() + other.data)
            return False
        else:
            return False

    def __repr__(self):
        return f"header = {self.header_to_bytes().hex()} data = {self.data.hex()} {self.cmd}"
