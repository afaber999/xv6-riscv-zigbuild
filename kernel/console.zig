

const SpinLock = @import("spinlock.zig").SpinLock;
const Proc = @import("Proc.zig");
const uart = @import("uart.zig");

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
