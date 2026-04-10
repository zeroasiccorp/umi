import math
import cocotb

from cocotb.triggers import Event, Combine, ClockCycles

from env import UMI2APBEnv
from cocotbext.umi.sumi import SumiTransaction, SumiCmdType, SumiCmd


@cocotb.test(timeout_time=50, timeout_unit="ms")
async def test_full_throughput(dut):
    """
    Back-to-back full-throughput tests alternating read/write transactions.

    - New request arrives in same cycle response becomes valid
    """

    env = UMI2APBEnv(dut)
    await env.start()

    # Always ready to accept responses
    dut.udev_resp_ready.value = 1

    data_size = env.data_size
    addr_width = env.addr_width
    umi_size = int(math.log2(data_size))

    num_transactions = 100

    print("=== Back-to-Back Full Throughput Test ===")

    send_events = []
    for i in range(num_transactions):
        txn_size = i % (umi_size + 1)
        txn_bytes = 1 << txn_size
        addr = i * data_size

        is_read = (i % 2) == 0

        if is_read:
            txn = SumiTransaction(
                cmd=SumiCmd.from_fields(
                    cmd_type=int(SumiCmdType.UMI_REQ_READ),
                    size=txn_size,
                    len=0,
                ),
                da=addr,
                sa=0x0,
                data=bytearray(txn_bytes),
            )

            expected_resp = SumiTransaction(
                cmd=SumiCmd.from_fields(
                    cmd_type=int(SumiCmdType.UMI_RESP_READ),
                    size=txn_size,
                    len=0,
                ),
                da=0x0,
                sa=addr,
                data=bytearray(txn_bytes),
                addr_width=addr_width,
            )

        else:
            data = bytes([i & 0xFF] * txn_bytes)
            txn = SumiTransaction(
                cmd=SumiCmd.from_fields(
                    cmd_type=int(SumiCmdType.UMI_REQ_WRITE),
                    size=txn_size,
                    len=0,
                ),
                da=addr,
                sa=0x0,
                data=data,
            )

            expected_resp = SumiTransaction(
                cmd=SumiCmd.from_fields(
                    cmd_type=int(SumiCmdType.UMI_RESP_WRITE),
                    size=txn_size,
                    len=0,
                ),
                da=0x0,
                sa=addr,
                data=bytearray(txn_bytes),
                addr_width=addr_width,
            )

        env.expected_responses.append(expected_resp)
        evt = Event()
        env.sumi_driver.append(txn, event=evt)
        send_events.append(evt)

    # Wait for all responses
    await Combine(*(e.wait() for e in send_events))

    await ClockCycles(env.clk, 100)

    print(f" All {num_transactions} back-to-back transactions completed successfully!")

    raise env.scoreboard.result
