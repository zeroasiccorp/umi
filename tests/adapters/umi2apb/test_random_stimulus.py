import random
import cocotb
from random import randint, randbytes
from cocotb.triggers import ClockCycles

from adapters.umi2apb.env import UMI2APBEnv, create_expected_write_response
from sumi import SumiTransaction, SumiCmdType, SumiCmd


async def random_ready_toggle(dut, clk, stop_event):
    """Background task that randomly toggles udev_resp_ready for backpressure testing."""
    while not stop_event["stop"]:
        # Random number of cycles to hold current ready state
        cycles = randint(1, 10)
        await ClockCycles(clk, cycles)
        # Toggle ready with 50% probability
        if random.choice([True, False]):
            dut.udev_resp_ready.value = 1 - int(dut.udev_resp_ready.value)


@cocotb.test(timeout_time=500, timeout_unit="ms")
async def test_random_stimulus(dut):
    """
    Randomized read/write stimulus.

    - Aligned addresses
    - Full-width accesses
    - Randomized ready/valid signaling (backpressure)
    - Memory model checked at end
    """
    # Grab shared test environment
    env = UMI2APBEnv(dut)
    await env.start()
    dut.udev_resp_ready.value = 1

    data_size = env.data_size
    addr_width = env.addr_width
    mem_size = env.mem_size
    umi_size = env.umi_size

    num_random_transactions = 512

    print(f"=== Randomized Test: {num_random_transactions} transactions ===")

    # Start background task for random ready toggling
    stop_event = {"stop": False}
    cocotb.start_soon(random_ready_toggle(dut, env.clk, stop_event))

    # Ideal memory model for writes/reads
    memory_model = {}

    for i in range(num_random_transactions):
        txn_bytes = env.data_size
        max_addr = (mem_size - txn_bytes) // txn_bytes

        # Randomized address and command type
        addr = randint(0, max_addr) * txn_bytes
        is_read = random.choice([True, False])

        if is_read:
            txn = SumiTransaction(
                cmd=SumiCmd.from_fields(
                    cmd_type=int(SumiCmdType.UMI_REQ_READ),
                    size=umi_size,
                    len=0,
                ),
                da=addr,
                sa=0x0,
                data=bytearray(txn_bytes),
            )

            expected_data = memory_model.get(addr, bytearray(txn_bytes))
            expected_resp = SumiTransaction(
                cmd=SumiCmd.from_fields(
                    cmd_type=int(SumiCmdType.UMI_RESP_READ),
                    size=umi_size,
                    len=0,
                ),
                da=0x0,
                sa=addr,
                data=expected_data,
                addr_width=addr_width,
            )

            env.expected_responses.append(expected_resp)

        else:
            data = randbytes(txn_bytes)
            memory_model[addr] = data

            txn = SumiTransaction(
                cmd=SumiCmd.from_fields(
                    cmd_type=int(SumiCmdType.UMI_REQ_WRITE),
                    size=umi_size,
                    len=0,
                ),
                da=addr,
                sa=0x0,
                data=data,
            )

            env.expected_responses.append(
                create_expected_write_response(txn, txn_bytes, addr_width)
            )

        await env.sumi_driver.send(txn)

        # Wait for response before sending next transaction (ordering required for scoreboard)
        await env.wait_for_responses(max_cycles=100)

        if (i + 1) % 100 == 0:
            print(f"    Completed {i+1}/{num_random_transactions} transactions...")

    # Stop the random ready toggle
    stop_event["stop"] = True
    dut.udev_resp_ready.value = 1  # Ensure ready high for memory verification

    # Memory verification
    num_verified = 0
    for addr, expected_data in memory_model.items():
        mem_data = await env.region.read(addr, data_size)
        assert mem_data == expected_data, (
            f"Memory mismatch at 0x{addr:x}: "
            f"expected {expected_data.hex()}, got {mem_data.hex()}"
        )
        num_verified += 1

    print("\n=== Test Statistics ===")
    print(f"    Total transactions: {num_random_transactions}")
    print(f"    Unique addresses written: {len(memory_model)}")
    print(f"    Memory locations verified: {num_verified}")
    print("    All transactions completed")

    raise env.scoreboard.result
