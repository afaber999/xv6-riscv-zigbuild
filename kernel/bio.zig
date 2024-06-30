const std = @import("std");
const riscv = @import("riscv.zig");
const memlayout = @import("memlayout.zig");
const param = @import("param.zig");
const spinlock = @import("spinlock.zig");

const c = @cImport({
    @cInclude("c_funcs.h");
});


pub export fn binit() void {
    return c.c_binit();
}

// fn bget(dev : u32, blockno : u32) *c.buf {
//     return c.c_bget(dev, blockno);
// }

pub export fn bread(dev : u32, blockno : u32) ?*c.buf {
    return c.c_bread(dev, blockno);
}

pub export fn bwrite(b : *c.buf) void {
    c.c_bwrite(b);
}

pub export fn brelse(b : *c.buf) void {
    c.c_brelse(b);
}

pub export fn bpin(b : *c.buf) void {
    c.c_bpin(b);
}

pub export fn bunpin(b : *c.buf) void {
    c.c_bunpin(b);
}
