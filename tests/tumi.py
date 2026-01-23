from typing import List
from clink.tests.utils.sumi import SumiCmd, SumiTransaction


class TumiTransaction:

    def __init__(
        self,
        cmd: SumiCmd,
        da: int,
        sa: int,
        data: bytes
    ):
        self._cmd = cmd
        self._data = data
        self._da = da
        self._sa = sa

    def to_sumi(self, data_bus_size: int, addr_width: int = 64) -> List[SumiTransaction]:
        sa = self._sa
        da = self._da

        sumi_size = 0

        data_grouped = [
            self._data[i:i+data_bus_size]
            for i in range(0, len(self._data), data_bus_size)
        ]

        rtn = []
        for idx, grouping in enumerate(data_grouped):
            group_len = len(grouping)

            for size in reversed(range(0, (1 << 3)-1)):
                if group_len % (2**size) == 0:
                    sumi_size = size
                    break

            group_len = int(group_len / (2**sumi_size))

            self._cmd.size.from_int(sumi_size)
            self._cmd.len.from_int(group_len-1)
            self._cmd.eom.from_int(1 if idx == len(data_grouped)-1 else 0)

            trans = SumiTransaction(
                cmd=self._cmd,
                da=da,
                sa=sa,
                data=grouping,
                addr_width=addr_width
            )
            rtn.append(trans)
            da += (int(self._cmd.len) + 1) << int(self._cmd.size)
            sa += (int(self._cmd.len) + 1) << int(self._cmd.size)
        return rtn
