const std = @import("std");
const riscv = @import("riscv.zig");
const kalloc = @import("kalloc.zig");
const memlayout = @import("memlayout.zig");
const KernelError = @import("errors.zig").KernelError;
const assert = std.debug.assert;

const c = @cImport({
    @cInclude("c_funcs.h");
});

pub const PAGESIZE = memlayout.PAGESIZE;


// extract the three 9-bit page table indices from a virtual address.
pub const PXMASK = 0x1FF; // 9 bits
pub fn PXSHIFT(level: u2) u6 {
    return riscv.PGSHIFT + 9 * @as(u6, level);
}
pub fn PX(level: u2, va: usize) usize {
    //std.debug.print("PX VA 0x{x:0>8} level {} shift {}\n", .{ va, level, PXSHIFT(level) });

    return (va >> PXSHIFT(level)) & PXMASK;
}
pub const ELEMENTSPERPAGE = PAGESIZE / @sizeOf(Pte);

pub const PteFlags = packed struct {
    valid: bool = false, // bit 0
    readable: bool = false, // bit 1
    writable: bool = false, // bit 2
    executable: bool = false, // bit 3
    user: bool = false, // bit 4
    global: bool = false, // bit 5
    accesses: bool = false, // bit 6
    dirty: bool = false, // bit 7
    rsw0: bool = false, // bit 8
    rsw1: bool = false, // bit 9
};

pub const Pte = packed struct {
    flags: PteFlags,
    page_number: u44 = 0,
    reserved: u10 = 0,

    pub fn fromRawPtr(pte_raw: *usize) *Pte {
        return @ptrCast(pte_raw);
    }

    pub fn getPageSlice(self: *const Pte) []u8 {
        return @as([*]u8, @ptrFromInt(self.getPA()))[0..PAGESIZE];
    }

    pub inline fn getPAPtr(self: *const Pte) ?*u8 {
        return @ptrFromInt(self.getPA());
    }

    pub inline fn getPA(self: *const Pte) usize {
        return @as(usize, self.page_number << 12);
    }
    pub inline fn setPA(self: *Pte, address: usize) void {
        self.page_number = @intCast(address >> 12);
    }

    pub inline fn clear(self: *Pte) void {
        self.* = .{ .flags = .{} };
    }
};

