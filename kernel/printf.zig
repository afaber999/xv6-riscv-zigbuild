
// .\printf.c:64:1: warning: TODO unable to translate variadic function, demoted to extern
pub extern fn printf(fmt: [*c]u8, ...) void;
pub export fn panic(arg_s: [*c]u8) noreturn {
    var s = arg_s;
    _ = &s;
    pr.locking = 0;
    printf(@as([*c]u8, @ptrCast(@volatileCast(@constCast("panic: ")))));
    printf(s);
    printf(@as([*c]u8, @ptrCast(@volatileCast(@constCast("\n")))));
    panicked = 1;
    while (true) {}
}
pub export fn printfinit() void {
    initlock(&pr.lock, @as([*c]u8, @ptrCast(@volatileCast(@constCast("pr")))));
    pr.locking = 1;
}
