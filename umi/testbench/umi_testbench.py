import os
import platform

import pytest
from siliconcompiler.core import SiliconCompilerError

def setup(chip):
    '''Adds sources/build configuration for the UMI testbench.

    Assumes that user plans to build using sclib verification flow.
    '''
    mydir = os.path.dirname(os.path.abspath(__file__))
    sbdir = os.path.join(mydir, '..', '..', 'submodules', 'switchboard')

    # Add testbench sources
    chip.add('input', 'verilog', f'{mydir}/verilog/umi_testbench.sv')
    chip.add('input', 'verilog', f'{sbdir}/verilog/sim/umi_rx_sim.sv')
    chip.add('input', 'verilog', f'{sbdir}/verilog/sim/umi_tx_sim.sv')

    chip.add('input', 'c', f'{mydir}/cpp/umi_testbench.cc')
    chip.add('input', 'c', f'{sbdir}/dpi/switchboard_dpi.cc')

    # testbench module is top-level
    chip.set('option', 'entrypoint', 'umi_testbench')

    trace = chip.get('option', 'trace')
    if trace:
        chip.add('option', 'define', 'TRACE')

    # Configure tools for verification flow
    cflags =['-Wno-unknown-warning-option', f'-I{sbdir}/cpp']
    if trace:
        cflags += ['-DTRACE']
    chip.set('tool', 'za_verilator', 'var', 'compile', '0', 'cflags', cflags)
    print('CFLAGS', cflags)

    if platform.system() == 'Darwin':
        cpp_libs = ['-lboost_system', '-lpthread']
    else:
        cpp_libs = ['-lboost_system', '-pthread', '-lrt']
    chip.set('tool', 'za_verilator', 'var', 'compile', '0', 'ldflags', cpp_libs)

    chip.set('tool', 'umidriver', 'path', f'{sbdir}/cpp')

    # Make Verilator allow warnings - missing connections in current testbench
    chip.set('option', 'relax', True)

def compile_tb(chip, module):
    '''Sets up and compiles a testbench from a Chip object.'''
    setup(chip)

    # Set up flow - only run to compile in this method
    chip.set('option', 'flow', 'verification')
    chip.set('option', 'steplist', ['import', 'compile'])
    chip.set('option', 'jobname', 'compile_tb')

    chip.add('option', 'define', f'MOD_UNDER_TEST={module}')

    chip.run()

    # Future runs will reuse the compilation results from this job
    chip.set('option', 'jobinput', 'execute', '0', 'compile_tb')

    return chip

def run_tb(chip, job):
    '''Runs the execute step of the verification flow.

    This function is meant to be run in the context of a pytest test.
    '''
    chip.set('option', 'jobname', job)
    chip.set('option', 'steplist', ['execute'])
    try:
        chip.run()
    except SiliconCompilerError:
        # If step fails, it's probably cause of test failure - no need to print
        # out stacktrace. If in quiet mode, print out conents of umidriver log.
        if chip.get('option', 'quiet'):
            workdir = chip._getworkdir(step='execute', index='0')
            log = f'{workdir}/execute.log'
            with open(log, 'r') as f:
                contents = f.read()
        else:
            contents = ''
        pytest.fail(contents, pytrace=False)