pub const PageTable = struct {
    pages: *[ELEMENTSPERPAGE]Pte,

    pub fn fromPtr(ptr: *anyopaque) PageTable {
        const pages_ptr: [*]Pte = @alignCast(@ptrCast(ptr));
        return PageTable{ .pages = pages_ptr[0..ELEMENTSPERPAGE] };
    }

    pub fn initFromPtr(ptr: *anyopaque) PageTable {
        const pages_ptr: [*]Pte = @alignCast(@ptrCast(ptr));

        const pt = PageTable{ .pages = pages_ptr[0..ELEMENTSPERPAGE] };
        for (pt.pages) |*pte| {
            pte.clear();
        }
        return pt;
    }

    // Return the address of the PTE in page table pagetable
    // that corresponds to virtual address va.  If alloc!=0,
    // create any required page-table pages.
    //
    // The risc-v Sv39 scheme has three levels of page-table
    // pages. A page-table page contains 512 64-bit PTEs.
    // A 64-bit virtual address is split into five fields:
    //   39..63 -- must be zero.
    //   30..38 -- 9 bits of level-2 index.
    //   21..29 -- 9 bits of level-1 index.
    //   12..20 -- 9 bits of level-0 index.
    //    0..11 -- 12 bits of byte offset within the page.
    pub fn walk(self: PageTable, va: usize, alloc: bool) ?*Pte {

        var pt_walk = self.pages;
        //c.printf( @constCast( "WALK :0x %p\n") , @intFromPtr(pt_walk));

        var level: u2 = 2;
        while (level > 0) : (level -= 1) {
            const idx = PX(level, va);
            //c.printf( @constCast("LEVEL %d %p"), @as(u8,level), @as(u64,pt_walk[idx]));
            if (!pt_walk[idx].flags.valid) {
                if (!alloc) return null;
                // alloc page
                const mem_ptr = kalloc.kalloc() orelse return null;
                const memory = @as([*]u8, @ptrCast(mem_ptr))[0..PAGESIZE];
                @memset(memory, 0);

                // fill in current page table entry
                pt_walk[idx].flags.valid = true;
                pt_walk[idx].setPA(@intCast(@intFromPtr(memory.ptr)));

                //c.printf( @constCast( "WALK ALLOC VA:0x%08X level:%d pt:0x%08X idx:0x%03X\n") , va, @as(u8,level) ,@intFromPtr(pt_walk), idx);
                //std.debug.print("WALK ALLOC VA:0x{x:0>8} level:{} pt:0x{x:0>8} idx:0x{x:0>3}\n", .{ va, level, @intFromPtr(pt_walk), idx });
            } else {
                //c.printf( @constCast( "WALK index VA:0x%08X level:%d pt:0x%08X idx:0x%03X\n") , va, @as(u8,level) ,@intFromPtr(pt_walk), idx);
                //std.debug.print("WALK INDEX VA:0x{x:0>8} level:{} pt:0x{x:0>8} idx:0x{x:0>3}\n", .{ va, level, @intFromPtr(pt_walk), idx });
            }

            pt_walk = PageTable.fromPtr(@ptrFromInt(pt_walk[idx].getPA())).pages;
            //std.debug.print("WALK NEXT -> PAGE ADDRESS 0x{x:0>8}\n", .{@intFromPtr(pt_walk)});
        }
        const idx0 = PX(level, va);
        const pa = &pt_walk[idx0];
        //std.debug.print("WALK LAST VA 0x{x:0>8} level {} pt:0x{x:0>8} idx 0x{x:0>3} -> PA 0x{x:0>8}\n", .{ va, level, @intFromPtr(pt_walk), idx0, @intFromPtr(pa) });
        //c.printf( @constCast( "WALK donE pa:0x%08X\n") ,pa);

        return pa;
    }

    // Look up a virtual address, return the physical address,
    // or 0 if not mapped.
    // Can only be used to look up user pages.
    pub fn walkaddr(self: *PageTable, va: usize) ?*anyopaque {
        //std.debug.print("walkaddr 0x{x:0>8}\n", .{va});
        const pte = self.walk(va, false) orelse return null;
        if (!pte.flags.valid or !pte.flags.user) return null;
        return pte.getPAPtr();
    }

    // Create PTEs for virtual addresses starting at va that refer to
    // physical addresses starting at pa. va and size might not
    // be page-aligned. Returns 0 on success, -1 if walk() couldn't
    // allocate a needed page-table page.
    pub fn mappages(self: PageTable, va: usize, size: usize, pa: usize, flags: PteFlags) KernelError!void {
        if (size == 0)
            @panic("mappages: size");

        var phys_addr = pa;
        var a = riscv.PGROUNDDOWN(va);
        const last = riscv.PGROUNDDOWN(va + size - 1);

        while (true) {
            if ((self.walk(a, true))) |pte| {
                if (pte.flags.valid) {
                    @panic("mappages: remap");
                }
                pte.setPA(phys_addr);

                pte.flags = flags;
                pte.flags.valid = true;

                //std.debug.print("MAPPAGES VA:0x{x:0>8} to PA: 0x{x:0>8} by setting PTE:0x{x:0>8}\n", .{ a, @intFromPtr(pte.getPAPtr()), @intFromPtr(pte) });
            } else {
                return KernelError.MapFailed;
            }
            if (a == last)
                break;
            a += PAGESIZE;
            phys_addr += PAGESIZE;
        }
    }

    // Copy from user to kernel.
    // Copy len bytes to dst from virtual address srcva in a given page table.
    // Return 0 on success, -1 on error.
    pub fn copyin(self: *PageTable, srcva: usize, dst: []u8) KernelError!void {
        var dst_slice = dst;
        var va = srcva;

        while (dst_slice.len > 0) {
            const va0 = riscv.PGROUNDDOWN(va);
            const pa0 = self.walkaddr(va0) orelse return KernelError.PageNotFound;

            const offset = (va - va0);
            var n = PAGESIZE - offset;
            if (n > dst_slice.len) n = dst_slice.len;

            //std.debug.print("\n\n **** COPYIN FROM VA:0x{x:0>8} PA:0x{x:0>8} n:{} offset:{} dst len:{}\n", .{ va, @intFromPtr(pa0), n, offset, dst_slice.len });

            const src_slice = @as([*]u8, @ptrCast(pa0))[offset..(offset + n)];
            std.mem.copyForwards(u8, dst_slice[0..n], src_slice);

            dst_slice = dst_slice[n..];
            va = va0 + PAGESIZE;
        }
    }

    // Copy from kernel to user.
    // Copy len bytes from src to virtual address dstva in a given page table.
    // Returns error on error.
    pub fn copyout(self: *PageTable, dstva: usize, src: []const u8) KernelError!void {
        var src_slice = src;
        var va = dstva;

        while (src_slice.len > 0) {
            const va0 = riscv.PGROUNDDOWN(va);
            const pa0 = self.walkaddr(va0) orelse return KernelError.PageNotFound;

            const offset = (va - va0);
            var n = PAGESIZE - offset;
            if (n > src_slice.len) n = src_slice.len;

            const dst_slice: []u8 = @as([*]u8, @ptrCast(pa0))[0..PAGESIZE];
            std.mem.copyForwards(u8, dst_slice[offset..], src_slice[0..n]);
            //std.debug.print("\n\n **** COPYOUT FROM VA:0x{x:0>8} PA:0x{x:0>8} n:{} offset:{} dst len:{}\n", .{ va, @intFromPtr(pa0), n, offset, dst_slice.len });

            src_slice = src_slice[n..];
            va = va0 + PAGESIZE;
        }
    }

    // Copy a null-terminated string from user to kernel.
    // Copy bytes to dst from virtual address srcva in a given page table,
    // until a '\0', or len of dst.
    // Possible errors: KernelError.PageNotFound or KernelError.NoNullSentinel
    pub fn copyInStr(self: *PageTable, srcva: usize, dst: []u8) KernelError!void {
        var dst_slice = dst;
        var va = srcva;

        while (dst_slice.len > 0) {
            const va0 = riscv.PGROUNDDOWN(va);
            const pa0 = self.walkaddr(va0) orelse return KernelError.PageNotFound;

            const offset = (va - va0);
            var n = PAGESIZE - offset;
            if (n > dst_slice.len) n = dst_slice.len;

            //std.debug.print("\n\n **** COPYINSTR FROM VA:0x{x:0>8} PA:0x{x:0>8} n:{} offset:{} dst len:{}\n", .{ va, @intFromPtr(pa0), n, offset, dst_slice.len });

            const src_slice = @as([*]u8, @ptrCast(pa0))[offset..(offset + n)];

            for (src_slice, 0..) |bt, idx| {
                dst_slice[idx] = bt;
                if (bt == 0) return;
            }
            dst_slice = dst_slice[n..];
            va = va0 + PAGESIZE;
        }
        if (dst[dst.len - 1] != 0) {
            return KernelError.NoNullSentinel;
        }
    }
};

