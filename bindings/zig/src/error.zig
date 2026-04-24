const std = @import("std");
const c = @import("c.zig");

pub const TursoError = error{
    Busy,
    BusySnapshot,
    Constraint,
    Corrupt,
    DatabaseFull,
    Generic,
    Interrupt,
    IOError,
    Misuse,
    NotADB,
    OutOfMemory,
    ReadOnly,
    UnexpectedStatus,
};

pub fn mapStatus(
    status_code: c.turso_status_code_t,
    error_ptr: [*c]const u8,
    allocator: std.mem.Allocator,
) TursoError {
    _ = allocator;

    if (error_ptr != null) {
        c.turso_str_deinit(error_ptr);
    }

    return switch (status_code) {
        c.TURSO_BUSY => error.Busy,
        c.TURSO_BUSY_SNAPSHOT => error.BusySnapshot,
        c.TURSO_CONSTRAINT => error.Constraint,
        c.TURSO_CORRUPT => error.Corrupt,
        c.TURSO_DATABASE_FULL => error.DatabaseFull,
        c.TURSO_ERROR => error.Generic,
        c.TURSO_INTERRUPT => error.Interrupt,
        c.TURSO_IOERR => error.IOError,
        c.TURSO_MISUSE => error.Misuse,
        c.TURSO_NOTADB => error.NotADB,
        c.TURSO_READONLY => error.ReadOnly,
        c.TURSO_OK, c.TURSO_DONE, c.TURSO_ROW, c.TURSO_IO => error.UnexpectedStatus,
        else => error.Generic,
    };
}

pub fn isControlFlow(status_code: c.turso_status_code_t) bool {
    return switch (status_code) {
        c.TURSO_OK, c.TURSO_DONE, c.TURSO_ROW, c.TURSO_IO => true,
        else => false,
    };
}
