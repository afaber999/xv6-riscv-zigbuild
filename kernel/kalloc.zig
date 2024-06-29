const std = @import("std");
const riscv = @import("riscv.zig");

const c = @cImport({
    @cInclude("c_funcs.h");
});


const Block = extern struct {
    next: ?*Block,
};

var lock: SpinLock = undefined;
var freelist: ?*Block = null;

//const Kalloc = @This();
const memlayout = @import("memlayout.zig");
const SpinLock = @import("spinlock.zig").SpinLock;

const Page = extern struct {
    pg : [memlayout.PAGESIZE]u8,
};

var pages : [] Page =undefined;
var kmem_start : usize = undefined;
var kmem_end : usize = undefined;

var do_log : bool = false;

pub export fn kinit() void {
    lock.init("zig_kalloc");

    // first address after kernel (not paged aligned!), see kernel.ld script
    const end = @extern([*c]c_char, .{ .name = "end" });

    kmem_start = riscv.PGROUNDUP( @intFromPtr(end) ); // get next page lined address
    kmem_end = memlayout.PHYSTOP; // max mem position
    const kmem_size : usize = kmem_end - kmem_start;
    const numPages : usize = (kmem_size / memlayout.PAGESIZE ); 

    pages = @as([*]Page, @ptrFromInt(kmem_start))[0..numPages];    

    c.printf(@constCast( "ZIG PAGES INITIALIZED !!!! start: %p len %d\n"), pages.ptr, pages.len);
    //c.printf(@constCast( "\nEND : %p\n"), c.end);
    c.printf(@constCast( "CEND : %p end : %p PHYSEND: %x\n"), c.end, end, kmem_end);
    c.printf(@constCast( "PAGE 0 : %p\n"), &pages[0]);
    c.printf(@constCast( "PAGE 1 : %p\n"), &pages[1]);
    c.printf(@constCast( "LAST PAGE  : %p\n"), &pages[pages.len - 1]);

    for (pages) |*page| {
        //c.printf(@constCast( "PAGE PTR : %p\n"), page);
        //kfree(page);
        freePage(page) catch unreachable;
    }
    c.printf(@constCast( "FREELIST  : %p\n"), freelist);


    //@as(?*anyopaque, @ptrFromInt(@as(c_ulong, 2147483648) +% @as(c_ulong, @bitCast(@as(c_long, (@as(c_int, 128) * @as(c_int, 1024)) * @as(c_int, 10

    //freerange(@ptrCast( c.end), @ptrFromInt(memlayout.PHYSTOP));

    c.printf(@constCast( "\nZIG KINIT!!!! %p\n"), c.end);
    c.c_kinit();

    do_log = true;
}

const MemPageErrors = error{
    AddressNotPageAligned,
    AddressTooLow,
    AddressTooHigh,
};

pub fn freePage(page_address: *anyopaque) MemPageErrors!void {

    const pa_u : usize = @intFromPtr(page_address);

    // check pointer
    if (pa_u % memlayout.PAGESIZE != 0) return error.AddressNotPageAligned;
    if (pa_u < kmem_start) return error.AddressTooLow;
    if (pa_u >= kmem_end) return error.AddressTooHigh;
    
    const as_page : *Page = @ptrCast( page_address);

    // Fill with junk to catch dangling refs.
    @memset(std.mem.asBytes( as_page), 1);
    
    const b: *Block = @alignCast(@ptrCast(page_address));

    // add block to free-list
    lock.acquire();
    defer lock.release();
    b.next = freelist;
    freelist = b;
}


pub export fn kalloc() ?*anyopaque {


    lock.acquire();
    defer lock.release();
    // const r_o = freelist;
    // if (r_o) |r| {
    //     freelist = r.next;
    // }
    // if (r_o) |r| {
    //     const ptr: [*]u8 = @ptrCast(r);
    //     @memset(ptr[0..memlayout.PAGESIZE], 5);
    // } else {
    //     // log.warn("out of memory", .{});
    //     return null;
    // }
    // const ptr: [*]align(memlayout.PAGESIZE) u8 = @alignCast(@ptrCast(r_o.?));
    // return ptr[0..memlayout.PAGESIZE];

    const ptr = c.c_kalloc();
    c.printf(@constCast( "ZIG ALLOC: %p\n"), ptr);
    return ptr;
}

pub export fn kfree(page_address: *anyopaque) void {

    if (do_log) {
        c.printf(@constCast( "ZIG FREE: %p\n"), page_address);
    }

    // const ptr: [*]u8 = @ptrCast(page_address);
    // freePage(@alignCast(ptr[0..memlayout.PAGESIZE])) catch {
    //     @panic("kfree error");
    // };

    return c.c_kfree(page_address);
}
