const std = @import("std");
const riscv = @import("riscv.zig");
const memlayout = @import("memlayout.zig");
const param = @import("param.zig");
const spinlock = @import("spinlock.zig");

// include funcs
comptime { _ = @import("Uart.zig"); }
comptime { _ = @import("Proc.zig"); }
comptime { _ = @import("Console.zig"); }
comptime { _ = @import("Cpu.zig"); }
comptime { _ = @import("kalloc.zig"); }
comptime { _ = @import("bio.zig"); }
comptime { _ = @import("vm.zig"); }
comptime { _ = @import("uvm.zig"); }

const console = @import("Console.zig");

const c = @cImport({
    @cInclude("c_funcs.h");
});

// a scratch area per CPU for machine-mode timer interrupts.
var timer_scratch: [param.NCPU][5]usize = undefined;

// entry.S needs one stack per CPU.
const stack_size: usize = param.CPU_STACK_SIZE * param.NCPU;

// assembly code in kernelvec.S for machine-mode timer interrupt.
extern fn timervec(...) void;

// entry.S needs one stack per CPU.
export var stack0 align(16) = [_]u8{0} ** stack_size;


/// entry jumps here in machine mode on stack0.
pub export fn zig_start() void {    
    if (riscv.intr_get()) {
        riscv.intr_off();
        riscv.intr_on();
    } else {
        riscv.intr_on();
        riscv.intr_off();
        //@panic("TEST PANIC!!!!!");
    }

    // set M Previous Privilege mode to Supervisor, for mret.
    var mstatus = riscv.r_mstatus();
    mstatus &= ~@as(usize, riscv.MSTATUS_MPP_MASK);
    mstatus |= @intFromEnum(riscv.MSTATUS.MPP_S);
    riscv.w_mstatus(mstatus);

    // set M Exception Program Counter to main, for mret.
    // requires gcc -mcmodel=medany
    //riscv.w_mepc(@intFromPtr(&c.main));
    riscv.w_mepc(@intFromPtr(&c.kmain));

    // disable paging for now.
    riscv.w_satp(0);
    
    // delegate all interrupts and exceptions to supervisor mode.
    riscv.w_medeleg(@as(usize, 0xffff));
    riscv.w_mideleg(@as(usize, 0xffff));
    riscv.w_sie(riscv.r_sie() |
        @intFromEnum(riscv.SIE.SEIE) |
        @intFromEnum(riscv.SIE.STIE) |
        @intFromEnum(riscv.SIE.SSIE));

    // configure Physical Memory Protection to give supervisor mode
    // access to all of physical memory.
    riscv.w_pmpaddr0(@as(usize, 0x3fffffffffffff));
    riscv.w_pmpcfg0(@as(usize, 0xf));

    timerinit();

    // keep each CPU's hartid in its tp register, for cpuid().
    const id = riscv.r_mhartid();
    riscv.w_tp(id);

    // switch to supervisor mode and jump to main().
    asm volatile("mret");
}

/// arrange to receive timer interrupts.
/// they will arrive in machine mode at
/// at timervec in kernelvec.S,
/// which turns them into software interrupts for
/// devintr() in trap.c.
pub fn timerinit() void {
    // each CPU has a separate source of timer interrupts.
    const id = riscv.r_mhartid();

    // ask the CLINT for a timer interrupt.
    const interval = 1000000; // cycles; about 1/10th second in qemu.
    memlayout.CLINT_MTIMECMP(id).* = memlayout.CLINT_MTIME.* + interval;

    // prepare information in scratch[] for timervec.
    // scratch[0..2] : space for timervec to save registers.
    // scratch[3] : address of CLINT MTIMECMP register.
    // scratch[4] : desired interval (in cycles) between timer interrupts.
    var scratch = timer_scratch[id];
    scratch[3] = @intFromPtr(memlayout.CLINT_MTIMECMP(id));
    scratch[4] = interval;
    riscv.w_mscratch(@intFromPtr(&scratch));

    // set the machine-mode trap handler.
    riscv.w_mtvec(@intFromPtr(&timervec));
    
    // enable machine-mode interrupts.
    riscv.w_mstatus(riscv.r_mstatus() | @intFromEnum(riscv.MSTATUS.MIE));

    // enable machine-mode timer interrupts.
    riscv.w_mie(riscv.r_mie() | @intFromEnum(riscv.MIE.MTIE));
}


pub fn panic(
    msg: []const u8,
    error_return_trace: ?*std.builtin.StackTrace,
    _: ?usize,
) noreturn {

    _ = error_return_trace;

    for (msg) |ch| {
        console.zig_consputc(ch);

    }

    //c.panic(msg);
    // @setCold(true);
    // const panic_log = std.log.scoped(.panic);
    // log_root.locking = false;
    // panic_log.err("{s}\n", .{msg});
    // log_root.panicked = true; // freeze uart output from other CPUs
    while (true) {}
}

