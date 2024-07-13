const std = @import("std");
const riscv = @import("riscv.zig");
const kalloc = @import("kalloc.zig");
const memlayout = @import("memlayout.zig");
const KernelError = @import("errors.zig").KernelError;
const vm = @import("vm.zig");

const assert = std.debug.assert;

const c = @cImport({
    @cInclude("c_funcs.h");
});

// create an empty user page table.
// returns 0 if out of memory.
pub fn zuvmcreate() ?vm.PageTable {
    const pt_mem = kalloc.kalloc() orelse return null;
    return vm.PageTable.initFromPtr(pt_mem);
}

// Load the user initcode into address 0 of pagetable,
// for the very first process.
// sz must be less than a page.
pub fn zuvmfirst(pagetable: vm.PageTable, init_code: []const u8) void {
    if (init_code.len >= vm.PAGESIZE)
        @panic("uvmfirst: more than a page");

    const mem = kalloc.kalloc_page();
    if (mem.len == 0) @panic("out of memory");
    @memset(mem, 0x00);

    const flags = .{ .writable = true, .readable = true, .executable = true, .user = true };
    pagetable.mappages(0, vm.PAGESIZE, @intFromPtr(mem.ptr), flags) catch @panic("map error");

    std.mem.copyForwards(u8, mem, init_code);
}

// Deallocate user pages to bring the process size from oldsz to
// newsz.  oldsz and newsz need not be page-aligned, nor does newsz
// need to be less than oldsz.  oldsz can be larger than the actual
// process size.  Returns the new process size.
pub fn uvmdealloc(pagetable: vm.PageTable, oldsz: usize, newsz: usize) void {
    if (newsz >= oldsz)
        return oldsz;

    if (riscv.PGROUNDUP(newsz) < riscv.PGROUNDUP(oldsz)) {
        const npages = (riscv.PGROUNDUP(oldsz) - riscv.PGROUNDUP(newsz)) / vm.PAGESIZE;
        uvmunmap(pagetable, riscv.PGROUNDUP(newsz), npages, 1);
    }

    return newsz;
}

// Allocate PTEs and physical memory to grow process from oldsz to
// newsz, which need not be page aligned.  Returns new size or 0 on error.
pub fn uvmalloc(pagetable: vm.PageTable, oldsz: usize, newsz: usize, flags: vm.PteFlags) KernelError!usize {
    if (newsz < oldsz)
        return oldsz;

    const oldsz_r = riscv.PGROUNDUP(oldsz);

    var cf = flags;
    cf.readable = true;
    cf.user = true;

    var a = oldsz_r;
    while (a < newsz) : (a += vm.PAGESIZE) {
        errdefer uvmdealloc(pagetable, a, oldsz);

        const mem = kalloc.kalloc_page();
        if (mem.len == 0) KernelError.OutOfMemory;
        errdefer kalloc.kfree(mem.ptr);
        @memset(mem, 0x00);
        pagetable.mappages(pagetable, a, vm.PAGESIZE, mem.ptr, cf) catch KernelError.MapFailed;
    }

    return newsz;
}

// Remove npages of mappings starting from va. va must be
// page-aligned. The mappings must exist.
// Optionally free the physical memory.
pub fn uvmunmap(pagetable: vm.PageTable, va: usize, npages: usize, do_free: bool) void {
    if ((va % vm.PAGESIZE) != 0)
        @panic("uvmunmap: not aligned");

    for (0..npages) |n| {
        const a = va + n * vm.PAGESIZE;
        const pte = pagetable.walk(@ptrFromInt(a), false) orelse @panic("uvmunmap: walk");
        if (!pte.valid) @panic("uvmunmap: not mapped");
        if (!(pte.readable | pte.writable | pte.executable)) @panic("uvmunmap: not a leaf");

        if (do_free) {
            kalloc.kfree(@ptrFromInt(pte.getPA()));
        }
        pte.clear();
    }
}

// Recursively free page-table pages.
// All leaf mappings must already have been removed.
pub fn freewalk(pagetable: vm.PageTable) void {
    // there are 2^9 = 512 PTEs in a page table.
    for (pagetable.pages) |*pte| {
        // this PTE points to a lower-level page table, only valid bit might be set
        if (pte.flags.valid and !(pte.flags.readable or pte.flags.writable or pte.flags.executable)) {
            const child = vm.PageTable.fromPtr(pte.getPAPtr());
            freewalk(child);
            pte.clear();
        } else if (pte.flags.valid) {
            @panic("freewalk: leaf");
        }
    }
    kalloc.kfree(pagetable.pages.ptr);
}

