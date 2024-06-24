

const SpinLock = @import("spinlock.zig").SpinLock;
const Proc = @import("Proc.zig");
const uart = @import("uart.zig");

const c = @cImport({
    @cInclude("c_funcs.h");
});


//
// send one character to the uart.
// called by printf(), and to echo input characters,
// but not from write().
//
// void
// consputc(int c)
// {
//   if(c == BACKSPACE){
//     // if the user typed backspace, overwrite with a space.
//     uartputc_sync('\b'); uartputc_sync(' '); uartputc_sync('\b');
//   } else {
//     uartputc_sync(c);
//   }
// }


// const c = @cImport({
//     @cInclude("spinlock.h");
//     @cInclude("c_funcs.h");
// });



// TEMP WRAPPERS, TODO REMOVE WHEN POSSIBLE
pub export fn zig_consputc(ch : c_int) void {
    c.consputc(ch);
}

pub export fn zig_consolewrite(user_src : c_int, src : u64,  n:c_int) c_int {
    return c.consolewrite(user_src, src, n);
}

pub export fn zig_consoleread(user_dst : c_int, dst : u64,  n:c_int) c_int {
    return c.consoleread(user_dst, dst, n);
}

pub export fn zig_consoleintr(ch : c_int) void {
    c.consoleintr(ch);
}

pub export fn zig_consoleinit() void {
    c.consoleinit();
}