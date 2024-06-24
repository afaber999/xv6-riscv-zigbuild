


const std = @import("std");
const riscv = @import("riscv.zig");
const memlayout = @import("memlayout.zig");
const param = @import("param.zig");
const SpinLock = @import("spinlock.zig").SpinLock;
const uart = @import("uart.zig");

const c = @cImport({
    @cInclude("c_funcs.h");
});


var pid_lock: SpinLock = undefined;
var next_pid: i32 = 0;

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



pub fn allocpid() i32
{
  pid_lock.acquire();
  defer pid_lock.release();

  const pid = next_pid;
  next_pid += 1;

  return pid;
}


// TEMP WRAPPERS, TODO REMOVE WHEN POSSIBLE
pub export fn zig_procinit() callconv(.C) void {
    init();
    //c.uartinit();
} 

pub export fn zig_allocpid() callconv(.C)  c_int {
    return allocpid();
} 

