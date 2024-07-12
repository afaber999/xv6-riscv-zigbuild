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

fn freelistLen() usize {
    var p = freelist;
    var cnt : usize = 0;
    while (p != null) : (p = p.?.next) {
        cnt += 1;
    }
    return cnt;
}

fn show_short() void {
    c.printf(@constCast( "FL: "));
    var p = freelist;

    for (0..5) |_| {
        if (p != null) {
            c.printf(@constCast( " %p"), p);
            p = p.?.next;
        }
    }
    c.printf(@constCast( " FLL: %d\n"), freelistLen());
}


pub export fn kinit() void {
    lock.init("zig_kalloc");

    // first address after kernel (not paged aligned!), see kernel.ld script
    const end = @extern([*c]c_char, .{ .name = "end" });

    kmem_start = riscv.PGROUNDUP( @intFromPtr(end) ); // get next page lined address
    kmem_end = memlayout.PHYSTOP; // max mem position
    //kmem_end = kmem_start + 4096 * 2000; //.PHYSTOP; // max mem position
    
    const kmem_size : usize = kmem_end - kmem_start;
    const numPages : usize = (kmem_size / memlayout.PAGESIZE ); 

    pages = @as([*]Page, @ptrFromInt(kmem_start))[0..numPages];    

    c.printf(@constCast( "PAGES PTR: %p LEN:%d\n"), pages.ptr, pages.len);

    for (pages) |*page| {
        freePage(page) catch unreachable;
    }
    show_short();
    do_log = false;
}

const MemPageErrors = error{
    AddressNotPageAligned,
    AddressTooLow,
    AddressTooHigh,
};

fn freePage(page_address: *anyopaque) MemPageErrors!void {

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

pub fn kalloc_page() []u8 {
    lock.acquire();
    defer lock.release();

    if (freelist) |new_page| {
        freelist = new_page.next;
        const new_page_slice = @as([*]u8, @ptrCast(new_page))[0..riscv.PGSIZE];

        // Fill with junk to catch dangling refs.
        @memset(new_page_slice, 1);
        return new_page_slice;
    }
    return &.{};
}

pub export fn kalloc() ?*anyopaque {
    lock.acquire();
    defer lock.release();

    if (freelist) |new_page| {
        freelist = new_page.next;

        // Fill with junk to catch dangling refs.
        @memset(std.mem.asBytes( new_page), 1);

        if (do_log) {
            c.printf(@constCast( "ZIG MY ALLOC: %p FLL: %d\n"), new_page, freelistLen());
        }
        return new_page;
    } else {
        //@panic("KERNEL ERROR: OUT OF MEMORY");
    }
    return null;
}

pub export fn kfree(page_address: *anyopaque) void {
    freePage(page_address) catch {
        @panic("kfree error");
    };

    if (do_log) {
        c.printf(@constCast( "ZIG FREE: %p FLL: %d\n"), page_address,  freelistLen());
    }
}