test "CopyInStr test" {
    kalloc.kinit();
    defer kalloc.kdeinit();
    const pt_mem = kalloc.kalloc_page();
    var pt = PageTable.initFromPtr(pt_mem.ptr);

    const pa0 = kalloc.kalloc_page();
    const pa1 = kalloc.kalloc_page();

    for (pa0, 0..) |*v, i| v.* = @as(u8, @truncate(i % 26)) + 'A';
    for (pa1, 0..) |*v, i| v.* = @as(u8, @truncate((i + 1) % 26)) + 'A';

    const va = 0x1000000;
    pt.mappages(va, PAGESIZE, @intFromPtr(pa0.ptr), .{ .user = true }) catch unreachable;
    pt.mappages(va + PAGESIZE, PAGESIZE, @intFromPtr(pa1.ptr), .{ .user = true }) catch unreachable;

    pa0[10] = 0;
    pa1[10] = 0;

    var dst0 = [_]u8{0xFF} ** 12; // basic check, copy to 0 sentinel
    pt.copyInStr(va, &dst0) catch unreachable;
    try std.testing.expectEqual(0, dst0[10]);
    try std.testing.expectEqual(0xFF, dst0[11]);
    try std.testing.expectEqualSlices(u8, pa0[0..11], dst0[0..11]);

    var dst1 = [_]u8{0xFF} ** 12; // VA check page index
    pt.copyInStr(va + PAGESIZE, &dst1) catch unreachable;
    try std.testing.expectEqual(0, dst1[10]);
    try std.testing.expectEqual(0xFF, dst1[11]);
    try std.testing.expectEqualSlices(u8, pa1[0..11], dst1[0..11]);

    var dst3 = [_]u8{0xFF} ** 22; // check cross page boundary
    pt.copyInStr(va + PAGESIZE - 10, &dst3) catch unreachable;
    try std.testing.expectEqual(0, dst3[20]);
    try std.testing.expectEqual(0xFF, dst3[21]);
    try std.testing.expectEqualSlices(u8, pa0[PAGESIZE - 10 ..], dst3[0..10]);
    try std.testing.expectEqualSlices(u8, pa1[0..11], dst3[10..21]);

    var dst4 = [_]u8{0xFF} ** 11; // dist length is just enough
    pt.copyInStr(va, &dst4) catch unreachable;
    try std.testing.expectEqual(0, dst4[10]);
    try std.testing.expectEqualSlices(u8, pa0[0..11], dst4[0..11]);

    var dst5 = [_]u8{0xFF} ** 10; // dst length is one short
    const res = pt.copyInStr(va, &dst5);
    try std.testing.expectEqual(res, KernelError.NoNullSentinel);
    try std.testing.expectEqualSlices(u8, pa0[0..10], dst5[0..10]);
}