// Free user memory pages,
// then free page-table pages.
pub fn uvmfree(pagetable: vm.PageTable, sz: usize) void {
    if (sz > 0)
        uvmunmap(pagetable, 0, riscv.PGROUNDUP(sz) / vm.PAGESIZE, 1);
    freewalk(pagetable);
}

// Given a parent process's page table, copy
// its memory into a child's page table.
// Copies both the page table and the
// physical memory.
// returns 0 on success, -1 on failure.
// frees any allocated pages on failure.
pub fn uvmcopy(pt_old: vm.PageTable, pt_new: vm.PageTable, sz: usize) KernelError!void {
    var i = 0;
    while (i < sz) : (i += vm.PAGESIZE) {
        errdefer uvmunmap(pt_new, 0, i / vm.PAGESIZE, true);

        // get src mem location
        const pte = vm.walk(pt_old, i, 0) orelse @panic("uvmcopy: pte should exist");
        if (!pte.flags.valid) @panic("uvmcopy: page not present");
        const src_slice = pte.getPageSlice();

        // create and map dst mem location, and copy page content from src to dst
        const dst_slice = kalloc.kalloc_page();
        if (dst_slice.len == 0) return KernelError.OutOfMemory;
        errdefer kalloc.kfree(dst_slice.ptr);

        std.mem.copyForwards(u8, dst_slice, src_slice);
        pt_new.mappages(i, vm.PAGESIZE, dst_slice.ptr, pte.flags) catch KernelError.MapFailed;
    }
}

// mark a PTE invalid for user access.
// used by exec for the user stack guard page.
pub fn uvmclear(pagetable: vm.PageTable, va: usize) void {
    const pte = pagetable.walk(va, 0) orelse @panic("uvmclear");
    pte.flags.user = false;
}

// // Remove npages of mappings starting from va. va must be
// // page-aligned. The mappings must exist.
// // Optionally free the physical memory.
// pub fn uvmunmap(pagetable: vm.PageTable, va: usize, npages: usize, do_free: bool) void {
//     //   uint64 a;
//     //   pte_t *pte;

//     if ((va % vm.PAGESIZE) != 0)
//         @panic("uvmunmap: not aligned");

//     var a = va;

//     while (a < va + (npages * vm.PAGESIZE)) : (a += vm.PAGESIZE) {
//         var pte = pagetable.walk(a, 0) orelse @panic("uvmunmap: walk");
//         if (!pte.valid) @panic("uvmunmap: not mapped");
//         if (!(pte.readable | pte.writable | pte.executable)) @panic("uvmunmap: not a leaf");

//         if (do_free) {
//             kalloc.kfree(pte.getPAPtr());
//         }
//         pte.clear();
//     }
// }

test "uvm create" {
    kalloc.kinit();
    defer kalloc.kdeinit();
    for (0..kalloc.NUMPAGES) |_| {
        const pt = zuvmcreate() orelse unreachable;
        for (pt.pages) |pte| {
            try std.testing.expect(!pte.flags.valid);
            try std.testing.expect(!pte.flags.readable);
            try std.testing.expect(!pte.flags.writable);
            try std.testing.expect(!pte.flags.executable);
            try std.testing.expectEqual(pte.getPAPtr(), null);
        }
    }
    // should fails
    const ept = zuvmcreate();
    try std.testing.expectEqual(ept, null);
}

test "uvmfirst" {
    kalloc.kinit();
    defer kalloc.kdeinit();
    var pt_mem = std.mem.zeroes([vm.ELEMENTSPERPAGE]usize);
    const init_code = [_]u8{ 0xBA, 0xBE, 0xFA, 0xCE };
    const zero_code = std.mem.zeroes([vm.PAGESIZE - init_code.len]u8);
    var pt = vm.PageTable.initFromPtr(&pt_mem);

    zuvmfirst(pt, &init_code);
    const mem = pt.walkaddr(0);
    const slice = @as([*]u8, @ptrCast(mem))[0..vm.PAGESIZE];
    try std.testing.expectEqualSlices(u8, &init_code, slice[0..init_code.len]);
    try std.testing.expectEqualSlices(u8, &zero_code, slice[init_code.len..]);
}


// pub export fn uvmcreate() c.pagetable_t {
//     const r = zuvmcreate() orelse return null ;
//     return @ptrCast( &r.pages[0]);
// }

// pub export fn uvmfirst(ptptr : c.pagetable_t, src : [*]u8, sz : u32) void {
//     const pt = vm.PageTable.fromPtr(ptptr);
//     const sl= src[0..sz];
//     zuvmfirst(pt, sl);
// } 
