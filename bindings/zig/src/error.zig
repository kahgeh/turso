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

/// Caller-owned diagnostic message captured from a C error string.
pub const Diagnostic = struct {
    allocator: std.mem.Allocator,
    message: ?[]u8 = null,

    pub fn init(allocator: std.mem.Allocator) Diagnostic {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Diagnostic) void {
        if (self.message) |message| {
            self.allocator.free(message);
        }
        self.message = null;
    }

    pub fn set(self: *Diagnostic, message: []const u8) void {
        if (self.message) |existing| {
            self.allocator.free(existing);
        }
        self.message = self.allocator.dupe(u8, message) catch null;
    }
};

pub fn mapStatus(
    status_code: c.turso_status_code_t,
    error_ptr: [*c]const u8,
    allocator: std.mem.Allocator,
) TursoError {
    return mapStatusWithDiagnostic(status_code, error_ptr, allocator, null);
}

pub fn mapStatusWithDiagnostic(
    status_code: c.turso_status_code_t,
    error_ptr: [*c]const u8,
    allocator: std.mem.Allocator,
    diagnostic: ?*Diagnostic,
) TursoError {
    _ = allocator;

    if (error_ptr != null) {
        if (diagnostic) |diag| {
            diag.set(std.mem.span(error_ptr));
        }
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
