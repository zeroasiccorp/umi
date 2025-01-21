import pytest
from switchboard import SbDut, UmiTxRx, random_umi_packet
from pathlib import Path
from umi import sumi
from fasteners import InterProcessLock
import numpy as np


def pytest_collection_modifyitems(items):
    for item in items:
        if "sumi_dut" in getattr(item, "fixturenames", ()):
            item.add_marker("switchboard")
            pass


@pytest.fixture
def build_dir(pytestconfig):
    return pytestconfig.cache.mkdir('sumi_build')


@pytest.fixture
def sumi_dut(build_dir, request):

    extra_args = {
        '--vldmode': dict(type=int, default=1, help='Valid mode'),
        '--rdymode': dict(type=int, default=1, help='Ready mode'),
    }

    dut = SbDut('testbench', cmdline=True, extra_args=extra_args,
                default_main=True, trace_type='fst', trace=True)

    dut.use(sumi)

    # Add testbench
    test_file_name = Path(request.fspath).stem
    assert (test_file_name[:5] == 'test_'), "Test file name must start with test_"
    testbench_name = f'sumi/testbench/testbench_{test_file_name[5:]}.sv'
    dut.input(testbench_name, package='umi')

    # TODO: How to add module/testbench specific parameters
    # dut.add('option', 'define', f'SPLIT={int(split)}')

    # Verilator configuration
    dut.set('tool', 'verilator', 'task', 'compile', 'file', 'config', 'sumi/testbench/config.vlt',
            package='umi')

    # Build simulator
    dut.set('option', 'builddir', build_dir / test_file_name)
    with InterProcessLock(build_dir / f'{test_file_name}.lock'):
        # ensure build only happens once
        # https://github.com/pytest-dev/pytest-xdist/blob/v3.6.1/docs/how-to.rst#making-session-scoped-fixtures-execute-only-once
        dut.build(fast=True)

    yield dut

    dut.terminate()


@pytest.fixture
def umi_send(random_seed):

    def setup(host_num, num_packets_to_send, num_out_ports):
        np.random.seed(random_seed)

        umi = UmiTxRx(f'client2rtl_{host_num}.q', '')
        tee = UmiTxRx(f'tee_{host_num}.q', '')

        for count in range(num_packets_to_send):
            dstport = np.random.randint(num_out_ports)
            dstaddr = (2**8)*np.random.randint(2**32) + dstport*(2**40)
            srcaddr = (2**8)*np.random.randint(2**32) + host_num*(2**40)
            txp = random_umi_packet(dstaddr=dstaddr, srcaddr=srcaddr)
            print(f"port {host_num} sending #{count} cmd: 0x{txp.cmd:08x}"
                  f"srcaddr: 0x{srcaddr:08x} dstaddr: 0x{dstaddr:08x} to port {dstport}")
            # send the packet to both simulation and local queues
            umi.send(txp)
            tee.send(txp)

    return setup


@pytest.fixture
def apply_atomic():

    def setup(origdata, atomicdata, operation, maxrange):
        tempval = origdata
        if (operation == 0):
            tempval = origdata + atomicdata
            if (tempval >= maxrange):
                tempval = tempval - maxrange
        elif (operation == 1):
            tempval = origdata & atomicdata
        elif (operation == 2):
            tempval = origdata | atomicdata
        elif (operation == 3):
            tempval = origdata ^ atomicdata
        elif (operation == 4):
            if (origdata & (maxrange >> 1)):
                origdata = int(origdata) - int(maxrange)
            else:
                origdata = int(origdata)
            if (atomicdata & (maxrange >> 1)):
                atomicdata = int(atomicdata) - int(maxrange)
            else:
                atomicdata = int(atomicdata)
            tempval = origdata if (origdata > atomicdata) else atomicdata
        elif (operation == 5):
            if (origdata & (maxrange >> 1)):
                origdata = int(origdata) - int(maxrange)
            else:
                origdata = int(origdata)
            if (atomicdata & (maxrange >> 1)):
                atomicdata = int(atomicdata) - int(maxrange)
            else:
                atomicdata = int(atomicdata)
            tempval = atomicdata if (origdata > atomicdata) else origdata
        elif (operation == 6):
            tempval = origdata if (origdata > atomicdata) else atomicdata
        elif (operation == 7):
            tempval = atomicdata if (origdata > atomicdata) else origdata
        elif (operation == 8):
            tempval = atomicdata
        else:
            tempval = atomicdata

        return tempval

    return setup
