pub const KernelError = error{
    AccessDenied,
    OutOfMemory,
    FileNotFound,
    MapFailed,
    PageNotFound,
    NoNullSentinel,
};
