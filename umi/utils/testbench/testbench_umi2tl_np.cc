// For Ctrl-C handling
#include <signal.h>

// For std::unique_ptr
#include <memory>

// Include common routines
#include <verilated.h>

// Include model header, generated from Verilating "top.v"
#include "Vtestbench.h"

#include "config.h"
#include "tlmemsim.h"

// Legacy function required only so linking works on Cygwin and MSVC++
double sc_time_stamp() {
    return 0;
}

// ref: https://stackoverflow.com/a/4217052
static volatile int got_sigint = 0;

void sigint_handler(int unused) {
    got_sigint = 1;
}

int main(int argc, char** argv, char** env) {
    // Prevent unused variable warnings
    if (false && argc && argv && env) {}

    // Using unique_ptr is similar to
    // "VerilatedContext* contextp = new VerilatedContext" then deleting at end.
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    // Do not instead make Vtop as a file-scope static variable, as the
    // "C++ static initialization order fiasco" may cause a crash

    // Verilator must compute traced signals
    contextp->traceEverOn(true);

    // Pass arguments so Verilated code can see them, e.g. $value$plusargs
    // This needs to be called before you create any model
    contextp->commandArgs(argc, argv);

    // Construct the Verilated model, from Vtop.h generated from Verilating "top.v".
    // Using unique_ptr is similar to "Vtop* top = new Vtop" then deleting at end.
    // "TOP" will be the hierarchical name of the module.
    const std::unique_ptr<Vtestbench> top{new Vtestbench{contextp.get(), "TOP"}};
    TLMemsim *ram{new TLMemsim(RAM_BASE, RAM_SIZE)};

    ram->reset();

    // Set Vtestbench's input signals
    top->clk = 0;
    top->eval();

    // Set up Ctrl-C handler
    signal(SIGINT, sigint_handler);

    // Main loop
    while (!(contextp->gotFinish() || got_sigint)) {
        // Historical note, before Verilator 4.200 Verilated::gotFinish()
        // was used above in place of contextp->gotFinish().
        // Most of the contextp-> calls can use Verilated:: calls instead;
        // the Verilated:: versions just assume there's a single context
        // being used (per thread).  It's faster and clearer to use the
        // newer contextp-> versions.

        // Historical note, before Verilator 4.200 a sc_time_stamp()
        // function was required instead of using timeInc.  Once timeInc()
        // is called (with non-zero), the Verilated libraries assume the
        // new API, and sc_time_stamp() will no longer work.

        uint8_t tl_a_ready = top->tl_a_ready;
        uint8_t tl_d_valid = top->tl_d_valid;
        uint8_t tl_d_opcode = top->tl_d_opcode;
        uint8_t tl_d_param = top->tl_d_param;
        uint8_t tl_d_size = top->tl_d_size;
        uint8_t tl_d_source = top->tl_d_source;
        uint8_t tl_d_sink = top->tl_d_sink;
        uint8_t tl_d_denied = top->tl_d_denied;
        uint8_t tl_d_corrupt = top->tl_d_corrupt;
        uint64_t tl_d_data = top->tl_d_data;

        ram->apply(
            tl_a_ready,
            top->tl_a_valid,
            top->tl_a_opcode,
            top->tl_a_param,
            top->tl_a_size,
            top->tl_a_source,
            top->tl_a_address,
            top->tl_a_mask,
            top->tl_a_data,
            top->tl_a_corrupt,
            top->tl_d_ready,
            tl_d_valid,
            tl_d_opcode,
            tl_d_param,
            tl_d_size,
            tl_d_source,
            tl_d_sink,
            tl_d_denied,
            tl_d_data,
            tl_d_corrupt
        );

        // Toggle a fast (time/2 period) clock
        top->clk = 1;

        // Evaluate model
        // (If you have multiple models being simulated in the same
        // timestep then instead of eval(), call eval_step() on each, then
        // eval_end_step() on each. See the manual.)
        top->eval();

        contextp->timeInc(1); // 1 timeprecision period passes...

        // Apply changed input signals after clock edge
        top->tl_a_ready = tl_a_ready;
        top->tl_d_valid = tl_d_valid;
        top->tl_d_opcode = tl_d_opcode;
        top->tl_d_param = tl_d_param;
        top->tl_d_size = tl_d_size;
        top->tl_d_source = tl_d_source;
        top->tl_d_sink = tl_d_sink;
        top->tl_d_denied = tl_d_denied;
        top->tl_d_corrupt = tl_d_corrupt;
        top->tl_d_data = tl_d_data;

        top->eval();

        contextp->timeInc(9); // 1 timeprecision period passes...

        top->clk = 0;
        top->eval();
        contextp->timeInc(1); // 1 timeprecision period passes...

        // If you have C++ model logic that changes after the negative edge it goes here
        top->eval();
        contextp->timeInc(9); // 1 timeprecision period passes...
    }

    if (VM_COVERAGE) {
        //printf("\n\nYes, Coverage is here\n\n");
        contextp->coveragep()->forcePerInstance(true);
        contextp->coveragep()->write("coverage.dat");
    }

    // Final model cleanup
    top->final();

    // Return good completion status
    // Don't use exit() or destructor won't get called
    return 0;
}