test "Check struct sizes" {
    try std.testing.expectEqual(@sizeOf(usize), @sizeOf(Pte));
    try std.testing.expectEqual(@sizeOf(usize), @sizeOf(PageTable));
}

test "Check the number of pages" {
    kalloc.kinit();
    defer kalloc.kdeinit();

    var pt_mem = std.mem.zeroes([ELEMENTSPERPAGE]usize);
    var pt = PageTable.initFromPtr(&pt_mem);

    // set va_start at level 2 page boundary
    const va_start = (0x1 << (12 + 9 + 9));
    try std.testing.expectEqual(kalloc.freelistLen(), kalloc.NUMPAGES);

    // one level 2 (0x000) one level 1 (0x1FF)
    pt.mappages(va_start - PAGESIZE, PAGESIZE, kalloc.kmem_start, .{}) catch unreachable;
    try std.testing.expectEqual(kalloc.freelistLen(), kalloc.NUMPAGES - 2);

    // one level 2 (0x001) one level 1 (0x000)
    pt.mappages(va_start + 0 * PAGESIZE, PAGESIZE, kalloc.kmem_start, .{}) catch unreachable;
    try std.testing.expectEqual(kalloc.freelistLen(), kalloc.NUMPAGES - 4);

    // no level 2 (0x001) no level 1 (0x000)
    pt.mappages(va_start + 1 * PAGESIZE, PAGESIZE * (ELEMENTSPERPAGE - 1), kalloc.kmem_start, .{}) catch unreachable;
    try std.testing.expectEqual(kalloc.freelistLen(), kalloc.NUMPAGES - 4);

    // no  level 2 (0x001) one level 1 (0x001)
    pt.mappages(va_start + ELEMENTSPERPAGE * PAGESIZE, PAGESIZE * ELEMENTSPERPAGE, kalloc.kmem_start, .{}) catch unreachable;
    try std.testing.expectEqual(kalloc.freelistLen(), kalloc.NUMPAGES - 5);
}

test "check page table elements are cleared with initFromPtr" {
    kalloc.kinit();
    defer kalloc.kdeinit();
    var pt_mem = [_]u8{0xFF} ** PAGESIZE;
    const pt = PageTable.initFromPtr(&pt_mem);
    for (pt.pages) |pte| {
        try std.testing.expect(!pte.flags.valid);
        try std.testing.expect(!pte.flags.readable);
        try std.testing.expect(!pte.flags.writable);
        try std.testing.expect(!pte.flags.executable);
        try std.testing.expectEqual(null, pte.getPAPtr());
    }
}

test "Init pagetable ptr" {
    kalloc.kinit();
    defer kalloc.kdeinit();
    const pt_mem = kalloc.kalloc() orelse unreachable;
    const pt = PageTable.initFromPtr(pt_mem);
    const pp: *anyopaque = @ptrCast(pt.pages.ptr);
    try std.testing.expectEqual(pt_mem, pp);
}

test "Test walkaddr" {
    kalloc.kinit();
    defer kalloc.kdeinit();
    const pt_mem = kalloc.kalloc_page();
    var pt = PageTable.initFromPtr(pt_mem.ptr);

    const pa = kalloc.kalloc_page();
    const va = 0x1000000;

    pt.mappages(va, PAGESIZE, @intFromPtr(pa.ptr), .{ .readable = true, .user = true }) catch unreachable;
    pt.mappages(va + PAGESIZE, PAGESIZE, @intFromPtr(pa.ptr), .{ .readable = true, .user = false }) catch unreachable;

    const walk_pa = pt.walkaddr(va) orelse unreachable;
    try std.testing.expectEqual(@as(*anyopaque, @ptrCast(pa.ptr)), walk_pa);

    const not_user = pt.walkaddr(va + PAGESIZE);
    try std.testing.expectEqual(null, not_user);
}

