#include <cstdio>
#include <iostream>
#include <thread>
#include <csignal>

#include "Vumi_testbench.h"
#include "verilated.h"

// quit flag set by SIGINT signal handler to gracefully clean up and close VCD
// file when simulation is quit.
volatile sig_atomic_t quit = 0;

void signal_handler(int signum) {
        quit = 1;
}

void step(Vumi_testbench *top) {
        top->eval();
        Verilated::timeInc(1);
}

int main(int argc, char **argv, char **env)
{
        Verilated::commandArgs(argc, argv);

#ifdef TRACE
        Verilated::traceEverOn(true);
#endif

        Vumi_testbench *top = new Vumi_testbench;

        signal(SIGINT, signal_handler);

        // reset
        top->nreset = 1;
        step(top);
        top->nreset = 0;
        step(top);
        top->nreset = 1;
        step(top);

        // main loop
        top->clk = 0;
        step(top);
        while (!Verilated::gotFinish() && !quit) {
                // update logic
                top->clk ^= 1;
                step(top);
        }

        top->final();
        delete top;

        return 0;
}
