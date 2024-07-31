const std = @import("std");
const SpinLock = @import("spinlock.zig").SpinLock;
const Proc = @import("proc.zig");
const Uart = @import("uart.zig");

const c = @cImport({
    @cInclude("c_funcs.h");
    //@cInclude("file.h");
});

const ascii = std.ascii;


const BUF_SIZE : usize = 128;

var lock: SpinLock = undefined;

// input
var buf: [BUF_SIZE]u8 = [_]u8{0} ** BUF_SIZE;
var read_idx: u32 = 0; // Read index
var write_idx: u32 = 0; // Write index
var edit_idx: u32 = 0; // Edit index


extern fn consoleread(user_dst: c_int, dst: usize, n: c_int) c_int;
extern fn consolewrite(user_src: c_int, src: usize, n: c_int) c_int;

pub fn init() void  {
    lock.init("cons");
    Uart.init();
    // connect read and write system calls
    // to consoleread and consolewrite.
    //c.devsw[c.CONSOLE].read = zig_consoleread;
    //c.devsw[c.CONSOLE].write = zig_consolewrite;    
}


//
// send one character to the uart.
// called by printf(), and to echo input characters,
// but not from write().
//
pub inline fn putc(ch : u8 ) void {
    Uart.putcSync(ch);
}

fn backspace() void {

    // if the user typed backspace, overwrite with a space.
    Uart.putcSync(ascii.control_code.bs);
    Uart.putcSync(' ');
    Uart.putcSync(ascii.control_code.bs);
}


// the console input interrupt handler.
// uartintr() calls this for input character.
// do erase/kill processing, append to cons.buf,
// wake up consoleread() if a whole line has arrived.
//
pub fn consoleintr(ch : u8) void {
    lock.acquire();
    defer lock.releae();

    switch( ch ) {
        'P' - '@', 'W' - '@' => {
            Proc.procdump();
        },
        'U' => {
            while (edit_idx != write_idx and
                buf[(edit_idx - 1) % BUF_SIZE] != '\n')
            {
                edit_idx -= 1;
                backspace();
            }
        },
        std.ascii.control_code.bs, std.ascii.control_code.del => {
            if (edit_idx != write_idx) {
                edit_idx -= 1;
                backspace();
            }          
        },
        else => if(ch != 0 and ((edit_idx - read_idx) < BUF_SIZE)) {
            ch = if (ch == '\r') '\n' else ch;
            
            // echo back to the user.            
            putc(ch);

            // store for consumption by consoleread().
            buf[edit_idx % BUF_SIZE] = ch;
            edit_idx += 1;            

            if (ch == '\n' or ch == std.ascii.control_code.del or
                edit_idx - read_idx == BUF_SIZE)
            {
                // wake up consoleread() if a whole line (or end-of-file)
                // has arrived or buffer is full
                write_idx = edit_idx;
                Proc.wakeup(&read_idx);
            }
        },
    }
}


//
// user write()s to the console go here.
//
// pub fn consolewrite(int user_src, uint64 src, int n)
// {
//   int i;

//   for(i = 0; i < n; i++){
//     char c;
//     if(either_copyin(&c, user_src, src+i, 1) == -1)
//       break;
//     zig_uartputc(c);
//   }

//   return i;
// }

//
// user read()s from the console go here.
// copy (up to) a whole input line to dst.
// user_dist indicates whether dst is a user
// or kernel address.
//
// pub fn consoleread(int user_dst, uint64 dst, int n)
// {
//   uint target;
//   int c;
//   char cbuf;

//   target = n;
//   acquire(&cons.lock);
//   while(n > 0){
//     // wait until interrupt handler has put some
//     // input into cons.buffer.
//     while(cons.r == cons.w){
//       if(killed(myproc())){
//         release(&cons.lock);
//         return -1;
//       }
//       sleep(&cons.r, &cons.lock);
//     }

//     c = cons.buf[cons.r++ % INPUT_BUF_SIZE];

//     if(c == C('D')){  // end-of-file
//       if(n < target){
//         // Save ^D for next time, to make sure
//         // caller gets a 0-byte result.
//         cons.r--;
//       }
//       break;
//     }

//     // copy the input byte to the user-space buffer.
//     cbuf = c;
//     if(either_copyout(user_dst, dst, &cbuf, 1) == -1)
//       break;

//     dst++;
//     --n;

//     if(c == '\n'){
//       // a whole line has arrived, return to
//       // the user-level read().
//       break;
//     }
//   }
//   release(&cons.lock);

//   return target - n;
// }

// TEMP WRAPPERS, TODO REMOVE WHEN POSSIBLE
pub export fn zig_consputc(ch : c_int) void {

        // const a : i32 = @intCast(ch);
        // const b : u32 = @bitCast(a);
        // const b1 : u8 = @truncate(b);

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
    // AF NOT HOOKED YET init();

    c.consoleinit();
}