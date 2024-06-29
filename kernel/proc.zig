

const std = @import("std");
const riscv = @import("riscv.zig");
const memlayout = @import("memlayout.zig");
const param = @import("Param.zig");
const SpinLock = @import("spinlock.zig").SpinLock;
const Uart = @import("Uart.zig");
const Cpu = @import("Cpu.zig");

const c = @cImport({
    @cInclude("c_funcs.h");
});


pub const TrapFrame = struct {
    kernel_satp: u64,
    kernel_sp: u64,
    kernel_trap: u64,
    epc: u64,
    kernel_hartid: u64,
    ra: u64,
    sp: u64,
    gp: u64,
    tp: u64,
    t0: u64,
    t1: u64,
    t2: u64,
    s0: u64,
    s1: u64,
    a0: u64,
    a1: u64,
    a2: u64,
    a3: u64,
    a4: u64,
    a5: u64,
    a6: u64,
    a7: u64,
    s2: u64,
    s3: u64,
    s4: u64,
    s5: u64,
    s6: u64,
    s7: u64,
    s8: u64,
    s9: u64,
    s10: u64,
    s11: u64,
    t3: u64,
    t4: u64,
    t5: u64,
    t6: u64,
};


pub var cpus: [param.NCPU]Cpu = undefined;


var pid_lock: SpinLock = undefined;
var next_pid: i32 = 0;

const Proc = @This();
var procs: [param.NPROC]Proc = undefined;

lock: SpinLock,
state: ProcState,
chan: ?*anyopaque,
killed: bool,
xstate: i32,
pid: i32,
parent: *Proc,

kstack: u64,
size: u64,
pagetable: riscv.PageTable,
trapframe: *TrapFrame,
context: Cpu.Context,


pub const ProcState = enum {
    UNUSED,
    USED,
    SLEEPING,
    RUNNABLE,
    RUNNING,
    ZOMBIE,
};



// initialize the proc table.
pub fn init() void
{
    pid_lock.init("zpid_lock");
    c.procinit();
//  struct proc *p;
  
//   initlock(&pid_lock, "nextpid");
//   initlock(&wait_lock, "wait_lock");
//   for(p = proc; p < &proc[NPROC]; p++) {
//       initlock(&p->lock, "proc");
//       p->state = UNUSED;
//       p->kstack = KSTACK((int) (p - proc));
//   }
}


pub fn cpuId() u32 {
    return @as(u32, @intCast(riscv.r_tp()));
}

pub fn MyCpu() *Cpu {
    return &cpus[cpuId()];
}

pub fn MyProc() *Proc {
    SpinLock.pushOff();
    defer SpinLock.popOff();
    const cpu = MyCpu();
    return cpu.proc;
}


pub fn allocpid() i32
{
  pid_lock.acquire();
  defer pid_lock.release();

  const pid = next_pid;
  next_pid += 1;

  return pid;
}


pub fn wakeup(chan: *anyopaque) void {
  c.wakeup(chan);
}

// TEMP WRAPPERS, TODO REMOVE WHEN POSSIBLE
pub export fn zig_procinit() void {
    init();
    //c.uartinit();
} 

pub export fn zig_allocpid() c_int {
    return allocpid();
} 

