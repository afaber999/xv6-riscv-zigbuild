const memlayout = @import("memlayout.zig");

const c = @cImport({
    @cInclude("spinlock.h");
    @cInclude("c_funcs.h");
});


/// the UART control registers.
/// some have different meanings for
/// read vs write.
/// see http://byterunner.com/16550.html
pub const RHR = 0; // receive holding register (for input bytes)
pub const THR = 0; // transmit holding register (for output bytes)
pub const IER = 1; // interrupt enable register
pub const IER_RX_ENABLE = 1 << 0;
pub const IER_TX_ENABLE = 1 << 1;
pub const FCR = 2; // FIFO control register
pub const FCR_FIFO_ENABLE = 1 << 0;
pub const FCR_FIFO_CLEAR = 3 << 1; // clear the content of the two FIFOs
pub const ISR = 2; // interrupt status register
pub const LCR = 3; // line control register
pub const LCR_EIGHT_BITS = 3 << 0;
pub const LCR_BAUD_LATCH = 1 << 7; // special mode to set baud rate
pub const LSR = 5; // line status register
pub const LSR_RX_READY = 1 << 0; // input is waiting to be read from RHR
pub const LSR_TX_IDLE = 1 << 5; // THR can accept another character to send


pub fn getRegPtr(reg: usize) *volatile u8 {
    return @ptrFromInt(memlayout.UART0 + reg);
}

pub fn readReg(reg: usize) u8 {
    return getRegPtr(reg).*;
}

pub fn writeReg(reg: usize, value: u8) void {
    getRegPtr(reg).* = value;
}


pub fn init() void {
    // disable interrupts.
    writeReg(IER, 0x00);

    // special mode to set baud rate.
    writeReg(LCR, LCR_BAUD_LATCH);

    // LSB for baud rate of 38.4K.
    writeReg(0, 0x03);

    // MSB for baud rate of 38.4K.
    writeReg(1, 0x00);

    // leave set-baud mode,
    // and set word length to 8 bits, no parity.
    writeReg(LCR, LCR_EIGHT_BITS);

    // reset and enable FIFOs.
    writeReg(FCR, FCR_FIFO_ENABLE | FCR_FIFO_CLEAR);

    // enable transmit and receive interrupts.
    writeReg(IER, IER_TX_ENABLE | IER_RX_ENABLE);

    c.initlock(&c.uart_tx_lock, @constCast(@ptrCast("uart")));
//     // tx_lock.init();

}

   
