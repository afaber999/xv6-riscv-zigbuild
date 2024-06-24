// for the time being, first warp in 

const c = @cImport({
    @cInclude("c_funcs.h");
    @cInclude("spinlock.h");
});
const std = @import("std");
const assert = std.debug.assert;
const Atomic = std.atomic.Value;
const riscv = @import("riscv");

const c_spinlock = extern struct {
    locked: u32 = 0, // Is the lock held?
    name: ?[*:0]const u8 = null,
    cpu: ?*c.struct_cpu = null,
};

pub const SpinLock = extern struct {
    const Self = @This();
    lock: c_spinlock,

    pub fn init(self: *Self, name: ?[*:0]const u8) void {
        c.initlock(@ptrCast(&self.lock), @constCast(@ptrCast(name)));
    }
    pub fn acquire(self: *SpinLock) void {
        c.acquire(@ptrCast(&self.lock));
    }
    pub fn release(self: *SpinLock) void {
        c.release(@ptrCast(&self.lock));
    }
    pub fn holding(self: *SpinLock) bool {
        return c.holding(@ptrCast(&self.lock)) == 1;
    }
    pub fn push_off() void  {
        return c.push_off();
    }
    pub fn pop_off() void  {
        return c.pop_off();
    }
};

