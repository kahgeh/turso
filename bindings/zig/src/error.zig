const std = @import("std");
const c = @import("c.zig");
const status = @import("status.zig");

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

    return switch (@as(status.StatusCode, @enumFromInt(status_code))) {
        .TURSO_BUSY => error.Busy,
        .TURSO_BUSY_SNAPSHOT => error.BusySnapshot,
        .TURSO_CONSTRAINT => error.Constraint,
        .TURSO_CORRUPT => error.Corrupt,
        .TURSO_DATABASE_FULL => error.DatabaseFull,
        .TURSO_ERROR => error.Generic,
        .TURSO_INTERRUPT => error.Interrupt,
        .TURSO_IOERR => error.IOError,
        .TURSO_MISUSE => error.Misuse,
        .TURSO_NOTADB => error.NotADB,
        .TURSO_READONLY => error.ReadOnly,
        .TURSO_OK, .TURSO_DONE, .TURSO_ROW, .TURSO_IO => error.UnexpectedStatus,
    };
}

pub fn isControlFlow(status_code: c.turso_status_code_t) bool {
    return switch (@as(status.StatusCode, @enumFromInt(status_code))) {
        .TURSO_OK, .TURSO_DONE, .TURSO_ROW, .TURSO_IO => true,
        else => false,
    };
}