test "CopyIn test" {
    kalloc.kinit();
    defer kalloc.kdeinit();
    const pt_mem = kalloc.kalloc_page();
    var pt = PageTable.initFromPtr(pt_mem.ptr);

    const pa0 = kalloc.kalloc_page();
    const pa1 = kalloc.kalloc_page();

    var rnd = std.rand.DefaultPrng.init(0);
    for (pa0) |*v| v.* = rnd.random().int(u8);
    for (pa1) |*v| v.* = rnd.random().int(u8);

    const va = 0x1000000;
    pt.mappages(va, PAGESIZE, @intFromPtr(pa0.ptr), .{ .user = true }) catch unreachable;
    pt.mappages(va + PAGESIZE, PAGESIZE, @intFromPtr(pa1.ptr), .{ .user = true }) catch unreachable;

    var dst = std.mem.zeroes([PAGESIZE]u8);
    pt.copyin(va, &dst) catch unreachable;
    try std.testing.expectEqualSlices(u8, pa0, &dst);

    dst = std.mem.zeroes([riscv.PGSIZE]u8);
    pt.copyin(va + riscv.PGSIZE, &dst) catch unreachable;
    try std.testing.expectEqualSlices(u8, pa1, &dst);

    dst = std.mem.zeroes([riscv.PGSIZE]u8);
    pt.copyin(va + 100, &dst) catch unreachable;
    try std.testing.expectEqualSlices(u8, pa0[100..], dst[0 .. dst.len - 100]);
    try std.testing.expectEqualSlices(u8, pa1[0..100], dst[dst.len - 100 ..]);

    var dst1 = std.mem.zeroes([13]u8);
    pt.copyin(va + 29, &dst1) catch unreachable;
    try std.testing.expectEqualSlices(u8, pa0[29..][0..dst1.len], &dst1);

    var dst2 = std.mem.zeroes([2 * riscv.PGSIZE]u8);
    pt.copyin(va, &dst2) catch unreachable;
    try std.testing.expectEqualSlices(u8, pa0, dst2[0..riscv.PGSIZE]);
    try std.testing.expectEqualSlices(u8, pa1, dst2[riscv.PGSIZE..]);
}

test "CopyOut test" {
    kalloc.kinit();
    defer kalloc.kdeinit();
    const pt_mem = kalloc.kalloc_page();
    var pt = PageTable.initFromPtr(pt_mem.ptr);

    const pa0 = kalloc.kalloc_page();
    const pa1 = kalloc.kalloc_page();

    const src0 = kalloc.kalloc_page();
    const src1 = kalloc.kalloc_page();

    var rnd = std.rand.DefaultPrng.init(0);
    for (src0) |*v| v.* = rnd.random().int(u8);
    for (src1) |*v| v.* = rnd.random().int(u8);

    const va = 0x1000000;
    pt.mappages(va, riscv.PGSIZE, @intFromPtr(pa0.ptr), .{ .user = true }) catch unreachable;
    pt.mappages(va + riscv.PGSIZE, riscv.PGSIZE, @intFromPtr(pa1.ptr), .{ .user = true }) catch unreachable;

    pt.copyout(va, src0) catch unreachable;
    try std.testing.expectEqualSlices(u8, pa0, src0);

    pt.copyout(va + riscv.PGSIZE, src1) catch unreachable;
    try std.testing.expectEqualSlices(u8, pa1, src1);

    pt.copyout(va + 119, src0) catch unreachable;
    try std.testing.expectEqualSlices(u8, pa0[119..], src0[0 .. src0.len - 119]);
    try std.testing.expectEqualSlices(u8, pa1[0..119], src0[src0.len - 119 ..]);
}


//////////////////////////////////////
// TEMP C WRAPPERS
//////////////////////////////////////
pub export fn walk( ptptr : c.pagetable_t, va : u64, alloc : i32) *c.pte_t  {
    const balloc  = (alloc != 0 );
    var pt = PageTable.fromPtr(ptptr);
    const ret = pt.walk(va, balloc) orelse null;

    return @ptrCast( ret );
    //return @ptrCast(c.walk_c(ptptr, va, alloc));
}

pub export fn walkaddr( ptptr : c.pagetable_t, va : u64 ) u64  {
    var pt = PageTable.fromPtr(ptptr);
    const ret = pt.walkaddr(va) orelse null;
    return @intFromPtr( ret );
    //return c.walkaddr_c(ptptr, va);
}


pub export fn mappages(ptptr : c.pagetable_t, va: usize, size: usize, pa: usize, perm : i32 ) i32 {

    // var pt = PageTable.fromPtr(ptptr);
    // var flags : PteFlags = .{};
    // if ( (perm & riscv.PTE_R) != 0) flags.readable = true;
    // if ( (perm & riscv.PTE_W) != 0) flags.writable = true;
    // if ( (perm & riscv.PTE_X) != 0) flags.executable = true;
    // if ( (perm & riscv.PTE_U) != 0 ) flags.user = true;

    // pt.mappages(va, size, pa, flags) catch return -1;
    // return 0;

    return c.mappages_c(ptptr, va, size, pa,perm);
}
